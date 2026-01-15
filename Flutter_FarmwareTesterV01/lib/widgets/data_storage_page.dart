// ============================================================================
// DataStoragePage - 資料儲存顯示頁面
// ============================================================================
// 功能：顯示 Arduino 和 STM32 儲存的數據
// - 左側顯示 Arduino 數據（翡翠綠主色調）
// - 右側顯示 STM32 數據（天空藍主色調）
// - 上方：左邊硬體無動作(Idle)，右邊硬體動作中(Running)，ID 0-17
// - 下方：感測器數據 ID 18-23（無狀態區分）
// - 有狀態判別的 ID，在硬體未運行時隱藏快速讀取按鈕
// - 一鍵讀取功能：硬體區間隔 0.3 秒，感測器區間隔 1 秒
// ============================================================================

import 'dart:async';
import 'package:flutter/material.dart';
import '../services/data_storage_service.dart';
import '../services/localization_service.dart';

/// 翡翠綠色調
class EmeraldColors {
  static const Color primary = Color(0xFF50C878);
  static const Color light = Color(0xFFE8F5E9);
  static const Color dark = Color(0xFF2E7D32);
  static const Color background = Color(0xFFF1F8E9);
}

/// 天空藍色調
class SkyBlueColors {
  static const Color primary = Color(0xFF87CEEB);
  static const Color light = Color(0xFFE3F2FD);
  static const Color dark = Color(0xFF1976D2);
  static const Color background = Color(0xFFE1F5FE);
}

/// ID 顯示名稱對照表（完整名稱）
class DisplayNames {
  static const Map<int, String> idToDisplayName = {
    // Slot 0-9: 小顆馬達
    0: 'Slot0',
    1: 'Slot1',
    2: 'Slot2',
    3: 'Slot3',
    4: 'Slot4',
    5: 'Slot5',
    6: 'Slot6',
    7: 'Slot7',
    8: 'Slot8',
    9: 'Slot9',
    // Water: 水泵
    10: 'WaterPump',
    // UVC 燈
    11: 'MainUVC',
    12: 'SpoutUVC',
    13: 'MixUVC',
    // 繼電器
    14: 'AmbientRL',
    15: 'CoolRL',
    16: 'SparkRL',
    // O3: 臭氧
    17: 'O3',
    // 感測器
    18: 'Flow',
    19: 'PressureCO2',
    20: 'PressureWater',
    21: 'MCUtemp',
    22: 'WATERtemp',
    23: 'BIBtemp',
  };

  /// 取得顯示名稱
  static String getName(int id) {
    return idToDisplayName[id] ?? 'ID$id';
  }
}

class DataStoragePage extends StatefulWidget {
  /// 數據儲存服務
  final DataStorageService dataStorage;

  /// Arduino 快速讀取回調
  final void Function(String command)? onArduinoQuickRead;

  /// STM32 快速讀取回調 (使用 0x03 指令)
  final void Function(int id)? onStm32QuickRead;

  /// STM32 發送原始指令回調 (發送完整 hex 指令)
  final void Function(List<int> hexCommand)? onStm32SendCommand;

  const DataStoragePage({
    super.key,
    required this.dataStorage,
    this.onArduinoQuickRead,
    this.onStm32QuickRead,
    this.onStm32SendCommand,
  });

  @override
  State<DataStoragePage> createState() => _DataStoragePageState();
}

class _DataStoragePageState extends State<DataStoragePage> {
  // ==================== 批次讀取狀態 ====================

  /// Arduino 硬體區批次讀取中
  bool _isArduinoHardwareBatchReading = false;

  /// Arduino 感測器區批次讀取中
  bool _isArduinoSensorBatchReading = false;

  /// STM32 硬體區批次讀取中
  bool _isStm32HardwareBatchReading = false;

  /// STM32 感測器區批次讀取中
  bool _isStm32SensorBatchReading = false;

  /// 批次讀取計時器
  Timer? _batchReadTimer;

  @override
  void dispose() {
    _batchReadTimer?.cancel();
    super.dispose();
  }

  // ==================== 批次讀取方法 ====================

