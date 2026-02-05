// ============================================================================
// BodyDoorNavigationPage - Body&Door Board 主導航頁面
// ============================================================================
// 功能說明：
// 本模式用於管理 Arduino USB 串口通訊，進行 BodyDoor 測試治具操作
// ============================================================================

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_libserialport/flutter_libserialport.dart';

import 'package:flutter_firmware_tester_unified/shared/services/data_storage_service.dart';
import 'package:flutter_firmware_tester_unified/main_mode/main_navigation_page.dart' show MainNavigationPage;
import 'package:flutter_firmware_tester_unified/mode_selection_page.dart';
import 'services/serial_port_manager.dart';
import 'package:flutter_firmware_tester_unified/shared/services/localization_service.dart';
import 'services/threshold_settings_service.dart';
import 'package:flutter_firmware_tester_unified/shared/widgets/arduino_panel.dart' hide EmeraldColors;
import 'widgets/data_storage_page.dart';
import 'widgets/auto_detection_page.dart';
import 'widgets/settings_page.dart';
import 'controllers/auto_detection_controller.dart';
import 'controllers/serial_controller.dart';

// ============================================================================
// BodyDoorNavigationPage - 主導航頁面（包含側邊抽屜）
// ============================================================================

class BodyDoorNavigationPage extends StatefulWidget {
  /// 從模式選擇頁面偵測到的 Arduino COM 口名稱（用於逐步啟動）
  final String? initialArduinoPort;

  const BodyDoorNavigationPage({super.key, this.initialArduinoPort});

  @override
  State<BodyDoorNavigationPage> createState() => _BodyDoorNavigationPageState();
}

