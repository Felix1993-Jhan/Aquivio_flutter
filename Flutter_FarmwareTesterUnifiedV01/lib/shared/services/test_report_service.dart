// ============================================================================
// TestReportService - 檢測報告累積服務（Main + Body&Door 共用）
// ============================================================================
// 功能：
// - 以「編號（前綴 + 數字後綴）」為 key 累積每一片板子的檢測結果
// - 每片可含「主測 + 多次重測」（重測在 Excel 中往下疊）
// - 每次檢測完成後擷取 DataStorageService 的快照（Idle / Running / 感應）
// - 供 ReportExcelExporter 匯出成 .xlsx
//
// 方向對應（與 UI 一致）：
// - 按「下一片」→ 後綴 +1 → 新的一片 → Excel 往右加一組欄
// - 不按下一片、直接再測一次 → 同編號 → 重測 → Excel 往下疊一個區塊
//
// 兩種模式差異全部收斂在 ReportConfig（設定驅動），邏輯不重複：
// - Main：硬體 ID 0~17、感應 18~23，含 STM32 / Offset / 電阻(R_Value)
// - Body&Door：全 Arduino，無 STM32 / Offset / 電阻
// ============================================================================

import 'package:flutter_firmware_tester_unified/shared/services/data_storage_service.dart';

/// 報告結構設定（描述各模式差異）
class ReportConfig {
  /// 模式資料夾名（桌面 → 檢測報告/<modeName>/）
  final String modeName;

  /// 檔名前綴（<filePrefix>_起_迄.xlsx）
  final String filePrefix;

  /// 硬體區 ID（有 Idle / Running 兩種狀態）
  final List<int> hwIds;

  /// 感應區 ID（只讀一次）
  final List<int> sensorIds;

  /// ID → 顯示名稱（Excel 列標籤）
  final Map<int, String> labels;

  /// 是否有 STM32 欄
  final bool hasStm32;

  /// 是否有 Offset 欄
  final bool hasOffset;

  /// 是否有電阻（R_Value）列
  final bool hasResistance;

  /// 電阻虛擬通道 ID
  final int resistanceId;

  /// Arduino 值需要 ÷10 顯示的 ID（例如 MCUtemp：原始 246 → 24.6°C）
  /// 與 UI 顯示邏輯一致，避免報告數值 / 上色與畫面不符
  final Set<int> arduinoDiv10Ids;

  /// 需要做「溫差比對」的溫度感測 ID（STM32 值與 Arduino 參考溫度比對）
  final Set<int> tempDiffIds;

  /// 溫差比對的 Arduino 參考溫度 ID（Main：MCUtemp = 21）
  final int tempRefId;

  /// 是否有「硬體動作中 (Running)」狀態。
  /// Main 有 Idle/Running 兩段；Body&Door 單次讀取、無 Running → 設 false，
  /// 報告 / Excel 會跳過 Running 區,只顯示讀值 + 感應。
  final bool hasRunningState;

  const ReportConfig({
    required this.modeName,
    required this.filePrefix,
    required this.hwIds,
    required this.sensorIds,
    required this.labels,
    required this.hasStm32,
    required this.hasOffset,
    required this.hasResistance,
    this.resistanceId = 0xF0,
    this.arduinoDiv10Ids = const {},
    this.tempDiffIds = const {},
    this.tempRefId = -1,
    this.hasRunningState = true,
  });

  /// Main Board 設定
  factory ReportConfig.main() {
    return const ReportConfig(
      modeName: 'Main',
      filePrefix: 'Main',
      hwIds: [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17],
      sensorIds: [18, 19, 20, 21, 22, 23],
      labels: {
        0: 'Slot_00', 1: 'Slot_01', 2: 'Slot_02', 3: 'Slot_03', 4: 'Slot_04',
        5: 'Slot_05', 6: 'Slot_06', 7: 'Slot_07', 8: 'Slot_08', 9: 'Slot_09',
        10: 'W_pump', 11: 'Spout_UVC', 12: 'Mix_UVC', 13: 'Main_UVC',
        14: 'Room_RL', 15: 'Cool_RL', 16: 'Spark_RL', 17: 'O3(CLEAN)',
        18: 'Flow', 19: 'CO2_press', 20: 'Water_press',
        21: 'MCUtemp', 22: 'Watertemp', 23: 'BIBtemp',
      },
      hasStm32: true,
      hasOffset: true,
      hasResistance: true,
      arduinoDiv10Ids: {21}, // MCUtemp Arduino ÷10（與畫面一致）
      tempDiffIds: {21, 22, 23}, // MCUtemp / WATERtemp / BIBtemp 溫差比對
      tempRefId: 21, // 以 Arduino MCUtemp 為參考
    );
  }