  /// Arduino 硬體區一鍵讀取 (ID 0-17, 間隔 300ms)
  void _startArduinoHardwareBatchRead() async {
    if (_isArduinoHardwareBatchReading || widget.onArduinoQuickRead == null) return;

    setState(() => _isArduinoHardwareBatchReading = true);

    for (int id = 0; id <= 17; id++) {
      if (!_isArduinoHardwareBatchReading) break; // 允許中途取消

      final command = _getArduinoReadCommand(id);
      if (command != null) {
        widget.onArduinoQuickRead!(command);
        await Future.delayed(const Duration(milliseconds: 300));
      }
    }

    if (mounted) {
      setState(() => _isArduinoHardwareBatchReading = false);
    }
  }

  /// Arduino 感測器區一鍵讀取 (ID 18-21, 間隔 1000ms)
  void _startArduinoSensorBatchRead() async {
    if (_isArduinoSensorBatchReading || widget.onArduinoQuickRead == null) return;

    setState(() => _isArduinoSensorBatchReading = true);

    for (int id = 18; id <= 21; id++) {
      if (!_isArduinoSensorBatchReading) break;

      final command = _getArduinoReadCommand(id);
      if (command != null) {
        widget.onArduinoQuickRead!(command);
        await Future.delayed(const Duration(milliseconds: 1000));
      }
    }

    if (mounted) {
      setState(() => _isArduinoSensorBatchReading = false);
    }
  }

  /// STM32 硬體區一鍵讀取 (ID 0-17, 間隔 300ms)
  void _startStm32HardwareBatchRead() async {
    if (_isStm32HardwareBatchReading || widget.onStm32QuickRead == null) return;

    setState(() => _isStm32HardwareBatchReading = true);

    for (int id = 0; id <= 17; id++) {
      if (!_isStm32HardwareBatchReading) break;

      widget.onStm32QuickRead!(id);
      await Future.delayed(const Duration(milliseconds: 300));
    }

    if (mounted) {
      setState(() => _isStm32HardwareBatchReading = false);
    }
  }

  /// STM32 感測器區一鍵讀取 (ID 18-23, 間隔 1000ms)
  void _startStm32SensorBatchRead() async {
    if (_isStm32SensorBatchReading || widget.onStm32QuickRead == null) return;

    setState(() => _isStm32SensorBatchReading = true);

    for (int id = 18; id <= 23; id++) {
      if (!_isStm32SensorBatchReading) break;

      widget.onStm32QuickRead!(id);
      await Future.delayed(const Duration(milliseconds: 1000));
    }

    if (mounted) {
      setState(() => _isStm32SensorBatchReading = false);
    }
  }

  /// 停止所有批次讀取
  void _stopAllBatchRead() {
    setState(() {
      _isArduinoHardwareBatchReading = false;
      _isArduinoSensorBatchReading = false;
      _isStm32HardwareBatchReading = false;
      _isStm32SensorBatchReading = false;
    });
  }

