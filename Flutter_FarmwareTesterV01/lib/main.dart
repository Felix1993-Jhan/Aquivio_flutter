// ============================================================================
// 命令控制應用程式 - 主程式入口
// ============================================================================
// 功能說明：
// 本程式用於同時管理 Arduino 和 STM32U073MCT6 兩個 USB 串口通訊
//
// 檔案結構：
// - lib/main.dart                            主程式入口與頁面
// - lib/services/serial_port_manager.dart    串口管理類別
// - lib/services/ur_command_builder.dart     UR 指令建構器
// - lib/services/data_storage_service.dart   數據儲存服務
// - lib/widgets/arduino_panel.dart           Arduino 控制面板
// - lib/widgets/ur_panel.dart                STM32 控制面板
// - lib/widgets/data_storage_page.dart       資料儲存頁面
// ============================================================================

import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_libserialport/flutter_libserialport.dart';
import 'package:window_manager/window_manager.dart';

import 'services/serial_port_manager.dart';
import 'services/ur_command_builder.dart';
import 'services/data_storage_service.dart';
import 'services/localization_service.dart';
import 'services/threshold_settings_service.dart';
import 'services/stlink_programmer_service.dart';
import 'widgets/arduino_panel.dart';
import 'widgets/ur_panel.dart';
import 'widgets/data_storage_page.dart';
import 'widgets/auto_detection_page.dart';
import 'widgets/settings_page.dart';
import 'widgets/splash_screen.dart';
import 'widgets/firmware_upload_page.dart';

// ==================== 應用程式入口 ====================

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 初始化視窗管理器並設定最小尺寸
  await windowManager.ensureInitialized();

  const windowOptions = WindowOptions(
    minimumSize: Size(800, 600),  // 最小寬度 800, 最小高度 600
    size: Size(1200, 800),        // 預設視窗大小
    center: true,
    title: 'Farmware Tester V01',
  );

  await windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
  });

  runApp(const MyApp());
}

/// 應用程式根 Widget
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Farmware Tester V01',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const SplashScreen(
        duration: Duration(milliseconds: 3000),
        child: MainNavigationPage(),
      ),
      debugShowCheckedModeBanner: false,
    );
  }
}

// ============================================================================
// MainNavigationPage - 主導航頁面（包含側邊抽屜）
// ============================================================================

class MainNavigationPage extends StatefulWidget {
  const MainNavigationPage({super.key});

  @override
  State<MainNavigationPage> createState() => _MainNavigationPageState();
}

class _MainNavigationPageState extends State<MainNavigationPage> {
  // ==================== 串口管理器 ====================

  final SerialPortManager _arduinoManager =
      SerialPortManager('Arduino', isTextMode: true);
  final SerialPortManager _urManager =
      SerialPortManager('UR', isTextMode: false);

  // ==================== 數據儲存服務 ====================

  final DataStorageService _dataStorage = DataStorageService();

  // ==================== 狀態變數 ====================

  String? _selectedArduinoPort;
  String? _selectedUrPort;
  List<String> _availablePorts = [];

  /// 當前選中的頁面索引
  int _selectedPageIndex = 0;

  /// Arduino flowon 是否啟動中
  bool _isFlowOn = false;

  /// 自動流量讀取定時器（flowon 啟動時每 2 秒讀取 STM32 flow ID 18）
  Timer? _flowReadTimer;

  /// 即時訊息（顯示在 AppBar 中）
  String _statusMessage = '';

  /// 訊息清除計時器
  Timer? _messageTimer;

  /// COM 埠監控定時器（每 1 秒檢查一次 COM 埠變化）
  Timer? _portMonitorTimer;

  /// 上次偵測到的 COM 埠列表（用於比較變化）
  List<String> _lastDetectedPorts = [];

  /// STM32 連接驗證超時計時器
  Timer? _urVerificationTimer;

  /// STM32 連接是否已驗證
  bool _urConnectionVerified = false;

  // ==================== 自動檢測流程狀態 ====================

  /// 是否正在進行自動檢測
  bool _isAutoDetecting = false;

  /// 自動檢測狀態文字
  String? _autoDetectionStatus;

  /// 自動檢測進度 (0.0 - 1.0)
  double _autoDetectionProgress = 0.0;

  /// 自動檢測是否被取消
  bool _autoDetectionCancelled = false;

  /// 當前正在讀取的項目 ID（用於高亮顯示）
  int? _currentReadingId;

  /// 當前正在讀取的區域類型（idle / running / sensor）
  String? _currentReadingSection;

  // ==================== ST-Link 燒入相關狀態 ====================

  /// ST-Link 服務
  final StLinkProgrammerService _stLinkService = StLinkProgrammerService();

  /// ST-Link 是否已連接
  bool _isStLinkConnected = false;

  /// ST-Link 連接資訊
  StLinkInfo? _stLinkInfo;

  /// 韌體檔案列表
  List<FileSystemEntity> _firmwareFiles = [];

  /// 選中的韌體檔案路徑
  String? _selectedFirmwarePath;

  /// ST-Link 頻率 (kHz)
  int _stLinkFrequency = StLinkProgrammerService.defaultFrequency;

  /// 是否正在燒入
  bool _isProgramming = false;

  /// 燒入進度 (0.0 - 1.0)
  double _programProgress = 0.0;

  /// 燒入狀態訊息
  String? _programStatus;

  // ==================== UI 控制器 ====================

  final TextEditingController _urHexController = TextEditingController();
  final TextEditingController _flowController = TextEditingController();

  // ==================== 生命週期 ====================

