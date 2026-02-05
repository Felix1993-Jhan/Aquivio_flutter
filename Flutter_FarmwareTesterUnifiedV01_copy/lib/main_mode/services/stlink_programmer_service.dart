// ============================================================================
// STLinkProgrammerService - ST-Link 韌體燒錄服務
// ============================================================================
// 功能：透過 STM32CubeProgrammer CLI 燒錄韌體到 STM32
// ============================================================================

import 'dart:async';
import 'dart:io';

/// 燒錄狀態
enum ProgrammerStatus {
  idle,           // 閒置
  checking,       // 檢查 ST-Link 連接
  erasing,        // 擦除 Flash
  programming,    // 燒錄中
  verifying,      // 驗證中
  resetting,      // 重置 MCU
  completed,      // 完成
  error,          // 錯誤
}

/// 燒錄結果
class ProgrammerResult {
  final bool success;
  final String message;
  final String? errorDetails;

  /// 用於多語言翻譯的 key（如果有設定，UI 層應使用此 key 進行翻譯）
  final String? messageKey;

  /// 翻譯參數（用於插入翻譯字串中的變數）
  final Map<String, dynamic>? messageParams;

  ProgrammerResult({
    required this.success,
    required this.message,
    this.errorDetails,
    this.messageKey,
    this.messageParams,
  });
}

/// ST-Link 資訊
class StLinkInfo {
  final String? serialNumber;
  final String? version;
  final bool isConnected;

  StLinkInfo({
    this.serialNumber,
    this.version,
    required this.isConnected,
  });
}

/// ST-Link Programmer 服務
class StLinkProgrammerService {
  // STM32CubeProgrammer CLI 預設路徑
  static const String _defaultCliPath =
      r'C:\Program Files\STMicroelectronics\STM32Cube\STM32CubeProgrammer\bin\STM32_Programmer_CLI.exe';

  String _cliPath = _defaultCliPath;

  // ST-Link 頻率選項 (kHz)
  static const List<int> frequencyOptions = [5, 50, 200, 1000, 3300, 8000, 24000];
  static const int defaultFrequency = 8000;

  // 連接模式選項 (必須大寫)
  static const List<String> modeOptions = ['NORMAL', 'HOTPLUG', 'UR'];  // UR = under reset
  static const String defaultMode = 'UR';

  // 重置模式選項
  static const List<String> resetModeOptions = ['SWrst', 'HWrst', 'Crst'];  // SW=Software, HW=Hardware, C=Core
  static const String defaultResetMode = 'HWrst';

  int _frequency = defaultFrequency;
  String _mode = defaultMode;
  String _resetMode = defaultResetMode;

  // 狀態
  ProgrammerStatus _status = ProgrammerStatus.idle;
  ProgrammerStatus get status => _status;

  // 進度 (0.0 - 1.0)
  double _progress = 0.0;
  double get progress => _progress;

  // 狀態訊息
  String _statusMessage = '';
  String get statusMessage => _statusMessage;

  // 當前執行的進程（用於取消）
  Process? _currentProcess;

  // 狀態變更回調
  Function(ProgrammerStatus status, double progress, String message)? onStatusChanged;

  /// 取消當前操作
  void cancelOperation() {
    if (_currentProcess != null) {
      try {
        _currentProcess!.kill(ProcessSignal.sigkill);
      } catch (e) {
        // Windows 上可能不支援 SIGKILL，嘗試普通 kill
        try {
          _currentProcess!.kill();
        } catch (_) {}
      }
      _currentProcess = null;
      _updateStatus(ProgrammerStatus.idle, 0, 'Operation cancelled');
    }
  }

  /// 設定 CLI 路徑
  void setCliPath(String path) {
    _cliPath = path;
  }

  /// 取得 CLI 路徑
  String get cliPath => _cliPath;

  /// 設定 ST-Link 頻率 (kHz)
  void setFrequency(int freq) {
    _frequency = freq;
  }

  /// 取得 ST-Link 頻率 (kHz)
  int get frequency => _frequency;

  /// 設定連接模式
  void setMode(String mode) {
    _mode = mode;
  }

  /// 取得連接模式
  String get mode => _mode;

  /// 設定重置模式
  void setResetMode(String resetMode) {
    _resetMode = resetMode;
  }

  /// 取得重置模式
  String get resetMode => _resetMode;

  /// 檢查 CLI 是否存在
  Future<bool> checkCliExists() async {
    final file = File(_cliPath);
    return await file.exists();
  }