  /// Body&Door Board 設定（全 Arduino，無 STM32 / Offset / 電阻）
  /// 註：hwIds / sensorIds 的分區沿用 Body&Door 自動檢測頁的分組；
  ///     若日後分組調整，只需改此處。
  factory ReportConfig.bodyDoor() {
    return const ReportConfig(
      modeName: 'Body&Door',
      filePrefix: 'BodyDoor',
      // 繼電器 / 泵 / UVC / 電源等致動類 → 硬體區
      hwIds: [0, 1, 2, 3, 4, 5, 12, 13, 15, 16, 17, 18],
      // 溫度 / 壓力 / 流量 / 漏液等感測類 → 感應區
      sensorIds: [6, 7, 8, 9, 10, 11, 14],
      labels: {
        0: 'AmbientRL', 1: 'CoolRL', 2: 'SparklingRL', 3: 'WaterPump',
        4: 'O3', 5: 'MainUVC', 6: 'BIBtemp', 7: 'FlowMeter', 8: 'WaterTemp',
        9: 'Leak', 10: 'WaterPressure', 11: 'CO2Pressure', 12: 'SpoutUVC',
        13: 'MixUVC', 14: 'FlowMeter2', 15: 'BodyPower_24V',
        16: 'BodyPower_12V', 17: 'BodyPower_UpScreen', 18: 'BodyPower_LowScreen',
      },
      hasStm32: false,
      hasOffset: false,
      hasResistance: false,
      hasRunningState: false, // 單次讀取，無 Running 區
    );
  }
}

/// 單一 ID 在某狀態下的一組量測值
class ChannelValues {
  final int? offset; // STM32 開機自校準 offset（無 offset 模式 / 感應區為 null）
  final int? arduino;
  final int? stm32;

  const ChannelValues({this.offset, this.arduino, this.stm32});
}

/// 一次完整檢測的快照（對應 Excel 中的一個「round」區塊）
class TestSnapshot {
  /// Idle（硬體無動作）：hwId → 值
  final Map<int, ChannelValues> idle;

  /// Running（硬體動作中）：hwId → 值
  final Map<int, ChannelValues> running;

  /// 感應偵測：sensorId → 值
  final Map<int, ChannelValues> sensor;

  /// 電阻分壓 ADC（R_Value）；無電阻模式為 null
  final int? rValue;

  /// offset 平均（hwIds 的 offset 平均）；無 offset 模式為 null
  final double? offsetAvg;

  /// 溫差過大的溫度感測 ID（STM32 值與 Arduino 參考溫差超過閾值 → 高機率感測器壞）
  /// 報告中這些 ID 的 STM32 值會標紅
  final Set<int> tempDiffErrorIds;

  /// 這片的異常項目（格式「類別:項目」,如「感測:MCUtemp (ID21)」）
  /// 註：宣告為可空是為了容忍熱重載——新增此欄位後,記憶體中「舊物件」讀到的是
  ///     null,若為非空型別會拋 _TypeError；可空即可讓熱重載存活,不需熱重啟。
  final List<String>? abnormalItems;

  /// 硬體/韌體版本名稱（由電阻 R_Value 偵測；無版本概念的模式為 null）
  final String? versionName;

  /// 擷取時間
  final DateTime time;

  const TestSnapshot({
    required this.idle,
    required this.running,
    required this.sensor,
    required this.rValue,
    required this.offsetAvg,
    required this.tempDiffErrorIds,
    required this.time,
    this.abnormalItems = const [],
    this.versionName,
  });
}

/// 一片板子的紀錄（一個編號，含主測 + 重測）
class BoardRecord {
  /// 完整編號（前綴 + 補零後綴，例如 adcdd001）
  final String serial;

  /// 各輪檢測：rounds[0] = 主測，rounds[1..] = 重測（往下疊）
  final List<TestSnapshot> rounds = [];

  BoardRecord(this.serial);
}

/// 檢測報告累積服務
class TestReportService {
  /// 模式設定
  final ReportConfig config;

  /// 本次執行（App 啟動）的時間 —— 決定 Excel 檔名的起始時間
  /// 每次程式重啟就是新的一份報告檔
  final DateTime sessionStart;

  /// 編號前綴（可由 UI 設定，預設空字串）
  String prefix;

  /// 編號後綴（數字，第幾片）；補零後輸出
  int suffix;

  /// 後綴補零位數
  final int suffixPadding;

  /// 已累積的各片紀錄（依加入順序 = Excel 由左至右）
  final List<BoardRecord> boards = [];

