// ============================================================================
// FirmwareUploadPage - 韌體燒錄頁面
// ============================================================================
// 功能：透過 ST-Link 燒錄韌體到 STM32
// - 選擇韌體檔案 (.elf, .bin, .hex)
// - 檢測 ST-Link 連接狀態
// - 燒錄進度顯示
// - 燒錄結果顯示
// ============================================================================

import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../services/stlink_programmer_service.dart';
import '../services/localization_service.dart';

class FirmwareUploadPage extends StatefulWidget {
  /// STM32 是否已連接
  final bool isStm32Connected;

  /// 斷開 STM32 連線的回調
  final VoidCallback? onDisconnectStm32;

  const FirmwareUploadPage({
    super.key,
    this.isStm32Connected = false,
    this.onDisconnectStm32,
  });

  @override
  State<FirmwareUploadPage> createState() => _FirmwareUploadPageState();
}

class _FirmwareUploadPageState extends State<FirmwareUploadPage> {
  final StLinkProgrammerService _programmer = StLinkProgrammerService();

  // 狀態
  bool _cliExists = false;
  StLinkInfo? _stLinkInfo;
  String? _selectedFilePath;
  String? _selectedFileName;
  bool _isChecking = false;
  bool _isProgramming = false;
  String _statusMessage = '';
  double _progress = 0.0;
  ProgrammerResult? _lastResult;

  // 選項
  bool _verifyAfterProgram = true;
  bool _resetAfterProgram = true;
  int _selectedFrequency = StLinkProgrammerService.defaultFrequency;
  String _selectedMode = StLinkProgrammerService.defaultMode;
  String _selectedResetMode = StLinkProgrammerService.defaultResetMode;

  // 韌體資料夾路徑
  String? _firmwareFolderPath;
  List<FileSystemEntity> _firmwareFiles = [];

  // 資料夾監聽器
  Stream<FileSystemEvent>? _folderWatcher;
  StreamSubscription<FileSystemEvent>? _folderWatcherSubscription;

  // 捲動控制器
  final ScrollController _scrollController = ScrollController();

