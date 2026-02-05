// ============================================================================
// AutoDetectionPage - 自動檢測流程-雙串口 頁面
// ============================================================================
// 功能：比較 Arduino 和 STM32 的數據，顯示差異和狀態
// - 上方：COM 選擇和連接控制區
// - 左邊：無動作區（Arduino、STM32、差值、狀態燈）
// - 右邊：動作中區（Arduino、STM32、差值、狀態燈）
// - 下方：感應偵測區（Arduino、STM32、差值、狀態燈）
// - 差值以 Arduino 為基準，可顯示正負值
// - 狀態燈：綠色為 Pass，紅色為 Error
// - ID 21-23 溫度誤差閾值：>2 為 Error
// - 其他誤差閾值：>250 為 Error
// ============================================================================

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_firmware_tester_unified/shared/services/data_storage_service.dart';
import 'package:flutter_firmware_tester_unified/shared/services/localization_service.dart';
import '../services/threshold_settings_service.dart';
import '../services/stlink_programmer_service.dart';
import 'data_storage_page.dart';

/// 相鄰腳位類型（用於顯示特殊類型）
enum AdjacentDataType {
  /// 一般 GPIO 腳位（有讀取數據）
  gpio,
  /// 電源 (Vdd)
  vdd,
  /// 接地 (Vss)
  vss,
  /// 無相鄰腳位
  none,
}

/// 相鄰腳位 Idle 數據（用於新模式在 Running 區域顯示）
class AdjacentIdleData {
  /// 相鄰腳位 ID（GPIO 類型才有意義）
  final int adjacentId;
  /// 相鄰腳位名稱
  final String pinName;
  /// Arduino 數值
  final int? arduinoValue;
  /// STM32 數值
  final int? stm32Value;
  /// 是否短路
  final bool isShort;
  /// 相鄰腳位類型（gpio / vdd / vss / none）
  final AdjacentDataType dataType;

  const AdjacentIdleData({
    required this.adjacentId,
    required this.pinName,
    this.arduinoValue,
    this.stm32Value,
    this.isShort = false,
    this.dataType = AdjacentDataType.gpio,
  });

  /// 是否為特殊類型（非 GPIO）
  bool get isSpecialType => dataType != AdjacentDataType.gpio;
}

/// 誤差閾值設定
/// 方便日後修改，集中管理
class ErrorThresholds {
  // ==================== 硬體誤差閾值 (ID 0-17) ====================

  /// Slot 0-9 誤差閾值
  static const int slot0 = 250;
  static const int slot1 = 250;
  static const int slot2 = 250;
  static const int slot3 = 250;
  static const int slot4 = 250;
  static const int slot5 = 250;
  static const int slot6 = 250;
  static const int slot7 = 250;
  static const int slot8 = 250;
  static const int slot9 = 250;

  /// WaterPump (ID 10) 誤差閾值
  static const int waterPump = 250;

  /// UVC 燈 (ID 11-13) 誤差閾值 (u0=SpoutUVC, u1=MixUVC, u2=MainUVC)
  static const int spoutUvc = 250;  // ID 11 (u0)
  static const int mixUvc = 250;    // ID 12 (u1)
  static const int mainUvc = 250;   // ID 13 (u2)

  /// 繼電器 (ID 14-16) 誤差閾值
  static const int ambientRl = 250;
  static const int coolRl = 250;
  static const int sparkRl = 250;

  /// O3 (ID 17) 誤差閾值
  static const int o3 = 250;

  // ==================== 感測器誤差閾值 (ID 18-23) ====================

  /// Flow (ID 18) 誤差閾值
  static const int flow = 250;

  /// PressureCO2 (ID 19) 誤差閾值
  static const int pressureCo2 = 250;

  /// PressureWater (ID 20) 誤差閾值
  static const int pressureWater = 250;

  /// MCUtemp (ID 21) 誤差閾值 - 溫度類型
  static const int mcuTemp = 2;

  /// WATERtemp (ID 22) 誤差閾值 - 溫度類型
  static const int waterTemp = 2;

  /// BIBtemp (ID 23) 誤差閾值 - 溫度類型
  static const int bibTemp = 2;

  /// 根據 ID 取得誤差閾值
  static int getThreshold(int id) {
    switch (id) {
      case 0: return slot0;
      case 1: return slot1;
      case 2: return slot2;
      case 3: return slot3;
      case 4: return slot4;
      case 5: return slot5;
      case 6: return slot6;
      case 7: return slot7;
      case 8: return slot8;
      case 9: return slot9;
      case 10: return waterPump;
      case 11: return spoutUvc;   // u0 = SpoutUVC
      case 12: return mixUvc;     // u1 = MixUVC
      case 13: return mainUvc;    // u2 = MainUVC
      case 14: return ambientRl;
      case 15: return coolRl;
      case 16: return sparkRl;
      case 17: return o3;
      case 18: return flow;
      case 19: return pressureCo2;
      case 20: return pressureWater;
      case 21: return mcuTemp;
      case 22: return waterTemp;
      case 23: return bibTemp;
      default: return 250;
    }
  }

  /// 判斷是否為溫度類型（需要特殊處理）
  static bool isTemperature(int id) {
    return id >= 21 && id <= 23;
  }

  /// 自動檢測流程使用的流量計閾值（較嚴格）
  static const int flowAutoDetection = 50;

  /// 取得自動檢測專用閾值（流量計使用較嚴格的閾值）
  static int getAutoDetectionThreshold(int id) {
    if (id == 18) return flowAutoDetection;
    return getThreshold(id);
  }
}

class AutoDetectionPage extends StatefulWidget {
  /// 數據儲存服務
  final DataStorageService dataStorage;

  /// 可用的 COM 埠列表
  final List<String> availablePorts;

  /// 已選擇的 Arduino COM 埠
  final String? selectedArduinoPort;

  /// 已選擇的 STM32 COM 埠
  final String? selectedStm32Port;

  /// Arduino 是否已連接
  final bool isArduinoConnected;

  /// STM32 是否已連接
  final bool isStm32Connected;

  /// STM32 韌體版本
  final String? stm32FirmwareVersion;

  /// Arduino COM 埠變更回調
  final void Function(String?) onArduinoPortChanged;

  /// STM32 COM 埠變更回調
  final void Function(String?) onStm32PortChanged;

  /// Arduino 連接回調
  final VoidCallback onArduinoConnect;

  /// Arduino 斷開回調
  final VoidCallback onArduinoDisconnect;

  /// STM32 連接回調
  final VoidCallback onStm32Connect;

  /// STM32 斷開回調
  final VoidCallback onStm32Disconnect;

  /// 刷新 COM 埠列表回調
  final VoidCallback onRefreshPorts;

  /// 自動檢測開始回調
  final VoidCallback? onStartAutoDetection;

  /// 是否正在自動檢測
  final bool isAutoDetecting;

  /// 自動檢測狀態文字
  final String? autoDetectionStatus;

  /// 自動檢測進度 (0.0 - 1.0)
  final double autoDetectionProgress;

  /// 當前正在讀取的項目 ID（用於高亮顯示）
  final int? currentReadingId;

  /// 當前正在讀取的區域類型（idle / running / sensor）
  final String? currentReadingSection;

  /// 次要高亮的項目 ID 列表（用於短路測試中顯示所有相鄰腳位，固定顯示在 Idle 區域）
  final List<int>? secondaryReadingIds;

  /// 相鄰腳位短路測試數據（用於新模式在 Running 區域顯示）
  /// key 為 Running ID，value 為相鄰腳位的 Idle 數據列表
  final Map<int, List<AdjacentIdleData>>? adjacentIdleData;

  /// 相鄰短路顯示模式切換回調
  final VoidCallback? onToggleAdjacentDisplayMode;

  /// 是否使用新模式（在 Running 區域顯示相鄰腳位數據）
  final bool adjacentDisplayInRunning;

  // ==================== ST-Link 燒入相關 ====================

  /// ST-Link 是否已連接
  final bool isStLinkConnected;

  /// ST-Link 連接資訊
  final StLinkInfo? stLinkInfo;

  /// 可用的韌體檔案列表
  final List<FileSystemEntity> firmwareFiles;

  /// 選中的韌體檔案路徑
  final String? selectedFirmwarePath;

  /// ST-Link 頻率 (kHz)
  final int stLinkFrequency;

  /// 是否正在燒入
  final bool isProgramming;

  /// 燒入進度 (0.0 - 1.0)
  final double programProgress;

  /// 燒入狀態訊息
  final String? programStatus;

  /// 韌體檔案選擇回調
  final void Function(String?) onFirmwareSelected;

  /// ST-Link 頻率變更回調
  final void Function(int) onStLinkFrequencyChanged;

  /// 開始燒入並自動檢測回調
  final VoidCallback? onStartProgramAndDetect;

  /// 檢查 ST-Link 連接回調
  final VoidCallback? onCheckStLink;

  /// 顯示檢測結果對話框回調
  final VoidCallback? onShowResultDialog;

  /// 是否啟用慢速調試模式
  final bool isSlowDebugMode;

  /// 切換慢速調試模式回調
  final VoidCallback? onToggleSlowDebugMode;

  /// 當前調試訊息（慢速模式下顯示詳細比較資訊）
  final String? debugMessage;

  /// 調試歷史當前索引（1-based）
  final int debugHistoryIndex;

  /// 調試歷史總數
  final int debugHistoryTotal;

  /// 查看上一條調試訊息回調
  final VoidCallback? onDebugHistoryPrev;

  /// 查看下一條調試訊息回調
  final VoidCallback? onDebugHistoryNext;

  /// 調試模式是否暫停
  final bool isDebugPaused;

  /// 切換調試暫停狀態回調
  final VoidCallback? onToggleDebugPause;