  TestReportService({
    required this.config,
    required this.sessionStart,
    this.prefix = '',
    this.suffix = 1,
    this.suffixPadding = 3,
  });

  /// 目前編號字串（前綴 + 補零後綴）
  String get currentSerial =>
      '$prefix${suffix.toString().padLeft(suffixPadding, '0')}';

  /// 目前編號對應的板子紀錄（不存在則回傳 null）
  BoardRecord? get _currentBoard {
    for (final b in boards) {
      if (b.serial == currentSerial) return b;
    }
    return null;
  }

  /// 是否已有任何資料
  bool get hasData => boards.any((b) => b.rounds.isNotEmpty);

  /// 「下一片」：後綴 +1（下次擷取會是新的一片，Excel 往右）
  void nextBoard() {
    suffix++;
  }

  /// 從 DataStorageService 擷取目前結果，加到「當前編號」
  /// - 若當前編號尚無紀錄 → 建立新片（主測）
  /// - 若已有紀錄 → 視為重測，往下疊一個 round
  TestSnapshot captureCurrentResults(
    DataStorageService ds, {
    DateTime? now,
    int Function(int id)? diffThreshold,
    List<String> abnormalItems = const [],
    String? versionName,
  }) {
    final snapshot = _buildSnapshot(
        ds, now ?? sessionStart, diffThreshold, abnormalItems, versionName);

    var board = _currentBoard;
    if (board == null) {
      board = BoardRecord(currentSerial);
      boards.add(board);
    }
    board.rounds.add(snapshot);
    return snapshot;
  }

  /// 建立一份快照（讀取 DataStorageService 當下的值，依 config 取捨）
  TestSnapshot _buildSnapshot(
      DataStorageService ds,
      DateTime time,
      int Function(int id)? diffThreshold,
      List<String> abnormalItems,
      String? versionName) {
    final idle = <int, ChannelValues>{};
    final running = <int, ChannelValues>{};

    final offsets = <int>[];
    for (final id in config.hwIds) {
      final offset = config.hasOffset ? ds.getStm32Offset(id) : null;
      if (offset != null) offsets.add(offset);

      idle[id] = ChannelValues(
        offset: offset,
        arduino: ds.getArduinoFirstIdleData(id)?.value,
        stm32: config.hasStm32 ? ds.getStm32FirstIdleData(id)?.value : null,
      );
      // 無 Running 狀態的模式（Body&Door）跳過,不留空白 Running 欄
      if (config.hasRunningState) {
        running[id] = ChannelValues(
          offset: offset,
          arduino: ds.getArduinoLatestRunningData(id)?.value,
          stm32: config.hasStm32 ? ds.getStm32LatestRunningData(id)?.value : null,
        );
      }
    }

    final sensor = <int, ChannelValues>{};
    for (final id in config.sensorIds) {
      var arduino = ds.getArduinoLatestRunningData(id)?.value ??
          ds.getArduinoLatestIdleData(id)?.value;
      // 與 UI 一致：部分通道（如 MCUtemp）Arduino 值需 ÷10
      if (arduino != null && config.arduinoDiv10Ids.contains(id)) {
        arduino = arduino ~/ 10;
      }
      final stm32 = config.hasStm32
          ? (ds.getStm32LatestRunningData(id)?.value ??
              ds.getStm32LatestIdleData(id)?.value)
          : null;
      sensor[id] = ChannelValues(arduino: arduino, stm32: stm32);
    }

    final rValue = config.hasResistance
        ? (ds.getStm32LatestRunningData(config.resistanceId)?.value ??
            ds.getStm32LatestIdleData(config.resistanceId)?.value)
        : null;

    final double? offsetAvg = (!config.hasOffset || offsets.isEmpty)
        ? null
        : offsets.reduce((a, b) => a + b) / offsets.length;

    // 溫差比對：STM32 溫度與 Arduino 參考溫度(tempRefId)差距超過閾值 → 標記異常
    final tempDiffErrorIds = <int>{};
    final refTemp = sensor[config.tempRefId]?.arduino;
    if (refTemp != null && diffThreshold != null) {
      for (final id in config.tempDiffIds) {
        final stm32Temp = sensor[id]?.stm32;
        if (stm32Temp != null &&
            (refTemp - stm32Temp).abs() > diffThreshold(id)) {
          tempDiffErrorIds.add(id);
        }
      }
    }

    return TestSnapshot(
      idle: idle,
      running: running,
      sensor: sensor,
      rValue: rValue,
      offsetAvg: offsetAvg,
      tempDiffErrorIds: tempDiffErrorIds,
      time: time,
      abnormalItems: abnormalItems,
      versionName: versionName,
    );
  }
}