  // 進度卡片的 Key（用於捲動定位）
  final GlobalKey _progressCardKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _initializeService();
  }

  @override
  void dispose() {
    // 取消資料夾監聽
    _folderWatcherSubscription?.cancel();
    // 釋放捲動控制器
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _initializeService() async {
    // 設定狀態回調
    _programmer.onStatusChanged = (status, progress, message) {
      if (mounted) {
        setState(() {
          _progress = progress;
          _statusMessage = message;
        });
      }
    };

    // 檢查 CLI 是否存在
    final cliExists = await _programmer.checkCliExists();
    setState(() {
      _cliExists = cliExists;
    });

    if (cliExists) {
      await _checkStLinkConnection();
    }

    // 檢查韌體資料夾
    await _checkFirmwareFolder();
  }

  /// 檢查韌體資料夾是否存在，並掃描其中的韌體檔案
  Future<void> _checkFirmwareFolder() async {
    // 取得應用程式執行路徑
    final exePath = Platform.resolvedExecutable;
    final exeDir = Directory(exePath).parent.path;
    final firmwareDir = Directory('$exeDir\\firmware');

    if (await firmwareDir.exists()) {
      _firmwareFolderPath = firmwareDir.path;
      // 掃描韌體檔案
      await _scanFirmwareFiles(firmwareDir);
      // 啟動資料夾監聽
      _startFolderWatcher(firmwareDir);
    } else {
      // 建立韌體資料夾
      try {
        await firmwareDir.create();
        _firmwareFolderPath = firmwareDir.path;
        // 啟動資料夾監聽
        _startFolderWatcher(firmwareDir);
      } catch (e) {
        // 忽略建立失敗
      }
    }
  }

  /// 掃描韌體資料夾中的檔案
  Future<void> _scanFirmwareFiles(Directory firmwareDir) async {
    try {
      final files = firmwareDir.listSync().where((f) {
        if (f is File) {
          final ext = f.path.toLowerCase();
          return ext.endsWith('.elf') || ext.endsWith('.bin') || ext.endsWith('.hex');
        }
        return false;
      }).toList();

      if (mounted) {
        setState(() {
          _firmwareFiles = files;
          // 如果資料夾中只有一個韌體檔案，自動選擇它
          if (files.length == 1 && _selectedFilePath == null) {
            _selectedFilePath = files.first.path;
            _selectedFileName = files.first.path.split('\\').last;
          }
          // 如果當前選擇的檔案已被刪除，清除選擇
          if (_selectedFilePath != null &&
              !files.any((f) => f.path == _selectedFilePath) &&
              !File(_selectedFilePath!).existsSync()) {
            _selectedFilePath = null;
            _selectedFileName = null;
          }
        });
      }
    } catch (e) {
      // 忽略掃描錯誤
    }
  }

  /// 啟動資料夾監聽器
  void _startFolderWatcher(Directory firmwareDir) {
    // 先取消舊的監聽器
    _folderWatcherSubscription?.cancel();

    try {
      _folderWatcher = firmwareDir.watch();
      _folderWatcherSubscription = _folderWatcher?.listen((event) {
        // 當資料夾內容變更時，重新掃描
        _scanFirmwareFiles(firmwareDir);
      });
    } catch (e) {
      // 某些系統可能不支援資料夾監聽
    }
  }

  Future<void> _checkStLinkConnection() async {
    setState(() {
      _isChecking = true;
      _statusMessage = tr('checking_stlink');
    });

    final info = await _programmer.checkStLinkConnection();

    setState(() {
      _stLinkInfo = info;
      _isChecking = false;
      _statusMessage = info.isConnected
          ? tr('stlink_connected')
          : tr('stlink_not_connected');
    });
  }

  Future<void> _selectFirmwareFile() async {
    // 如果韌體資料夾有多個檔案，顯示選擇對話框
    if (_firmwareFiles.length > 1) {
      await _showFirmwareSelectionDialog();
    } else {
      // 使用檔案選擇器
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['elf', 'bin', 'hex'],
        dialogTitle: tr('select_firmware_file'),
        initialDirectory: _firmwareFolderPath,
      );

      if (result != null && result.files.single.path != null) {
        setState(() {
          _selectedFilePath = result.files.single.path;
          _selectedFileName = result.files.single.name;
          _lastResult = null;
        });
      }
    }
  }

  /// 顯示韌體檔案選擇對話框
  Future<void> _showFirmwareSelectionDialog() async {
    final selected = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr('select_firmware_file')),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 韌體資料夾中的檔案列表
              ..._firmwareFiles.map((file) {
                final fileName = file.path.split('\\').last;
                return ListTile(
                  leading: const Icon(Icons.memory, color: Color(0xFF5C6BC0)),
                  title: Text(fileName),
                  subtitle: Text(file.path, style: const TextStyle(fontSize: 11)),
                  onTap: () => Navigator.pop(context, file.path),
                );
              }),
              const Divider(),
              // 選擇其他檔案選項
              ListTile(
                leading: const Icon(Icons.folder_open, color: Colors.grey),
                title: Text(tr('select_other_file')),
                onTap: () => Navigator.pop(context, 'BROWSE'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(tr('cancel')),
          ),
        ],
      ),
    );

    if (selected == 'BROWSE') {
      // 使用檔案選擇器
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['elf', 'bin', 'hex'],
        dialogTitle: tr('select_firmware_file'),
        initialDirectory: _firmwareFolderPath,
      );

      if (result != null && result.files.single.path != null) {
        setState(() {
          _selectedFilePath = result.files.single.path;
          _selectedFileName = result.files.single.name;
          _lastResult = null;
        });
      }
    } else if (selected != null) {
      setState(() {
        _selectedFilePath = selected;
        _selectedFileName = selected.split('\\').last;
        _lastResult = null;
      });
    }
  }

  Future<void> _programFirmware() async {
    if (_selectedFilePath == null) {
      _showSnackBar(tr('please_select_firmware'), isError: true);
      return;
    }

    if (_stLinkInfo == null || !_stLinkInfo!.isConnected) {
      _showSnackBar(tr('stlink_not_connected'), isError: true);
      return;
    }

    // 燒錄前先斷開 STM32 串口連線（避免燒錄時 STM32 無回應導致問題）
    if (widget.isStm32Connected && widget.onDisconnectStm32 != null) {
      _showSnackBar(tr('disconnecting_stm32_for_program'), isError: false);
      widget.onDisconnectStm32!();
      // 等待斷線完成
      await Future.delayed(const Duration(milliseconds: 300));
    }

    setState(() {
      _isProgramming = true;
      _progress = 0.0;
      _statusMessage = tr('starting_program');
      _lastResult = null;
    });

    // 延遲一幀讓 UI 先更新，確保取消按鈕可用
    await Future.delayed(const Duration(milliseconds: 100));

    // 自動捲動到進度卡片
    _scrollToProgressCard();

    // 使用非阻塞方式執行，讓 UI 可以回應取消操作
    _programmer.programFirmware(
      firmwarePath: _selectedFilePath!,
      verify: _verifyAfterProgram,
      reset: _resetAfterProgram,
    ).then((result) {
      if (mounted) {
        setState(() {
          _isProgramming = false;
          _lastResult = result;
          _statusMessage = result.message;
        });

        if (result.success) {
          _showSnackBar(tr('program_success'), isError: false);
        } else {
          _showSnackBar(result.message, isError: true);
        }
      }
    });
  }

  Future<void> _eraseFlash() async {
    if (_stLinkInfo == null || !_stLinkInfo!.isConnected) {
      _showSnackBar(tr('stlink_not_connected'), isError: true);
      return;
    }

    // 確認對話框
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr('confirm_erase')),
        content: Text(tr('erase_warning')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(tr('cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text(tr('erase')),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() {
      _isProgramming = true;
      _progress = 0.0;
      _statusMessage = tr('erasing_flash');
    });

    final result = await _programmer.eraseFlash();

    setState(() {
      _isProgramming = false;
      _lastResult = result;
      _statusMessage = result.message;
    });

    _showSnackBar(result.message, isError: !result.success);
  }

  Future<void> _resetMcu() async {
    if (_stLinkInfo == null || !_stLinkInfo!.isConnected) {
      _showSnackBar(tr('stlink_not_connected'), isError: true);
      return;
    }

    setState(() {
      _isProgramming = true;
      _statusMessage = tr('resetting_mcu');
    });

    final result = await _programmer.resetMcu();

    setState(() {
      _isProgramming = false;
      _lastResult = result;
      _statusMessage = result.message;
    });

    _showSnackBar(result.message, isError: !result.success);
  }

  void _showSnackBar(String message, {required bool isError}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.green,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  /// 自動捲動到進度卡片
  void _scrollToProgressCard() {
    // 延遲一幀確保 Widget 已經建立
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_progressCardKey.currentContext != null) {
        // 使用 Scrollable.ensureVisible 捲動到進度卡片
        Scrollable.ensureVisible(
          _progressCardKey.currentContext!,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        );
      } else {
        // 如果找不到 Key，直接捲動到底部
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(tr('firmware_upload')),
        backgroundColor: const Color(0xFF5C6BC0),
        foregroundColor: Colors.white,
        actions: [
          // 刷新 ST-Link 連接
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _isChecking || _isProgramming ? null : _checkStLinkConnection,
            tooltip: tr('refresh_stlink'),
          ),
        ],
      ),
      body: _cliExists ? _buildMainContent() : _buildCliNotFoundContent(),
    );
  }

  Widget _buildCliNotFoundContent() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.error_outline,
              size: 80,
              color: Colors.red,
            ),
            const SizedBox(height: 24),
            Text(
              tr('cli_not_found'),
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Text(
              tr('cli_not_found_hint'),
              style: const TextStyle(fontSize: 14, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: SelectableText(
                _programmer.cliPath,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMainContent() {
    return SingleChildScrollView(
      controller: _scrollController,
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ST-Link 狀態卡片
          _buildStLinkStatusCard(),
          const SizedBox(height: 24),

          // 韌體檔案選擇卡片
          _buildFileSelectionCard(),
          const SizedBox(height: 24),

          // 燒錄選項卡片
          _buildOptionsCard(),
          const SizedBox(height: 24),

          // 操作按鈕
          _buildActionButtons(),
          const SizedBox(height: 24),

          // 進度顯示
          if (_isProgramming || _progress > 0)
            Container(
              key: _progressCardKey,
              child: _buildProgressCard(),
            ),

          // 結果顯示
          if (_lastResult != null) _buildResultCard(),
        ],
      ),
    );
  }

  Widget _buildStLinkStatusCard() {
    final isConnected = _stLinkInfo?.isConnected ?? false;

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.usb,
                  color: isConnected ? Colors.green : Colors.grey,
                ),
                const SizedBox(width: 12),
                Text(
                  'ST-Link ${tr('status')}',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                if (_isChecking)
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: isConnected ? Colors.green.shade100 : Colors.red.shade100,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      isConnected ? tr('connected') : tr('not_connected'),
                      style: TextStyle(
                        color: isConnected ? Colors.green.shade700 : Colors.red.shade700,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ),
            if (isConnected && _stLinkInfo != null) ...[
              const SizedBox(height: 12),
              const Divider(),
              const SizedBox(height: 8),
              if (_stLinkInfo!.version != null)
                _buildInfoRow(tr('version'), _stLinkInfo!.version!),
              if (_stLinkInfo!.serialNumber != null)
                _buildInfoRow(tr('serial_number'), _stLinkInfo!.serialNumber!),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Text(
            '$label: ',
            style: const TextStyle(color: Colors.grey),
          ),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }

  Widget _buildFileSelectionCard() {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.file_present, color: Color(0xFF5C6BC0)),
                const SizedBox(width: 12),
                Text(
                  tr('firmware_file'),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            InkWell(
              onTap: _isProgramming ? null : _selectFirmwareFile,
              borderRadius: BorderRadius.circular(8),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: _selectedFilePath != null
                        ? const Color(0xFF5C6BC0)
                        : Colors.grey.shade300,
                    width: 2,
                    style: BorderStyle.solid,
                  ),
                  borderRadius: BorderRadius.circular(8),
                  color: _selectedFilePath != null
                      ? const Color(0xFF5C6BC0).withValues(alpha: 0.05)
                      : Colors.grey.shade50,
                ),
                child: Column(
                  children: [
                    Icon(
                      _selectedFilePath != null ? Icons.check_circle : Icons.upload_file,
                      size: 48,
                      color: _selectedFilePath != null
                          ? const Color(0xFF5C6BC0)
                          : Colors.grey,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _selectedFileName ?? tr('click_to_select'),
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: _selectedFilePath != null
                            ? FontWeight.bold
                            : FontWeight.normal,
                        color: _selectedFilePath != null
                            ? const Color(0xFF5C6BC0)
                            : Colors.grey,
                      ),
                    ),
                    if (_selectedFilePath != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        _selectedFilePath!,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    const SizedBox(height: 8),
                    Text(
                      tr('supported_formats'),
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade500,
                      ),
                    ),
                    // 顯示韌體資料夾中的檔案數量
                    if (_firmwareFiles.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade50,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '${_firmwareFiles.length} ${tr('firmware_file')} in firmware/',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.blue.shade700,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOptionsCard() {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.settings, color: Color(0xFF5C6BC0)),
                const SizedBox(width: 12),
                Text(
                  tr('program_options'),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // ST-Link 頻率選擇
            ListTile(
              title: Text(tr('stlink_frequency')),
              subtitle: Text(tr('stlink_frequency_hint')),
              trailing: DropdownButton<int>(
                value: _selectedFrequency,
                onChanged: _isProgramming
                    ? null
                    : (value) {
                        if (value != null) {
                          setState(() => _selectedFrequency = value);
                          _programmer.setFrequency(value);
                        }
                      },
                items: StLinkProgrammerService.frequencyOptions
                    .map((freq) => DropdownMenuItem<int>(
                          value: freq,
                          child: Text('$freq kHz'),
                        ))
                    .toList(),
              ),
            ),
            // 連接模式選擇
            ListTile(
              title: Text(tr('connect_mode')),
              subtitle: Text(tr('connect_mode_hint')),
              trailing: DropdownButton<String>(
                value: _selectedMode,
                onChanged: _isProgramming
                    ? null
                    : (value) {
                        if (value != null) {
                          setState(() => _selectedMode = value);
                          _programmer.setMode(value);
                        }
                      },
                items: StLinkProgrammerService.modeOptions
                    .map((mode) => DropdownMenuItem<String>(
                          value: mode,
                          child: Text(_getModeDisplayName(mode)),
                        ))
                    .toList(),
              ),
            ),
            // 重置模式選擇
            ListTile(
              title: Text(tr('reset_mode')),
              subtitle: Text(tr('reset_mode_hint')),
              trailing: DropdownButton<String>(
                value: _selectedResetMode,
                onChanged: _isProgramming
                    ? null
                    : (value) {
                        if (value != null) {
                          setState(() => _selectedResetMode = value);
                          _programmer.setResetMode(value);
                        }
                      },
                items: StLinkProgrammerService.resetModeOptions
                    .map((mode) => DropdownMenuItem<String>(
                          value: mode,
                          child: Text(_getResetModeDisplayName(mode)),
                        ))
                    .toList(),
              ),
            ),
            const Divider(),
            SwitchListTile(
              title: Text(tr('verify_after_program')),
              subtitle: Text(tr('verify_hint')),
              value: _verifyAfterProgram,
              onChanged: _isProgramming
                  ? null
                  : (value) => setState(() => _verifyAfterProgram = value),
            ),
            SwitchListTile(
              title: Text(tr('reset_after_program')),
              subtitle: Text(tr('reset_hint')),
              value: _resetAfterProgram,
              onChanged: _isProgramming
                  ? null
                  : (value) => setState(() => _resetAfterProgram = value),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButtons() {
    final canProgram = _selectedFilePath != null &&
        (_stLinkInfo?.isConnected ?? false) &&
        !_isProgramming;

    return Row(
      children: [
        // 燒錄按鈕 或 取消按鈕
        Expanded(
          flex: 2,
          child: _isProgramming
              ? ElevatedButton.icon(
                  onPressed: _cancelOperation,
                  icon: const Icon(Icons.cancel),
                  label: Text(tr('cancel')),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                )
              : ElevatedButton.icon(
                  onPressed: canProgram ? _programFirmware : null,
                  icon: const Icon(Icons.download),
                  label: Text(tr('program_firmware')),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF5C6BC0),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
        ),
        const SizedBox(width: 12),
        // 擦除按鈕
        Expanded(
          child: OutlinedButton.icon(
            onPressed: (_stLinkInfo?.isConnected ?? false) && !_isProgramming
                ? _eraseFlash
                : null,
            icon: const Icon(Icons.delete_forever),
            label: Text(tr('erase')),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.red,
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
          ),
        ),
        const SizedBox(width: 12),
        // 重置按鈕
        Expanded(
          child: OutlinedButton.icon(
            onPressed: (_stLinkInfo?.isConnected ?? false) && !_isProgramming
                ? _resetMcu
                : null,
            icon: const Icon(Icons.restart_alt),
            label: Text(tr('reset')),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
          ),
        ),
      ],
    );
  }

  void _cancelOperation() {
    _programmer.cancelOperation();
    setState(() {
      _isProgramming = false;
      _progress = 0.0;
      _statusMessage = tr('cancel');
    });
  }

  Widget _buildProgressCard() {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.sync, color: Color(0xFF5C6BC0)),
                const SizedBox(width: 12),
                Text(
                  tr('progress'),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                Text(
                  '${(_progress * 100).toInt()}%',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF5C6BC0),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            LinearProgressIndicator(
              value: _progress,
              backgroundColor: Colors.grey.shade200,
              valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF5C6BC0)),
              minHeight: 8,
              borderRadius: BorderRadius.circular(4),
            ),
            const SizedBox(height: 12),
            Text(
              _statusMessage,
              style: TextStyle(
                color: Colors.grey.shade600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 取得連接模式的顯示名稱
  String _getModeDisplayName(String mode) {
    switch (mode.toUpperCase()) {
      case 'NORMAL':
        return 'Normal';
      case 'HOTPLUG':
        return 'Hot Plug';
      case 'UR':
        return 'Under Reset';
      default:
        return mode;
    }
  }

  /// 取得重置模式的顯示名稱
  String _getResetModeDisplayName(String mode) {
    switch (mode) {
      case 'SWrst':
        return 'Software Reset';
      case 'HWrst':
        return 'Hardware Reset';
      case 'Crst':
        return 'Core Reset';
      default:
        return mode;
    }
  }

  Widget _buildResultCard() {
    final result = _lastResult!;
    final isSuccess = result.success;

    // 根據 messageKey 和 messageParams 取得翻譯後的訊息
    String displayMessage;
    if (result.messageKey != null) {
      if (result.messageParams != null && result.messageParams!.isNotEmpty) {
        displayMessage = trParams(result.messageKey!, result.messageParams!);
      } else {
        displayMessage = tr(result.messageKey!);
      }
    } else {
      displayMessage = result.message;
    }

    return Card(
      elevation: 2,
      color: isSuccess ? Colors.green.shade50 : Colors.red.shade50,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  isSuccess ? Icons.check_circle : Icons.error,
                  color: isSuccess ? Colors.green : Colors.red,
                  size: 28,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    displayMessage,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: isSuccess ? Colors.green.shade700 : Colors.red.shade700,
                    ),
                  ),
                ),
              ],
            ),
            if (result.errorDetails != null) ...[
              const SizedBox(height: 12),
              Text(
                tr('cli_output'),
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: isSuccess ? Colors.green.shade700 : Colors.red.shade700,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                height: 200,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isSuccess ? Colors.green.shade200 : Colors.red.shade200,
                  ),
                ),
                child: SingleChildScrollView(
                  child: SelectableText(
                    result.errorDetails!,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                      color: isSuccess ? Colors.grey.shade800 : Colors.red.shade700,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
