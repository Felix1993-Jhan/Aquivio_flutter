// ============================================================================
// BodyDoor 測試應用程式 - 主程式入口
// ============================================================================
// 功能說明：
// 本程式用於管理 Arduino USB 串口通訊，進行 BodyDoor 測試治具操作
//
// 檔案結構：
// - lib/main.dart                            主程式入口與頁面
// - lib/services/serial_port_manager.dart    串口管理類別
// - lib/services/data_storage_service.dart   數據儲存服務
// - lib/widgets/arduino_panel.dart           Arduino 控制面板
// ============================================================================

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_libserialport/flutter_libserialport.dart';
import 'package:window_manager/window_manager.dart';

import 'services/serial_port_manager.dart';
import 'services/data_storage_service.dart';
import 'services/localization_service.dart';
import 'services/threshold_settings_service.dart';
import 'widgets/arduino_panel.dart';
import 'widgets/data_storage_page.dart';
import 'widgets/auto_detection_page.dart';
import 'widgets/settings_page.dart';
import 'widgets/splash_screen.dart';
import 'controllers/auto_detection_controller.dart';
import 'controllers/serial_controller.dart';

// ==================== 應用程式入口 ====================

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 初始化視窗管理器並設定最小尺寸
  await windowManager.ensureInitialized();

  const windowOptions = WindowOptions(
    minimumSize: Size(800, 600),
    size: Size(1200, 800),
    center: true,
    title: 'BodyDoor Tester V01',
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
      title: 'BodyDoor Tester V01',
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
    with AutoDetectionController, SerialController {
  // ==================== 串口管理器 ====================

  final SerialPortManager _arduinoManager =
      SerialPortManager('Arduino', isTextMode: true);

  // ==================== 數據儲存服務 ====================

  final DataStorageService _dataStorage = DataStorageService();

  // ==================== 狀態變數 ====================

  String? _selectedArduinoPort;
  List<String> _availablePorts = [];

  /// 當前選中的頁面索引
  int _selectedPageIndex = 0;

  /// 即時訊息（顯示在 AppBar 中，使用 ValueNotifier 避免全頁 setState）
  final ValueNotifier<String> _statusMessage = ValueNotifier('');

  /// 訊息清除計時器
  Timer? _messageTimer;

  /// COM 埠監控定時器（每 1 秒檢查一次 COM 埠變化）
  Timer? _portMonitorTimer;

  /// 上次偵測到的 COM 埠列表（用於比較變化）
  List<String> _lastDetectedPorts = [];

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

  // ==================== 連接重試計數 ====================

  /// Arduino 連接重試計數
  int _arduinoConnectRetryCount = 0;

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
  List<String> get availablePorts => _availablePorts;

  @override
  String? get selectedArduinoPort => _selectedArduinoPort;

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
  void setCurrentReadingState(int? id, String? section) {
    setState(() {
      _currentReadingId = id;
      _currentReadingSection = section;
    });
  }

  @override
  void clearCurrentReadingState() {
    setState(() {
      _currentReadingId = null;
      _currentReadingSection = null;
    });
  }

  @override
  void refreshPorts() => _refreshPorts();

  @override
  void showSnackBarMessage(String message) => _showSnackBar(message);

  @override
  @override
  void showTestResultDialog(bool passed, List<String> failedItems) =>
    _showTestResultDialog(passed, failedItems);

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

  // ==================== SerialController Mixin 實作 ====================

  @override
  set selectedArduinoPort(String? value) => setState(() => _selectedArduinoPort = value);

  @override
  int get arduinoConnectRetryCount => _arduinoConnectRetryCount;

  @override
  set arduinoConnectRetryCount(int value) => _arduinoConnectRetryCount = value;

  @override
  void showErrorDialogMessage(String message) => _showErrorDialog(message);

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

    // 設置 Arduino 心跳失敗回調
    _arduinoManager.onHeartbeatFailed = () {
      _handleArduinoHeartbeatFailed();
    };

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshPorts();
      _startPortMonitor();
    });
  }

  /// 初始化閾值設定服務
  Future<void> _initThresholdService() async {
    await ThresholdSettingsService().init();
  }

  @override
  void dispose() {
    _portMonitorTimer?.cancel();
    _messageTimer?.cancel();
    _statusMessage.dispose();
    _arduinoManager.dispose();
    _dataStorage.dispose();
    super.dispose();
  }

  // ==================== COM 埠監控 ====================

  /// 啟動 COM 埠監控（每 1 秒檢查一次）
  void _startPortMonitor() {
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
        if (_arduinoManager.isConnected &&
            _arduinoManager.currentPortName == removedPort) {
          _handleArduinoDisconnected();
        }
      }
    }

    // 如果有 COM 埠變化，更新可用列表
    if (removedPorts.isNotEmpty || addedPorts.isNotEmpty) {
      if (mounted) {
        setState(() {
          _availablePorts = List.from(currentPorts);

          if (_selectedArduinoPort != null &&
              !currentPorts.contains(_selectedArduinoPort)) {
            _selectedArduinoPort = null;
          }
        });

        if (addedPorts.isNotEmpty) {
          _showSnackBar(tr('new_com_port_detected').replaceAll('{ports}', addedPorts.join(", ")));
        }
      }
    }

    _lastDetectedPorts = List.from(currentPorts);
  }

  /// 處理 Arduino USB 斷開
  void _handleArduinoDisconnected() {
    _arduinoManager.forceClose();
    if (mounted) {
      setState(() {
        _selectedArduinoPort = null;
      });
      _showSnackBar(tr('arduino_usb_removed'));
    }
  }

  /// 處理 Arduino 心跳失敗
  void _handleArduinoHeartbeatFailed() {
    _arduinoManager.forceClose();
    if (mounted) {
      setState(() {
        _selectedArduinoPort = null;
      });
      _showErrorDialog(tr('arduino_connection_error'));
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
    _statusMessage.value = message;
    _messageTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) {
        _statusMessage.value = '';
      }
    });
  }

  /// 顯示錯誤提示對話框
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
        // 2 秒後自動關閉
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

  // ==================== UI 建構 ====================

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppLanguage>(
      valueListenable: LocalizationService().currentLanguageNotifier,
      builder: (context, _, __) {
        return Scaffold(
          appBar: AppBar(
            title: Row(
              children: [
                Text(_getPageTitle()),
                const SizedBox(width: 16),
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
          DrawerHeader(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  EmeraldColors.primary,
                  EmeraldColors.primary.withValues(alpha: 0.7),
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
          // 頁面選項 1: 自動檢測流程（預設頁面）
          ListTile(
            leading: const Icon(Icons.fact_check),
            title: Text(tr('page_auto_detection')),
            selected: _selectedPageIndex == 0,
            selectedTileColor: Colors.blue.shade50,
            onTap: () {
              Navigator.pop(context);
              if (_selectedPageIndex != 0) {
                Future.delayed(const Duration(milliseconds: 250), () {
                  if (mounted) setState(() => _selectedPageIndex = 0);
                });
              }
            },
          ),
          // 頁面選項 2: 命令控制
          ListTile(
            leading: const Icon(Icons.usb),
            title: Text(tr('page_command_control')),
            selected: _selectedPageIndex == 1,
            selectedTileColor: Colors.blue.shade50,
            onTap: () {
              Navigator.pop(context);
              if (_selectedPageIndex != 1) {
                Future.delayed(const Duration(milliseconds: 250), () {
                  if (mounted) setState(() => _selectedPageIndex = 1);
                });
              }
            },
          ),
          // 頁面選項 3: 資料儲存
          ListTile(
            leading: const Icon(Icons.storage),
            title: Text(tr('page_data_storage')),
            selected: _selectedPageIndex == 2,
            selectedTileColor: Colors.blue.shade50,
            onTap: () {
              Navigator.pop(context);
              if (_selectedPageIndex != 2) {
                Future.delayed(const Duration(milliseconds: 250), () {
                  if (mounted) setState(() => _selectedPageIndex = 2);
                });
              }
            },
          ),
          // 頁面選項 4: 設定
          ListTile(
            leading: const Icon(Icons.settings),
            title: Text(tr('page_settings')),
            selected: _selectedPageIndex == 3,
            selectedTileColor: Colors.blue.shade50,
            onTap: () {
              Navigator.pop(context);
              if (_selectedPageIndex != 3) {
                Future.delayed(const Duration(milliseconds: 250), () {
                  if (mounted) setState(() => _selectedPageIndex = 3);
                });
              }
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

  /// 建構頁面內容（IndexedStack 保留所有頁面狀態）
  Widget _buildBody() {
    return IndexedStack(
      index: _selectedPageIndex,
      children: [
        _buildAutoDetectionPage(),
        _buildCommandPage(),
        _buildDataStoragePage(),
        const SettingsPage(),
      ],
    );
  }

  /// 建構 Arduino 命令控制頁面
  Widget _buildCommandPage() {
    return ArduinoPanel(
      manager: _arduinoManager,
      selectedPort: _selectedArduinoPort,
      availablePorts: _availablePorts,
      onPortChanged: (value) {
        setState(() => _selectedArduinoPort = value);
      },
      onConnect: connectArduino,
      onDisconnect: disconnectArduino,
      onSendCommand: sendArduinoCommand,
    );
  }

  /// 建構資料儲存頁面
  Widget _buildDataStoragePage() {
    return DataStoragePage(
      dataStorage: _dataStorage,
      onArduinoQuickRead: onArduinoQuickRead,
    );
  }

  // ==================== 測試結果對話框 (由 AutoDetectionController 調用) ====================

  void _showTestResultDialog(bool passed, List<String> failedItems) {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: '',
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (context, animation, secondaryAnimation) {
        return const SizedBox.shrink();
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
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
                      width: 400,
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
                            _buildFailedColumn(
                              title: tr('test_failed_items'),
                              items: failedItems,
                              color: Colors.red,
                            ),
                          ],
                        ),
                      ),
                    ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
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
      isArduinoConnected: _arduinoManager.isConnected,
      onArduinoPortChanged: (port) {
        setState(() => _selectedArduinoPort = port);
      },
      onArduinoConnect: connectArduino,
      onArduinoDisconnect: disconnectArduino,
      onRefreshPorts: _refreshPorts,
      onStartAutoDetection: startAutoDetection,
      isAutoDetecting: _isAutoDetecting,
      autoDetectionStatus: _autoDetectionStatus,
      autoDetectionProgress: _autoDetectionProgress,
      currentReadingId: _currentReadingId,
      currentReadingSection: _currentReadingSection,
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
    );
  }

  /// 切換慢速調試模式
  void _toggleSlowDebugMode() {
    setState(() {
      _isSlowDebugMode = !_isSlowDebugMode;
      if (!_isSlowDebugMode) {
        _debugMessage = null;
        _debugHistoryIndex = 0;
        _debugHistoryTotal = 0;
        _isDebugPaused = false;
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

  /// 顯示當前檢測結果
  void _showCurrentTestResult() {
    showCurrentResult();
  }
}
