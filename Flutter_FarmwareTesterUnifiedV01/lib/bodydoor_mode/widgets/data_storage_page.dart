// ============================================================================
// DataStoragePage - 資料儲存顯示頁面 (BodyDoor 版本)
// ============================================================================
// 功能：顯示 Arduino 儲存的數據（僅 Arduino，無 STM32）
// - 全寬顯示 Arduino 數據（翡翠綠主色調）
// - 上方：左邊硬體無動作(Idle)，右邊硬體動作中(Running)，ID 0-18
// - 有狀態判別的 ID，在硬體未運行時隱藏快速讀取按鈕
// - 一鍵讀取功能：間隔 0.3 秒
// ============================================================================

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_firmware_tester_unified/shared/services/data_storage_service.dart';
import 'package:flutter_firmware_tester_unified/shared/services/localization_service.dart';
import '../services/threshold_settings_service.dart';

/// 翡翠綠色調
class EmeraldColors {
  static const Color primary = Color(0xFF50C878);
  static const Color light = Color(0xFFE8F5E9);
  static const Color dark = Color(0xFF2E7D32);
  static const Color background = Color(0xFFF1F8E9);
}

/// ID 顯示名稱對照表（BodyDoor 19 個 ADC 通道）
class DisplayNames {
  static const Map<int, String> idToDisplayName = {
    0: 'AmbientRL',      // A0
    1: 'CoolRL',         // A1
    2: 'SparklingRL',    // A2
    3: 'WaterPump',      // A3
    4: 'O3',             // A4
    5: 'MainUVC',        // A5
    6: 'BibTemp',        // A6
    7: 'FlowMeter',      // A7
    8: 'WaterTemp',      // A8
    9: 'Leak',           // A9
    10: 'WaterPressure',  // A10
    11: 'CO2Pressure',    // A11
    12: 'SpoutUVC',       // A12
    13: 'MixUVC',         // A13
    14: 'FlowMeter2',     // A14
    15: 'BP_24V',         // A15,CH5
    16: 'BP_12V',         // A15,CH7
    17: 'BP_UpScreen',    // A15,CH6
    18: 'BP_LowScreen',   // A15,CH4
  };

