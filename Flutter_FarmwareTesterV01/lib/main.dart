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
import 'services/data_storage_service.dart';
import 'services/localization_service.dart';
import 'services/threshold_settings_service.dart';
import 'services/stlink_programmer_service.dart';
import 'services/cli_checker_service.dart';
import 'widgets/arduino_panel.dart';
import 'widgets/cli_check_dialog.dart';
import 'widgets/ur_panel.dart';
import 'widgets/data_storage_page.dart';
import 'widgets/auto_detection_page.dart';
import 'widgets/settings_page.dart';
import 'widgets/splash_screen.dart';
import 'widgets/firmware_upload_page.dart';
import 'widgets/operation_page.dart';
import 'controllers/auto_detection_controller.dart';
import 'controllers/serial_controller.dart';
import 'controllers/firmware_controller.dart';

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

class _MainNavigationPageState extends State<MainNavigationPage>
    with AutoDetectionController, SerialController, FirmwareController {
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
  final ValueNotifier<String> _statusMessage = ValueNotifier('');

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

  /// 次要高亮的項目 ID 列表（用於短路測試中顯示所有相鄰腳位）
  List<int>? _secondaryReadingIds;

  /// 慢速調試模式
  bool _isSlowDebugMode = false;

  /// 調試模式暫停狀態
  bool _isDebugPaused = false;

  /// 調試訊息
  String? _debugMessage;

  /// 調試歷史當前索引（1-based）
  int _debugHistoryIndex = 0;

  /// 調試歷史總數
  int _debugHistoryTotal = 0;

  /// 相鄰腳位短路測試數據（用於新模式在 Running 區域顯示）
  Map<int, List<AdjacentIdleData>> _adjacentIdleData = {};

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

  // ==================== 連接重試計數 ====================

  /// Arduino 連接重試計數
  int _arduinoConnectRetryCount = 0;

  /// STM32 連接重試計數
  int _urConnectRetryCount = 0;

  // ==================== UI 控制器 ====================

  final TextEditingController _urHexController = TextEditingController();
  final TextEditingController _flowController = TextEditingController();

  // ==================== AutoDetectionController Mixin 實作 ====================

  @override
  bool get isAutoDetecting => _isAutoDetecting;

  @override
  bool get isAutoDetectionCancelled => _autoDetectionCancelled;

  @override
  DataStorageService get dataStorage => _dataStorage;

  @override
  SerialPortManager get arduinoManager => _arduinoManager;

  @override
  SerialPortManager get urManager => _urManager;

  @override
  List<String> get availablePorts => _availablePorts;

  @override
  String? get selectedArduinoPort => _selectedArduinoPort;

  @override
  String? get selectedUrPort => _selectedUrPort;

  @override
  void setAutoDetectionState(String status, double progress) {
    setState(() {
      _autoDetectionStatus = status;
      _autoDetectionProgress = progress;
    });
  }

  @override
  void beginAutoDetection() {
    setState(() {
      _isAutoDetecting = true;
      _autoDetectionCancelled = false;
      _autoDetectionStatus = tr('auto_detection_step_connect');
      _autoDetectionProgress = 0.0;
    });
  }

  @override
  void endAutoDetection() {
    if (mounted) {
      setState(() {
        _isAutoDetecting = false;
        _autoDetectionProgress = 1.0;
      });
    }
  }

  @override
  void setSelectedArduinoPort(String port) {
    setState(() => _selectedArduinoPort = port);
  }

  @override
  void setSelectedUrPort(String port) {
    setState(() => _selectedUrPort = port);
  }

  @override
  void setCurrentReadingState(int? id, String? section, [List<int>? secondaryIds]) {
    setState(() {
      _currentReadingId = id;
      _currentReadingSection = section;
      _secondaryReadingIds = secondaryIds;
    });
  }

  @override
  void clearCurrentReadingState() {
    setState(() {
      _currentReadingId = null;
      _currentReadingSection = null;
      _secondaryReadingIds = null;
    });
  }

  @override
  void refreshPorts() => _refreshPorts();

  @override
  void showSnackBarMessage(String message) => _showSnackBar(message);

  @override
  void showTestResultDialog(
    bool passed,
    List<String> failedIdleItems,
    List<String> failedRunningItems,
    List<String> failedSensorItems, {
    List<String> vddShortItems = const [],
    List<String> vssShortItems = const [],
    List<String> adjacentShortItems = const [],
    List<String> loadDisconnectedItems = const [],
    List<String> gsShortItems = const [],
    List<String> gpioStuckOnItems = const [],
    List<String> gpioStuckOffItems = const [],
    List<String> wireErrorItems = const [],
    List<String> d12vShortItems = const [],
  }) => _showTestResultDialog(
    passed,
    failedIdleItems,
    failedRunningItems,
    failedSensorItems,
    vddShortItems: vddShortItems,
    vssShortItems: vssShortItems,
    adjacentShortItems: adjacentShortItems,
    loadDisconnectedItems: loadDisconnectedItems,
    gsShortItems: gsShortItems,
    gpioStuckOnItems: gpioStuckOnItems,
    gpioStuckOffItems: gpioStuckOffItems,
    wireErrorItems: wireErrorItems,
    d12vShortItems: d12vShortItems,
  );

  @override
  bool get isSlowDebugMode => _isSlowDebugMode;

  @override
  bool get isDebugPaused => _isDebugPaused;

  @override
  void setDebugPaused(bool paused) {
    if (mounted) {
      setState(() => _isDebugPaused = paused);
    }
  }

  @override
  void setDebugMessage(String message) {
    if (mounted) {
      setState(() => _debugMessage = message);
    }
  }

  @override
  void setDebugHistoryState(int index, int total) {
    if (mounted) {
      setState(() {
        _debugHistoryIndex = index;
        _debugHistoryTotal = total;
      });
    }
  }

  @override
  void setAdjacentIdleData(int runningId, List<AdjacentIdleData> data) {
    if (mounted) {
      setState(() {
        _adjacentIdleData[runningId] = data;
      });
    }
  }

  @override
  void clearAdjacentIdleData() {
    if (mounted) {
      setState(() {
        _adjacentIdleData.clear();
      });
    }
  }

  // ==================== SerialController Mixin 實作 ====================

  @override
  set selectedArduinoPort(String? value) => setState(() => _selectedArduinoPort = value);

  @override
  set selectedUrPort(String? value) => setState(() => _selectedUrPort = value);

  @override
  bool get isFlowOn => _isFlowOn;

  @override
  set isFlowOn(bool value) => _isFlowOn = value;

  @override
  Timer? get flowReadTimer => _flowReadTimer;

  @override
  set flowReadTimer(Timer? value) => _flowReadTimer = value;

  @override
  Timer? get urVerificationTimer => _urVerificationTimer;

  @override
  set urVerificationTimer(Timer? value) => _urVerificationTimer = value;

  @override
  bool get urConnectionVerified => _urConnectionVerified;

  @override
  set urConnectionVerified(bool value) => _urConnectionVerified = value;

  @override
  int get arduinoConnectRetryCount => _arduinoConnectRetryCount;

  @override
  set arduinoConnectRetryCount(int value) => _arduinoConnectRetryCount = value;

  @override
  int get urConnectRetryCount => _urConnectRetryCount;

  @override
  set urConnectRetryCount(int value) => _urConnectRetryCount = value;

  @override
  void showErrorDialogMessage(String message) => _showErrorDialog(message);

  // ==================== FirmwareController Mixin 實作 ====================

  @override
  StLinkProgrammerService get stLinkService => _stLinkService;

  @override
  bool get isProgramming => _isProgramming;

  @override
  set isProgramming(bool value) => setState(() => _isProgramming = value);

  @override
  bool get isStLinkConnected => _isStLinkConnected;

  @override
  String? get selectedFirmwarePath => _selectedFirmwarePath;

  @override
  int get stLinkFrequency => _stLinkFrequency;

  @override
  double get programProgress => _programProgress;

  @override
  set programProgress(double value) => setState(() => _programProgress = value);

  @override
  String? get programStatus => _programStatus;

  @override
  set programStatus(String? value) => setState(() => _programStatus = value);

  @override
  bool get isUrConnected => _urManager.isConnected;

  @override
  void disconnectUrPort() => disconnectUr();

  @override
  void startAutoDetectionProcess() => startAutoDetection();

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
          sendUrCommand(payload);
        }
      });
      // 2. 發送清除流量計指令: 0x04 + ID 18 (0x12)
      Future.delayed(const Duration(milliseconds: 400), () {
        if (_urManager.isConnected) {
          final clearFlowPayload = [0x04, 0x12, 0x00, 0x00, 0x00];
          sendUrCommand(clearFlowPayload);
        }
      });
    };

    // 設置 STM32 連接驗證回調
    _urManager.onConnectionVerified = (bool success) {
      cancelUrVerificationTimeout();
      if (success) {
        _urConnectionVerified = true;
        // 連接驗證成功，啟動心跳機制
        _urManager.startHeartbeat();
        // 連接驗證成功，發送 flowoff 到 Arduino
        sendArduinoFlowoff();
      }
    };

    // 設置 STM32 GPIO 命令確認回調（用於自動檢測流程）
    _urManager.onGpioCommandConfirmed = (int command, int bitMask) {
      handleGpioCommandConfirmed(command, bitMask);
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
      _checkRequiredCli();  // 檢查必要的 CLI 工具
    });
  }

  /// 檢查必要的 CLI 工具
  Future<void> _checkRequiredCli() async {
    CliCheckResult checkResult = await CliCheckerService.checkAllCli();

    // 如果所有 CLI 都已安裝，直接返回
    if (checkResult.allCliReady) return;

    // 顯示檢查對話框
    if (!mounted) return;

    // 使用遞迴方式避免 async gap 問題
    _showCliCheckDialogLoop(checkResult);
  }

  /// 顯示 CLI 檢查對話框（遞迴處理重新檢查）
  Future<void> _showCliCheckDialogLoop(CliCheckResult checkResult) async {
    if (!mounted) return;

    final continueAnyway = await showCliCheckDialog(context, checkResult);

    if (!mounted) return;

    if (continueAnyway) {
      // 使用者選擇略過，繼續使用程式
      return;
    }

    // 使用者選擇重新檢查
    final newResult = await CliCheckerService.checkAllCli();

    if (!mounted) return;

    if (newResult.allCliReady) {
      // 現在都安裝好了
      _showSnackBar('STM32CubeProgrammer CLI ${tr('cli_status_installed')}');
    } else {
      // 還是沒安裝，再次顯示對話框
      _showCliCheckDialogLoop(newResult);
    }
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
    _statusMessage.dispose();
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
    stopAutoFlowRead();  // 停止自動流量讀取
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
    stopAutoFlowRead();  // 停止自動流量讀取
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
    cancelUrVerificationTimeout();  // 取消驗證超時
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
    cancelUrVerificationTimeout();  // 取消驗證超時
    sendArduinoFlowoff();  // 發送 flowoff 到 Arduino
    _urManager.forceClose();  // 強制關閉連接
    if (mounted) {
      setState(() {
        _selectedUrPort = null;  // 清除選中的 port
      });
      _showErrorDialog(tr('stm32_connection_error'));
    }
  }

  // ==================== 串口操作 ====================

  /// 刷新可用 COM 埠列表和韌體檔案
  void _refreshPorts() {
    setState(() {
      _availablePorts = SerialPort.availablePorts;
    });

    // 同時刷新韌體檔案列表
    _scanFirmwareFiles();

    if (_availablePorts.isEmpty) {
      _showSnackBar(tr('no_com_port'));
    } else {
      _showSnackBar(tr('com_port_detected').replaceAll('{count}', '${_availablePorts.length}'));
    }
  }

  void _showSnackBar(String message) {
    _messageTimer?.cancel();
    _statusMessage.value = message;
    _messageTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) {
        _statusMessage.value = '';
      }
    });
  }

  /// 顯示錯誤提示對話框（畫面中央，2秒後自動關閉，或點擊關閉，帶淡入縮放動畫）
  void _showErrorDialog(String message) {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: '',
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (context, animation, secondaryAnimation) {
        return const SizedBox.shrink();
      },
      transitionBuilder: (dialogContext, animation, secondaryAnimation, child) {
        if (animation.status == AnimationStatus.completed) {
          Future.delayed(const Duration(seconds: 2), () {
            if (mounted && Navigator.of(dialogContext).canPop()) {
              Navigator.of(dialogContext).pop();
            }
          });
        }
        return FadeTransition(
          opacity: animation,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.95, end: 1.0).animate(
              CurvedAnimation(parent: animation, curve: Curves.easeOut),
            ),
            child: AlertDialog(
              backgroundColor: Colors.red.shade50,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: Colors.red.shade400, width: 2),
              ),
              content: InkWell(
                onTap: () => Navigator.of(dialogContext).pop(),
                child: Column(
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
                    const SizedBox(height: 8),
                    Text(
                      '(點擊關閉)',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  // ==================== 串口輸入處理 ====================

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

      // 使用 mixin 的 sendUrCommand 以便同時追蹤硬體狀態
      sendUrCommand(payload);
    } catch (e) {
      _showSnackBar(tr('parse_error').replaceAll('{error}', '$e'));
    }
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
                ValueListenableBuilder<String>(
                  valueListenable: _statusMessage,
                  builder: (context, msg, _) {
                    if (msg.isEmpty) return const SizedBox.shrink();
                    return Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Text(
                          msg,
                          style: const TextStyle(fontSize: 12, color: Colors.white),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    );
                  },
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
      case 5:
        return tr('page_operation');
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
              if (_selectedPageIndex != 0) {
                setState(() => _selectedPageIndex = 0);
              }
              Navigator.pop(context);
              _scanFirmwareFiles();
            },
          ),
          // 頁面選項 2: 命令控制
          ListTile(
            leading: const Icon(Icons.usb),
            title: Text(tr('page_command_control')),
            selected: _selectedPageIndex == 1,
            selectedTileColor: Colors.blue.shade50,
            onTap: () {
              if (_selectedPageIndex != 1) {
                setState(() => _selectedPageIndex = 1);
              }
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
              if (_selectedPageIndex != 2) {
                setState(() => _selectedPageIndex = 2);
              }
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
              if (_selectedPageIndex != 3) {
                setState(() => _selectedPageIndex = 3);
              }
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
              if (_selectedPageIndex != 4) {
                setState(() => _selectedPageIndex = 4);
              }
              Navigator.pop(context);
            },
          ),
          // 頁面選項 6: 操作畫面
          ListTile(
            leading: const Icon(Icons.touch_app),
            title: Text(tr('page_operation')),
            selected: _selectedPageIndex == 5,
            selectedTileColor: Colors.blue.shade50,
            onTap: () {
              if (_selectedPageIndex != 5) {
                setState(() => _selectedPageIndex = 5);
              }
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

  /// 建構頁面內容（使用 switch-case 每次只建構當前頁面）
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
          onDisconnectStm32: disconnectUr,
        );
      case 4:
        return const SettingsPage();
      case 5:
        return _buildOperationPage();
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
            onPortChanged: _onArduinoPortChanged,
            onConnect: connectArduino,
            onDisconnect: disconnectArduino,
            onSendCommand: sendArduinoCommand,
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
            onPortChanged: _onStm32PortChanged,
            onConnect: connectUr,
            onDisconnect: disconnectUr,
            onSendPayload: sendUrCommand,
            onSendFromInput: _sendUrFromInput,
          ),
        ),
      ],
    );
  }

  /// 建構操作畫面
  Widget _buildOperationPage() {
    return OperationPage(
      urManager: _urManager,
      availablePorts: _availablePorts,
      selectedUrPort: _selectedUrPort,
      arduinoPortName: _arduinoManager.currentPortName,
      isStm32Connected: _urManager.isConnected,
      onConnectStm32: connectUr,
      onDisconnectStm32: disconnectUr,
      onStm32PortChanged: _onStm32PortChanged,
      onSendUrCommand: sendUrCommand,
      onShowSnackBar: _showSnackBar,
    );
  }

  /// 建構資料儲存頁面
  Widget _buildDataStoragePage() {
    return DataStoragePage(
      dataStorage: _dataStorage,
      onArduinoQuickRead: onArduinoQuickRead,
      onStm32QuickRead: onStm32QuickRead,
      onStm32SendCommand: onStm32SendCommand,
    );
  }

  // ==================== 測試結果對話框 (由 AutoDetectionController 調用) ====================

  /// 顯示測試結果對話框
  /// 三欄顯示：左邊 Idle、中間 Running、右邊感測器
  void _showTestResultDialog(
    bool passed,
    List<String> failedIdleItems,
    List<String> failedRunningItems,
    List<String> failedSensorItems, {
    List<String> vddShortItems = const [],
    List<String> vssShortItems = const [],
    List<String> adjacentShortItems = const [],
    List<String> loadDisconnectedItems = const [],
    List<String> gsShortItems = const [],
    List<String> gpioStuckOnItems = const [],
    List<String> gpioStuckOffItems = const [],
    List<String> wireErrorItems = const [],
    List<String> d12vShortItems = const [],
  }) {
    // 取得短路測試顯示設定
    final thresholdService = ThresholdSettingsService();
    final showVdd = thresholdService.showVddShortTest;
    // Vss 短路目前隱藏（保留變數供未來擴展）
    // final showVss = thresholdService.showVssShortTest;

    // 檢查是否有短路問題（根據設定過濾）
    // Vss 短路目前隱藏，不參與判斷
    // D極與12V短路總是顯示（屬於 MOSFET 診斷的一部分）
    final hasShortCircuit = (showVdd && vddShortItems.isNotEmpty) ||
                            adjacentShortItems.isNotEmpty ||
                            d12vShortItems.isNotEmpty;

    // 檢查是否有診斷問題（根據設定過濾）
    final showLoadDetection = thresholdService.showLoadDetection;
    final showMosfetDetection = thresholdService.showMosfetDetection;
    final showGpioStatusDetection = thresholdService.showGpioStatusDetection;
    final showWireErrorDetection = thresholdService.showWireErrorDetection;
    // GPIO 狀態偵測暫時停用（與 MOSFET 診斷功能重疊）
    final hasDiagnosticIssue = (showLoadDetection && loadDisconnectedItems.isNotEmpty) ||
                               (showMosfetDetection && gsShortItems.isNotEmpty) ||
                               // (showGpioStatusDetection && (gpioStuckOnItems.isNotEmpty || gpioStuckOffItems.isNotEmpty)) ||
                               (showWireErrorDetection && wireErrorItems.isNotEmpty);

    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: '',
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (context, animation, secondaryAnimation) {
        return const SizedBox.shrink();
      },
      transitionBuilder: (dialogContext, animation, secondaryAnimation, child) {
        return FadeTransition(
          opacity: animation,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.95, end: 1.0).animate(
              CurvedAnimation(parent: animation, curve: Curves.easeOut),
            ),
            child: AlertDialog(
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
                  width: (hasShortCircuit || hasDiagnosticIssue) ? 800 : 600,  // 有短路或診斷問題時加寬
                  child: SingleChildScrollView(
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
                        // 第一列：Idle、Running、感測器異常
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxHeight: 200),
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
                        // 第二列：短路測試結果（如果有）
                        if (hasShortCircuit) ...[
                          const SizedBox(height: 16),
                          const Divider(),
                          const SizedBox(height: 8),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxHeight: 180),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Vdd 短路（根據設定顯示）
                                if (showVdd)
                                  Expanded(
                                    child: _buildFailedColumn(
                                      title: tr('vdd_short_detected'),
                                      items: vddShortItems,
                                      color: Colors.deepOrange,
                                    ),
                                  ),
                                if (showVdd && adjacentShortItems.isNotEmpty)
                                  const SizedBox(width: 8),
                                // Vss 短路目前隱藏（保留程式碼供未來擴展）
                                // if (showVss)
                                //   Expanded(
                                //     child: _buildFailedColumn(
                                //       title: tr('vss_short_detected'),
                                //       items: vssShortItems,
                                //       color: Colors.brown,
                                //     ),
                                //   ),
                                // if (showVss && adjacentShortItems.isNotEmpty)
                                //   const SizedBox(width: 8),
                                // 相鄰腳位短路（總是顯示，沒有設定開關）
                                Expanded(
                                  child: _buildFailedColumn(
                                    title: tr('adjacent_short_detected'),
                                    items: adjacentShortItems,
                                    color: Colors.indigo,
                                  ),
                                ),
                                if (d12vShortItems.isNotEmpty)
                                  const SizedBox(width: 8),
                                // D極與12V短路（MOSFET 診斷，總是顯示）
                                if (d12vShortItems.isNotEmpty)
                                  Expanded(
                                    child: _buildFailedColumn(
                                      title: tr('d12v_short_detected'),
                                      items: d12vShortItems,
                                      color: Colors.red.shade800,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                        // 第三列：診斷偵測結果（如果有）
                        if (hasDiagnosticIssue) ...[
                          const SizedBox(height: 16),
                          const Divider(),
                          const SizedBox(height: 8),
                          Text(
                            tr('diag_detail_title'),
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: Colors.teal.shade800,
                            ),
                          ),
                          const SizedBox(height: 8),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxHeight: 180),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // 負載未連接（根據設定顯示）
                                if (showLoadDetection)
                                  Expanded(
                                    child: _buildFailedColumn(
                                      title: tr('diag_load_disconnected'),
                                      items: loadDisconnectedItems,
                                      color: Colors.grey,
                                    ),
                                  ),
                                if (showLoadDetection && (showMosfetDetection || showGpioStatusDetection))
                                  const SizedBox(width: 8),
                                // G-S 短路（根據設定顯示）
                                if (showMosfetDetection)
                                  Expanded(
                                    child: _buildFailedColumn(
                                      title: tr('diag_gs_short'),
                                      items: gsShortItems,
                                      color: Colors.deepOrange,
                                    ),
                                  ),
                                // GPIO 狀態偵測暫時停用（與 MOSFET 診斷功能重疊）
                                // 保留程式碼供未來使用
                                // if (showMosfetDetection && showGpioStatusDetection)
                                //   const SizedBox(width: 8),
                                // // GPIO 卡在 ON（根據設定顯示）
                                // if (showGpioStatusDetection)
                                //   Expanded(
                                //     child: _buildFailedColumn(
                                //       title: tr('diag_gpio_stuck_on'),
                                //       items: gpioStuckOnItems,
                                //       color: Colors.amber.shade700,
                                //     ),
                                //   ),
                                // if (showGpioStatusDetection && gpioStuckOffItems.isNotEmpty)
                                //   const SizedBox(width: 8),
                                // // GPIO 卡在 OFF（根據設定顯示）
                                // if (showGpioStatusDetection)
                                //   Expanded(
                                //     child: _buildFailedColumn(
                                //       title: tr('diag_gpio_stuck_off'),
                                //       items: gpioStuckOffItems,
                                //       color: Colors.blueGrey,
                                //     ),
                                //   ),
                                if (showWireErrorDetection && wireErrorItems.isNotEmpty)
                                  const SizedBox(width: 8),
                                // 線材錯誤（根據設定顯示）
                                if (showWireErrorDetection)
                                  Expanded(
                                    child: _buildFailedColumn(
                                      title: tr('diag_wire_error'),
                                      items: wireErrorItems,
                                      color: Colors.brown,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
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
            ),
          ),
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
      onArduinoPortChanged: _onArduinoPortChanged,
      onStm32PortChanged: _onStm32PortChanged,
      onArduinoConnect: connectArduino,
      onArduinoDisconnect: disconnectArduino,
      onStm32Connect: connectUr,
      onStm32Disconnect: disconnectUr,
      onRefreshPorts: _refreshPorts,
      // 自動檢測相關
      onStartAutoDetection: startAutoDetection,
      isAutoDetecting: _isAutoDetecting,
      autoDetectionStatus: _autoDetectionStatus,
      autoDetectionProgress: _autoDetectionProgress,
      currentReadingId: _currentReadingId,
      currentReadingSection: _currentReadingSection,
      secondaryReadingIds: _secondaryReadingIds,
      // ST-Link 燒入相關
      isStLinkConnected: _isStLinkConnected,
      stLinkInfo: _stLinkInfo,
      firmwareFiles: _firmwareFiles,
      selectedFirmwarePath: _selectedFirmwarePath,
      stLinkFrequency: _stLinkFrequency,
      isProgramming: _isProgramming,
      programProgress: _programProgress,
      programStatus: _programStatus,
      onFirmwareSelected: _onFirmwareSelected,
      onStLinkFrequencyChanged: _onStLinkFrequencyChanged,
      onStartProgramAndDetect: _startProgramAndDetect,
      onCheckStLink: _checkStLinkConnection,
      onShowResultDialog: _showCurrentTestResult,
      // 慢速調試模式
      isSlowDebugMode: _isSlowDebugMode,
      onToggleSlowDebugMode: _toggleSlowDebugMode,
      debugMessage: _debugMessage,
      debugHistoryIndex: _debugHistoryIndex,
      debugHistoryTotal: _debugHistoryTotal,
      onDebugHistoryPrev: debugHistoryPrev,
      onDebugHistoryNext: debugHistoryNext,
      isDebugPaused: _isDebugPaused,
      onToggleDebugPause: _toggleDebugPause,
      // 相鄰短路顯示模式
      adjacentIdleData: _adjacentIdleData,
      onToggleAdjacentDisplayMode: _toggleAdjacentDisplayMode,
      adjacentDisplayInRunning: ThresholdSettingsService().adjacentShortDisplayInRunning,
    );
  }

  // ==================== 命名回調方法 ====================

  void _onArduinoPortChanged(String? port) {
    setState(() => _selectedArduinoPort = port);
  }

  void _onStm32PortChanged(String? port) {
    setState(() => _selectedUrPort = port);
  }

  void _onFirmwareSelected(String? path) {
    setState(() => _selectedFirmwarePath = path);
  }

  void _onStLinkFrequencyChanged(int freq) {
    setState(() => _stLinkFrequency = freq);
    _stLinkService.setFrequency(freq);
  }

  /// 切換相鄰短路顯示模式
  void _toggleAdjacentDisplayMode() {
    final thresholdService = ThresholdSettingsService();
    final newValue = !thresholdService.adjacentShortDisplayInRunning;
    thresholdService.setAdjacentShortDisplayInRunning(newValue);
    setState(() {});  // 觸發 UI 更新
  }

  /// 切換慢速調試模式
  void _toggleSlowDebugMode() {
    setState(() {
      _isSlowDebugMode = !_isSlowDebugMode;
      if (!_isSlowDebugMode) {
        _debugMessage = null;  // 關閉時清除調試訊息
        _debugHistoryIndex = 0;
        _debugHistoryTotal = 0;
        _isDebugPaused = false;  // 關閉時也取消暫停
      }
    });
    _showSnackBar(_isSlowDebugMode
        ? tr('slow_debug_mode_on')
        : tr('slow_debug_mode_off'));
  }

  /// 切換調試暫停狀態
  void _toggleDebugPause() {
    setState(() {
      _isDebugPaused = !_isDebugPaused;
    });
  }

  /// 顯示當前檢測結果（可隨時查看）
  void _showCurrentTestResult() {
    // 調用 mixin 中的方法來顯示結果
    showCurrentResult();
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
      disconnectUr();
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
        await Future.delayed(const Duration(milliseconds: 8000));

        // 開始自動檢測流程
        startAutoDetection();
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

}