  @override
  void initState() {
    super.initState();

    // 初始化閾值設定服務
    _initThresholdService();

    // 設置 Arduino 數據接收回調
    _arduinoManager.onDataReceived = (int id, int value) {
      _dataStorage.saveArduinoData(id, value);
    };

    // 設置 STM32 數據接收回調
    _urManager.onDataReceived = (int id, int value) {
      _dataStorage.saveStm32Data(id, value);
    };

    // 設置 STM32 韌體版本回調
    // 當收到韌體版本後，自動發送初始化指令
    _urManager.onFirmwareVersionReceived = (String version) {
      _showSnackBar(tr('stm32_firmware_version').replaceAll('{version}', version));
      // 1. 發送關閉全部 IO 指令: 0x02 FF FF 03 00
      // FF FF 03 = 24-bit 位元遮罩 (ID 0-17 全部)
      Future.delayed(const Duration(milliseconds: 200), () {
        if (_urManager.isConnected) {
          final payload = [0x02, 0xFF, 0xFF, 0x03, 0x00];
          _sendUrCommand(payload);
        }
      });
      // 2. 發送清除流量計指令: 0x04 + ID 18 (0x12)
      Future.delayed(const Duration(milliseconds: 400), () {
        if (_urManager.isConnected) {
          final clearFlowPayload = [0x04, 0x12, 0x00, 0x00, 0x00];
          _sendUrCommand(clearFlowPayload);
        }
      });
    };

    // 設置 STM32 連接驗證回調
    _urManager.onConnectionVerified = (bool success) {
      _cancelUrVerificationTimeout();
      if (success) {
        _urConnectionVerified = true;
        // 連接驗證成功，啟動心跳機制
        _urManager.startHeartbeat();
        // 連接驗證成功，發送 flowoff 到 Arduino
        _sendArduinoFlowoff();
      }
    };

    // 設置 Arduino 心跳失敗回調
    _arduinoManager.onHeartbeatFailed = () {
      _handleArduinoHeartbeatFailed();
    };

    // 設置 STM32 心跳失敗回調
    _urManager.onHeartbeatFailed = () {
      _handleStm32HeartbeatFailed();
    };

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshPorts();
      _startPortMonitor();  // 啟動 COM 埠監控
      _initStLinkService(); // 初始化 ST-Link 服務
    });
  }

  /// 初始化 ST-Link 服務
  Future<void> _initStLinkService() async {
    // 設定狀態回調
    _stLinkService.onStatusChanged = (status, progress, message) {
      if (mounted) {
        setState(() {
          _programProgress = progress;
          _programStatus = message;
        });
      }
    };

    // 檢查 CLI 是否存在並檢查連接
    final cliExists = await _stLinkService.checkCliExists();
    if (cliExists) {
      await _checkStLinkConnection();
    }

    // 掃描韌體檔案
    await _scanFirmwareFiles();
  }

  /// 檢查 ST-Link 連接狀態
  Future<void> _checkStLinkConnection() async {
    final info = await _stLinkService.checkStLinkConnection();
    if (mounted) {
      setState(() {
        _isStLinkConnected = info.isConnected;
        _stLinkInfo = info;
      });
    }
  }

  /// 掃描韌體資料夾中的檔案
  Future<void> _scanFirmwareFiles() async {
    try {
      // 取得應用程式執行路徑
      final exePath = Platform.resolvedExecutable;
      final exeDir = Directory(exePath).parent.path;
      final firmwareDir = Directory('$exeDir${Platform.pathSeparator}firmware');

      if (!await firmwareDir.exists()) {
        await firmwareDir.create();
      }

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
          // 如果只有一個韌體檔案，自動選擇
          if (files.length == 1) {
            _selectedFirmwarePath = files.first.path;
          }
        });
      }
    } catch (e) {
      // 忽略錯誤
    }
  }

  /// 初始化閾值設定服務
  Future<void> _initThresholdService() async {
    await ThresholdSettingsService().init();
  }

  @override
  void dispose() {
    _portMonitorTimer?.cancel();
    _flowReadTimer?.cancel();
    _messageTimer?.cancel();
    _urVerificationTimer?.cancel();
    _arduinoManager.dispose();
    _urManager.dispose();
    _dataStorage.dispose();
    _urHexController.dispose();
    _flowController.dispose();
    super.dispose();
  }

  // ==================== COM 埠監控 ====================

  /// 啟動 COM 埠監控（每 1 秒檢查一次）
  /// 當偵測到 COM 埠變化時：
  /// - 移除：檢查並斷開已拔除的連接
  /// - 新增：自動更新可用列表
  void _startPortMonitor() {
    // 初始化已知的 COM 埠列表
    _lastDetectedPorts = List.from(_availablePorts);

    _portMonitorTimer?.cancel();
    _portMonitorTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _checkPortChanges();
    });
  }

  /// 檢查 COM 埠變化
  void _checkPortChanges() {
    List<String> currentPorts;
    try {
      currentPorts = SerialPort.availablePorts;
    } catch (e) {
      // 如果獲取失敗，不做任何操作
      return;
    }

    // 找出被移除的 COM 埠
    final removedPorts = _lastDetectedPorts
        .where((port) => !currentPorts.contains(port))
        .toList();

    // 找出新增的 COM 埠
    final addedPorts = currentPorts
        .where((port) => !_lastDetectedPorts.contains(port))
        .toList();

    // 處理被移除的 COM 埠
    if (removedPorts.isNotEmpty) {
      for (final removedPort in removedPorts) {
        // 檢查 Arduino（已連接）
        if (_arduinoManager.isConnected &&
            _arduinoManager.currentPortName == removedPort) {
          _handleArduinoDisconnected();
        }

        // 檢查 STM32（已連接）
        if (_urManager.isConnected &&
            _urManager.currentPortName == removedPort) {
          _handleStm32Disconnected();
        }
      }
    }

    // 如果有 COM 埠變化（新增或移除），更新可用列表
    if (removedPorts.isNotEmpty || addedPorts.isNotEmpty) {
      if (mounted) {
        setState(() {
          _availablePorts = List.from(currentPorts);

          // 清除已不存在的選擇（無論是否已連接）
          // 這確保 DropdownButton 的 value 永遠有效
          if (_selectedArduinoPort != null &&
              !currentPorts.contains(_selectedArduinoPort)) {
            _selectedArduinoPort = null;
          }
          if (_selectedUrPort != null &&
              !currentPorts.contains(_selectedUrPort)) {
            _selectedUrPort = null;
          }
        });

        // 顯示變化訊息
        if (addedPorts.isNotEmpty) {
          _showSnackBar(tr('new_com_port_detected').replaceAll('{ports}', addedPorts.join(", ")));
        }
      }
    }

    // 更新上次偵測的列表
    _lastDetectedPorts = List.from(currentPorts);
  }

  /// 處理 Arduino USB 斷開
  void _handleArduinoDisconnected() {
    _stopAutoFlowRead();  // 停止自動流量讀取
    _arduinoManager.forceClose();  // 強制關閉連接
    if (mounted) {
      setState(() {
        _selectedArduinoPort = null;  // 清除選中的 port
      });
      _showSnackBar(tr('arduino_usb_removed'));
    }
  }

  /// 處理 Arduino 心跳失敗（連接可能已斷開或連接錯誤）
  void _handleArduinoHeartbeatFailed() {
    _stopAutoFlowRead();  // 停止自動流量讀取
    _arduinoManager.forceClose();  // 強制關閉連接
    if (mounted) {
      setState(() {
        _selectedArduinoPort = null;  // 清除選中的 port
      });
      _showErrorDialog(tr('arduino_connection_error'));
    }
  }

  /// 處理 STM32 USB 斷開
  void _handleStm32Disconnected() {
    _cancelUrVerificationTimeout();  // 取消驗證超時
    _urManager.forceClose();  // 強制關閉連接
    if (mounted) {
      setState(() {
        _selectedUrPort = null;  // 清除選中的 port
      });
      _showSnackBar(tr('stm32_usb_removed'));
    }
  }

  /// 處理 STM32 心跳失敗（連接可能已斷開或連接錯誤）
  void _handleStm32HeartbeatFailed() {
    _cancelUrVerificationTimeout();  // 取消驗證超時
    _sendArduinoFlowoff();  // 發送 flowoff 到 Arduino
    _urManager.forceClose();  // 強制關閉連接
    if (mounted) {
      setState(() {
        _selectedUrPort = null;  // 清除選中的 port
      });
      _showErrorDialog(tr('stm32_connection_error'));
    }
  }

  // ==================== 串口操作 ====================

  /// 刷新可用 COM 埠列表
  void _refreshPorts() {
    setState(() {
      _availablePorts = SerialPort.availablePorts;
    });

    if (_availablePorts.isEmpty) {
      _showSnackBar(tr('no_com_port'));
    } else {
      _showSnackBar(tr('com_port_detected').replaceAll('{count}', '${_availablePorts.length}'));
    }
  }

  void _showSnackBar(String message) {
    _messageTimer?.cancel();
    setState(() {
      _statusMessage = message;
    });
    // 2 秒後自動清除訊息
    _messageTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() {
          _statusMessage = '';
        });
      }
    });
  }

  /// 顯示錯誤提示對話框（畫面中央，2秒後自動關閉）
  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black54,
      builder: (BuildContext dialogContext) {
        // 2秒後自動關閉
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted && Navigator.of(dialogContext).canPop()) {
            Navigator.of(dialogContext).pop();
          }
        });

        return AlertDialog(
          backgroundColor: Colors.red.shade50,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: Colors.red.shade400, width: 2),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, color: Colors.red.shade700, size: 64),
              const SizedBox(height: 16),
              Text(
                message,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.red.shade800,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        );
      },
    );
  }

  // ==================== Arduino 操作 ====================

  /// Arduino 連接重試計數
  int _arduinoConnectRetryCount = 0;

  /// Arduino 連接重試最大次數
  static const int _maxConnectRetry = 6;

  void _connectArduino() {
    if (_selectedArduinoPort == null) {
      _showSnackBar(tr('select_arduino_port'));
      return;
    }
    if (_selectedArduinoPort == _selectedUrPort && _urManager.isConnected) {
      _showSnackBar(tr('arduino_port_in_use'));
      return;
    }

    _arduinoConnectRetryCount = 0;
    _tryConnectArduino();
  }

  /// 嘗試連接 Arduino（支援自動重試）
  void _tryConnectArduino() {
    if (_selectedArduinoPort == null) return;

    if (_arduinoManager.open(_selectedArduinoPort!)) {
      _arduinoManager.startHeartbeat();  // 啟動心跳機制
      setState(() {});
      _showSnackBar(tr('arduino_connected'));
      _arduinoConnectRetryCount = 0;
      // 連接成功後發送 flowoff
      Future.delayed(const Duration(milliseconds: 500), () {
        _sendArduinoFlowoff();
      });
    } else {
      _arduinoConnectRetryCount++;
      if (_arduinoConnectRetryCount < _maxConnectRetry) {
        // 連接失敗，500ms 後自動重試
        _showSnackBar(tr('arduino_connecting').replaceAll('{current}', '$_arduinoConnectRetryCount').replaceAll('{max}', '$_maxConnectRetry'));
        Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted && !_arduinoManager.isConnected) {
            _tryConnectArduino();
          }
        });
      } else {
        _showSnackBar(tr('arduino_connect_failed'));
        _arduinoConnectRetryCount = 0;
      }
    }
  }

  void _disconnectArduino() {
    _sendArduinoFlowoff();  // 斷開前發送 flowoff
    _stopAutoFlowRead();  // 斷開時停止自動流量讀取
    _arduinoManager.close();
    setState(() {});
    _showSnackBar(tr('arduino_disconnected'));
  }

  /// 發送 flowoff 指令到 Arduino（如果已連接）
  void _sendArduinoFlowoff() {
    if (_arduinoManager.isConnected) {
      _arduinoManager.sendString('flowoff');
    }
  }

  void _sendArduinoCommand(String command) {
    if (!_arduinoManager.isConnected) {
      _showSnackBar(tr('connect_arduino_first'));
      return;
    }
    _arduinoManager.sendString(command);

    // 追蹤 flowon/flowoff 狀態
    final lowerCommand = command.toLowerCase();
    if (lowerCommand == 'flowon' || lowerCommand.startsWith('flowon')) {
      _startAutoFlowRead();
    } else if (lowerCommand == 'flowoff') {
      // flowoff: 停止自動讀取 → 讀取一次 flow → 清除 flow
      _stopAutoFlowReadAndClear();
    }
  }

  /// 啟動自動流量讀取（每 2 秒讀取 STM32 flow ID 18）
  void _startAutoFlowRead() {
    if (_isFlowOn) return;  // 已經在運行中

    _isFlowOn = true;
    _flowReadTimer?.cancel();
    _flowReadTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (_urManager.isConnected && _isFlowOn) {
        // 發送 0x03 讀取指令讀取 ID 18 (flow)
        final payload = [0x03, 18, 0x00, 0x00, 0x00];
        final cmd = URCommandBuilder.buildCommand(payload);
        _urManager.sendHex(cmd);
      }
    });
  }

  /// 停止自動流量讀取
  void _stopAutoFlowRead() {
    _isFlowOn = false;
    _flowReadTimer?.cancel();
    _flowReadTimer = null;
  }

  /// 停止自動流量讀取並執行 flowoff 後續動作
  /// 1. 停止自動讀取
  /// 2. 讀取一次 STM32 flow 數值
  /// 3. 發送清除 flow 指令
  void _stopAutoFlowReadAndClear() {
    _stopAutoFlowRead();

    if (_urManager.isConnected) {
      // 讀取一次 flow 數值 (ID 18)
      final readPayload = [0x03, 18, 0x00, 0x00, 0x00];
      final readCmd = URCommandBuilder.buildCommand(readPayload);
      _urManager.sendHex(readCmd);

      // 延遲 500ms 後發送清除 flow 指令
      Future.delayed(const Duration(milliseconds: 500), () {
        if (_urManager.isConnected) {
          // 清除流量計指令: 0x04 + ID 18 (0x12)
          final clearPayload = [0x04, 0x12, 0x00, 0x00, 0x00];
          final clearCmd = URCommandBuilder.buildCommand(clearPayload);
          _urManager.sendHex(clearCmd);
        }
      });
    }
  }

  // ==================== STM32 操作 ====================

  /// STM32 連接重試計數
  int _urConnectRetryCount = 0;

  /// STM32 連接驗證超時時間（毫秒）
  static const int _urVerificationTimeoutMs = 2000;

  /// 取消 STM32 連接驗證超時
  void _cancelUrVerificationTimeout() {
    _urVerificationTimer?.cancel();
    _urVerificationTimer = null;
  }

  /// 啟動 STM32 連接驗證超時計時器
  void _startUrVerificationTimeout() {
    _cancelUrVerificationTimeout();
    _urConnectionVerified = false;

    _urVerificationTimer = Timer(Duration(milliseconds: _urVerificationTimeoutMs), () {
      // 超時未收到正確回應
      if (!_urConnectionVerified && _urManager.isConnected) {
        _urManager.close();
        setState(() {});
        _showErrorDialog(tr('stm32_wrong_port'));
      }
    });
  }

  void _connectUr() {
    if (_selectedUrPort == null) {
      _showSnackBar(tr('select_stm32_port'));
      return;
    }
    if (_selectedUrPort == _selectedArduinoPort && _arduinoManager.isConnected) {
      _showSnackBar(tr('stm32_port_in_use'));
      return;
    }

    _urConnectRetryCount = 0;
    _tryConnectUr();
  }

  /// 嘗試連接 STM32（支援自動重試）
  void _tryConnectUr() {
    if (_selectedUrPort == null) return;

    if (_urManager.open(_selectedUrPort!)) {
      setState(() {});
      _showSnackBar(tr('stm32_verifying'));
      _urConnectRetryCount = 0;

      // 啟動連接驗證超時（2秒內需收到正確回應）
      _startUrVerificationTimeout();

      // 連接成功後自動查詢韌體版本（作為 PING）
      // 指令: 40 71 30 05 00 00 00 00 [CS]
      // payload: [0x05, 0x00, 0x00, 0x00, 0x00]
      Future.delayed(const Duration(milliseconds: 300), () {
        if (_urManager.isConnected) {
          final payload = [0x05, 0x00, 0x00, 0x00, 0x00];
          final cmd = URCommandBuilder.buildCommand(payload);
          _urManager.sendHex(cmd);
        }
      });
    } else {
      _urConnectRetryCount++;
      if (_urConnectRetryCount < _maxConnectRetry) {
        // 連接失敗，500ms 後自動重試
        _showSnackBar(tr('stm32_connecting').replaceAll('{current}', '$_urConnectRetryCount').replaceAll('{max}', '$_maxConnectRetry'));
        Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted && !_urManager.isConnected) {
            _tryConnectUr();
          }
        });
      } else {
        _showSnackBar(tr('stm32_connect_failed'));
        _urConnectRetryCount = 0;
      }
    }
  }

  void _disconnectUr() {
    _cancelUrVerificationTimeout();  // 斷開時取消驗證超時
    _sendArduinoFlowoff();  // 斷開時發送 flowoff 到 Arduino
    _urManager.close();
    setState(() {});
    _showSnackBar(tr('stm32_disconnected'));
  }

  void _sendUrCommand(List<int> payload) {
    if (!_urManager.isConnected) {
      _showSnackBar(tr('connect_stm32_first'));
      return;
    }
    final cmd = URCommandBuilder.buildCommand(payload);
    _urManager.sendHex(cmd);

    // 根據指令類型更新硬體狀態（Arduino 和 STM32 共用此狀態）
    // 0x01/0x02 指令格式: [命令, lowByte, midByte, highByte, 0x00]
    // lowByte/midByte/highByte 組成 24-bit 位元遮罩，每一位代表一個 ID
    if (payload.length >= 4) {
      final command = payload[0];
      if (command == 0x01 || command == 0x02) {
        // 從 payload 提取 24-bit 位元遮罩
        final lowByte = payload[1];
        final midByte = payload[2];
        final highByte = payload[3];
        final bitMask = lowByte | (midByte << 8) | (highByte << 16);

        // 檢查每個 ID (0-23) 是否在位元遮罩中被設置
        for (int id = 0; id < 24; id++) {
          if ((bitMask & (1 << id)) != 0) {
            // 此 ID 被選中，更新其硬體狀態
            final state = (command == 0x01)
                ? HardwareState.running
                : HardwareState.idle;
            _dataStorage.setHardwareState(id, state);
          }
        }
      }
    }
  }

  void _sendUrFromInput() {
    if (!_urManager.isConnected) {
      _showSnackBar(tr('connect_stm32_first'));
      return;
    }

    final input = _urHexController.text.trim();
    if (input.isEmpty) {
      _showSnackBar(tr('enter_payload'));
      return;
    }

    try {
      final hexStr = input.replaceAll(' ', '').replaceAll(',', '');
      if (hexStr.length % 2 != 0) {
        _showSnackBar(tr('hex_length_error'));
        return;
      }

      List<int> payload = [];
      for (int i = 0; i < hexStr.length; i += 2) {
        payload.add(int.parse(hexStr.substring(i, i + 2), radix: 16));
      }

      // 使用 _sendUrCommand 以便同時追蹤硬體狀態
      _sendUrCommand(payload);
    } catch (e) {
      _showSnackBar(tr('parse_error').replaceAll('{error}', '$e'));
    }
  }

  // ==================== 快速讀取操作 ====================

  /// Arduino 快速讀取
  void _onArduinoQuickRead(String command) {
    if (!_arduinoManager.isConnected) {
      _showSnackBar(tr('connect_arduino_first'));
      return;
    }
    _sendArduinoCommand(command);
    _showSnackBar(tr('sent_arduino_command').replaceAll('{command}', command));
  }

  /// STM32 快速讀取 (使用 0x03 指令)
  void _onStm32QuickRead(int id) {
    if (!_urManager.isConnected) {
      _showSnackBar(tr('connect_stm32_first'));
      return;
    }
    // 建構 0x03 讀取指令: [0x03, ID, 0x00, 0x00, 0x00]
    // 格式: 命令(1) + ID(1) + 數值(3 bytes, 讀取時填0)
    final payload = [0x03, id, 0x00, 0x00, 0x00];
    _sendUrCommand(payload);
    _showSnackBar(tr('sent_stm32_read_command').replaceAll('{id}', '$id'));
  }

  // ==================== UI 建構 ====================

  @override
  Widget build(BuildContext context) {
    // 監聽語言變更，自動更新 UI
    return ValueListenableBuilder<AppLanguage>(
      valueListenable: LocalizationService().currentLanguageNotifier,
      builder: (context, _, __) {
        return Scaffold(
          appBar: AppBar(
            title: Row(
              children: [
                Text(_getPageTitle()),
                const SizedBox(width: 16),
                // 即時訊息顯示
                if (_statusMessage.isNotEmpty)
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text(
                        _statusMessage,
                        style: const TextStyle(fontSize: 12, color: Colors.white),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
              ],
            ),
            backgroundColor: Theme.of(context).colorScheme.inversePrimary,
            actions: [
              IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: _refreshPorts,
                tooltip: tr('refresh'),
              ),
            ],
          ),
          drawer: _buildDrawer(),
          body: _buildBody(),
        );
      },
    );
  }

  /// 取得當前頁面標題
  String _getPageTitle() {
    switch (_selectedPageIndex) {
      case 0:
        return tr('page_auto_detection');
      case 1:
        return tr('page_command_control');
      case 2:
        return tr('page_data_storage');
      case 3:
        return tr('page_firmware_upload');
      case 4:
        return tr('page_settings');
      default:
        return tr('page_auto_detection');
    }
  }

  /// 建構側邊抽屜
  Widget _buildDrawer() {
    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          // 抽屜標題
          DrawerHeader(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  EmeraldColors.primary,
                  SkyBlueColors.primary,
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                const Icon(
                  Icons.settings_input_hdmi,
                  color: Colors.white,
                  size: 48,
                ),
                const SizedBox(height: 8),
                Text(
                  tr('drawer_title'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  tr('drawer_subtitle'),
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
          // 頁面選項 1: 自動檢測流程-雙串口（預設頁面）
          ListTile(
            leading: const Icon(Icons.fact_check),
            title: Text(tr('page_auto_detection')),
            selected: _selectedPageIndex == 0,
            selectedTileColor: Colors.blue.shade50,
            onTap: () {
              setState(() => _selectedPageIndex = 0);
              Navigator.pop(context);
            },
          ),
          // 頁面選項 2: 命令控制
          ListTile(
            leading: const Icon(Icons.usb),
            title: Text(tr('page_command_control')),
            selected: _selectedPageIndex == 1,
            selectedTileColor: Colors.blue.shade50,
            onTap: () {
              setState(() => _selectedPageIndex = 1);
              Navigator.pop(context);
            },
          ),
          // 頁面選項 3: 資料儲存
          ListTile(
            leading: const Icon(Icons.storage),
            title: Text(tr('page_data_storage')),
            selected: _selectedPageIndex == 2,
            selectedTileColor: Colors.blue.shade50,
            onTap: () {
              setState(() => _selectedPageIndex = 2);
              Navigator.pop(context);
            },
          ),
          // 頁面選項 4: 韌體燒錄
          ListTile(
            leading: const Icon(Icons.memory),
            title: Text(tr('page_firmware_upload')),
            selected: _selectedPageIndex == 3,
            selectedTileColor: Colors.blue.shade50,
            onTap: () {
              setState(() => _selectedPageIndex = 3);
              Navigator.pop(context);
            },
          ),
          // 頁面選項 5: 設定
          ListTile(
            leading: const Icon(Icons.settings),
            title: Text(tr('page_settings')),
            selected: _selectedPageIndex == 4,
            selectedTileColor: Colors.blue.shade50,
            onTap: () {
              setState(() => _selectedPageIndex = 4);
              Navigator.pop(context);
            },
          ),
          const Divider(),
          // 連接狀態顯示
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tr('connection_status'),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.grey,
                  ),
                ),
                const SizedBox(height: 8),
                _buildConnectionStatus(
                  'Arduino',
                  _arduinoManager.isConnected,
                  EmeraldColors.primary,
                ),
                const SizedBox(height: 4),
                _buildConnectionStatus(
                  'STM32',
                  _urManager.isConnected,
                  SkyBlueColors.primary,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 建構連接狀態指示器
  Widget _buildConnectionStatus(String name, bool isConnected, Color color) {
    return Row(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isConnected ? Colors.green : Colors.red,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          name,
          style: TextStyle(color: color, fontWeight: FontWeight.w500),
        ),
        const Spacer(),
        Text(
          isConnected ? tr('connected') : tr('disconnected'),
          style: TextStyle(
            color: isConnected ? Colors.green : Colors.red,
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  /// 建構頁面內容
  Widget _buildBody() {
    switch (_selectedPageIndex) {
      case 0:
        return _buildAutoDetectionPage();
      case 1:
        return _buildDualSerialPage();
      case 2:
        return _buildDataStoragePage();
      case 3:
        return FirmwareUploadPage(
          isStm32Connected: _urManager.isConnected,
          onDisconnectStm32: _disconnectUr,
        );
      case 4:
        return const SettingsPage();
      default:
        return _buildAutoDetectionPage();
    }
  }

  /// 建構雙串口控制頁面
  Widget _buildDualSerialPage() {
    return Row(
      children: [
        // 左側：Arduino 控制區
        Expanded(
          child: ArduinoPanel(
            manager: _arduinoManager,
            selectedPort: _selectedArduinoPort,
            availablePorts: _availablePorts,
            flowController: _flowController,
            onPortChanged: (value) {
              setState(() => _selectedArduinoPort = value);
            },
            onConnect: _connectArduino,
            onDisconnect: _disconnectArduino,
            onSendCommand: _sendArduinoCommand,
          ),
        ),
        const VerticalDivider(width: 1),
        // 右側：STM32 控制區
        Expanded(
          child: UrPanel(
            manager: _urManager,
            selectedPort: _selectedUrPort,
            availablePorts: _availablePorts,
            hexController: _urHexController,
            onPortChanged: (value) {
              setState(() => _selectedUrPort = value);
            },
            onConnect: _connectUr,
            onDisconnect: _disconnectUr,
            onSendPayload: _sendUrCommand,
            onSendFromInput: _sendUrFromInput,
          ),
        ),
      ],
    );
  }

  /// 建構資料儲存頁面
  Widget _buildDataStoragePage() {
    return DataStoragePage(
      dataStorage: _dataStorage,
      onArduinoQuickRead: _onArduinoQuickRead,
      onStm32QuickRead: _onStm32QuickRead,
      onStm32SendCommand: _onStm32SendCommand,
    );
  }

  // ==================== 自動檢測流程 ====================

  /// 更新自動檢測狀態
  void _updateAutoDetectionStatus(String status, double progress) {
    if (mounted) {
      setState(() {
        _autoDetectionStatus = status;
        _autoDetectionProgress = progress;
      });
    }
  }

  /// 開始自動檢測流程
  Future<void> _startAutoDetection() async {
    if (_isAutoDetecting) return;

    // 清除所有數據，初始化頁面
    _dataStorage.clearAllData();

    setState(() {
      _isAutoDetecting = true;
      _autoDetectionCancelled = false;
      _autoDetectionStatus = tr('auto_detection_step_connect');
      _autoDetectionProgress = 0.0;
    });

    try {
      // 步驟 1: 連接設備
      _updateAutoDetectionStatus(tr('auto_detection_step_connect'), 0.0);
      final connectResult = await _autoDetectionStep1Connect();
      if (!connectResult || _autoDetectionCancelled) {
        _endAutoDetection();
        return;
      }

      // 步驟 2: 讀取無動作狀態 (Idle)
      _updateAutoDetectionStatus(tr('auto_detection_step_idle'), 0.17);
      final idleResult = await _autoDetectionStep2ReadIdle();
      if (!idleResult || _autoDetectionCancelled) {
        _endAutoDetection();
        return;
      }

      // 步驟 3: 讀取動作中狀態 (Running)
      _updateAutoDetectionStatus(tr('auto_detection_step_running'), 0.33);
      final runningResult = await _autoDetectionStep3ReadRunning();
      if (!runningResult || _autoDetectionCancelled) {
        _endAutoDetection();
        return;
      }

      // 步驟 4: 關閉 GPIO
      _updateAutoDetectionStatus(tr('auto_detection_step_close'), 0.50);
      await _autoDetectionStep4CloseGpio();
      if (_autoDetectionCancelled) {
        _endAutoDetection();
        return;
      }

      // 步驟 5: 感測器測試
      _updateAutoDetectionStatus(tr('auto_detection_step_sensor'), 0.67);
      final sensorResult = await _autoDetectionStep5SensorTest();
      if (!sensorResult || _autoDetectionCancelled) {
        _endAutoDetection();
        return;
      }

      // 步驟 6: 結果判定
      _updateAutoDetectionStatus(tr('auto_detection_step_result'), 0.83);
      await Future.delayed(const Duration(milliseconds: 500));
      _autoDetectionStep6ShowResult();

    } catch (e) {
      _showSnackBar('自動檢測錯誤: $e');
    } finally {
      _endAutoDetection();
    }
  }

  /// 結束自動檢測
  void _endAutoDetection() {
    if (mounted) {
      setState(() {
        _isAutoDetecting = false;
        _autoDetectionProgress = 1.0;
      });
    }
  }

  /// 步驟 1: 連接設備
  /// 先逐一嘗試連接 Arduino，成功後再逐一嘗試連接 STM32
  Future<bool> _autoDetectionStep1Connect() async {
    // 先刷新 COM 埠列表，確保有最新的可用埠
    _refreshPorts();
    await Future.delayed(const Duration(milliseconds: 300));

    // 檢查是否有可用的 COM 埠
    if (_availablePorts.isEmpty) {
      _showSnackBar(tr('usb_not_connected'));
      return false;
    }

    // ===== 第一階段：連接 Arduino =====
    if (!_arduinoManager.isConnected) {
      _updateAutoDetectionStatus(tr('connecting_arduino'), 0.02);

      // 建立要嘗試的 COM 埠列表
      // 如果已選擇的埠有效，優先嘗試；否則從第一個開始
      final portsToTry = <String>[];
      if (_selectedArduinoPort != null && _availablePorts.contains(_selectedArduinoPort)) {
        portsToTry.add(_selectedArduinoPort!);
        portsToTry.addAll(_availablePorts.where((p) => p != _selectedArduinoPort));
      } else {
        portsToTry.addAll(_availablePorts);
      }

      bool arduinoConnected = false;

      // 逐一嘗試每個 COM 埠
      for (int i = 0; i < portsToTry.length && !arduinoConnected; i++) {
        if (_autoDetectionCancelled) return false;

        final port = portsToTry[i];
        _updateAutoDetectionStatus(
          '${tr('connecting_arduino')} ($port, ${i + 1}/${portsToTry.length})',
          0.02 + (i * 0.02)
        );

        // 嘗試開啟連接埠
        if (_arduinoManager.open(port)) {
          // 等待一下讓連接穩定（Arduino 重置後需要時間初始化）
          await Future.delayed(const Duration(milliseconds: 1000));

          // 發送測試指令驗證是否為 Arduino
          _arduinoManager.sendString('s0');
          await Future.delayed(const Duration(milliseconds: 1000));

          // 檢查是否收到有效回應（Arduino 會回應數值）
          final testData = _dataStorage.getArduinoLatestIdleData(0) ??
                          _dataStorage.getArduinoLatestRunningData(0);

          if (testData != null) {
            // 確認是 Arduino，連接成功
            _arduinoManager.startHeartbeat();
            arduinoConnected = true;
            setState(() => _selectedArduinoPort = port);

            // 清除測試數據
            _dataStorage.clearAllData();
          } else {
            // 不是 Arduino，關閉連接，嘗試下一個
            _arduinoManager.close();
          }
        }

        // 短暫延遲再嘗試下一個
        if (!arduinoConnected && i < portsToTry.length - 1) {
          await Future.delayed(const Duration(milliseconds: 200));
        }
      }

      if (!arduinoConnected) {
        _showSnackBar(tr('arduino_connect_failed'));
        return false;
      }

      // Arduino 連接成功，發送 flowoff
      await Future.delayed(const Duration(milliseconds: 300));
      _sendArduinoFlowoff();
    }

    // ===== 第二階段：連接 STM32 =====
    if (!_urManager.isConnected) {
      _updateAutoDetectionStatus(tr('connecting_stm32'), 0.08);

      // 取得剩餘可用的 COM 埠（排除 Arduino 使用的）
      final availableForStm32 = _availablePorts
          .where((p) => p != _arduinoManager.currentPortName)
          .toList();

      if (availableForStm32.isEmpty) {
        _showSnackBar(tr('usb_not_connected'));
        return false;
      }

      // 建立要嘗試的 COM 埠列表
      final portsToTry = <String>[];
      if (_selectedUrPort != null && availableForStm32.contains(_selectedUrPort)) {
        portsToTry.add(_selectedUrPort!);
        portsToTry.addAll(availableForStm32.where((p) => p != _selectedUrPort));
      } else {
        portsToTry.addAll(availableForStm32);
      }

      bool stm32Connected = false;

      // 逐一嘗試每個 COM 埠
      for (int i = 0; i < portsToTry.length && !stm32Connected; i++) {
        if (_autoDetectionCancelled) return false;

        final port = portsToTry[i];
        _updateAutoDetectionStatus(
          '${tr('connecting_stm32')} ($port, ${i + 1}/${portsToTry.length})',
          0.08 + (i * 0.02)
        );

        // 嘗試開啟連接埠
        if (_urManager.open(port)) {
          // 發送韌體版本查詢來驗證是否為 STM32
          final payload = [0x05, 0x00, 0x00, 0x00, 0x00];
          final cmd = URCommandBuilder.buildCommand(payload);
          _urManager.sendHex(cmd);

          // 等待驗證回應
          await Future.delayed(const Duration(milliseconds: 1500));

          if (_urManager.firmwareVersionNotifier.value != null) {
            // 確認是 STM32，連接成功
            _urManager.startHeartbeat();
            stm32Connected = true;
            setState(() => _selectedUrPort = port);
          } else {
            // 不是 STM32，關閉連接，嘗試下一個
            _urManager.close();
          }
        }

        // 短暫延遲再嘗試下一個
        if (!stm32Connected && i < portsToTry.length - 1) {
          await Future.delayed(const Duration(milliseconds: 200));
        }
      }

      if (!stm32Connected) {
        _showSnackBar(tr('stm32_connect_failed'));
        return false;
      }
    }

    // 確認兩者都已連接
    return _arduinoManager.isConnected && _urManager.isConnected;
  }

  /// 步驟 2: 讀取無動作狀態 (Idle)
  Future<bool> _autoDetectionStep2ReadIdle() async {
    const maxRetries = 3;

    // 發送關閉全部 GPIO 指令
    final closePayload = [0x02, 0xFF, 0xFF, 0x03, 0x00];
    _sendUrCommand(closePayload);
    await Future.delayed(const Duration(milliseconds: 500));

    for (int retry = 0; retry < maxRetries; retry++) {
      if (_autoDetectionCancelled) return false;

      if (retry > 0) {
        _updateAutoDetectionStatus(
          tr('retry_step').replaceAll('{current}', '$retry').replaceAll('{max}', '$maxRetries'),
          0.20
        );
        await Future.delayed(const Duration(milliseconds: 500));
      }

      // 同時讀取 Arduino 和 STM32 硬體數據 (ID 0-17)
      _updateAutoDetectionStatus(tr('reading_hardware_data'), 0.20);
      await _batchReadHardwareParallel(HardwareState.idle);

      // 檢查是否所有 ID 都有數據
      bool allDataReceived = true;
      for (int id = 0; id < 18; id++) {
        if (_dataStorage.getArduinoLatestIdleData(id) == null ||
            _dataStorage.getStm32LatestIdleData(id) == null) {
          allDataReceived = false;
          break;
        }
      }

      if (allDataReceived) return true;
    }

    return false;
  }

  /// 步驟 3: 讀取動作中狀態 (Running)
  Future<bool> _autoDetectionStep3ReadRunning() async {
    const maxRetries = 3;

    // 發送開啟全部 GPIO 指令
    final openPayload = [0x01, 0xFF, 0xFF, 0x03, 0x00];
    _sendUrCommand(openPayload);
    await Future.delayed(const Duration(milliseconds: 500));

    for (int retry = 0; retry < maxRetries; retry++) {
      if (_autoDetectionCancelled) return false;

      if (retry > 0) {
        _updateAutoDetectionStatus(
          tr('retry_step').replaceAll('{current}', '$retry').replaceAll('{max}', '$maxRetries'),
          0.40
        );
        await Future.delayed(const Duration(milliseconds: 500));
      }

      // 同時讀取 Arduino 和 STM32 硬體數據 (ID 0-17)
      _updateAutoDetectionStatus(tr('reading_hardware_data'), 0.38);
      await _batchReadHardwareParallel(HardwareState.running);

      // 檢查是否所有 ID 都有數據
      bool allDataReceived = true;
      for (int id = 0; id < 18; id++) {
        if (_dataStorage.getArduinoLatestRunningData(id) == null ||
            _dataStorage.getStm32LatestRunningData(id) == null) {
          allDataReceived = false;
          break;
        }
      }

      if (allDataReceived) return true;
    }

    return false;
  }

  /// 步驟 4: 關閉 GPIO
  Future<void> _autoDetectionStep4CloseGpio() async {
    // 發送關閉全部 GPIO 指令
    final closePayload = [0x02, 0xFF, 0xFF, 0x03, 0x00];
    _sendUrCommand(closePayload);
    await Future.delayed(const Duration(milliseconds: 500));
  }

  /// 步驟 5: 感測器測試
  Future<bool> _autoDetectionStep5SensorTest() async {
    // ===== 第一階段：先讀取溫度和壓力感測器（不含流量計）=====
    _updateAutoDetectionStatus(tr('auto_detection_step_sensor'), 0.68);

    // 先讀取 Arduino 溫度和壓力 (ID 19-21)
    if (_arduinoManager.isConnected) {
      for (int id = 19; id <= 21; id++) {
        if (_autoDetectionCancelled) return false;
        // 設定感測器區域高亮
        setState(() {
          _currentReadingId = id;
          _currentReadingSection = 'sensor';
        });
        _dataStorage.setHardwareState(id, HardwareState.running);
        _arduinoManager.sendString(_getArduinoSensorCommand(id));
        await Future.delayed(const Duration(milliseconds: 400));
      }
    }

    // 讀取 STM32 溫度和壓力 (ID 19-23)
    // 使用 1000ms 間隔（與資料儲存頁面一致），確保溫度感測器有足夠時間回應
    if (_urManager.isConnected) {
      for (int id = 19; id <= 23; id++) {
        if (_autoDetectionCancelled) return false;
        // 設定感測器區域高亮
        setState(() {
          _currentReadingId = id;
          _currentReadingSection = 'sensor';
        });
        _dataStorage.setHardwareState(id, HardwareState.running);
        final payload = [0x03, id, 0x00, 0x00, 0x00];
        final cmd = URCommandBuilder.buildCommand(payload);
        _urManager.sendHex(cmd);
        await Future.delayed(const Duration(milliseconds: 1000));
      }
    }

    // 額外等待確保溫度數據都收到
    await Future.delayed(const Duration(milliseconds: 500));

    // ===== 第二階段：流量計測試 =====
    // 發送 flowon 啟動流量計
    _updateAutoDetectionStatus(tr('starting_flow_test'), 0.75);
    // 設定流量計高亮 (ID 18)
    setState(() {
      _currentReadingId = 18;
      _currentReadingSection = 'sensor';
    });
    if (_arduinoManager.isConnected) {
      _arduinoManager.sendString('flowon');
    }

    // 等待流量計啟動
    await Future.delayed(const Duration(milliseconds: 500));

    // 讀取流量計數據 3 次，每次間隔 1 秒
    for (int i = 0; i < 3; i++) {
      if (_autoDetectionCancelled) return false;

      _updateAutoDetectionStatus(tr('auto_detection_step_sensor'), 0.76 + i * 0.02);

      // 保持流量計高亮
      setState(() {
        _currentReadingId = 18;
        _currentReadingSection = 'sensor';
      });

      // Arduino 流量計讀取 (ID 18)
      if (_arduinoManager.isConnected) {
        _dataStorage.setHardwareState(18, HardwareState.running);
        _arduinoManager.sendString('flowon');  // flowon 同時讀取流量
        await Future.delayed(const Duration(milliseconds: 300));
      }

      // STM32 流量計讀取 (ID 18)
      if (_urManager.isConnected) {
        _dataStorage.setHardwareState(18, HardwareState.running);
        final payload = [0x03, 18, 0x00, 0x00, 0x00];
        final cmd = URCommandBuilder.buildCommand(payload);
        _urManager.sendHex(cmd);
        await Future.delayed(const Duration(milliseconds: 300));
      }

      if (i < 2) {
        await Future.delayed(const Duration(milliseconds: 700));
      }
    }

    // 清除高亮
    setState(() {
      _currentReadingId = null;
      _currentReadingSection = null;
    });

    // 發送 flowoff 停止流量計
    _updateAutoDetectionStatus(tr('stopping_flow_test'), 0.82);
    if (_arduinoManager.isConnected) {
      _arduinoManager.sendString('flowoff');
    }

    await Future.delayed(const Duration(milliseconds: 500));

    // 讀取最終流量計數值
    if (_urManager.isConnected) {
      final readPayload = [0x03, 18, 0x00, 0x00, 0x00];
      final readCmd = URCommandBuilder.buildCommand(readPayload);
      _urManager.sendHex(readCmd);
    }

    await Future.delayed(const Duration(milliseconds: 300));

    // 清除流量計
    if (_urManager.isConnected) {
      final clearPayload = [0x04, 0x12, 0x00, 0x00, 0x00];
      _sendUrCommand(clearPayload);
    }

    return true;
  }

  /// 取得 Arduino 感測器指令
  String _getArduinoSensorCommand(int id) {
    switch (id) {
      case 19: return 'prec';      // PressureCO2
      case 20: return 'prew';      // PressureWater
      case 21: return 'mcutemp';   // MCUtemp
      default: return '';
    }
  }

  /// 步驟 6: 顯示結果
  /// 使用 ThresholdSettingsService 進行範圍驗證
  /// - 硬體 (ID 0-17): Arduino 和 STM32 測量同一元件，任一異常則該項目異常
  /// - 感測器 (ID 18-23): 驗證各設備的感測器數值是否在設定範圍內
  ///   - 溫度感測器 (ID 21-23) 需要額外的溫差比對
  void _autoDetectionStep6ShowResult() {
    final failedIdleItems = <String>[];      // Idle 異常項目
    final failedRunningItems = <String>[];   // Running 異常項目
    final failedSensorItems = <String>[];    // 感測器異常項目
    final thresholdService = ThresholdSettingsService();

    // 檢查硬體數據 (ID 0-17) - Idle 狀態
    // Arduino 和 STM32 測量同一元件，任一異常則該項目異常
    for (int id = 0; id < 18; id++) {
      final arduinoData = _dataStorage.getArduinoLatestIdleData(id);
      final stm32Data = _dataStorage.getStm32LatestIdleData(id);

      bool hasError = false;

      // 驗證 Arduino Idle 數值
      if (arduinoData != null) {
        final isValid = thresholdService.validateHardwareValue(
          DeviceType.arduino, StateType.idle, id, arduinoData.value);
        if (!isValid) hasError = true;
      }

      // 驗證 STM32 Idle 數值
      if (stm32Data != null) {
        final isValid = thresholdService.validateHardwareValue(
          DeviceType.stm32, StateType.idle, id, stm32Data.value);
        if (!isValid) hasError = true;
      }

      // 只要有一個異常，記錄該項目
      if (hasError) {
        failedIdleItems.add(DisplayNames.getName(id));
      }
    }

    // 檢查硬體數據 (ID 0-17) - Running 狀態
    for (int id = 0; id < 18; id++) {
      final arduinoData = _dataStorage.getArduinoLatestRunningData(id);
      final stm32Data = _dataStorage.getStm32LatestRunningData(id);

      bool hasError = false;

      // 驗證 Arduino Running 數值
      if (arduinoData != null) {
        final isValid = thresholdService.validateHardwareValue(
          DeviceType.arduino, StateType.running, id, arduinoData.value);
        if (!isValid) hasError = true;
      }

      // 驗證 STM32 Running 數值
      if (stm32Data != null) {
        final isValid = thresholdService.validateHardwareValue(
          DeviceType.stm32, StateType.running, id, stm32Data.value);
        if (!isValid) hasError = true;
      }

      // 只要有一個異常，記錄該項目
      if (hasError) {
        failedRunningItems.add(DisplayNames.getName(id));
      }
    }

    // 檢查感測器數據 (ID 18-23)
    final checkedSensorIds = <int>{};

    // 先取得 Arduino MCUtemp (ID 21) 用於溫度比對
    int? arduinoMcuTemp;
    {
      final runningData = _dataStorage.getArduinoLatestRunningData(21);
      final idleData = _dataStorage.getArduinoLatestIdleData(21);
      final data = runningData ?? idleData;
      if (data != null) {
        arduinoMcuTemp = data.value ~/ 10;  // MCUtemp 需要除以 10
      }
    }

    // Arduino 感測器 (ID 18-20) - 非溫度類
    for (int id = 18; id <= 20; id++) {
      final arduinoRunningData = _dataStorage.getArduinoLatestRunningData(id);
      final arduinoIdleData = _dataStorage.getArduinoLatestIdleData(id);
      final arduinoData = arduinoRunningData ?? arduinoIdleData;

      final stm32RunningData = _dataStorage.getStm32LatestRunningData(id);
      final stm32IdleData = _dataStorage.getStm32LatestIdleData(id);
      final stm32Data = stm32RunningData ?? stm32IdleData;

      bool hasError = false;

      if (arduinoData != null) {
        final isValid = thresholdService.validateSensorValue(DeviceType.arduino, id, arduinoData.value);
        if (!isValid) hasError = true;
      }

      if (stm32Data != null) {
        final isValid = thresholdService.validateSensorValue(DeviceType.stm32, id, stm32Data.value);
        if (!isValid) hasError = true;
      }

      if (hasError && !checkedSensorIds.contains(id)) {
        checkedSensorIds.add(id);
        failedSensorItems.add(DisplayNames.getName(id));
      }
    }

    // 溫度感測器 (ID 21-23) - 需要分別檢查並顯示詳細資訊
    for (int id = 21; id <= 23; id++) {
      final stm32RunningData = _dataStorage.getStm32LatestRunningData(id);
      final stm32IdleData = _dataStorage.getStm32LatestIdleData(id);
      final stm32Data = stm32RunningData ?? stm32IdleData;

      bool hasError = false;
      String errorDetail = '';

      // ID 21 (MCUtemp) Arduino 也有
      if (id == 21) {
        final arduinoRunningData = _dataStorage.getArduinoLatestRunningData(id);
        final arduinoIdleData = _dataStorage.getArduinoLatestIdleData(id);
        final arduinoData = arduinoRunningData ?? arduinoIdleData;

        if (arduinoData != null) {
          final value = arduinoData.value ~/ 10;
          final isValid = thresholdService.validateSensorValue(DeviceType.arduino, id, value);
          if (!isValid) {
            hasError = true;
            errorDetail = 'Arduino: $value°C';
          }
        }
      }

      if (stm32Data != null) {
        final isValid = thresholdService.validateSensorValue(DeviceType.stm32, id, stm32Data.value);
        if (!isValid) {
          hasError = true;
          if (errorDetail.isNotEmpty) errorDetail += ', ';
          errorDetail += 'STM32: ${stm32Data.value}°C';
        }

        // 與 Arduino MCUtemp 溫差比對
        if (arduinoMcuTemp != null) {
          final diffThreshold = thresholdService.getDiffThreshold(id);
          final tempDiff = (arduinoMcuTemp - stm32Data.value).abs();
          if (tempDiff > diffThreshold) {
            hasError = true;
            if (errorDetail.isNotEmpty) errorDetail += ', ';
            errorDetail += '溫差$tempDiff°C';
          }
        }
      }

      if (hasError && !checkedSensorIds.contains(id)) {
        checkedSensorIds.add(id);
        final name = DisplayNames.getName(id);
        failedSensorItems.add(errorDetail.isNotEmpty ? '$name ($errorDetail)' : name);
      }
    }

    // 顯示結果對話框
    final passed = failedIdleItems.isEmpty && failedRunningItems.isEmpty && failedSensorItems.isEmpty;
    _showTestResultDialog(passed, failedIdleItems, failedRunningItems, failedSensorItems);
  }

  /// 顯示測試結果對話框
  /// 三欄顯示：左邊 Idle、中間 Running、右邊感測器
  void _showTestResultDialog(
    bool passed,
    List<String> failedIdleItems,
    List<String> failedRunningItems,
    List<String> failedSensorItems,
  ) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          backgroundColor: passed ? Colors.green.shade50 : Colors.red.shade50,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
              color: passed ? Colors.green.shade400 : Colors.red.shade400,
              width: 2,
            ),
          ),
          title: Row(
            children: [
              Icon(
                passed ? Icons.check_circle : Icons.error,
                color: passed ? Colors.green : Colors.red,
                size: 32,
              ),
              const SizedBox(width: 12),
              Text(
                passed ? tr('test_result_pass') : tr('test_result_fail'),
                style: TextStyle(
                  color: passed ? Colors.green.shade800 : Colors.red.shade800,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          content: passed
              ? Text(
                  tr('test_all_passed'),
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.green.shade700,
                  ),
                )
              : SizedBox(
                  width: 600,  // 固定寬度以容納三欄
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tr('test_failed_items'),
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Colors.red.shade800,
                        ),
                      ),
                      const SizedBox(height: 12),
                      // 三欄顯示
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 250),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // 左欄：Idle 異常
                            Expanded(
                              child: _buildFailedColumn(
                                title: 'Idle',
                                items: failedIdleItems,
                                color: Colors.orange,
                              ),
                            ),
                            const SizedBox(width: 8),
                            // 中欄：Running 異常
                            Expanded(
                              child: _buildFailedColumn(
                                title: 'Running',
                                items: failedRunningItems,
                                color: Colors.red,
                              ),
                            ),
                            const SizedBox(width: 8),
                            // 右欄：感測器異常
                            Expanded(
                              child: _buildFailedColumn(
                                title: tr('sensor'),
                                items: failedSensorItems,
                                color: Colors.purple,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(
                tr('confirm'),
                style: TextStyle(
                  color: passed ? Colors.green.shade700 : Colors.red.shade700,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  /// 建構異常項目欄位
  Widget _buildFailedColumn({
    required String title,
    required List<String> items,
    required Color color,
  }) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: color.withValues(alpha: 0.3)),
        borderRadius: BorderRadius.circular(8),
        color: color.withValues(alpha: 0.05),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 標題
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 6),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(7),
                topRight: Radius.circular(7),
              ),
            ),
            child: Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: Color.lerp(color, Colors.black, 0.3),
              ),
            ),
          ),
          // 項目列表
          if (items.isEmpty)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.check_circle, color: Colors.green, size: 16),
                  const SizedBox(width: 4),
                  Text(
                    'OK',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.green.shade700,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            )
          else
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: items.map((item) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.warning, color: color, size: 14),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            item,
                            style: TextStyle(
                              fontSize: 11,
                              color: Color.lerp(color, Colors.black, 0.4),
                            ),
                          ),
                        ),
                      ],
                    ),
                  )).toList(),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// 並行批次讀取 Arduino 和 STM32 硬體數據 (ID 0-17)
  /// 兩邊同時發送指令，減少總讀取時間
  Future<void> _batchReadHardwareParallel(HardwareState state) async {
    // Arduino 指令對應表
    final arduinoCommands = ['s0', 's1', 's2', 's3', 's4', 's5', 's6', 's7', 's8', 's9',
                             'water', 'u0', 'u1', 'u2', 'arl', 'crl', 'srl', 'o3'];

    // 設定當前讀取的區域類型
    final sectionName = state == HardwareState.idle ? 'idle' : 'running';

    for (int id = 0; id < 18; id++) {
      if (_autoDetectionCancelled) return;

      // 設定當前讀取的項目 ID 和區域（用於高亮顯示）
      setState(() {
        _currentReadingId = id;
        _currentReadingSection = sectionName;
      });

      // 設定當前硬體狀態
      _dataStorage.setHardwareState(id, state);

      // 同時發送 Arduino 和 STM32 指令
      if (_arduinoManager.isConnected) {
        _arduinoManager.sendString(arduinoCommands[id]);
      }
      if (_urManager.isConnected) {
        final payload = [0x03, id, 0x00, 0x00, 0x00];
        final cmd = URCommandBuilder.buildCommand(payload);
        _urManager.sendHex(cmd);
      }

      // 等待回應
      await Future.delayed(const Duration(milliseconds: 300));
    }

    // 讀取完成後清除高亮
    setState(() {
      _currentReadingId = null;
      _currentReadingSection = null;
    });
  }

  /// 批次讀取 Arduino 感測器數據 (ID 18-21)
  Future<void> _batchReadArduinoSensor() async {
    if (!_arduinoManager.isConnected) return;

    final commands = ['flowon', 'prec', 'prew', 'mcutemp'];
    final ids = [18, 19, 20, 21];

    for (int i = 0; i < commands.length; i++) {
      if (_autoDetectionCancelled) return;

      _dataStorage.setHardwareState(ids[i], HardwareState.running);
      _arduinoManager.sendString(commands[i]);
      await Future.delayed(const Duration(milliseconds: 300));
    }
  }

  /// 批次讀取 STM32 感測器數據 (ID 18-23)
  Future<void> _batchReadStm32Sensor() async {
    if (!_urManager.isConnected) return;

    for (int id = 18; id <= 23; id++) {
      if (_autoDetectionCancelled) return;

      _dataStorage.setHardwareState(id, HardwareState.running);

      final payload = [0x03, id, 0x00, 0x00, 0x00];
      final cmd = URCommandBuilder.buildCommand(payload);
      _urManager.sendHex(cmd);
      // 增加等待時間確保 STM32 有足夠時間回應
      await Future.delayed(const Duration(milliseconds: 400));
    }
    // 額外等待確保最後一個回應也被接收
    await Future.delayed(const Duration(milliseconds: 300));
  }

  /// 建構自動檢測流程頁面
  Widget _buildAutoDetectionPage() {
    return AutoDetectionPage(
      dataStorage: _dataStorage,
      availablePorts: _availablePorts,
      selectedArduinoPort: _selectedArduinoPort,
      selectedStm32Port: _selectedUrPort,
      isArduinoConnected: _arduinoManager.isConnected,
      isStm32Connected: _urManager.isConnected,
      stm32FirmwareVersion: _urManager.firmwareVersionNotifier.value,
      onArduinoPortChanged: (port) {
        setState(() => _selectedArduinoPort = port);
      },
      onStm32PortChanged: (port) {
        setState(() => _selectedUrPort = port);
      },
      onArduinoConnect: _connectArduino,
      onArduinoDisconnect: _disconnectArduino,
      onStm32Connect: _connectUr,
      onStm32Disconnect: _disconnectUr,
      onRefreshPorts: _refreshPorts,
      // 自動檢測相關
      onStartAutoDetection: _startAutoDetection,
      isAutoDetecting: _isAutoDetecting,
      autoDetectionStatus: _autoDetectionStatus,
      autoDetectionProgress: _autoDetectionProgress,
      currentReadingId: _currentReadingId,
      currentReadingSection: _currentReadingSection,
      // ST-Link 燒入相關
      isStLinkConnected: _isStLinkConnected,
      stLinkInfo: _stLinkInfo,
      firmwareFiles: _firmwareFiles,
      selectedFirmwarePath: _selectedFirmwarePath,
      stLinkFrequency: _stLinkFrequency,
      isProgramming: _isProgramming,
      programProgress: _programProgress,
      programStatus: _programStatus,
      onFirmwareSelected: (path) {
        setState(() => _selectedFirmwarePath = path);
      },
      onStLinkFrequencyChanged: (freq) {
        setState(() => _stLinkFrequency = freq);
        _stLinkService.setFrequency(freq);
      },
      onStartProgramAndDetect: _startProgramAndDetect,
      onCheckStLink: _checkStLinkConnection,
    );
  }

  /// 燒入並自動檢測
  Future<void> _startProgramAndDetect() async {
    if (_isProgramming || _isAutoDetecting) return;
    if (_selectedFirmwarePath == null) {
      _showSnackBar(tr('please_select_firmware'));
      return;
    }
    if (!_isStLinkConnected) {
      _showSnackBar(tr('stlink_not_connected'));
      return;
    }

    // 燒入前先斷開 STM32 串口連線
    if (_urManager.isConnected) {
      _showSnackBar(tr('disconnecting_stm32_for_program'));
      _disconnectUr();
      await Future.delayed(const Duration(milliseconds: 300));
    }

    setState(() {
      _isProgramming = true;
      _programProgress = 0.0;
      _programStatus = tr('starting_program');
    });

    try {
      // 設定頻率
      _stLinkService.setFrequency(_stLinkFrequency);

      // 執行燒入
      final result = await _stLinkService.programFirmware(
        firmwarePath: _selectedFirmwarePath!,
        verify: true,
        reset: true,
      );

      setState(() {
        _isProgramming = false;
      });

      if (result.success) {
        // 燒入成功，顯示翻譯後的訊息
        String message;
        if (result.messageKey != null) {
          if (result.messageParams != null && result.messageParams!.isNotEmpty) {
            message = trParams(result.messageKey!, result.messageParams!);
          } else {
            message = tr(result.messageKey!);
          }
        } else {
          message = result.message;
        }
        _showSnackBar(message);

        // 等待 STM32 啟動完成（STM32 重置後需要約 5 秒啟動時間）
        setState(() {
          _programStatus = tr('waiting_stm32_startup');
        });
        await Future.delayed(const Duration(milliseconds: 5000));

        // 開始自動檢測流程
        _startAutoDetection();
      } else {
        // 燒入失敗，顯示錯誤訊息
        String message;
        if (result.messageKey != null) {
          message = tr(result.messageKey!);
        } else {
          message = result.message;
        }
        _showSnackBar(message);
      }
    } catch (e) {
      setState(() {
        _isProgramming = false;
      });
      _showSnackBar('${tr('execution_error')}: $e');
    }
  }

  /// STM32 發送原始指令 (直接發送完整 hex 指令)
  void _onStm32SendCommand(List<int> hexCommand) {
    if (!_urManager.isConnected) {
      _showSnackBar(tr('connect_stm32_first'));
      return;
    }
    _urManager.sendHex(hexCommand);

    // 從指令中解析出 payload 以追蹤硬體狀態
    // 指令格式: 40 71 30 [CMD] [LOW] [MID] [HIGH] [00] [CS]
    if (hexCommand.length >= 8 && hexCommand[0] == 0x40 && hexCommand[1] == 0x71 && hexCommand[2] == 0x30) {
      final command = hexCommand[3];
      if (command == 0x01 || command == 0x02) {
        final lowByte = hexCommand[4];
        final midByte = hexCommand[5];
        final highByte = hexCommand[6];
        final bitMask = lowByte | (midByte << 8) | (highByte << 16);

        for (int id = 0; id < 24; id++) {
          if ((bitMask & (1 << id)) != 0) {
            final state = (command == 0x01)
                ? HardwareState.running
                : HardwareState.idle;
            _dataStorage.setHardwareState(id, state);
          }
        }

        final action = (command == 0x01) ? tr('output_opened') : tr('output_closed');
        _showSnackBar(tr('all_outputs_toggled').replaceAll('{action}', action));
      }
    }
  }
}