  const AutoDetectionPage({
    super.key,
    required this.dataStorage,
    required this.availablePorts,
    required this.selectedArduinoPort,
    required this.selectedStm32Port,
    required this.isArduinoConnected,
    required this.isStm32Connected,
    this.stm32FirmwareVersion,
    required this.onArduinoPortChanged,
    required this.onStm32PortChanged,
    required this.onArduinoConnect,
    required this.onArduinoDisconnect,
    required this.onStm32Connect,
    required this.onStm32Disconnect,
    required this.onRefreshPorts,
    this.onStartAutoDetection,
    this.isAutoDetecting = false,
    this.autoDetectionStatus,
    this.autoDetectionProgress = 0.0,
    this.currentReadingId,
    this.currentReadingSection,
    this.secondaryReadingIds,
    this.adjacentIdleData,
    this.onToggleAdjacentDisplayMode,
    this.adjacentDisplayInRunning = false,
    // ST-Link 燒入相關
    this.isStLinkConnected = false,
    this.stLinkInfo,
    this.firmwareFiles = const [],
    this.selectedFirmwarePath,
    this.stLinkFrequency = 200,
    this.isProgramming = false,
    this.programProgress = 0.0,
    this.programStatus,
    required this.onFirmwareSelected,
    required this.onStLinkFrequencyChanged,
    this.onStartProgramAndDetect,
    this.onCheckStLink,
    this.onShowResultDialog,
    this.isSlowDebugMode = false,
    this.onToggleSlowDebugMode,
    this.debugMessage,
    this.debugHistoryIndex = 0,
    this.debugHistoryTotal = 0,
    this.onDebugHistoryPrev,
    this.onDebugHistoryNext,
    this.isDebugPaused = false,
    this.onToggleDebugPause,
  });

  @override
  State<AutoDetectionPage> createState() => _AutoDetectionPageState();
}

class _AutoDetectionPageState extends State<AutoDetectionPage> {
  // 硬體區域的 ScrollController（Idle 和 Running 共用相同的項目數，可以同步滾動）
  final ScrollController _idleScrollController = ScrollController();
  final ScrollController _runningScrollController = ScrollController();
  // 感測器區域的 ScrollController
  final ScrollController _sensorScrollController = ScrollController();

  // 硬體數據行的統一高度（確保 Idle 和 Running 區域高度一致，也用於滾動位置計算）
  static const double _hardwareRowHeight = 40.0;

  // 感測器區域的項目高度（用於計算滾動位置）
  static const double _sensorRowHeight = 32.0;

  // 是否顯示相鄰腳位短路詳細資料
  bool _showAdjacentDetails = false;

  @override
  void dispose() {
    _idleScrollController.dispose();
    _runningScrollController.dispose();
    _sensorScrollController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(AutoDetectionPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 當 currentReadingId 或 currentReadingSection 變化時，自動滾動到對應位置
    if (widget.currentReadingId != oldWidget.currentReadingId ||
        widget.currentReadingSection != oldWidget.currentReadingSection ||
        _listChanged(widget.secondaryReadingIds, oldWidget.secondaryReadingIds)) {
      _scrollToCurrentItem();
    }
  }

  /// 檢查兩個 List 是否不同
  bool _listChanged(List<int>? a, List<int>? b) {
    if (a == null && b == null) return false;
    if (a == null || b == null) return true;
    if (a.length != b.length) return true;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return true;
    }
    return false;
  }

  /// 自動滾動到當前正在讀取的項目
  void _scrollToCurrentItem() {
    final id = widget.currentReadingId;
    final section = widget.currentReadingSection;
    if (id == null || section == null) return;

    // 根據區域類型選擇對應的 ScrollController 和計算項目索引
    if (section == 'idle' || section == 'running') {
      // 硬體區域 (ID 0-17) - 使用硬體行高
      if (id >= 0 && id <= 17) {
        final targetOffset = id * _hardwareRowHeight;
        final controller = section == 'idle' ? _idleScrollController : _runningScrollController;
        _animateScrollTo(controller, targetOffset, _hardwareRowHeight);
      }
    } else if (section == 'sensor') {
      // 感測器區域 (ID 18-23) - 使用感測器行高
      if (id >= 18 && id <= 23) {
        final targetOffset = (id - 18) * _sensorRowHeight;
        _animateScrollTo(_sensorScrollController, targetOffset, _sensorRowHeight);
      }
    }

    // 次要捲動：相鄰腳位在 Idle 區域
    // 當主要區域是 Running 且有次要 ID 時，捲動 Idle 區域到最小的相鄰腳位
    final secondaryIds = widget.secondaryReadingIds;
    if (section == 'running' && secondaryIds != null && secondaryIds.isNotEmpty) {
      // 找出最小的 ID 進行捲動
      final minId = secondaryIds.reduce((a, b) => a < b ? a : b);
      if (minId >= 0 && minId <= 17) {
        final secondaryOffset = minId * _hardwareRowHeight;
        _animateScrollTo(_idleScrollController, secondaryOffset, _hardwareRowHeight);
      }
    }
  }