  /// Body 組 ID 列表 (ID 0-11)
  static const List<int> bodyIds = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11];

  /// Body 12V 子組 (ID 0-5, 7)
  static const List<int> body12vIds = [0, 1, 2, 3, 4, 5, 7];

  /// Body 3.3V 子組 (ID 6, 8-11)
  static const List<int> body33vIds = [6, 8, 9, 10, 11];

  /// Door 組 ID 列表 (ID 12-18)
  static const List<int> doorIds = [12, 13, 14, 15, 16, 17, 18];

  /// 3.3V 電源檢測 ID 列表 (ID 6, 8, 9, 10, 11)
  /// 這些通道同時數值過低 (< 50) 表示 3.3V 電源異常
  static const List<int> power33vCheckIds = [6, 8, 9, 10, 11];
  static int get power33vThreshold => ThresholdSettingsService().power33vThreshold;

  /// Body 12V 電源檢測 ID 列表 (ID 0,1,2,3,4,5,7)
  /// 全部過低且 3.3V 異常 → Body 12V 電源異常
  static const List<int> powerBody12vCheckIds = [0, 1, 2, 3, 4, 5, 7];
  static int get powerBody12vThreshold => ThresholdSettingsService().powerBody12vThreshold;

  /// Door 24V 升壓電路檢測 ID (BP_24V = ID15)
  static const List<int> powerDoor24vCheckIds = [15];
  static int get powerDoor24vThreshold => ThresholdSettingsService().powerDoor24vThreshold;

  /// Door 12V 電源檢測 ID 列表 (Door 組去除 BP_24V)
  static const List<int> powerDoor12vCheckIds = [12, 13, 14, 16, 17, 18];
  static int get powerDoor12vThreshold => ThresholdSettingsService().powerDoor12vThreshold;

  /// FarmwareTesterV01 的 ID 對照（無對應者取 J 編號數字）
  static const Map<int, int> v01Id = {
    0: 14, 1: 15, 2: 16, 3: 10, 4: 17, 5: 13,
    6: 23, 7: 18, 8: 22, 9: 209, 10: 20, 11: 19,
    12: 11, 13: 12, 14: 106, 15: 103, 16: 102, 17: 101, 18: 101,
  };

  /// 接頭 J 編號對照
  static const Map<int, String> jNumber = {
    0: 'J201', 1: 'J203', 2: 'J206', 3: 'J200', 4: 'J207', 5: 'J204',
    6: 'J208', 7: 'J212', 8: 'J202', 9: 'J209', 10: 'J211', 11: 'J210',
    12: 'J104', 13: 'J105', 14: 'J106', 15: 'J103', 16: 'J102', 17: 'J101', 18: 'J101',
  };

  /// Arduino ADC 腳位對照
  static const Map<int, String> adcPin = {
    0: 'A0', 1: 'A1', 2: 'A2', 3: 'A3', 4: 'A4', 5: 'A5',
    6: 'A6', 7: 'A7', 8: 'A8', 9: 'A9', 10: 'A10', 11: 'A11',
    12: 'A12', 13: 'A13', 14: 'A14',
    15: 'A15,CH5', 16: 'A15,CH7', 17: 'A15,CH6', 18: 'A15,CH4',
  };

  /// 取得顯示名稱（包含 V01 ID、J 編號、ADC 腳位）
  /// 例如：AmbientRL (ID14/J201/A0)
  static String getName(int id) {
    final name = idToDisplayName[id];
    final vid = v01Id[id];
    final jno = jNumber[id];
    final adc = adcPin[id];
    if (name != null && vid != null && jno != null && adc != null) {
      return '$name (ID$vid/$jno/$adc)';
    }
    return 'ID$id';
  }

  /// 取得純名稱（不含 ID）
  static String getNameOnly(int id) {
    return idToDisplayName[id] ?? 'ID$id';
  }

  /// 判斷 ID 是否屬於 Body 組
  static bool isBody(int id) => bodyIds.contains(id);

  /// 判斷 ID 是否屬於 Door 組
  static bool isDoor(int id) => doorIds.contains(id);

  /// 檢查 3.3V 電源是否異常
  /// 傳入一個取得 ID 數值的函式，回傳是否所有 3.3V 檢測 ID 都低於閾值
  static bool check33vAnomaly(int? Function(int id) getIdValue) {
    for (final id in power33vCheckIds) {
      final value = getIdValue(id);
      if (value == null || value >= power33vThreshold) {
        return false; // 有任一個不低於閾值，則不算 3.3V 異常
      }
    }
    return true; // 全部都低於閾值 → 3.3V 異常
  }

  /// 檢查 Body 12V 電源是否異常
  /// 前置條件：3.3V 必須也異常（階層式檢測）
  static bool checkBody12vAnomaly(int? Function(int id) getIdValue) {
    if (!check33vAnomaly(getIdValue)) return false;
    for (final id in powerBody12vCheckIds) {
      final value = getIdValue(id);
      if (value == null || value >= powerBody12vThreshold) return false;
    }
    return true;
  }

  /// 檢查 Door 24V 升壓電路是否異常
  static bool checkDoor24vAnomaly(int? Function(int id) getIdValue) {
    for (final id in powerDoor24vCheckIds) {
      final value = getIdValue(id);
      if (value == null || value >= powerDoor24vThreshold) return false;
    }
    return true;
  }

  /// 檢查 Door 12V 電源是否異常
  static bool checkDoor12vAnomaly(int? Function(int id) getIdValue) {
    for (final id in powerDoor12vCheckIds) {
      final value = getIdValue(id);
      if (value == null || value >= powerDoor12vThreshold) return false;
    }
    return true;
  }
}

class DataStoragePage extends StatefulWidget {
  /// 數據儲存服務
  final DataStorageService dataStorage;

  /// Arduino 快速讀取回調
  final void Function(String command)? onArduinoQuickRead;

  const DataStoragePage({
    super.key,
    required this.dataStorage,
    this.onArduinoQuickRead,
  });

  @override
  State<DataStoragePage> createState() => _DataStoragePageState();
}

class _DataStoragePageState extends State<DataStoragePage> {
  // ==================== 批次讀取狀態 ====================

  /// Arduino 硬體區批次讀取中
  bool _isArduinoHardwareBatchReading = false;

  /// 批次讀取計時器
  Timer? _batchReadTimer;