class _BodyDoorNavigationPageState extends State<BodyDoorNavigationPage>
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

  /// 錯誤模式對話框是否正在顯示（防止重複彈出）
  bool _isWrongModeDialogShowing = false;

  /// 錯誤對話框是否正在顯示（防止重複彈出）
  bool _isErrorDialogShowing = false;

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

  void onWrongModeDetected(String portName) => _showWrongModeDialog(portName);

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

      // 監聽錯誤模式偵測
      _arduinoManager.wrongModeDetectedNotifier.addListener(_onWrongModeDetected);

      // 延遲執行自動連線，確保 _availablePorts 已更新完成
      Future.delayed(const Duration(milliseconds: 200), () {
        if (mounted) {
          _autoConnectArduinoIfNeeded();
        }
      });
    });
  }

  /// 初始化閾值設定服務
  Future<void> _initThresholdService() async {
    await ThresholdSettingsService().init();
  }

  /// 如果從模式選擇頁帶入已偵測的 Arduino 埠，自動連線
  void _autoConnectArduinoIfNeeded() {
    final port = widget.initialArduinoPort;
    if (port != null && port.isNotEmpty && _availablePorts.contains(port)) {
      // 設定選中的埠並自動連線
      setState(() => _selectedArduinoPort = port);
      // 延遲一小段時間讓 UI 更新後再連線
      Future.delayed(const Duration(milliseconds: 100), () {
        if (mounted && !_arduinoManager.isConnected) {
          connectArduino();
        }
      });
    }
  }

  /// 監聽錯誤模式偵測（在 BodyDoor 模式下偵測到 Main 裝置）
  void _onWrongModeDetected() {
    if (_arduinoManager.wrongModeDetectedNotifier.value) {
      // 重置 notifier
      _arduinoManager.wrongModeDetectedNotifier.value = false;

      // 如果對話框已經在顯示，不重複彈出
      if (_isWrongModeDialogShowing) return;

      // 取得當前連線的埠名稱
      final detectedPort = _arduinoManager.currentPortName;
      if (detectedPort != null) {
        _showWrongModeDialog(detectedPort);
      }
    }
  }

  @override
  void dispose() {
    _portMonitorTimer?.cancel();
    _messageTimer?.cancel();
    _statusMessage.dispose();
    _arduinoManager.wrongModeDetectedNotifier.removeListener(_onWrongModeDetected);
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
    if (!mounted) return;  // 防止在 dispose 後使用
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
    // 防止重複彈出錯誤對話框
    if (_isErrorDialogShowing) return;
    _isErrorDialogShowing = true;

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
            if (!mounted) return;
            try {
              final navigator = Navigator.of(dialogContext);
              if (navigator.canPop()) {
                navigator.pop();
              }
            } catch (e) {
              // dialogContext 已失效，忽略錯誤
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
    ).then((_) {
      // 對話框關閉時重置標記
      _isErrorDialogShowing = false;
    });
  }

  /// 顯示偵測到錯誤模式裝置的對話框
  void _showWrongModeDialog(String detectedPort) {
    _isWrongModeDialogShowing = true;

    showDialog(
      context: context,
      barrierDismissible: true,  // 允許點擊外部關閉（視為取消）
      builder: (dialogContext) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.swap_horiz, color: Colors.orange.shade700),
            const SizedBox(width: 8),
            Text(tr('wrong_mode_detected')),
          ],
        ),
        content: Text(
          tr('bodydoor_wrong_mode_detected_message'),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              // _isWrongModeDialogShowing 保持 true，讓 .then() 執行斷開連線
            },
            child: Text(tr('cancel')),
          ),
          ElevatedButton.icon(
            onPressed: () {
              _isWrongModeDialogShowing = false;  // 先設為 false，避免 .then() 執行斷開連線
              Navigator.of(dialogContext).pop();
              // 直接切換到 Main 模式，並傳入偵測到的串口
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(
                  builder: (_) => MainNavigationPage(initialArduinoPort: detectedPort),
                ),
              );
            },
            icon: const Icon(Icons.swap_horiz),
            label: Text(tr('switch_to_main_mode')),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    ).then((_) {
      // 點擊外部或取消按鈕關閉時執行斷開連線
      if (_isWrongModeDialogShowing) {
        _isWrongModeDialogShowing = false;
        disconnectArduino();
      }
    });
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
        return tr('bodydoor_page_auto_detection');
      case 1:
        return tr('page_command_control');
      case 2:
        return tr('page_data_storage');
      case 3:
        return tr('page_settings');
      default:
        return tr('bodydoor_page_auto_detection');
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
            title: Text(tr('bodydoor_page_auto_detection')),
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
                // 使用 ValueListenableBuilder 局部更新，避免整個抽屜重建
                ValueListenableBuilder<bool>(
                  valueListenable: _arduinoManager.isConnectedNotifier,
                  builder: (context, isConnected, _) {
                    return _buildConnectionStatus(
                      'Arduino',
                      isConnected,
                      EmeraldColors.primary,
                    );
                  },
                ),
              ],
            ),
          ),
          const Divider(),
          // 切換模式選項
          ListTile(
            leading: const Icon(Icons.swap_horiz),
            title: Text(tr('switch_mode')),
            onTap: () {
              Navigator.pop(context); // 關閉抽屜
              // 斷開所有連接
              disconnectArduino();
              // 返回模式選擇頁面
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                  builder: (context) => const ModeSelectionPage(),
                ),
              );
            },
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

  /// 取得 Arduino 指令分組（BodyDoor 模式）
  List<Map<String, dynamic>> _getArduinoCommandGroups() => [
    {
      'label': 'Body 12V (ID 0-5,7)',
      'commands': ['ambientrl', 'coolrl', 'sparklingrl', 'waterpump', 'o3', 'mainuvc', 'flowmeter'],
    },
    {
      'label': 'Body 3.3V (ID 6,8-11)',
      'commands': ['bibtemp', 'watertemp', 'leak', 'waterpressure', 'co2pressure'],
    },
    {
      'label': 'Door (ID 12-14)',
      'commands': ['spoutuvc', 'mixuvc', 'flowmeter2'],
    },
    {
      'label': 'Door (ID 15-18)',
      'commands': ['bp24v', 'bp12v', 'bpup', 'bplow'],
    },
    {
      'label': tr('cmd_tool'),
      'commands': ['readall'],
    },
  ];

  /// 建構 Arduino 命令控制頁面
  Widget _buildCommandPage() {
    return ArduinoPanel(
      logNotifier: _arduinoManager.logNotifier,
      heartbeatOkNotifier: _arduinoManager.heartbeatOkNotifier,
      isConnectedNotifier: _arduinoManager.isConnectedNotifier,
      onClearLog: () => _arduinoManager.clearLog(),
      selectedPort: _selectedArduinoPort,
      availablePorts: _availablePorts,
      commandGroups: _getArduinoCommandGroups(),
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