  /// 平滑滾動到指定位置，將目標項目滾動到可視區域中央
  /// [itemHeight] 用於計算項目位置
  void _animateScrollTo(ScrollController controller, double offset, double itemHeight) {
    if (!controller.hasClients) return;

    // 取得當前滾動位置和可視區域高度
    final currentOffset = controller.offset;
    final viewportHeight = controller.position.viewportDimension;

    // 計算項目的頂部和底部位置
    final itemTop = offset;
    final itemBottom = offset + itemHeight;

    // 檢查項目是否完全在可視區域中央附近（上下各留 1/4 的邊距）
    final marginTop = viewportHeight * 0.25;
    final marginBottom = viewportHeight * 0.25;
    final isComfortablyVisible = itemTop >= (currentOffset + marginTop) &&
        itemBottom <= (currentOffset + viewportHeight - marginBottom);

    // 如果項目已經在舒適的可視範圍內，不需要滾動
    if (isComfortablyVisible) return;

    // 計算目標滾動位置：將項目放在可視區域中央
    final centerOffset = offset - (viewportHeight / 2) + (itemHeight / 2);

    // 確保 offset 不超過最大滾動範圍
    final maxOffset = controller.position.maxScrollExtent;
    final targetOffset = centerOffset.clamp(0.0, maxOffset);

    controller.animateTo(
      targetOffset,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    // 監聽語言變更，自動更新 UI
    return ValueListenableBuilder<AppLanguage>(
      valueListenable: LocalizationService().currentLanguageNotifier,
      builder: (context, _, __) {
        return ValueListenableBuilder<int>(
          valueListenable: widget.dataStorage.dataUpdateNotifier,
          builder: (context, _, __) {
            return ValueListenableBuilder<int>(
              valueListenable: widget.dataStorage.runningStateNotifier,
              builder: (context, _, __) {
                return Stack(
                  children: [
                    // 主要內容
                    Column(
                      children: [
                        // 最上方：ST-Link 燒入控制區
                        _buildStLinkProgramBar(),
                        // 燒入進度指示器（僅在燒入中時顯示）
                        if (widget.isProgramming) _buildProgramProgress(),
                        // COM 選擇和連接控制區 + 自動檢測按鈕
                        _buildConnectionControlBar(),
                        // 自動檢測進度指示器（僅在進行中時顯示）
                        if (widget.isAutoDetecting) _buildAutoDetectionProgress(),
                        // 中間：硬體數據區 (ID 0-17)
                        // 使用 Expanded + Row + CrossAxisAlignment.stretch 確保兩個區塊高度一致
                        Expanded(
                          flex: 3,
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                // 左邊：無動作區（卡片式外框）
                                Expanded(
                                  child: Card(
                                    elevation: 4,
                                    shadowColor: Colors.blueGrey.shade400,
                                    margin: EdgeInsets.zero,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      side: BorderSide(color: Colors.blueGrey.shade400, width: 2),
                                    ),
                                    clipBehavior: Clip.antiAlias,
                                    child: _buildHardwareSection(
                                      title: tr('hardware_idle'),
                                      state: HardwareState.idle,
                                      color: Colors.blueGrey,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                // 右邊：動作中區（卡片式外框）
                                Expanded(
                                  child: Card(
                                    elevation: 4,
                                    shadowColor: Colors.orange.shade400,
                                    margin: EdgeInsets.zero,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      side: BorderSide(color: Colors.orange.shade400, width: 2),
                                    ),
                                    clipBehavior: Clip.antiAlias,
                                    child: _buildHardwareSection(
                                      title: tr('hardware_running'),
                                      state: HardwareState.running,
                                      color: Colors.orange.shade700,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        // 下方：感應偵測區 (ID 18-23)
                        // flex 增加到 2 以容納 6 行感測器資料
                        // 左右與程式邊界相隔 80 像素
                        Expanded(
                          flex: 2,
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(80, 8, 80, 8),
                            child: Card(
                              elevation: 4,
                              shadowColor: Colors.grey.shade500,
                              margin: EdgeInsets.zero,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                                side: BorderSide(color: Colors.grey.shade500, width: 2),
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: _buildSensorSection(),
                            ),
                          ),
                        ),
                      ],
                    ),
                    // 右下角浮動小球按鈕 - 查看檢測結果
                    if (widget.onShowResultDialog != null)
                      Positioned(
                        right: 16,
                        bottom: 16,
                        child: _buildFloatingResultButton(),
                      ),
                    // 慢速調試模式按鈕（在結果按鈕上方）
                    if (widget.onToggleSlowDebugMode != null)
                      Positioned(
                        right: 16,
                        bottom: 76,
                        child: _buildSlowDebugButton(),
                      ),
                    // 自動檢測開始按鈕（在調試按鈕上方）
                    if (widget.onStartAutoDetection != null)
                      Positioned(
                        right: 16,
                        bottom: 136,
                        child: _buildAutoStartButton(),
                      ),
                    // 調試訊息顯示區（慢速模式下顯示）
                    if (widget.isSlowDebugMode && widget.debugMessage != null && widget.debugMessage!.isNotEmpty)
                      Positioned(
                        left: 16,
                        right: 80,
                        bottom: 16,
                        child: _buildDebugMessagePanel(),
                      ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  /// 建構浮動結果按鈕（右下角小球）
  Widget _buildFloatingResultButton() {
    return Material(
      elevation: 6,
      shadowColor: Colors.black45,
      shape: const CircleBorder(),
      child: InkWell(
        onTap: widget.onShowResultDialog,
        customBorder: const CircleBorder(),
        child: Container(
          width: 50,
          height: 50,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.blue.shade400,
                Colors.blue.shade700,
              ],
            ),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.3),
              width: 2,
            ),
          ),
          child: const Icon(
            Icons.assignment,
            color: Colors.white,
            size: 24,
          ),
        ),
      ),
    );
  }

  /// 建構慢速調試模式按鈕
  Widget _buildSlowDebugButton() {
    return Material(
      elevation: 6,
      shadowColor: Colors.black45,
      shape: const CircleBorder(),
      child: InkWell(
        onTap: widget.onToggleSlowDebugMode,
        customBorder: const CircleBorder(),
        child: Container(
          width: 50,
          height: 50,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: widget.isSlowDebugMode
                  ? [Colors.orange.shade400, Colors.orange.shade700]
                  : [Colors.grey.shade400, Colors.grey.shade600],
            ),
            border: Border.all(
              color: widget.isSlowDebugMode
                  ? Colors.yellow.withValues(alpha: 0.5)
                  : Colors.white.withValues(alpha: 0.3),
              width: 2,
            ),
          ),
          child: Icon(
            widget.isSlowDebugMode ? Icons.slow_motion_video : Icons.speed,
            color: Colors.white,
            size: 24,
          ),
        ),
      ),
    );
  }

  /// 建構自動檢測開始浮動按鈕
  Widget _buildAutoStartButton() {
    final isDetecting = widget.isAutoDetecting;
    return Material(
      elevation: 6,
      shadowColor: Colors.black45,
      shape: const CircleBorder(),
      child: InkWell(
        onTap: isDetecting ? null : () => widget.onStartAutoDetection?.call(),
        customBorder: const CircleBorder(),
        child: Container(
          width: 50,
          height: 50,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: isDetecting
                  ? [Colors.grey.shade400, Colors.grey.shade600]
                  : [Colors.green.shade400, Colors.green.shade700],
            ),
            border: Border.all(
              color: isDetecting
                  ? Colors.white.withValues(alpha: 0.3)
                  : Colors.lightGreen.withValues(alpha: 0.5),
              width: 2,
            ),
          ),
          child: Icon(
            isDetecting ? Icons.hourglass_empty : Icons.play_arrow,
            color: Colors.white,
            size: 28,
          ),
        ),
      ),
    );
  }

  /// 建構調試訊息面板
  Widget _buildDebugMessagePanel() {
    final canGoPrev = widget.debugHistoryIndex > 1;
    final canGoNext = widget.debugHistoryIndex < widget.debugHistoryTotal;

    // 解析調試訊息
    final parsedData = _parseDebugMessage(widget.debugMessage);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black87,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.orange, width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // 標題列和導航按鈕
          Row(
            children: [
              const Icon(Icons.bug_report, color: Colors.orange, size: 16),
              const SizedBox(width: 6),
              Text(
                tr('debug_mode'),
                style: const TextStyle(
                  color: Colors.orange,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
              const Spacer(),
              // 歷史導航
              if (widget.debugHistoryTotal > 0) ...[
                // 上一條按鈕
                IconButton(
                  onPressed: canGoPrev ? widget.onDebugHistoryPrev : null,
                  icon: Icon(
                    Icons.arrow_upward,
                    color: canGoPrev ? Colors.white : Colors.grey,
                    size: 18,
                  ),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  tooltip: tr('prev_record'),
                ),
                // 索引顯示
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '${widget.debugHistoryIndex} / ${widget.debugHistoryTotal}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                // 下一條按鈕
                IconButton(
                  onPressed: canGoNext ? widget.onDebugHistoryNext : null,
                  icon: Icon(
                    Icons.arrow_downward,
                    color: canGoNext ? Colors.white : Colors.grey,
                    size: 18,
                  ),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  tooltip: tr('next_record'),
                ),
                const SizedBox(width: 8),
                // 暫停/繼續按鈕
                IconButton(
                  onPressed: widget.onToggleDebugPause,
                  icon: Icon(
                    widget.isDebugPaused ? Icons.play_arrow : Icons.pause,
                    color: widget.isDebugPaused ? Colors.green : Colors.white,
                    size: 20,
                  ),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  tooltip: widget.isDebugPaused ? tr('debug_resume') : tr('debug_pause'),
                  style: IconButton.styleFrom(
                    backgroundColor: widget.isDebugPaused
                        ? Colors.green.withValues(alpha: 0.3)
                        : Colors.white.withValues(alpha: 0.2),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          // 根據解析結果決定顯示方式
          if (parsedData != null) ...[
            // 標題：測試腳位資訊
            _buildDebugHeader(parsedData),
            const SizedBox(height: 8),
            // 測試結果卡片（並排顯示）
            _buildDebugTestCards(parsedData),
          ] else ...[
            // 無法解析時顯示原始文字
            Text(
              widget.debugMessage ?? '',
              style: const TextStyle(
                color: Colors.white,
                fontFamily: 'monospace',
                fontSize: 11,
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// 解析調試訊息
  _DebugParsedData? _parseDebugMessage(String? message) {
    if (message == null || message.isEmpty) return null;

    final lines = message.split('\n');
    if (lines.length < 4) return null;

    // 解析標題資訊（第二行通常是 [Running] PB10 (ID5) 這樣的格式）
    String? runningPinName;
    int? runningId;
    String? adjacentIds;

    for (final line in lines) {
      // 解析 Running 腳位（支援中英文）
      final runningMatch = RegExp(r'\[Running\]\s*(\S+)\s*\(ID(\d+)\)').firstMatch(line);
      final runningMatchZh = RegExp(r'【Running】\s*(\S+)\s*\(ID(\d+)\)').firstMatch(line);
      if (runningMatch != null) {
        runningPinName = runningMatch.group(1);
        runningId = int.tryParse(runningMatch.group(2) ?? '');
      } else if (runningMatchZh != null) {
        runningPinName = runningMatchZh.group(1);
        runningId = int.tryParse(runningMatchZh.group(2) ?? '');
      }

      // 解析相鄰腳位（支援中英文）
      final adjacentMatch = RegExp(r'\[Adjacent IDs\]\s*(.+)').firstMatch(line);
      final adjacentMatchZh = RegExp(r'【相鄰腳位】\s*(.+)').firstMatch(line);
      if (adjacentMatch != null) {
        adjacentIds = adjacentMatch.group(1);
      } else if (adjacentMatchZh != null) {
        adjacentIds = adjacentMatchZh.group(1);
      }
    }

    if (runningPinName == null || runningId == null) return null;

    // 解析測試結果
    final testResults = <_DebugTestResult>[];
    _DebugTestResult? currentResult;

    for (final line in lines) {
      // 檢測新的測試項目開始（支援中英文）
      final testMatch = RegExp(r'\[(\d+)\]\s*Testing Adjacent:\s*(\S+)\s*\(ID(\d+)\)').firstMatch(line);
      final testMatchZh = RegExp(r'【(\d+)】檢測相鄰:\s*(\S+)\s*\(ID(\d+)\)').firstMatch(line);

      if (testMatch != null || testMatchZh != null) {
        if (currentResult != null) {
          testResults.add(currentResult);
        }
        final match = testMatch ?? testMatchZh!;
        currentResult = _DebugTestResult(
          index: int.tryParse(match.group(1) ?? '') ?? 0,
          pinName: match.group(2) ?? '',
          pinId: int.tryParse(match.group(3) ?? '') ?? 0,
        );
        continue;
      }

      if (currentResult != null) {
        // 解析配對資訊（支援中英文）
        final pairMatch = RegExp(r'Pair:\s*(\S+)\s*↔\s*(\S+)').firstMatch(line);
        final pairMatchZh = RegExp(r'配對:\s*(\S+)\s*↔\s*(\S+)').firstMatch(line);
        if (pairMatch != null) {
          currentResult.pairLeft = pairMatch.group(1);
          currentResult.pairRight = pairMatch.group(2);
        } else if (pairMatchZh != null) {
          currentResult.pairLeft = pairMatchZh.group(1);
          currentResult.pairRight = pairMatchZh.group(2);
        }

        // 解析 STM32 結果（支援中英文）
        // 英文: STM32: Base 1 → New 3 Diff:2 ✓Normal
        // 中文: STM32: 基準1 → 新值3 差:2 ✓正常
        // 使用更寬鬆的匹配，處理各種空格情況
        final trimmedLine = line.trim();
        if (trimmedLine.contains('STM32')) {
          // 通用匹配：STM32: ... base值 → ... new值 ... diff值 ... 狀態
          final stm32GenericMatch = RegExp(r'STM32[:\s]+(?:Base|基準)\s*(\S+)\s*→\s*(?:New|新值)\s*(\S+)\s*(?:Diff|差)[:\s]*(\d+)\s*(.*)').firstMatch(trimmedLine);
          if (stm32GenericMatch != null) {
            currentResult.stm32Base = stm32GenericMatch.group(1);
            currentResult.stm32New = stm32GenericMatch.group(2);
            currentResult.stm32Diff = stm32GenericMatch.group(3);
            final status = stm32GenericMatch.group(4) ?? '';
            currentResult.stm32IsNormal = status.contains('Normal') || status.contains('正常') || status.contains('✓');
          }
        }

        // 解析 Arduino 結果（支援中英文）
        // 英文: Arduino: Base 798 → New 798 Diff:0 ✓Normal
        // 中文: Arduino: 基準798 → 新值798 差:0 ✓正常
        if (trimmedLine.contains('Arduino')) {
          final arduinoGenericMatch = RegExp(r'Arduino[:\s]+(?:Base|基準)\s*(\S+)\s*→\s*(?:New|新值)\s*(\S+)\s*(?:Diff|差)[:\s]*(\d+)\s*(.*)').firstMatch(trimmedLine);
          if (arduinoGenericMatch != null) {
            currentResult.arduinoBase = arduinoGenericMatch.group(1);
            currentResult.arduinoNew = arduinoGenericMatch.group(2);
            currentResult.arduinoDiff = arduinoGenericMatch.group(3);
            final status = arduinoGenericMatch.group(4) ?? '';
            currentResult.arduinoIsNormal = status.contains('Normal') || status.contains('正常') || status.contains('✓');
            currentResult.arduinoSkipped = status.contains('Skip') || status.contains('跳過');
          }
        }

        // 解析閾值（支援中英文）
        // 英文: Threshold: 100
        // 中文: 閾值: 100
        final thresholdMatch = RegExp(r'Threshold:\s*(\d+)').firstMatch(line);
        final thresholdMatchZh = RegExp(r'閾值:\s*(\d+)').firstMatch(line);
        if (thresholdMatch != null) {
          currentResult.threshold = thresholdMatch.group(1);
        } else if (thresholdMatchZh != null) {
          currentResult.threshold = thresholdMatchZh.group(1);
        }
      }
    }

    // 加入最後一個結果
    if (currentResult != null) {
      testResults.add(currentResult);
    }

    if (testResults.isEmpty) return null;

    return _DebugParsedData(
      runningPinName: runningPinName,
      runningId: runningId,
      adjacentIds: adjacentIds ?? '',
      testResults: testResults,
    );
  }

  /// 建構調試訊息標題
  Widget _buildDebugHeader(_DebugParsedData data) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        children: [
          Text(
            '[Running] ${data.runningPinName} (ID${data.runningId})',
            style: const TextStyle(
              color: Colors.orange,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              '[Adjacent IDs] ${data.adjacentIds}',
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 11,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  /// 建構測試結果卡片（兩個並排）
  Widget _buildDebugTestCards(_DebugParsedData data) {
    final results = data.testResults;

    // 計算需要幾行（每行兩個卡片）
    final rowCount = (results.length / 2).ceil();

    return Column(
      children: List.generate(rowCount, (rowIndex) {
        final leftIndex = rowIndex * 2;
        final rightIndex = leftIndex + 1;

        return Padding(
          padding: EdgeInsets.only(bottom: rowIndex < rowCount - 1 ? 8 : 0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 左側卡片
              Expanded(
                child: _buildSingleTestCard(results[leftIndex]),
              ),
              const SizedBox(width: 8),
              // 右側卡片（如果存在）
              Expanded(
                child: rightIndex < results.length
                    ? _buildSingleTestCard(results[rightIndex])
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        );
      }),
    );
  }

  /// 建構單個測試結果卡片
  Widget _buildSingleTestCard(_DebugTestResult result) {
    final isStm32Normal = result.stm32IsNormal;
    final isArduinoNormal = result.arduinoIsNormal || result.arduinoSkipped;
    final isAllNormal = isStm32Normal && isArduinoNormal;

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: isAllNormal
            ? Colors.green.withValues(alpha: 0.15)
            : Colors.red.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: isAllNormal ? Colors.green : Colors.red,
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 標題：[1] PB11 (ID4)
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '[${result.index}]',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '${result.pinName} (ID${result.pinId})',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Icon(
                isAllNormal ? Icons.check_circle : Icons.error,
                color: isAllNormal ? Colors.green : Colors.red,
                size: 16,
              ),
            ],
          ),
          const SizedBox(height: 6),
          // 配對資訊
          if (result.pairLeft != null && result.pairRight != null) ...[
            Text(
              '${result.pairLeft} ↔ ${result.pairRight}',
              style: const TextStyle(
                color: Colors.white60,
                fontSize: 10,
              ),
            ),
            const SizedBox(height: 4),
          ],
          // STM32 結果
          _buildDeviceResultRow(
            'STM32',
            result.stm32Base,
            result.stm32New,
            result.stm32Diff,
            result.stm32IsNormal,
            false,
          ),
          const SizedBox(height: 2),
          // Arduino 結果
          _buildDeviceResultRow(
            'Arduino',
            result.arduinoBase,
            result.arduinoNew,
            result.arduinoDiff,
            result.arduinoIsNormal,
            result.arduinoSkipped,
          ),
          const SizedBox(height: 4),
          // 閾值
          Text(
            'Threshold: ${result.threshold ?? "N/A"}',
            style: const TextStyle(
              color: Colors.white54,
              fontSize: 9,
            ),
          ),
        ],
      ),
    );
  }

  /// 建構設備結果行
  Widget _buildDeviceResultRow(
    String deviceName,
    String? baseValue,
    String? newValue,
    String? diff,
    bool isNormal,
    bool isSkipped,
  ) {
    final statusColor = isSkipped ? Colors.grey : (isNormal ? Colors.green : Colors.red);
    final statusText = isSkipped ? 'Skip' : (isNormal ? '√' : '✗');

    return Row(
      children: [
        SizedBox(
          width: 48,
          child: Text(
            deviceName,
            style: TextStyle(
              color: deviceName == 'STM32' ? SkyBlueColors.primary : EmeraldColors.primary,
              fontSize: 9,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        Expanded(
          child: Text(
            '${baseValue ?? "N/A"} → ${newValue ?? "N/A"}',
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 9,
              fontFamily: 'monospace',
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 4),
        Text(
          'Δ${diff ?? "0"}',
          style: const TextStyle(
            color: Colors.white54,
            fontSize: 9,
          ),
        ),
        const SizedBox(width: 4),
        Text(
          statusText,
          style: TextStyle(
            color: statusColor,
            fontSize: 10,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  /// 建構連接控制列
  Widget _buildConnectionControlBar() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        // 三級佈局模式：
        // >= 900: 完整模式
        // 500-899: 緊湊模式（水平）
        // < 500: 極緊湊模式（垂直堆疊）
        final isVertical = width < 500;
        final isCompact = width < 900;

        if (isVertical) {
          // 極緊湊模式：垂直堆疊
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Arduino 控制區
              _buildDeviceConnectionPanelMinimal(
                deviceName: 'Arduino',
                deviceIcon: Icons.memory,
                isConnected: widget.isArduinoConnected,
                selectedPort: widget.selectedArduinoPort,
                primaryColor: EmeraldColors.primary,
                onPortChanged: widget.onArduinoPortChanged,
                onConnect: widget.onArduinoConnect,
                onDisconnect: widget.onArduinoDisconnect,
              ),
              // 燒入並檢測按鈕
              _buildProgramAndDetectButton(isCompact: false),
              // STM32 控制區
              _buildDeviceConnectionPanelMinimal(
                deviceName: 'STM32',
                deviceIcon: Icons.developer_board,
                isConnected: widget.isStm32Connected,
                selectedPort: widget.selectedStm32Port,
                primaryColor: SkyBlueColors.primary,
                onPortChanged: widget.onStm32PortChanged,
                onConnect: widget.onStm32Connect,
                onDisconnect: widget.onStm32Disconnect,
                firmwareVersion: widget.stm32FirmwareVersion,
              ),
            ],
          );
        }

        // 水平模式（緊湊或完整）- 三個 Card 佈局
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 左側：Arduino 控制區（Card）
                Expanded(
                  child: Card(
                    elevation: 3,
                    shadowColor: EmeraldColors.primary.withValues(alpha: 0.5),
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                      side: BorderSide(color: EmeraldColors.primary, width: 2),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: _buildDeviceConnectionPanel(
                      deviceName: tr('arduino_control'),
                      deviceIcon: Icons.memory,
                      isConnected: widget.isArduinoConnected,
                      selectedPort: widget.selectedArduinoPort,
                      primaryColor: EmeraldColors.primary,
                      secondaryColor: EmeraldColors.light,
                      onPortChanged: widget.onArduinoPortChanged,
                      onConnect: widget.onArduinoConnect,
                      onDisconnect: widget.onArduinoDisconnect,
                      isCompact: isCompact,
                    ),
                  ),
                ),
                // 中間：燒入並檢測按鈕
                _buildProgramAndDetectButton(isCompact: isCompact),
                // 右側：STM32 控制區（Card）
                Expanded(
                  child: Card(
                    elevation: 3,
                    shadowColor: SkyBlueColors.primary.withValues(alpha: 0.5),
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                      side: BorderSide(color: SkyBlueColors.primary, width: 2),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: _buildDeviceConnectionPanel(
                      deviceName: tr('stm32_control'),
                      deviceIcon: Icons.developer_board,
                      isConnected: widget.isStm32Connected,
                      selectedPort: widget.selectedStm32Port,
                      primaryColor: SkyBlueColors.primary,
                      secondaryColor: SkyBlueColors.light,
                      onPortChanged: widget.onStm32PortChanged,
                      onConnect: widget.onStm32Connect,
                      onDisconnect: widget.onStm32Disconnect,
                      firmwareVersion: widget.stm32FirmwareVersion,
                      isCompact: isCompact,
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

  /// 建構玻璃質感橢圓形按鈕 (Glassy Oval Button)
  Widget _buildMetallicButton({
    required bool isCompact,
    required bool isAutoDetecting,
    required VoidCallback onPressed,
  }) {
    // 玻璃質感配色
    const glassLight = Color(0xFFF5F5F5);
    const glassMid = Color(0xFFE8E8E8);
    const glassDark = Color(0xFFD0D0D0);
    const borderColor = Color(0xFFBDBDBD);
    const textColor = Color(0xFF424242);
    const disabledText = Color(0xFF9E9E9E);

    if (isCompact) {
      // 緊湊模式：圓形玻璃按鈕
      return Center(
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [glassLight, glassMid, glassDark],
              stops: [0.0, 0.5, 1.0],
            ),
            shape: BoxShape.circle,
            border: Border.all(color: borderColor, width: 1),
            boxShadow: const [
              BoxShadow(
                color: Colors.black26,
                blurRadius: 4,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: isAutoDetecting ? null : onPressed,
              borderRadius: BorderRadius.circular(20),
              child: Center(
                child: Icon(
                  isAutoDetecting ? Icons.hourglass_empty : Icons.play_arrow,
                  color: isAutoDetecting ? disabledText : textColor,
                  size: 22,
                ),
              ),
            ),
          ),
        ),
      );
    }

    // 完整模式：橢圓形玻璃按鈕
    return Center(
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(30),
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [glassLight, glassMid, glassDark],
            stops: [0.0, 0.6, 1.0],
          ),
          border: Border.all(color: borderColor, width: 1),
          boxShadow: const [
            BoxShadow(
              color: Colors.black26,
              blurRadius: 6,
              offset: Offset(0, 3),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: isAutoDetecting ? null : onPressed,
            borderRadius: BorderRadius.circular(30),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isAutoDetecting ? Icons.hourglass_empty : Icons.play_arrow,
                    color: isAutoDetecting ? disabledText : textColor,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    isAutoDetecting
                        ? tr('auto_detection_running')
                        : tr('auto_detection_start'),
                    style: TextStyle(
                      color: isAutoDetecting ? disabledText : textColor,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 建構燒入並檢測按鈕（玻璃質感，琥珀色調）
  Widget _buildProgramAndDetectButton({required bool isCompact}) {
    final canStart = widget.isStLinkConnected &&
                     !widget.isProgramming &&
                     !widget.isAutoDetecting;
    final isProcessing = widget.isProgramming || widget.isAutoDetecting;

    // 琥珀色玻璃質感配色
    final amberLight = Colors.amber.shade200;
    final amberMid = Colors.amber.shade400;
    final amberDark = Colors.amber.shade600;
    const borderColor = Color(0xFFFFB300); // 深琥珀色邊框
    const textColor = Color(0xFF424242);
    const disabledText = Color(0xFF9E9E9E);
    final disabledLight = Colors.grey.shade300;
    final disabledMid = Colors.grey.shade400;
    final disabledDark = Colors.grey.shade500;

    if (isCompact) {
      // 緊湊模式：圓形按鈕
      return Center(
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: canStart
                  ? [amberLight, amberMid, amberDark]
                  : [disabledLight, disabledMid, disabledDark],
              stops: const [0.0, 0.5, 1.0],
            ),
            shape: BoxShape.circle,
            border: Border.all(
              color: canStart ? borderColor : Colors.grey.shade400,
              width: 1,
            ),
            boxShadow: const [
              BoxShadow(
                color: Colors.black26,
                blurRadius: 4,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: canStart ? widget.onStartProgramAndDetect : null,
              borderRadius: BorderRadius.circular(20),
              child: Center(
                child: Icon(
                  isProcessing ? Icons.hourglass_empty : Icons.bolt,
                  color: canStart ? textColor : disabledText,
                  size: 22,
                ),
              ),
            ),
          ),
        ),
      );
    }

    // 完整模式：橢圓形按鈕
    return Center(
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(30),
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: canStart
                ? [amberLight, amberMid, amberDark]
                : [disabledLight, disabledMid, disabledDark],
            stops: const [0.0, 0.6, 1.0],
          ),
          border: Border.all(
            color: canStart ? borderColor : Colors.grey.shade400,
            width: 1,
          ),
          boxShadow: const [
            BoxShadow(
              color: Colors.black26,
              blurRadius: 6,
              offset: Offset(0, 3),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: canStart ? widget.onStartProgramAndDetect : null,
            borderRadius: BorderRadius.circular(30),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isProcessing ? Icons.hourglass_empty : Icons.bolt,
                    color: canStart ? textColor : disabledText,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    widget.isProgramming
                        ? tr('programming')
                        : tr('program_and_detect'),
                    style: TextStyle(
                      color: canStart ? textColor : disabledText,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 建構設備連接面板（原有兩行式佈局）
  Widget _buildDeviceConnectionPanel({
    required String deviceName,
    required IconData deviceIcon,
    required bool isConnected,
    required String? selectedPort,
    required Color primaryColor,
    required Color secondaryColor,
    required void Function(String?) onPortChanged,
    required VoidCallback onConnect,
    required VoidCallback onDisconnect,
    String? firmwareVersion,
    required bool isCompact,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 第一行：設備名稱和連接狀態
        Container(
          color: primaryColor,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            children: [
              Icon(deviceIcon, color: Colors.white, size: 16),
              const SizedBox(width: 6),
              // 設備名稱
              Text(
                deviceName,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              // 中間：韌體版本（置中顯示）
              Expanded(
                child: Center(
                  child: (firmwareVersion != null && isConnected)
                      ? Text(
                          'FW: $firmwareVersion',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
              ),
              // 連接狀態圖標
              Icon(
                isConnected ? Icons.link : Icons.link_off,
                color: Colors.white,
                size: 14,
              ),
            ],
          ),
        ),
        // 第二行：COM 選擇和連接按鈕
        Container(
          color: secondaryColor,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // COM 下拉選單
              Container(
                width: isCompact ? 70 : 80,
                height: 28,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(4),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 6),
                alignment: Alignment.center,
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: widget.availablePorts.contains(selectedPort) ? selectedPort : null,
                    hint: Text('COM', style: TextStyle(fontSize: isCompact ? 10 : 11)),
                    isExpanded: true,
                    isDense: true,
                    style: TextStyle(fontSize: isCompact ? 10 : 11, color: Colors.black),
                    iconSize: 16,
                    items: widget.availablePorts.map((port) {
                      return DropdownMenuItem(
                        value: port,
                        child: Text(port, style: TextStyle(fontSize: isCompact ? 10 : 11)),
                      );
                    }).toList(),
                    onChanged: isConnected ? null : onPortChanged,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // 連接/斷開按鈕
              SizedBox(
                height: 28,
                child: ElevatedButton(
                  onPressed: isConnected ? onDisconnect : onConnect,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isConnected ? Colors.red : Colors.white,
                    foregroundColor: isConnected ? Colors.white : Colors.black87,
                    padding: EdgeInsets.symmetric(horizontal: isCompact ? 8 : 12),
                    elevation: 0,
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(
                    isConnected ? tr('disconnect') : tr('connect'),
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: isCompact ? 10 : 11),
                  ),
                ),
              ),
              if (!isCompact) ...[
                const SizedBox(width: 8),
                // 連接狀態文字（只在完整模式顯示）
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: isConnected ? Colors.green : Colors.grey,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    isConnected ? tr('connected') : tr('not_connected'),
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  /// 建構極簡設備連接面板（用於垂直堆疊模式）
  Widget _buildDeviceConnectionPanelMinimal({
    required String deviceName,
    required IconData deviceIcon,
    required bool isConnected,
    required String? selectedPort,
    required Color primaryColor,
    required void Function(String?) onPortChanged,
    required VoidCallback onConnect,
    required VoidCallback onDisconnect,
    String? firmwareVersion,
  }) {
    return Container(
      color: primaryColor,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,  // 垂直置中
        children: [
          // 設備圖標
          Icon(deviceIcon, color: Colors.white, size: 14),
          const SizedBox(width: 4),
          // 設備名稱
          Text(
            deviceName,
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 2),
          // 連接狀態圖標
          Icon(
            isConnected ? Icons.link : Icons.link_off,
            color: Colors.white,
            size: 10,
          ),
          // 韌體版本（緊湊顯示）
          if (firmwareVersion != null && isConnected) ...[
            const SizedBox(width: 2),
            Text(
              firmwareVersion,
              style: TextStyle(
                fontSize: 8,
                color: Colors.white.withValues(alpha: 0.8),
              ),
            ),
          ],
          const Spacer(),
          // COM 下拉選單
          Container(
            width: 70,
            height: 26,  // 增加高度
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(3),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 4),
            alignment: Alignment.center,  // 內容置中
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: widget.availablePorts.contains(selectedPort) ? selectedPort : null,
                hint: const Text('COM', style: TextStyle(fontSize: 9)),
                isExpanded: true,
                isDense: true,
                style: const TextStyle(fontSize: 9, color: Colors.black),
                iconSize: 14,
                items: widget.availablePorts.map((port) {
                  return DropdownMenuItem(
                    value: port,
                    child: Text(port, style: const TextStyle(fontSize: 9)),
                  );
                }).toList(),
                onChanged: isConnected ? null : onPortChanged,
              ),
            ),
          ),
          const SizedBox(width: 4),
          // 連接/斷開按鈕
          SizedBox(
            height: 26,  // 增加高度，與 COM 下拉選單一致
            child: ElevatedButton(
              onPressed: isConnected ? onDisconnect : onConnect,
              style: ElevatedButton.styleFrom(
                backgroundColor: isConnected ? Colors.red : Colors.white,
                foregroundColor: isConnected ? Colors.white : primaryColor,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                elevation: 0,
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(
                isConnected ? tr('disconnect') : tr('connect'),
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 9),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 建構 ST-Link 燒入控制區
  Widget _buildStLinkProgramBar() {
    // 深紫色系配色（與其他區塊區分）
    const primaryColor = Color(0xFF7B1FA2);  // 深紫色
    const lightColor = Color(0xFFCE93D8);    // 淺紫色

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [primaryColor, lightColor],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          // ST-Link 狀態圖示
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(
              Icons.usb,
              color: widget.isStLinkConnected ? Colors.greenAccent : Colors.white70,
              size: 20,
            ),
          ),
          const SizedBox(width: 8),

          // ST-Link 連接狀態文字
          GestureDetector(
            onTap: widget.onCheckStLink,
            child: Text(
              widget.isStLinkConnected
                  ? 'ST-Link ${widget.stLinkInfo?.version ?? ""}'
                  : tr('stlink_not_connected'),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(width: 16),

          // 頻率選擇
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(4),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<int>(
                value: widget.stLinkFrequency,
                dropdownColor: primaryColor,
                icon: const Icon(Icons.arrow_drop_down, color: Colors.white, size: 18),
                style: const TextStyle(color: Colors.white, fontSize: 12),
                isDense: true,
                items: StLinkProgrammerService.frequencyOptions.map((freq) {
                  return DropdownMenuItem<int>(
                    value: freq,
                    child: Text('$freq kHz'),
                  );
                }).toList(),
                onChanged: widget.isProgramming ? null : (value) {
                  if (value != null) widget.onStLinkFrequencyChanged(value);
                },
              ),
            ),
          ),
          const SizedBox(width: 16),

          // 韌體檔案選擇
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(4),
              ),
              child: widget.firmwareFiles.isEmpty
                  ? Text(
                      tr('no_firmware_files'),
                      style: const TextStyle(color: Colors.white70, fontSize: 12),
                    )
                  : widget.firmwareFiles.length == 1
                      ? Text(
                          widget.firmwareFiles.first.path.split(Platform.pathSeparator).last,
                          style: const TextStyle(color: Colors.white, fontSize: 12),
                          overflow: TextOverflow.ellipsis,
                        )
                      : DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: widget.selectedFirmwarePath,
                            dropdownColor: primaryColor,
                            icon: const Icon(Icons.arrow_drop_down, color: Colors.white, size: 18),
                            style: const TextStyle(color: Colors.white, fontSize: 12),
                            isDense: true,
                            isExpanded: true,
                            hint: Text(
                              tr('select_firmware'),
                              style: const TextStyle(color: Colors.white70, fontSize: 12),
                            ),
                            items: widget.firmwareFiles.map((file) {
                              final fileName = file.path.split(Platform.pathSeparator).last;
                              return DropdownMenuItem<String>(
                                value: file.path,
                                child: Text(fileName, overflow: TextOverflow.ellipsis),
                              );
                            }).toList(),
                            onChanged: widget.isProgramming ? null : widget.onFirmwareSelected,
                          ),
                        ),
            ),
          ),
        ],
      ),
    );
  }

  /// 建構燒入進度指示器
  Widget _buildProgramProgress() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: Colors.purple.shade50,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 進度條
          LinearProgressIndicator(
            value: widget.programProgress > 0 ? widget.programProgress : null,
            backgroundColor: Colors.purple.shade100,
            valueColor: AlwaysStoppedAnimation<Color>(Colors.purple.shade600),
          ),
          const SizedBox(height: 6),
          // 狀態文字
          Text(
            widget.programStatus ?? '',
            style: TextStyle(
              fontSize: 12,
              color: Colors.purple.shade800,
              fontWeight: FontWeight.w500,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  /// 建構自動檢測進度指示器
  Widget _buildAutoDetectionProgress() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: Colors.blue.shade50,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 進度條
          LinearProgressIndicator(
            value: widget.autoDetectionProgress > 0 ? widget.autoDetectionProgress : null,
            backgroundColor: Colors.blue.shade100,
            valueColor: AlwaysStoppedAnimation<Color>(Colors.blue.shade600),
          ),
          const SizedBox(height: 6),
          // 狀態文字
          Text(
            widget.autoDetectionStatus ?? '',
            style: TextStyle(
              fontSize: 12,
              color: Colors.blue.shade800,
              fontWeight: FontWeight.w500,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  /// 建構硬體數據區塊
  Widget _buildHardwareSection({
    required String title,
    required HardwareState state,
    required Color color,
  }) {
    // 判斷是否為 Running 區域且使用新模式
    final isRunningWithNewMode = state == HardwareState.running && widget.adjacentDisplayInRunning;

    return Container(
      color: Colors.grey.shade50,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 標題列（使用圓角裝飾，配合 Card 的 clipBehavior）
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: color,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(10),
                topRight: Radius.circular(10),
              ),
            ),
            child: Row(
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const Spacer(),
                // 詳細資料展開按鈕（僅 Running 區塊顯示）
                if (state == HardwareState.running)
                  IconButton(
                    icon: Icon(
                      _showAdjacentDetails ? Icons.expand_less : Icons.expand_more,
                      color: Colors.white,
                      size: 20,
                    ),
                    onPressed: () => setState(() => _showAdjacentDetails = !_showAdjacentDetails),
                    tooltip: tr('show_adjacent_details'),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  ),
              ],
            ),
          ),
          // 表頭（根據模式選擇不同表頭）
          isRunningWithNewMode ? _buildRunningTableHeaderWithAdjacent() : _buildTableHeader(),
          // 數據列表
          Expanded(
            child: SingleChildScrollView(
              // 根據 state 選擇對應的 ScrollController
              controller: state == HardwareState.idle ? _idleScrollController : _runningScrollController,
              child: Column(
                children: List.generate(18, (id) =>
                  isRunningWithNewMode
                    ? _buildRunningDataRowWithAdjacent(id)
                    : _buildHardwareDataRow(id, state)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 建構感應偵測區塊
  Widget _buildSensorSection() {
    return Container(
      color: Colors.grey.shade100,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 標題列（使用圓角裝飾，配合 Card 的 clipBehavior）
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.grey.shade600,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(10),
                topRight: Radius.circular(10),
              ),
            ),
            child: Text(
              tr('sensor_detection'),
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // 表頭
          _buildTableHeader(),
          // 數據列表
          Expanded(
            child: SingleChildScrollView(
              controller: _sensorScrollController,
              child: Column(
                children: List.generate(6, (i) => _buildSensorDataRow(i + 18)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 建構表頭
  Widget _buildTableHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        border: Border(
          bottom: BorderSide(color: Colors.grey.shade400),
        ),
      ),
      child: Row(
        children: [
          // 名稱欄
          Expanded(
            flex: 2,
            child: Text(
              tr('column_name'),
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 10),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // Arduino 欄
          Expanded(
            flex: 2,
            child: Text(
              tr('column_arduino'),
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 10,
                color: Color(0xFF2E7D32), // EmeraldColors.dark
              ),
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // STM32 欄
          Expanded(
            flex: 2,
            child: Text(
              tr('column_stm32'),
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 10,
                color: Color(0xFF1976D2), // SkyBlueColors.dark
              ),
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // 差值欄（已隱藏 - 目前未使用）
          // Expanded(
          //   flex: 2,
          //   child: Text(
          //     tr('column_diff'),
          //     style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 10),
          //     textAlign: TextAlign.center,
          //     overflow: TextOverflow.ellipsis,
          //   ),
          // ),
          // 狀態欄
          const SizedBox(
            width: 28,
            child: Text(
              '',  // 狀態欄不顯示標題文字，節省空間
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  /// 建構 Running 區域表頭（新模式：包含相鄰腳位欄位）
  Widget _buildRunningTableHeaderWithAdjacent() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        border: Border(
          bottom: BorderSide(color: Colors.grey.shade400),
        ),
      ),
      child: Row(
        children: [
          // 名稱欄
          Expanded(
            flex: 2,
            child: Text(
              tr('column_name'),
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 9),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // Arduino 欄
          Expanded(
            flex: 2,
            child: Text(
              tr('column_arduino'),
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 9,
                color: Color(0xFF2E7D32),
              ),
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // STM32 欄
          Expanded(
            flex: 2,
            child: Text(
              tr('column_stm32'),
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 9,
                color: Color(0xFF1976D2),
              ),
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // 相鄰 1 欄
          Expanded(
            flex: 2,
            child: Text(
              tr('adjacent_idle_1'),
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 9,
                color: Colors.purple.shade700,
              ),
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // 相鄰 2 欄
          Expanded(
            flex: 2,
            child: Text(
              tr('adjacent_idle_2'),
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 9,
                color: Colors.purple.shade700,
              ),
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // 狀態欄
          const SizedBox(
            width: 24,
            child: Text(
              '',
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  /// 建構 Running 區域數據行（新模式：包含相鄰腳位數據）
  Widget _buildRunningDataRowWithAdjacent(int id) {
    final name = DisplayNames.getName(id);
    final thresholdService = ThresholdSettingsService();

    // 取得 Running 狀態數據
    final arduinoData = widget.dataStorage.getArduinoLatestRunningData(id);
    final stm32Data = widget.dataStorage.getStm32LatestRunningData(id);

    final arduinoValue = arduinoData?.value;
    final stm32Value = stm32Data?.value;

    // 判斷狀態
    bool arduinoInRange = true;
    bool stm32InRange = true;

    if (arduinoValue != null) {
      arduinoInRange = thresholdService.validateHardwareValue(
        DeviceType.arduino, StateType.running, id, arduinoValue);
    }

    if (stm32Value != null) {
      stm32InRange = thresholdService.validateHardwareValue(
        DeviceType.stm32, StateType.running, id, stm32Value);
    }

    final isError = !arduinoInRange || !stm32InRange;

    // 取得相鄰腳位數據
    final adjacentDataList = widget.adjacentIdleData?[id] ?? [];
    final adjacentY = adjacentDataList.isNotEmpty ? adjacentDataList[0] : null;
    final adjacentZ = adjacentDataList.length > 1 ? adjacentDataList[1] : null;

    // 判斷當前項目是否正在被讀取
    final isCurrentlyReading = widget.currentReadingId == id && widget.currentReadingSection == 'running';

    return Container(
      constraints: BoxConstraints(minHeight: _hardwareRowHeight),  // 使用統一的行高
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      decoration: BoxDecoration(
        color: isCurrentlyReading ? Colors.yellow.shade200 : null,
        border: Border(
          bottom: BorderSide(color: Colors.grey.shade300),
        ),
      ),
      child: Row(
        children: [
          // 名稱欄
          Expanded(
            flex: 2,
            child: Container(
              padding: isCurrentlyReading
                  ? const EdgeInsets.symmetric(horizontal: 4, vertical: 2)
                  : EdgeInsets.zero,
              decoration: isCurrentlyReading
                  ? BoxDecoration(
                      color: Colors.orange.shade300,
                      borderRadius: BorderRadius.circular(4),
                    )
                  : null,
              child: Text(
                name,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 9,
                  color: isCurrentlyReading ? Colors.white : null,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          // Arduino 欄
          Expanded(
            flex: 2,
            child: Text(
              arduinoValue != null ? '$arduinoValue' : '--',
              style: TextStyle(
                fontSize: 9,
                fontWeight: (arduinoValue != null && !arduinoInRange)
                    ? FontWeight.bold : FontWeight.normal,
                color: arduinoValue != null
                    ? (arduinoInRange ? EmeraldColors.dark : Colors.red)
                    : Colors.grey,
              ),
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // STM32 欄
          Expanded(
            flex: 2,
            child: Text(
              stm32Value != null ? '$stm32Value' : '--',
              style: TextStyle(
                fontSize: 9,
                fontWeight: (stm32Value != null && !stm32InRange)
                    ? FontWeight.bold : FontWeight.normal,
                color: stm32Value != null
                    ? (stm32InRange ? SkyBlueColors.dark : Colors.red)
                    : Colors.grey,
              ),
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // 相鄰 Y 欄
          Expanded(
            flex: 2,
            child: _buildAdjacentIdleCell(adjacentY),
          ),
          // 相鄰 Z 欄
          Expanded(
            flex: 2,
            child: _buildAdjacentIdleCell(adjacentZ),
          ),
          // 狀態燈欄
          SizedBox(
            width: 24,
            child: Center(
              child: (arduinoValue != null && stm32Value != null)
                  ? Container(
                      width: 16,
                      height: 16,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isError ? Colors.red : Colors.green,
                        boxShadow: [
                          BoxShadow(
                            color: (isError ? Colors.red : Colors.green).withValues(alpha: 0.5),
                            blurRadius: 3,
                            spreadRadius: 0.5,
                          ),
                        ],
                      ),
                      child: Icon(
                        isError ? Icons.close : Icons.check,
                        color: Colors.white,
                        size: 10,
                      ),
                    )
                  : Container(
                      width: 16,
                      height: 16,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.grey.shade400,
                      ),
                      child: const Icon(
                        Icons.remove,
                        color: Colors.white,
                        size: 10,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  /// 建構相鄰腳位 Idle 數據欄位
  /// 顯示格式：名稱 + Arduino/STM32 數值
  /// 特殊類型（Vdd/Vss/none）直接顯示標籤
  Widget _buildAdjacentIdleCell(AdjacentIdleData? data) {
    if (data == null) {
      return const Text(
        '--',
        style: TextStyle(fontSize: 9, color: Colors.grey),
        textAlign: TextAlign.center,
      );
    }

    // 特殊類型：直接顯示標籤
    if (data.isSpecialType) {
      String label;
      Color color;
      IconData? icon;

      switch (data.dataType) {
        case AdjacentDataType.vdd:
          label = 'Vdd';
          color = Colors.orange.shade700;
          icon = Icons.bolt;
          break;
        case AdjacentDataType.vss:
          label = 'Vss';
          color = Colors.brown.shade600;
          icon = Icons.horizontal_rule;
          break;
        case AdjacentDataType.none:
          label = 'none';
          color = Colors.grey.shade500;
          icon = Icons.remove_circle_outline;
          break;
        default:
          label = '--';
          color = Colors.grey;
          icon = null;
      }

      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null)
            Icon(icon, size: 10, color: color),
          Text(
            label,
            style: TextStyle(
              fontSize: 9,
              color: color,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      );
    }

    // 一般 GPIO 類型：顯示名稱 + Arduino/STM32 數值
    final hasShort = data.isShort;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 相鄰腳位名稱
        Text(
          data.pinName,
          style: TextStyle(
            fontSize: 8,
            color: hasShort ? Colors.red : Colors.purple.shade700,
            fontWeight: FontWeight.bold,
          ),
          overflow: TextOverflow.ellipsis,
        ),
        // Arduino/STM32 數值
        Text(
          '${data.arduinoValue ?? "-"}/${data.stm32Value ?? "-"}',
          style: TextStyle(
            fontSize: 9,
            color: hasShort ? Colors.red : Colors.black87,
            fontWeight: hasShort ? FontWeight.bold : FontWeight.normal,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  /// 建構硬體數據行
  /// 使用 ThresholdSettingsService 的範圍設定來判斷狀態
  Widget _buildHardwareDataRow(int id, HardwareState state) {
    final name = DisplayNames.getName(id);
    final thresholdService = ThresholdSettingsService();

    // 取得 Arduino 和 STM32 的數據
    // Idle 區域使用第一筆數據（原始基準值），不會被後續相鄰讀取覆蓋
    // Running 區域使用最新數據
    final arduinoData = state == HardwareState.idle
        ? widget.dataStorage.getArduinoFirstIdleData(id)
        : widget.dataStorage.getArduinoLatestRunningData(id);
    final stm32Data = state == HardwareState.idle
        ? widget.dataStorage.getStm32FirstIdleData(id)
        : widget.dataStorage.getStm32LatestRunningData(id);

    final arduinoValue = arduinoData?.value;
    final stm32Value = stm32Data?.value;

    // 計算差值（以 Arduino 為基準：Arduino - STM32）- 僅供顯示
    int? diff;
    if (arduinoValue != null && stm32Value != null) {
      diff = arduinoValue - stm32Value;
    }

    // 判斷狀態 - 使用範圍驗證
    // Arduino 和 STM32 各自驗證是否在其設定的範圍內
    final stateType = state == HardwareState.idle ? StateType.idle : StateType.running;

    bool arduinoInRange = true;
    bool stm32InRange = true;

    if (arduinoValue != null) {
      arduinoInRange = thresholdService.validateHardwareValue(
        DeviceType.arduino, stateType, id, arduinoValue);
    }

    if (stm32Value != null) {
      stm32InRange = thresholdService.validateHardwareValue(
        DeviceType.stm32, stateType, id, stm32Value);
    }

    // 只要有一個設備的數值超出範圍就是 Error
    final isError = !arduinoInRange || !stm32InRange;

    // 根據 state 決定區域類型
    final section = state == HardwareState.idle ? 'idle' : 'running';

    return _buildDataRow(
      id: id,
      section: section,
      name: name,
      arduinoValue: arduinoValue,
      stm32Value: stm32Value,
      diff: diff,
      isError: isError,
      isTemperature: false,
      arduinoInRange: arduinoInRange,
      stm32InRange: stm32InRange,
      minHeight: _hardwareRowHeight,  // 使用統一的行高
    );
  }

  /// 建構感測器數據行
  /// 使用 ThresholdSettingsService 的範圍設定來判斷狀態
  /// ID 21-23 (MCUtemp, WATERtemp, BIBtemp) 的 STM32 數值需要與 Arduino MCUtemp (ID 21) 進行溫差比對
  Widget _buildSensorDataRow(int id) {
    final name = DisplayNames.getName(id);
    final isTemp = ErrorThresholds.isTemperature(id);
    final thresholdService = ThresholdSettingsService();

    // 感測器數據不區分狀態，取最新的
    // Arduino 只有 ID 18-21，沒有 22, 23
    int? arduinoValue;
    bool arduinoHasSensor = (id <= 21);  // Arduino 只有到 ID 21

    // 取得 Arduino MCUtemp (ID 21) 的數值，用於 ID 22, 23 的溫差比對
    int? arduinoMcuTemp;
    {
      final runningData = widget.dataStorage.getArduinoLatestRunningData(21);
      final idleData = widget.dataStorage.getArduinoLatestIdleData(21);
      final data = runningData ?? idleData;
      if (data != null) {
        arduinoMcuTemp = data.value ~/ 10;  // MCUtemp 需要除以 10
      }
    }

    if (arduinoHasSensor) {
      final runningData = widget.dataStorage.getArduinoLatestRunningData(id);
      final idleData = widget.dataStorage.getArduinoLatestIdleData(id);
      final data = runningData ?? idleData;
      if (data != null) {
        arduinoValue = data.value;
        // MCUtemp (ID 21) 需要除以 10
        if (id == 21) {
          arduinoValue = arduinoValue ~/ 10;
        }
      }
    }
    // ID 22, 23 Arduino 沒有這些感測器
    // 但需要顯示 Arduino MCUtemp 作為比對基準
    int? displayArduinoValue = arduinoHasSensor ? arduinoValue : arduinoMcuTemp;

    // STM32 數據
    final stm32RunningData = widget.dataStorage.getStm32LatestRunningData(id);
    final stm32IdleData = widget.dataStorage.getStm32LatestIdleData(id);
    final stm32Data = stm32RunningData ?? stm32IdleData;
    final stm32Value = stm32Data?.value;

    // 計算差值
    // ID 21-23 (溫度): 與 Arduino MCUtemp 比對溫差
    // 其他 ID: Arduino - STM32
    int? diff;
    if (id >= 21 && id <= 23) {
      // MCUtemp/WATERtemp/BIBtemp 與 Arduino MCUtemp 比對
      if (arduinoMcuTemp != null && stm32Value != null) {
        diff = arduinoMcuTemp - stm32Value;
      }
    } else if (arduinoHasSensor && arduinoValue != null && stm32Value != null) {
      diff = arduinoValue - stm32Value;
    }

    // 判斷狀態 - 使用範圍驗證
    bool arduinoInRange = true;
    bool stm32InRange = true;
    bool tempDiffOk = true;  // 溫差是否在閾值內

    if (arduinoHasSensor && arduinoValue != null) {
      arduinoInRange = thresholdService.validateSensorValue(
        DeviceType.arduino, id, arduinoValue);
    }

    if (stm32Value != null) {
      stm32InRange = thresholdService.validateSensorValue(
        DeviceType.stm32, id, stm32Value);
    }

    // ID 21-23 (溫度): 檢查 STM32 與 Arduino MCUtemp 的溫差是否超過閾值
    if (id >= 21 && id <= 23 && arduinoMcuTemp != null && stm32Value != null) {
      final diffThreshold = thresholdService.getDiffThreshold(id);
      tempDiffOk = (arduinoMcuTemp - stm32Value).abs() <= diffThreshold;
    }

    // 判斷錯誤狀態
    bool isError;
    if (id >= 21 && id <= 23) {
      // 溫度類 (MCUtemp/WATERtemp/BIBtemp):
      // - Arduino 範圍驗證 (僅 ID 21)
      // - STM32 範圍驗證
      // - 與 Arduino MCUtemp 溫差驗證
      if (id == 21) {
        isError = !arduinoInRange || !stm32InRange || !tempDiffOk;
      } else {
        isError = !stm32InRange || !tempDiffOk;
      }
    } else if (arduinoHasSensor) {
      // Arduino 有此感測器：任一設備超出範圍就是 Error
      isError = !arduinoInRange || !stm32InRange;
    } else {
      // 其他情況
      isError = stm32Value != null && !stm32InRange;
    }

    return _buildDataRow(
      id: id,
      section: 'sensor',  // 感測器區域
      name: name,
      arduinoValue: displayArduinoValue,  // ID 22, 23 顯示 MCUtemp
      stm32Value: stm32Value,
      diff: diff,
      isError: isError,
      isTemperature: isTemp,
      showNaForArduino: false,  // ID 22, 23 也顯示 Arduino MCUtemp
      arduinoInRange: arduinoInRange && (id >= 21 && id <= 23 ? tempDiffOk : true),
      stm32InRange: stm32InRange && (id >= 21 && id <= 23 ? tempDiffOk : true),
    );
  }

  /// 建構單一數據行
  Widget _buildDataRow({
    required int id,  // 項目 ID，用於高亮判斷
    required String section,  // 區域類型：idle / running / sensor
    required String name,
    required int? arduinoValue,
    required int? stm32Value,
    required int? diff,
    required bool isError,
    required bool isTemperature,
    bool showNaForArduino = false,  // ID 22, 23 Arduino 沒有這些感測器
    bool arduinoInRange = true,  // Arduino 數值是否在範圍內
    bool stm32InRange = true,    // STM32 數值是否在範圍內
    double? minHeight,  // 可選的最小高度（用於硬體區域統一高度）
  }) {
    // 判斷是否有數據可比較
    final hasData = arduinoValue != null && stm32Value != null;

    // 判斷當前項目是否正在被讀取（用於高亮顯示）
    // 需要同時匹配 ID 和區域類型
    final isCurrentlyReading = widget.currentReadingId == id && widget.currentReadingSection == section;

    // 判斷是否為次要高亮項目（短路測試中的所有相鄰腳位，固定顯示在 Idle 區域）
    final isSecondaryReading = section == 'idle' &&
        widget.secondaryReadingIds != null &&
        widget.secondaryReadingIds!.contains(id);

    // 決定背景顏色：主要高亮 > 次要高亮 > 無
    Color? backgroundColor;
    if (isCurrentlyReading) {
      backgroundColor = Colors.yellow.shade200;
    } else if (isSecondaryReading) {
      backgroundColor = Colors.yellow.shade50;  // 較淡的黃色
    }

    return Container(
      constraints: minHeight != null ? BoxConstraints(minHeight: minHeight) : null,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      decoration: BoxDecoration(
        // 正在讀取時顯示高亮背景
        color: backgroundColor,
        border: Border(
          bottom: BorderSide(color: Colors.grey.shade300),
        ),
      ),
      child: Row(
        children: [
          // 名稱欄
          Expanded(
            flex: 2,
            child: Container(
              padding: (isCurrentlyReading || isSecondaryReading)
                  ? const EdgeInsets.symmetric(horizontal: 4, vertical: 2)
                  : EdgeInsets.zero,
              decoration: isCurrentlyReading
                  ? BoxDecoration(
                      color: Colors.orange.shade300,
                      borderRadius: BorderRadius.circular(4),
                    )
                  : isSecondaryReading
                      ? BoxDecoration(
                          color: Colors.orange.shade100,  // 較淡的橘色
                          borderRadius: BorderRadius.circular(4),
                        )
                      : null,
              child: Text(
                name,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 10,
                  color: isCurrentlyReading ? Colors.white : (isSecondaryReading ? Colors.orange.shade800 : null),
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          // Arduino 欄
          Expanded(
            flex: 2,
            child: Text(
              showNaForArduino
                  ? 'N/A'
                  : (arduinoValue != null ? '$arduinoValue' : '--'),
              style: TextStyle(
                fontSize: 10,
                fontWeight: (!showNaForArduino && arduinoValue != null && !arduinoInRange)
                    ? FontWeight.bold : FontWeight.normal,
                color: showNaForArduino
                    ? Colors.grey.shade400
                    : (arduinoValue != null
                        ? (arduinoInRange ? EmeraldColors.dark : Colors.red)
                        : Colors.grey),
                fontStyle: showNaForArduino ? FontStyle.italic : FontStyle.normal,
              ),
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // STM32 欄
          Expanded(
            flex: 2,
            child: Text(
              stm32Value != null ? '$stm32Value' : '--',
              style: TextStyle(
                fontSize: 10,
                fontWeight: (stm32Value != null && !stm32InRange)
                    ? FontWeight.bold : FontWeight.normal,
                color: stm32Value != null
                    ? (stm32InRange ? SkyBlueColors.dark : Colors.red)
                    : Colors.grey,
              ),
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // 差值欄（已隱藏 - 目前未使用）
          // Expanded(
          //   flex: 2,
          //   child: Text(
          //     showNaForArduino
          //         ? 'N/A'
          //         : (diff != null
          //             ? (diff >= 0 ? '+$diff' : '$diff')
          //             : '--'),
          //     style: TextStyle(
          //       fontSize: 10,
          //       fontWeight: (!showNaForArduino && diff != null) ? FontWeight.bold : FontWeight.normal,
          //       fontStyle: showNaForArduino ? FontStyle.italic : FontStyle.normal,
          //       color: showNaForArduino
          //           ? Colors.grey.shade400
          //           : (diff != null
          //               ? (isError ? Colors.red : Colors.black)
          //               : Colors.grey),
          //     ),
          //     textAlign: TextAlign.center,
          //     overflow: TextOverflow.ellipsis,
          //   ),
          // ),
          // 狀態燈欄
          // 對於 ID 22, 23 (showNaForArduino=true)，只要 STM32 有數據就顯示綠燈
          SizedBox(
            width: 28,
            child: Center(
              child: (showNaForArduino ? stm32Value != null : hasData)
                  ? Container(
                      width: 18,
                      height: 18,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isError ? Colors.red : Colors.green,
                        boxShadow: [
                          BoxShadow(
                            color: (isError ? Colors.red : Colors.green).withValues(alpha: 0.5),
                            blurRadius: 3,
                            spreadRadius: 0.5,
                          ),
                        ],
                      ),
                      child: Icon(
                        isError ? Icons.close : Icons.check,
                        color: Colors.white,
                        size: 12,
                      ),
                    )
                  : Container(
                      width: 18,
                      height: 18,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.grey.shade400,
                      ),
                      child: const Icon(
                        Icons.remove,
                        color: Colors.white,
                        size: 12,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// Debug 解析用資料類別
// ============================================================================

/// 解析後的調試數據
class _DebugParsedData {
  final String runningPinName;
  final int runningId;
  final String adjacentIds;
  final List<_DebugTestResult> testResults;

  _DebugParsedData({
    required this.runningPinName,
    required this.runningId,
    required this.adjacentIds,
    required this.testResults,
  });
}

/// 單個測試結果
class _DebugTestResult {
  final int index;
  final String pinName;
  final int pinId;

  String? pairLeft;
  String? pairRight;

  String? stm32Base;
  String? stm32New;
  String? stm32Diff;
  bool stm32IsNormal = true;

  String? arduinoBase;
  String? arduinoNew;
  String? arduinoDiff;
  bool arduinoIsNormal = true;
  bool arduinoSkipped = false;

  String? threshold;

  _DebugTestResult({
    required this.index,
    required this.pinName,
    required this.pinId,
  });
}