  // ==================== 當前讀取標示 ====================

  /// Arduino 硬體區當前正在讀取的 ID
  int? _arduinoHardwareReadingId;

  @override
  void dispose() {
    _batchReadTimer?.cancel();
    super.dispose();
  }

  // ==================== 批次讀取方法 ====================

  /// 重試最大次數
  static const int _maxRetries = 3;

  /// Arduino 硬體區一鍵讀取 (ID 0-18, 間隔 300ms，含重試機制)
  void _startArduinoHardwareBatchRead() async {
    if (_isArduinoHardwareBatchReading || widget.onArduinoQuickRead == null) return;

    setState(() => _isArduinoHardwareBatchReading = true);

    for (int id = 0; id <= 18; id++) {
      if (!_isArduinoHardwareBatchReading) break; // 允許中途取消

      final command = _getArduinoReadCommand(id);
      if (command != null) {
        // 重試機制：最多重試 _maxRetries 次
        for (int retry = 0; retry <= _maxRetries; retry++) {
          if (!_isArduinoHardwareBatchReading) break;

          setState(() => _arduinoHardwareReadingId = id);
          widget.onArduinoQuickRead!(command);
          await Future.delayed(const Duration(milliseconds: 300));

          // 檢查是否收到 Idle 數據
          final data = widget.dataStorage.getArduinoLatestIdleData(id);

          if (data != null || retry >= _maxRetries) break;
          // 數據為 null，等待後重試
          await Future.delayed(const Duration(milliseconds: 100));
        }
      }
    }

    if (mounted) {
      setState(() {
        _isArduinoHardwareBatchReading = false;
        _arduinoHardwareReadingId = null;
      });
    }
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

  @override
  Widget build(BuildContext context) {
    // 監聽語言變更，自動更新 UI
    return ValueListenableBuilder<AppLanguage>(
      valueListenable: LocalizationService().currentLanguageNotifier,
      builder: (context, _, _) {
        return ValueListenableBuilder<int>(
          valueListenable: widget.dataStorage.dataUpdateNotifier,
          builder: (context, _, _) {
            return ValueListenableBuilder<int>(
              valueListenable: widget.dataStorage.runningStateNotifier,
              builder: (context, _, _) {
                return _buildArduinoSection();
              },
            );
          },
        );
      },
    );
  }

  // ==================== Arduino 區域 ====================

  /// 建構 Arduino 數據區（全寬）
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
          // 電源異常警告
          _build33vWarningBanner(),
          _buildBody12vWarningBanner(),
          _buildDoor24vWarningBanner(),
          _buildDoor12vWarningBanner(),
          // 數據列表
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildArduinoStateArea(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 檢查當前數據是否觸發 3.3V 異常
  bool _check33vAnomaly() {
    return DisplayNames.check33vAnomaly((id) {
      final data = widget.dataStorage.getArduinoLatestIdleData(id);
      return data?.value;
    });
  }

  /// 建構 3.3V 電源異常警告橫幅
  Widget _build33vWarningBanner() {
    if (!_check33vAnomaly()) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: Colors.red.shade700,
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, color: Colors.white, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              tr('power_33v_anomaly'),
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 檢查 Body 12V 電源異常
  bool _checkBody12vAnomaly() {
    return DisplayNames.checkBody12vAnomaly((id) {
      final data = widget.dataStorage.getArduinoLatestIdleData(id);
      return data?.value;
    });
  }

  /// 檢查 Door 24V 升壓電路異常
  bool _checkDoor24vAnomaly() {
    return DisplayNames.checkDoor24vAnomaly((id) {
      final data = widget.dataStorage.getArduinoLatestIdleData(id);
      return data?.value;
    });
  }

  /// 檢查 Door 12V 電源異常
  bool _checkDoor12vAnomaly() {
    return DisplayNames.checkDoor12vAnomaly((id) {
      final data = widget.dataStorage.getArduinoLatestIdleData(id);
      return data?.value;
    });
  }

  /// 建構 Body 12V 電源異常警告橫幅
  Widget _buildBody12vWarningBanner() {
    if (!_checkBody12vAnomaly()) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: Colors.deepOrange.shade700,
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, color: Colors.white, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              tr('power_body12v_anomaly'),
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  /// 建構 Door 24V 升壓電路異常警告橫幅
  Widget _buildDoor24vWarningBanner() {
    if (!_checkDoor24vAnomaly()) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: Colors.purple.shade700,
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, color: Colors.white, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              tr('power_door24v_anomaly'),
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  /// 建構 Door 12V 電源異常警告橫幅
  Widget _buildDoor12vWarningBanner() {
    if (!_checkDoor12vAnomaly()) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: Colors.indigo.shade700,
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, color: Colors.white, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              tr('power_door12v_anomaly'),
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  /// 建構 Arduino 狀態區域（分 Body/Door 兩區）
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
        // Body / Door 左右分區
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Body 區 (ID 0-11)，分 12V / 3.3V 子組
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildGroupHeader('Body', Colors.teal),
                  _buildSubGroupHeader('12V', Colors.teal.shade300),
                  ...DisplayNames.body12vIds.map((id) => _buildArduinoDataItem(id)),
                  _buildSubGroupHeader('3.3V', Colors.orange.shade400),
                  ...DisplayNames.body33vIds.map((id) => _buildArduinoDataItem(id)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // Door 區 (ID 12-18)
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildGroupHeader('Door', Colors.indigo),
                  ...DisplayNames.doorIds.map((id) => _buildArduinoDataItem(id)),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// 建構分組標頭
  Widget _buildGroupHeader(String title, Color color) {
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      ),
    );
  }

  /// 建構子分組標頭（比主標頭小）
  Widget _buildSubGroupHeader(String title, Color color) {
    return Container(
      margin: const EdgeInsets.only(bottom: 2, top: 4),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      ),
    );
  }

  /// 建構單一 Arduino 數據項（僅 Idle）
  Widget _buildArduinoDataItem(int id) {
    final name = DisplayNames.getName(id);
    final command = _getArduinoReadCommand(id);
    final data = widget.dataStorage.getArduinoLatestIdleData(id);

    // 判斷當前項目是否正在被讀取（用於高亮顯示）
    final isCurrentlyReading = _arduinoHardwareReadingId == id;

    return Container(
      margin: const EdgeInsets.only(bottom: 3),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
      decoration: BoxDecoration(
        color: isCurrentlyReading
            ? Colors.yellow.shade200
            : (data != null ? Colors.white : Colors.grey.shade200),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: isCurrentlyReading
              ? Colors.orange.shade400
              : (data != null
                  ? EmeraldColors.primary.withValues(alpha: 0.5)
                  : Colors.grey.shade400),
          width: isCurrentlyReading ? 2 : 1,
        ),
      ),
      child: Row(
        children: [
          // ID 和名稱
          SizedBox(
            width: 70,
            child: Container(
              padding: isCurrentlyReading
                  ? const EdgeInsets.symmetric(horizontal: 4, vertical: 1)
                  : EdgeInsets.zero,
              decoration: isCurrentlyReading
                  ? BoxDecoration(
                      color: Colors.orange.shade300,
                      borderRadius: BorderRadius.circular(3),
                    )
                  : null,
              child: Text(
                name,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 10,
                  color: isCurrentlyReading
                      ? Colors.white
                      : (data != null ? Colors.black : Colors.grey),
                ),
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
            child: (command != null && widget.onArduinoQuickRead != null)
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

  /// 取得 Arduino 讀取指令（BodyDoor 19 個 ADC 通道）
  String? _getArduinoReadCommand(int id) {
    switch (id) {
      case 0: return 'ambientrl';
      case 1: return 'coolrl';
      case 2: return 'sparklingrl';
      case 3: return 'waterpump';
      case 4: return 'o3';
      case 5: return 'mainuvc';
      case 6: return 'bibtemp';
      case 7: return 'flowmeter';
      case 8: return 'watertemp';
      case 9: return 'leak';
      case 10: return 'waterpressure';
      case 11: return 'co2pressure';
      case 12: return 'spoutuvc';
      case 13: return 'mixuvc';
      case 14: return 'flowmeter2';
      case 15: return 'bp24v';
      case 16: return 'bp12v';
      case 17: return 'bpup';
      case 18: return 'bplow';
      default: return null;
    }
  }

  /// 格式化時間
  String _formatTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:'
           '${time.minute.toString().padLeft(2, '0')}:'
           '${time.second.toString().padLeft(2, '0')}';
  }
}
