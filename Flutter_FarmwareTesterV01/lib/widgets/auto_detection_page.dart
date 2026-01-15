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
import '../services/data_storage_service.dart';
import '../services/localization_service.dart';
import '../services/threshold_settings_service.dart';
import '../services/stlink_programmer_service.dart';
import 'data_storage_page.dart';

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

  /// UVC 燈 (ID 11-13) 誤差閾值
  static const int mainUvc = 250;
  static const int spoutUvc = 250;
  static const int mixUvc = 250;

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
      case 11: return mainUvc;
      case 12: return spoutUvc;
      case 13: return mixUvc;
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

class AutoDetectionPage extends StatelessWidget {
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
  });

  @override
  Widget build(BuildContext context) {
    // 監聽語言變更，自動更新 UI
    return ValueListenableBuilder<AppLanguage>(
      valueListenable: LocalizationService().currentLanguageNotifier,
      builder: (context, _, __) {
        return ValueListenableBuilder<int>(
          valueListenable: dataStorage.dataUpdateNotifier,
          builder: (context, _, __) {
            return ValueListenableBuilder<int>(
              valueListenable: dataStorage.runningStateNotifier,
              builder: (context, _, __) {
                return Column(
                  children: [
                    // 最上方：ST-Link 燒入控制區
                    _buildStLinkProgramBar(),
                    // 燒入進度指示器（僅在燒入中時顯示）
                    if (isProgramming) _buildProgramProgress(),
                    // COM 選擇和連接控制區 + 自動檢測按鈕
                    _buildConnectionControlBar(),
                    // 自動檢測進度指示器（僅在進行中時顯示）
                    if (isAutoDetecting) _buildAutoDetectionProgress(),
                    // 中間：硬體數據區 (ID 0-17)
                    Expanded(
                      flex: 3,
                      child: Row(
                        children: [
                          // 左邊：無動作區
                          Expanded(
                            child: _buildHardwareSection(
                              title: tr('hardware_idle'),
                              state: HardwareState.idle,
                              color: Colors.blueGrey,
                            ),
                          ),
                          const VerticalDivider(width: 1),
                          // 右邊：動作中區
                          Expanded(
                            child: _buildHardwareSection(
                              title: tr('hardware_running'),
                              state: HardwareState.running,
                              color: Colors.orange.shade700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    // 下方：感應偵測區 (ID 18-23)
                    // flex 增加到 2 以容納 6 行感測器資料
                    Expanded(
                      flex: 2,
                      child: _buildSensorSection(),
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
                isConnected: isArduinoConnected,
                selectedPort: selectedArduinoPort,
                primaryColor: EmeraldColors.primary,
                onPortChanged: onArduinoPortChanged,
                onConnect: onArduinoConnect,
                onDisconnect: onArduinoDisconnect,
              ),
              // 自動檢測按鈕（金屬機械風格）
              _buildMetallicButton(
                isCompact: false,
                isAutoDetecting: isAutoDetecting,
                onPressed: () => onStartAutoDetection?.call(),
              ),
              // STM32 控制區
              _buildDeviceConnectionPanelMinimal(
                deviceName: 'STM32',
                deviceIcon: Icons.developer_board,
                isConnected: isStm32Connected,
                selectedPort: selectedStm32Port,
                primaryColor: SkyBlueColors.primary,
                onPortChanged: onStm32PortChanged,
                onConnect: onStm32Connect,
                onDisconnect: onStm32Disconnect,
                firmwareVersion: stm32FirmwareVersion,
              ),
            ],
          );
        }

        // 水平模式（緊湊或完整）- 原有兩行式佈局
        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 左側：Arduino 控制區
              Expanded(
                child: _buildDeviceConnectionPanel(
                  deviceName: tr('arduino_control'),
                  deviceIcon: Icons.memory,
                  isConnected: isArduinoConnected,
                  selectedPort: selectedArduinoPort,
                  primaryColor: EmeraldColors.primary,
                  secondaryColor: EmeraldColors.light,
                  onPortChanged: onArduinoPortChanged,
                  onConnect: onArduinoConnect,
                  onDisconnect: onArduinoDisconnect,
                  isCompact: isCompact,
                ),
              ),
              // 中間：自動檢測開始按鈕（金屬機械風格）
              _buildMetallicButton(
                isCompact: isCompact,
                isAutoDetecting: isAutoDetecting,
                onPressed: () => onStartAutoDetection?.call(),
              ),
              // 右側：STM32 控制區
              Expanded(
                child: _buildDeviceConnectionPanel(
                  deviceName: tr('stm32_control'),
                  deviceIcon: Icons.developer_board,
                  isConnected: isStm32Connected,
                  selectedPort: selectedStm32Port,
                  primaryColor: SkyBlueColors.primary,
                  secondaryColor: SkyBlueColors.light,
                  onPortChanged: onStm32PortChanged,
                  onConnect: onStm32Connect,
                  onDisconnect: onStm32Disconnect,
                  firmwareVersion: stm32FirmwareVersion,
                  isCompact: isCompact,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// 建構玻璃質感橢圓形按鈕 (Glassy Oval Button) - 四角顏色背景
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

    // 四角顏色（左邊 Arduino 綠色系，右邊 STM32 藍色系）
    const leftTopColor = EmeraldColors.primary;       // 左上 - Arduino 深綠
    const leftBottomColor = EmeraldColors.light;      // 左下 - Arduino 淺綠
    const rightTopColor = SkyBlueColors.primary;      // 右上 - STM32 深藍
    const rightBottomColor = SkyBlueColors.light;     // 右下 - STM32 淺藍

    if (isCompact) {
      // 緊湊模式：四角背景 + 圓形玻璃按鈕
      return SizedBox(
        width: 48,
        height: 48,
        child: Stack(
          children: [
            // 四角顏色背景
            Row(
              children: [
                // 左側（Arduino 綠色）
                Expanded(
                  child: Column(
                    children: [
                      Expanded(child: Container(color: leftTopColor)),
                      Expanded(child: Container(color: leftBottomColor)),
                    ],
                  ),
                ),
                // 右側（STM32 藍色）
                Expanded(
                  child: Column(
                    children: [
                      Expanded(child: Container(color: rightTopColor)),
                      Expanded(child: Container(color: rightBottomColor)),
                    ],
                  ),
                ),
              ],
            ),
            // 中央圓形玻璃按鈕
            Center(
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
            ),
          ],
        ),
      );
    }

    // 完整模式：四角背景 + 橢圓形玻璃按鈕
    // 高度需要匹配左右面板的兩行高度
    // 第一行: padding 6*2 + 內容約16 = 28
    // 第二行: padding 4*2 + 內容28 = 36
    const buttonWidth = 200.0;

    return SizedBox(
      width: buttonWidth,
      child: Stack(
        children: [
          // 四角顏色背景（使用 Column + Expanded 對齊左右面板高度）
          Column(
            children: [
              // 上半部（對應第一行：設備名稱列）
              Expanded(
                flex: 29,
                child: Row(
                  children: [
                    Expanded(child: Container(color: leftTopColor)),
                    Expanded(child: Container(color: rightTopColor)),
                  ],
                ),
              ),
              // 下半部（對應第二行：COM選擇列）
              Expanded(
                flex: 35,
                child: Row(
                  children: [
                    Expanded(child: Container(color: leftBottomColor)),
                    Expanded(child: Container(color: rightBottomColor)),
                  ],
                ),
              ),
            ],
          ),
          // 中央橢圓形玻璃按鈕
          Center(
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
          ),
        ],
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
                    value: availablePorts.contains(selectedPort) ? selectedPort : null,
                    hint: Text('COM', style: TextStyle(fontSize: isCompact ? 10 : 11)),
                    isExpanded: true,
                    isDense: true,
                    style: TextStyle(fontSize: isCompact ? 10 : 11, color: Colors.black),
                    iconSize: 16,
                    items: availablePorts.map((port) {
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
                value: availablePorts.contains(selectedPort) ? selectedPort : null,
                hint: const Text('COM', style: TextStyle(fontSize: 9)),
                isExpanded: true,
                isDense: true,
                style: const TextStyle(fontSize: 9, color: Colors.black),
                iconSize: 14,
                items: availablePorts.map((port) {
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

    // 判斷是否可以開始燒入
    final canStartProgram = isStLinkConnected &&
        selectedFirmwarePath != null &&
        !isProgramming &&
        !isAutoDetecting;

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
              color: isStLinkConnected ? Colors.greenAccent : Colors.white70,
              size: 20,
            ),
          ),
          const SizedBox(width: 8),

          // ST-Link 連接狀態文字
          GestureDetector(
            onTap: onCheckStLink,
            child: Text(
              isStLinkConnected
                  ? 'ST-Link ${stLinkInfo?.version ?? ""}'
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
                value: stLinkFrequency,
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
                onChanged: isProgramming ? null : (value) {
                  if (value != null) onStLinkFrequencyChanged(value);
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
              child: firmwareFiles.isEmpty
                  ? Text(
                      tr('no_firmware_files'),
                      style: const TextStyle(color: Colors.white70, fontSize: 12),
                    )
                  : firmwareFiles.length == 1
                      ? Text(
                          firmwareFiles.first.path.split(Platform.pathSeparator).last,
                          style: const TextStyle(color: Colors.white, fontSize: 12),
                          overflow: TextOverflow.ellipsis,
                        )
                      : DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: selectedFirmwarePath,
                            dropdownColor: primaryColor,
                            icon: const Icon(Icons.arrow_drop_down, color: Colors.white, size: 18),
                            style: const TextStyle(color: Colors.white, fontSize: 12),
                            isDense: true,
                            isExpanded: true,
                            hint: Text(
                              tr('select_firmware'),
                              style: const TextStyle(color: Colors.white70, fontSize: 12),
                            ),
                            items: firmwareFiles.map((file) {
                              final fileName = file.path.split(Platform.pathSeparator).last;
                              return DropdownMenuItem<String>(
                                value: file.path,
                                child: Text(fileName, overflow: TextOverflow.ellipsis),
                              );
                            }).toList(),
                            onChanged: isProgramming ? null : onFirmwareSelected,
                          ),
                        ),
            ),
          ),
          const SizedBox(width: 12),

          // 燒入並檢測按鈕
          ElevatedButton.icon(
            onPressed: canStartProgram ? onStartProgramAndDetect : null,
            icon: Icon(
              isProgramming ? Icons.hourglass_empty : Icons.bolt,
              size: 18,
            ),
            label: Text(
              isProgramming
                  ? tr('programming')
                  : tr('program_and_detect'),
              style: const TextStyle(fontSize: 12),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.amber,
              foregroundColor: Colors.black87,
              disabledBackgroundColor: Colors.grey.shade400,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
            value: programProgress > 0 ? programProgress : null,
            backgroundColor: Colors.purple.shade100,
            valueColor: AlwaysStoppedAnimation<Color>(Colors.purple.shade600),
          ),
          const SizedBox(height: 6),
          // 狀態文字
          Text(
            programStatus ?? '',
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
            value: autoDetectionProgress > 0 ? autoDetectionProgress : null,
            backgroundColor: Colors.blue.shade100,
            valueColor: AlwaysStoppedAnimation<Color>(Colors.blue.shade600),
          ),
          const SizedBox(height: 6),
          // 狀態文字
          Text(
            autoDetectionStatus ?? '',
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
    return Container(
      color: Colors.grey.shade50,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 標題列
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            color: color,
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 12,
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
              child: Column(
                children: List.generate(18, (id) => _buildHardwareDataRow(id, state)),
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
          // 標題列
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            color: Colors.grey.shade600,
            child: Text(
              tr('sensor_detection'),
              style: const TextStyle(
                fontSize: 12,
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
          // 差值欄
          Expanded(
            flex: 2,
            child: Text(
              tr('column_diff'),
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 10),
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
            ),
          ),
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

  /// 建構硬體數據行
  /// 使用 ThresholdSettingsService 的範圍設定來判斷狀態
  Widget _buildHardwareDataRow(int id, HardwareState state) {
    final name = DisplayNames.getName(id);
    final thresholdService = ThresholdSettingsService();

    // 取得 Arduino 和 STM32 的數據
    final arduinoData = state == HardwareState.idle
        ? dataStorage.getArduinoLatestIdleData(id)
        : dataStorage.getArduinoLatestRunningData(id);
    final stm32Data = state == HardwareState.idle
        ? dataStorage.getStm32LatestIdleData(id)
        : dataStorage.getStm32LatestRunningData(id);

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
      final runningData = dataStorage.getArduinoLatestRunningData(21);
      final idleData = dataStorage.getArduinoLatestIdleData(21);
      final data = runningData ?? idleData;
      if (data != null) {
        arduinoMcuTemp = data.value ~/ 10;  // MCUtemp 需要除以 10
      }
    }

    if (arduinoHasSensor) {
      final runningData = dataStorage.getArduinoLatestRunningData(id);
      final idleData = dataStorage.getArduinoLatestIdleData(id);
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
    final stm32RunningData = dataStorage.getStm32LatestRunningData(id);
    final stm32IdleData = dataStorage.getStm32LatestIdleData(id);
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
  }) {
    // 判斷是否有數據可比較
    final hasData = arduinoValue != null && stm32Value != null;

    // 判斷當前項目是否正在被讀取（用於高亮顯示）
    // 需要同時匹配 ID 和區域類型
    final isCurrentlyReading = currentReadingId == id && currentReadingSection == section;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      decoration: BoxDecoration(
        // 正在讀取時顯示黃色高亮背景
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
                  fontSize: 10,
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
          // 差值欄
          Expanded(
            flex: 2,
            child: Text(
              showNaForArduino
                  ? 'N/A'
                  : (diff != null
                      ? (diff >= 0 ? '+$diff' : '$diff')
                      : '--'),
              style: TextStyle(
                fontSize: 10,
                fontWeight: (!showNaForArduino && diff != null) ? FontWeight.bold : FontWeight.normal,
                fontStyle: showNaForArduino ? FontStyle.italic : FontStyle.normal,
                color: showNaForArduino
                    ? Colors.grey.shade400
                    : (diff != null
                        ? (isError ? Colors.red : Colors.black)
                        : Colors.grey),
              ),
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
            ),
          ),
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