  /// 建構批次讀取按鈕
  Widget _buildBatchReadButton({
    required String label,
    required bool isLoading,
    required VoidCallback onPressed,
    required VoidCallback onStop,
    required Color color,
  }) {
    return SizedBox(
      height: 24,
      child: isLoading
          ? ElevatedButton.icon(
              onPressed: onStop,
              icon: const SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              ),
              label: Text(tr('stop'), style: const TextStyle(fontSize: 10)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
            )
          : ElevatedButton.icon(
              onPressed: onPressed,
              icon: const Icon(Icons.playlist_play, size: 14),
              label: Text(label, style: const TextStyle(fontSize: 10)),
              style: ElevatedButton.styleFrom(
                backgroundColor: color,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
            ),
    );
  }

  // ==================== STM32 輸出控制 ====================

  /// 開啟全部輸出 (0x01 指令, FF FF 03 遮罩)
  void _openAllOutputs() {
    if (widget.onStm32SendCommand != null) {
      // 40 71 30 01 FF FF 03 00 1D
      widget.onStm32SendCommand!([0x40, 0x71, 0x30, 0x01, 0xFF, 0xFF, 0x03, 0x00, 0x1D]);
    }
  }

  /// 關閉全部輸出 (0x02 指令, FF FF 03 遮罩)
  void _closeAllOutputs() {
    if (widget.onStm32SendCommand != null) {
      // 40 71 30 02 FF FF 03 00 1C
      widget.onStm32SendCommand!([0x40, 0x71, 0x30, 0x02, 0xFF, 0xFF, 0x03, 0x00, 0x1C]);
    }
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
                return Column(
                  children: [
                    // 頂部控制列
                    _buildTopControlBar(),
                    // 數據區域
                    Expanded(
                      child: Row(
                        children: [
                          // 左側：Arduino 數據區（翡翠綠）
                          Expanded(
                            child: _buildArduinoSection(),
                          ),
                          const VerticalDivider(width: 1),
                          // 右側：STM32 數據區（天空藍）
                          Expanded(
                            child: _buildStm32Section(),
                          ),
                        ],
                      ),
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

  /// 建構頂部控制列
  Widget _buildTopControlBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        border: Border(
          bottom: BorderSide(color: Colors.grey.shade300),
        ),
      ),
      child: Row(
        children: [
          Text(
            tr('stm32_output_control'),
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
          const SizedBox(width: 16),
          // 開啟全部輸出按鈕
          ElevatedButton.icon(
            onPressed: widget.onStm32SendCommand != null ? _openAllOutputs : null,
            icon: const Icon(Icons.power, size: 16),
            label: Text(tr('open_all_outputs')),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green.shade600,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
          ),
          const SizedBox(width: 12),
          // 關閉全部輸出按鈕
          ElevatedButton.icon(
            onPressed: widget.onStm32SendCommand != null ? _closeAllOutputs : null,
            icon: const Icon(Icons.power_off, size: 16),
            label: Text(tr('close_all_outputs')),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade600,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
          ),
        ],
      ),
    );
  }

  // ==================== Arduino 區域 ====================

  /// 建構 Arduino 數據區
  Widget _buildArduinoSection() {
    return Container(
      color: EmeraldColors.background,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 標題列
          Container(
            padding: const EdgeInsets.all(12),
            color: EmeraldColors.primary,
            child: Row(
              children: [
                const Icon(Icons.memory, color: Colors.white),
                const SizedBox(width: 8),
                Text(
                  tr('arduino_data'),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
          // 數據列表
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 上方：ID 0-17，左邊 Idle 右邊 Running
                  _buildArduinoStateArea(),
                  const SizedBox(height: 16),
                  // 下方：ID 18-23 感測器數據
                  _buildArduinoSensorSection(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 建構 Arduino 狀態區域（ID 0-17，左 Idle 右 Running）
  Widget _buildArduinoStateArea() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 一鍵讀取按鈕列
        Row(
          children: [
            Text(tr('hardware_data'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
            const Spacer(),
            _buildBatchReadButton(
              label: tr('batch_read'),
              isLoading: _isArduinoHardwareBatchReading,
              onPressed: _startArduinoHardwareBatchRead,
              onStop: () => setState(() => _isArduinoHardwareBatchReading = false),
              color: EmeraldColors.dark,
            ),
          ],
        ),
        const SizedBox(height: 8),
        // 數據列
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 左欄：硬體無動作 (Idle)
            Expanded(
              child: _buildArduinoStateColumn(tr('hardware_idle'), HardwareState.idle),
            ),
            const SizedBox(width: 8),
            // 右欄：硬體動作中 (Running)
            Expanded(
              child: _buildArduinoStateColumn(tr('hardware_running'), HardwareState.running),
            ),
          ],
        ),
      ],
    );
  }

  /// 建構 Arduino 狀態欄位
  Widget _buildArduinoStateColumn(String title, HardwareState state) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: state == HardwareState.idle ? EmeraldColors.dark : Colors.orange.shade700,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 11,
            ),
          ),
        ),
        const SizedBox(height: 8),
        // ID 0-17 按順序排列
        ...List.generate(18, (id) => _buildArduinoDataItem(id, state)),
      ],
    );
  }

  /// 建構 Arduino 感測器數據區（ID 18-21）
  /// Arduino 只有 flow(18), prec(19), prew(20), mcutemp(21)
  /// 沒有 watertemp(22) 和 bibtemp(23)
  Widget _buildArduinoSensorSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 一鍵讀取按鈕列
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.grey.shade600,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                tr('sensor_data'),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ),
            const Spacer(),
            _buildBatchReadButton(
              label: tr('batch_read'),
              isLoading: _isArduinoSensorBatchReading,
              onPressed: _startArduinoSensorBatchRead,
              onStop: () => setState(() => _isArduinoSensorBatchReading = false),
              color: EmeraldColors.dark,
            ),
          ],
        ),
        const SizedBox(height: 8),
        ...List.generate(4, (i) => _buildArduinoSensorDataItem(i + 18)),
      ],
    );
  }

  /// 建構單一 Arduino 數據項（有狀態）
  Widget _buildArduinoDataItem(int id, HardwareState state) {
    final name = DisplayNames.getName(id);
    final command = _getArduinoReadCommand(id);
    final data = state == HardwareState.idle
        ? widget.dataStorage.getArduinoLatestIdleData(id)
        : widget.dataStorage.getArduinoLatestRunningData(id);

    // 檢查此 ID 的硬體是否正在運行中
    final isRunning = widget.dataStorage.isHardwareRunning(id);
    // 只有當硬體正在運行且查看 Running 欄位，或硬體未運行且查看 Idle 欄位時，才顯示快速讀取按鈕
    final showQuickRead = (state == HardwareState.running && isRunning) ||
                          (state == HardwareState.idle && !isRunning);

    return Container(
      margin: const EdgeInsets.only(bottom: 3),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
      decoration: BoxDecoration(
        color: data != null ? Colors.white : Colors.grey.shade200,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: data != null
              ? EmeraldColors.primary.withValues(alpha: 0.5)
              : Colors.grey.shade400,
        ),
      ),
      child: Row(
        children: [
          // ID 和名稱
          SizedBox(
            width: 70,
            child: Text(
              name,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 10,
                color: data != null ? Colors.black : Colors.grey,
              ),
            ),
          ),
          // 數值
          Expanded(
            child: Text(
              data != null ? '${data.value}' : '--',
              style: TextStyle(
                fontSize: 10,
                color: data != null ? Colors.black : Colors.grey,
              ),
            ),
          ),
          // 時間
          if (data != null)
            Text(
              _formatTime(data.timestamp),
              style: TextStyle(fontSize: 8, color: Colors.grey.shade600),
            ),
          // 快速讀取按鈕（保留空間，只在適當狀態時可點擊）
          SizedBox(
            width: 22,
            height: 22,
            child: (command != null && widget.onArduinoQuickRead != null && showQuickRead)
                ? IconButton(
                    icon: const Icon(Icons.refresh, size: 12),
                    padding: EdgeInsets.zero,
                    onPressed: () => widget.onArduinoQuickRead!(command),
                    tooltip: '讀取 $name',
                    color: EmeraldColors.dark,
                  )
                : null, // 保留空間但不顯示按鈕
          ),
        ],
      ),
    );
  }

  /// 格式化 Arduino 感測器數值
  /// MCUtemp (ID 21) 的數值需要除以 10 取整數（例如 246 → 24）
  String _formatArduinoSensorValue(int id, int value) {
    if (id == 21) {
      // MCUtemp: 除以 10 取整數
      return '${value ~/ 10}';
    }
    return '$value';
  }

  /// 建構 Arduino 感測器數據項（無狀態）
  Widget _buildArduinoSensorDataItem(int id) {
    final name = DisplayNames.getName(id);
    final command = _getArduinoReadCommand(id);
    // 感測器數據不區分狀態，取最新的
    final runningData = widget.dataStorage.getArduinoLatestRunningData(id);
    final idleData = widget.dataStorage.getArduinoLatestIdleData(id);
    final data = runningData ?? idleData;

    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: data != null ? Colors.white : Colors.grey.shade200,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: data != null
              ? EmeraldColors.primary.withValues(alpha: 0.5)
              : Colors.grey.shade400,
        ),
      ),
      child: Row(
        children: [
          // ID 和名稱
          SizedBox(
            width: 100,
            child: Text(
              name,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 12,
                color: data != null ? Colors.black : Colors.grey,
              ),
            ),
          ),
          // 數值
          Expanded(
            child: Text(
              data != null ? _formatArduinoSensorValue(id, data.value) : '--',
              style: TextStyle(
                fontSize: 12,
                color: data != null ? Colors.black : Colors.grey,
              ),
            ),
          ),
          // 時間
          if (data != null)
            Text(
              _formatTime(data.timestamp),
              style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
            ),
          const SizedBox(width: 8),
          // 感測器數據始終顯示快速讀取按鈕
          if (command != null && widget.onArduinoQuickRead != null)
            IconButton(
              icon: const Icon(Icons.refresh, size: 16),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              onPressed: () => widget.onArduinoQuickRead!(command),
              tooltip: '讀取 $name',
              color: EmeraldColors.dark,
            ),
        ],
      ),
    );
  }

  /// 取得 Arduino 讀取指令
  /// Arduino 只支援 ID 0-21，沒有 watertemp(22) 和 bibtemp(23)
  String? _getArduinoReadCommand(int id) {
    switch (id) {
      case 0: return 's0';
      case 1: return 's1';
      case 2: return 's2';
      case 3: return 's3';
      case 4: return 's4';
      case 5: return 's5';
      case 6: return 's6';
      case 7: return 's7';
      case 8: return 's8';
      case 9: return 's9';
      case 10: return 'water';
      case 11: return 'u0';
      case 12: return 'u1';
      case 13: return 'u2';
      case 14: return 'arl';
      case 15: return 'crl';
      case 16: return 'srl';
      case 17: return 'o3';
      case 18: return 'flowon';
      case 19: return 'prec';
      case 20: return 'prew';
      case 21: return 'mcutemp';
      // Arduino 沒有 watertemp(22) 和 bibtemp(23)
      default: return null;
    }
  }

  // ==================== STM32 區域 ====================

  /// 建構 STM32 數據區
  Widget _buildStm32Section() {
    return Container(
      color: SkyBlueColors.background,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 標題列
          Container(
            padding: const EdgeInsets.all(12),
            color: SkyBlueColors.primary,
            child: Row(
              children: [
                const Icon(Icons.developer_board, color: Colors.white),
                const SizedBox(width: 8),
                Text(
                  tr('stm32_data'),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
          // 數據列表
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 上方：ID 0-17，左邊 Idle 右邊 Running
                  _buildStm32StateArea(),
                  const SizedBox(height: 16),
                  // 下方：ID 18-23 感測器數據
                  _buildStm32SensorSection(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 建構 STM32 狀態區域（ID 0-17，左 Idle 右 Running）
  Widget _buildStm32StateArea() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 一鍵讀取按鈕列
        Row(
          children: [
            Text(tr('hardware_data'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
            const Spacer(),
            _buildBatchReadButton(
              label: tr('batch_read'),
              isLoading: _isStm32HardwareBatchReading,
              onPressed: _startStm32HardwareBatchRead,
              onStop: () => setState(() => _isStm32HardwareBatchReading = false),
              color: SkyBlueColors.dark,
            ),
          ],
        ),
        const SizedBox(height: 8),
        // 數據列
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 左欄：硬體無動作 (Idle)
            Expanded(
              child: _buildStm32StateColumn(tr('hardware_idle'), HardwareState.idle),
            ),
            const SizedBox(width: 8),
            // 右欄：硬體動作中 (Running)
            Expanded(
              child: _buildStm32StateColumn(tr('hardware_running'), HardwareState.running),
            ),
          ],
        ),
      ],
    );
  }

  /// 建構 STM32 狀態欄位
  Widget _buildStm32StateColumn(String title, HardwareState state) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: state == HardwareState.idle ? SkyBlueColors.dark : Colors.orange.shade700,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 11,
            ),
          ),
        ),
        const SizedBox(height: 8),
        // ID 0-17 按順序排列
        ...List.generate(18, (id) => _buildStm32DataItem(id, state)),
      ],
    );
  }

  /// 建構 STM32 感測器數據區（ID 18-23）
  Widget _buildStm32SensorSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 一鍵讀取按鈕列
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.grey.shade600,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                tr('sensor_data'),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ),
            const Spacer(),
            _buildBatchReadButton(
              label: tr('batch_read'),
              isLoading: _isStm32SensorBatchReading,
              onPressed: _startStm32SensorBatchRead,
              onStop: () => setState(() => _isStm32SensorBatchReading = false),
              color: SkyBlueColors.dark,
            ),
          ],
        ),
        const SizedBox(height: 8),
        ...List.generate(6, (i) => _buildStm32SensorDataItem(i + 18)),
      ],
    );
  }

  /// 建構單一 STM32 數據項（有狀態）
  Widget _buildStm32DataItem(int id, HardwareState state) {
    final name = DisplayNames.getName(id);
    final data = state == HardwareState.idle
        ? widget.dataStorage.getStm32LatestIdleData(id)
        : widget.dataStorage.getStm32LatestRunningData(id);

    // 檢查此 ID 的硬體是否正在運行中
    final isRunning = widget.dataStorage.isHardwareRunning(id);
    // 只有當硬體正在運行且查看 Running 欄位，或硬體未運行且查看 Idle 欄位時，才顯示快速讀取按鈕
    final showQuickRead = (state == HardwareState.running && isRunning) ||
                          (state == HardwareState.idle && !isRunning);

    return Container(
      margin: const EdgeInsets.only(bottom: 3),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
      decoration: BoxDecoration(
        color: data != null ? Colors.white : Colors.grey.shade200,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: data != null
              ? SkyBlueColors.primary.withValues(alpha: 0.5)
              : Colors.grey.shade400,
        ),
      ),
      child: Row(
        children: [
          // ID 和名稱
          SizedBox(
            width: 70,
            child: Text(
              name,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 10,
                color: data != null ? Colors.black : Colors.grey,
              ),
            ),
          ),
          // 數值
          Expanded(
            child: Text(
              data != null ? '${data.value}' : '--',
              style: TextStyle(
                fontSize: 10,
                color: data != null ? Colors.black : Colors.grey,
              ),
            ),
          ),
          // 時間
          if (data != null)
            Text(
              _formatTime(data.timestamp),
              style: TextStyle(fontSize: 8, color: Colors.grey.shade600),
            ),
          // 快速讀取按鈕（保留空間，只在適當狀態時可點擊）
          SizedBox(
            width: 22,
            height: 22,
            child: (widget.onStm32QuickRead != null && showQuickRead)
                ? IconButton(
                    icon: const Icon(Icons.refresh, size: 12),
                    padding: EdgeInsets.zero,
                    onPressed: () => widget.onStm32QuickRead!(id),
                    tooltip: '讀取 ID$id (0x03)',
                    color: SkyBlueColors.dark,
                  )
                : null, // 保留空間但不顯示按鈕
          ),
        ],
      ),
    );
  }

  /// 建構 STM32 感測器數據項（無狀態）
  Widget _buildStm32SensorDataItem(int id) {
    final name = DisplayNames.getName(id);
    // 感測器數據不區分狀態，取最新的
    final runningData = widget.dataStorage.getStm32LatestRunningData(id);
    final idleData = widget.dataStorage.getStm32LatestIdleData(id);
    final data = runningData ?? idleData;

    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: data != null ? Colors.white : Colors.grey.shade200,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: data != null
              ? SkyBlueColors.primary.withValues(alpha: 0.5)
              : Colors.grey.shade400,
        ),
      ),
      child: Row(
        children: [
          // ID 和名稱
          SizedBox(
            width: 100,
            child: Text(
              name,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 12,
                color: data != null ? Colors.black : Colors.grey,
              ),
            ),
          ),
          // 數值
          Expanded(
            child: Text(
              data != null ? '${data.value}' : '--',
              style: TextStyle(
                fontSize: 12,
                color: data != null ? Colors.black : Colors.grey,
              ),
            ),
          ),
          // 時間
          if (data != null)
            Text(
              _formatTime(data.timestamp),
              style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
            ),
          const SizedBox(width: 8),
          // 感測器數據始終顯示快速讀取按鈕
          if (widget.onStm32QuickRead != null)
            IconButton(
              icon: const Icon(Icons.refresh, size: 16),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              onPressed: () => widget.onStm32QuickRead!(id),
              tooltip: '讀取 ID$id (0x03)',
              color: SkyBlueColors.dark,
            ),
        ],
      ),
    );
  }

  /// 格式化時間
  String _formatTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:'
           '${time.minute.toString().padLeft(2, '0')}:'
           '${time.second.toString().padLeft(2, '0')}';
  }
}