  /// 檢查 ST-Link 連接狀態
  Future<StLinkInfo> checkStLinkConnection() async {
    _updateStatus(ProgrammerStatus.checking, 0, 'Checking ST-Link connection...');

    try {
      // 使用 -l 列出所有 ST-Link（不需要連接）
      final result = await Process.run(
        _cliPath,
        ['-l'],  // 只列出設備，不連接
        stdoutEncoding: systemEncoding,  // 使用系統編碼避免 UTF-8 錯誤
        stderrEncoding: systemEncoding,
      ).timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          _updateStatus(ProgrammerStatus.error, 0, 'Connection check timeout');
          return ProcessResult(-1, -1, '', 'Connection check timeout (15s)');
        },
      );

      if (result.exitCode == -1) {
        _updateStatus(ProgrammerStatus.error, 0, 'Connection check timeout');
        return StLinkInfo(isConnected: false);
      }

      final output = result.stdout.toString() + result.stderr.toString();

      // 檢查是否找到 ST-Link
      if (output.contains('ST-LINK') && !output.contains('No ST-LINK detected')) {
        // 嘗試解析序號
        String? serialNumber;
        final snMatch = RegExp(r'ST-LINK SN\s*:\s*(\S+)').firstMatch(output);
        if (snMatch != null) {
          serialNumber = snMatch.group(1);
        }

        // 嘗試解析版本
        String? version;
        final versionMatch = RegExp(r'ST-LINK V(\d+)').firstMatch(output);
        if (versionMatch != null) {
          version = 'V${versionMatch.group(1)}';
        }

        _updateStatus(ProgrammerStatus.idle, 0, 'ST-Link connected');
        return StLinkInfo(
          isConnected: true,
          serialNumber: serialNumber,
          version: version,
        );
      } else {
        _updateStatus(ProgrammerStatus.idle, 0, 'ST-Link not connected');
        return StLinkInfo(isConnected: false);
      }
    } catch (e) {
      _updateStatus(ProgrammerStatus.error, 0, 'Check failed: $e');
      return StLinkInfo(isConnected: false);
    }
  }

  /// 第二次重試時使用的頻率
  static const int retry2ndFrequency = 50;

  /// 第三次重試時使用的頻率
  static const int retry3rdFrequency = 5;

  /// 燒錄韌體
  /// [firmwarePath] - 韌體檔案路徑 (.elf, .bin, .hex)
  /// [startAddress] - 起始位址 (僅 .bin 檔案需要，預設 0x08000000)
  /// [verify] - 是否驗證
  /// [reset] - 燒錄後是否重置
  /// [autoRetry] - 失敗時是否自動以較低頻率重試（預設 true）
  Future<ProgrammerResult> programFirmware({
    required String firmwarePath,
    String startAddress = '0x08000000',
    bool verify = true,
    bool reset = true,
    bool autoRetry = true,
  }) async {
    // 檢查檔案是否存在
    final file = File(firmwarePath);
    if (!await file.exists()) {
      _updateStatus(ProgrammerStatus.error, 0, 'Firmware file not found');
      return ProgrammerResult(
        success: false,
        message: 'Firmware file not found',
        messageKey: 'firmware_file_not_found',
        errorDetails: firmwarePath,
      );
    }

    // 檢查檔案格式
    final extension = firmwarePath.toLowerCase().split('.').last;
    if (!['elf', 'bin', 'hex'].contains(extension)) {
      _updateStatus(ProgrammerStatus.error, 0, 'Unsupported file format');
      return ProgrammerResult(
        success: false,
        message: 'Unsupported file format: .$extension',
        messageKey: 'unsupported_file_format',
        messageParams: {'extension': extension},
        errorDetails: 'Supported formats: .elf, .bin, .hex',
      );
    }

    // 第一次嘗試（使用使用者設定的頻率）
    var result = await _executeProgramming(
      firmwarePath: firmwarePath,
      startAddress: startAddress,
      extension: extension,
      verify: verify,
      reset: reset,
      frequency: _frequency,
      attemptNumber: 1,
    );

    // 如果第一次失敗且允許自動重試
    if (!result.success && autoRetry) {
      // 第二次嘗試：使用 200kHz
      final retry2ndFreq = _frequency > retry2ndFrequency ? retry2ndFrequency : _frequency;

      _updateStatus(ProgrammerStatus.programming, 0.05, 'Retry 2nd attempt at $retry2ndFreq kHz...');
      await Future.delayed(const Duration(milliseconds: 500));

      result = await _executeProgramming(
        firmwarePath: firmwarePath,
        startAddress: startAddress,
        extension: extension,
        verify: verify,
        reset: reset,
        frequency: retry2ndFreq,
        attemptNumber: 2,
      );

      if (result.success) {
        return ProgrammerResult(
          success: true,
          message: 'Program success (2nd attempt, $retry2ndFreq kHz)',
          messageKey: 'program_success_retry',
          messageParams: {'attempt': 2, 'frequency': retry2ndFreq},
          errorDetails: result.errorDetails,
        );
      }

      // 第三次嘗試：使用 50kHz
      final retry3rdFreq = retry2ndFreq > retry3rdFrequency ? retry3rdFrequency : retry2ndFreq;

      _updateStatus(ProgrammerStatus.programming, 0.05, 'Retry 3rd attempt at $retry3rdFreq kHz...');
      await Future.delayed(const Duration(milliseconds: 500));

      result = await _executeProgramming(
        firmwarePath: firmwarePath,
        startAddress: startAddress,
        extension: extension,
        verify: verify,
        reset: reset,
        frequency: retry3rdFreq,
        attemptNumber: 3,
      );

      if (result.success) {
        return ProgrammerResult(
          success: true,
          message: 'Program success (3rd attempt, $retry3rdFreq kHz)',
          messageKey: 'program_success_retry',
          messageParams: {'attempt': 3, 'frequency': retry3rdFreq},
          errorDetails: result.errorDetails,
        );
      }
    }

    return result;
  }

  /// 執行實際的燒錄操作
  Future<ProgrammerResult> _executeProgramming({
    required String firmwarePath,
    required String startAddress,
    required String extension,
    required bool verify,
    required bool reset,
    required int frequency,
    required int attemptNumber,
  }) async {
    try {
      // 建立燒錄參數
      // STM32_Programmer_CLI 格式: -c port=SWD mode=UR freq=4000 reset=HWrst -w file.elf -v -rst
      final args = <String>[
        '-c',
        'port=SWD',
        'mode=$_mode',
        'freq=$frequency',
        'reset=$_resetMode',
        '-w',
        firmwarePath,
      ];

      // .bin 檔案需要指定起始位址
      if (extension == 'bin') {
        args.add(startAddress);
      }

      // 驗證選項
      if (verify) {
        args.add('-v');
      }

      // 重置選項
      if (reset) {
        args.add('-rst');
      }

      final attemptText = attemptNumber > 1 ? ' (attempt $attemptNumber)' : '';
      _updateStatus(ProgrammerStatus.programming, 0.1, 'Connecting ST-Link...$attemptText');

      // 使用 Process.run 執行（更穩定）
      final result = await Process.run(
        _cliPath,
        args,
        stdoutEncoding: systemEncoding,  // 使用系統編碼避免 UTF-8 錯誤
        stderrEncoding: systemEncoding,
      ).timeout(
        const Duration(seconds: 120),
        onTimeout: () {
          _updateStatus(ProgrammerStatus.error, 0, 'Program timeout');
          return ProcessResult(-1, -1, '', 'Program timeout (120s)');
        },
      );

      final exitCode = result.exitCode;
      final output = result.stdout.toString() + result.stderr.toString();

      // 檢查是否超時
      if (exitCode == -1) {
        _updateStatus(ProgrammerStatus.error, 0, 'Program timeout');
        return ProgrammerResult(
          success: false,
          message: 'Program timeout (120s)',
          messageKey: 'program_timeout_error',
          errorDetails: output.isEmpty ? 'No output, possible ST-Link connection issue' : output,
        );
      }

      if (exitCode == 0 && !output.contains('Error')) {
        _updateStatus(ProgrammerStatus.completed, 1.0, 'Program completed');
        return ProgrammerResult(
          success: true,
          message: 'Firmware program success',
          messageKey: 'program_success',
          errorDetails: output,
        );
      } else {
        // 解析錯誤訊息
        String errorMsg = 'Program failed';
        String? errorKey;
        if (output.contains('No ST-LINK detected')) {
          errorMsg = 'ST-Link not connected';
          errorKey = 'stlink_not_detected';
        } else if (output.contains('Target not connected')) {
          errorMsg = 'Target MCU not connected';
          errorKey = 'target_not_connected';
        } else if (output.contains('Error: Flash memory not erased')) {
          errorMsg = 'Flash erase failed';
          errorKey = 'flash_erase_failed';
        } else {
          errorKey = 'program_failed';
        }

        _updateStatus(ProgrammerStatus.error, 0, errorMsg);
        return ProgrammerResult(
          success: false,
          message: errorMsg,
          messageKey: errorKey,
          errorDetails: output,
        );
      }
    } catch (e) {
      _currentProcess = null;
      _updateStatus(ProgrammerStatus.error, 0, 'Execution error: $e');
      return ProgrammerResult(
        success: false,
        message: 'Execution error',
        messageKey: 'execution_error',
        errorDetails: e.toString(),
      );
    }
  }

  /// 擦除 Flash
  Future<ProgrammerResult> eraseFlash() async {
    _updateStatus(ProgrammerStatus.erasing, 0, 'Erasing Flash...');

    try {
      final result = await Process.run(
        _cliPath,
        ['-c', 'port=SWD', 'mode=$_mode', 'freq=$_frequency', 'reset=$_resetMode', '-e', 'all'],
        stdoutEncoding: systemEncoding,  // 使用系統編碼避免 UTF-8 錯誤
        stderrEncoding: systemEncoding,
      ).timeout(
        const Duration(seconds: 60),
        onTimeout: () {
          _updateStatus(ProgrammerStatus.error, 0, 'Erase timeout');
          return ProcessResult(-1, -1, '', 'Erase timeout (60s)');
        },
      );

      if (result.exitCode == -1) {
        return ProgrammerResult(
          success: false,
          message: 'Erase timeout (60s)',
          messageKey: 'erase_timeout_error',
          errorDetails: 'Operation timeout, possible ST-Link connection issue',
        );
      }

      final output = result.stdout.toString() + result.stderr.toString();

      if (result.exitCode == 0 && !output.contains('Error')) {
        _updateStatus(ProgrammerStatus.completed, 1.0, 'Erase completed');
        return ProgrammerResult(success: true, message: 'Erase completed', messageKey: 'erase_completed', errorDetails: output);
      } else {
        _updateStatus(ProgrammerStatus.error, 0, 'Erase failed');
        return ProgrammerResult(
          success: false,
          message: 'Erase failed',
          messageKey: 'erase_failed',
          errorDetails: output,
        );
      }
    } catch (e) {
      _updateStatus(ProgrammerStatus.error, 0, 'Erase error: $e');
      return ProgrammerResult(
        success: false,
        message: 'Erase error',
        messageKey: 'erase_error',
        errorDetails: e.toString(),
      );
    }
  }

  /// 重置 MCU
  Future<ProgrammerResult> resetMcu() async {
    _updateStatus(ProgrammerStatus.resetting, 0.5, 'Resetting MCU...');

    try {
      final result = await Process.run(
        _cliPath,
        ['-c', 'port=SWD', 'mode=$_mode', 'freq=$_frequency', 'reset=$_resetMode', '-rst'],
        stdoutEncoding: systemEncoding,  // 使用系統編碼避免 UTF-8 錯誤
        stderrEncoding: systemEncoding,
      ).timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          _updateStatus(ProgrammerStatus.error, 0, 'Reset timeout');
          return ProcessResult(-1, -1, '', 'Reset timeout (30s)');
        },
      );

      if (result.exitCode == -1) {
        return ProgrammerResult(
          success: false,
          message: 'Reset timeout (30s)',
          messageKey: 'mcu_reset_timeout_error',
          errorDetails: 'Operation timeout, possible ST-Link connection issue',
        );
      }

      final output = result.stdout.toString() + result.stderr.toString();

      if (result.exitCode == 0) {
        _updateStatus(ProgrammerStatus.completed, 1.0, 'Reset completed');
        return ProgrammerResult(success: true, message: 'Reset completed', messageKey: 'mcu_reset_completed', errorDetails: output);
      } else {
        _updateStatus(ProgrammerStatus.error, 0, 'Reset failed');
        return ProgrammerResult(
          success: false,
          message: 'Reset failed',
          messageKey: 'mcu_reset_failed',
          errorDetails: output,
        );
      }
    } catch (e) {
      _updateStatus(ProgrammerStatus.error, 0, 'Reset error: $e');
      return ProgrammerResult(
        success: false,
        message: 'Reset error',
        messageKey: 'mcu_reset_error',
        errorDetails: e.toString(),
      );
    }
  }

  /// 解析進度
  void _parseProgress(String output) {
    // 解析燒錄進度
    if (output.contains('Download in Progress')) {
      _updateStatus(ProgrammerStatus.programming, 0.3, 'Programming...');
    } else if (output.contains('File download complete')) {
      _updateStatus(ProgrammerStatus.verifying, 0.7, 'Verifying...');
    } else if (output.contains('Verifying')) {
      _updateStatus(ProgrammerStatus.verifying, 0.8, 'Verifying...');
    } else if (output.contains('Download verified successfully')) {
      _updateStatus(ProgrammerStatus.resetting, 0.9, 'Resetting...');
    }

    // 嘗試解析百分比
    final percentMatch = RegExp(r'(\d+)%').firstMatch(output);
    if (percentMatch != null) {
      final percent = int.tryParse(percentMatch.group(1) ?? '0') ?? 0;
      final progress = 0.3 + (percent / 100) * 0.4; // 30% - 70%
      _updateStatus(_status, progress, _statusMessage);
    }
  }

  /// 更新狀態
  void _updateStatus(ProgrammerStatus status, double progress, String message) {
    _status = status;
    _progress = progress;
    _statusMessage = message;
    onStatusChanged?.call(status, progress, message);
  }

  /// 重置狀態
  void reset() {
    _updateStatus(ProgrammerStatus.idle, 0, '');
  }
}
