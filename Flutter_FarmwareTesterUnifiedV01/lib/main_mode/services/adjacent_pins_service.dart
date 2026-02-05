// ============================================================================
// AdjacentPinsService - 相鄰腳位對照表服務
// ============================================================================
// 功能：定義 STM32 GPIO 腳位的物理相鄰關係，用於短路測試
// - ID 0-17 為硬體輸出腳位
// - 部分腳位相鄰 Vdd 或 Vss（電源/接地）
// ============================================================================

/// 相鄰腳位類型
enum AdjacentType {
  /// 一般輸出腳位
  gpio,
  /// 電源 (Vdd)
  vdd,
  /// 接地 (Vss)
  vss,
  /// 無相鄰（空）
  none,
}

/// 相鄰腳位資訊
class AdjacentPin {
  /// 相鄰腳位的 ID（如果是 GPIO）
  final int? id;

  /// 相鄰腳位的類型
  final AdjacentType type;

  /// STM32 腳位名稱（用於顯示）
  final String pinName;

  const AdjacentPin({
    this.id,
    required this.type,
    this.pinName = '',
  });

  /// 是否為有效的 GPIO 相鄰腳位
  bool get isGpio => type == AdjacentType.gpio && id != null;

  /// 是否相鄰 Vdd
  bool get isVdd => type == AdjacentType.vdd;

  /// 是否相鄰 Vss
  bool get isVss => type == AdjacentType.vss;
}

/// 腳位資訊
class PinInfo {
  /// ID 編號
  final int id;

  /// STM32 腳位名稱
  final String pinName;

  /// 相鄰腳位 1
  final AdjacentPin adjacent1;

  /// 相鄰腳位 2
  final AdjacentPin adjacent2;

  const PinInfo({
    required this.id,
    required this.pinName,
    required this.adjacent1,
    required this.adjacent2,
  });

  /// 取得所有相鄰的 GPIO ID（不含 Vdd/Vss/null）
  List<int> get adjacentGpioIds {
    final result = <int>[];
    if (adjacent1.isGpio) result.add(adjacent1.id!);
    if (adjacent2.isGpio) result.add(adjacent2.id!);
    return result;
  }

  /// 是否有相鄰 Vdd
  bool get hasAdjacentVdd => adjacent1.isVdd || adjacent2.isVdd;

  /// 是否有相鄰 Vss
  bool get hasAdjacentVss => adjacent1.isVss || adjacent2.isVss;
}

/// 相鄰腳位對照表服務
class AdjacentPinsService {
  /// 預設短路測試誤差閾值
  static const int defaultShortCircuitThreshold = 100;

  /// 短路測試誤差閾值（可設定）
  int _shortCircuitThreshold = defaultShortCircuitThreshold;

  int get shortCircuitThreshold => _shortCircuitThreshold;
  set shortCircuitThreshold(int value) => _shortCircuitThreshold = value;

  /// 腳位資訊對照表
  /// 根據使用者提供的 STM32 腳位配置
  static const Map<int, PinInfo> pinInfoMap = {
    0: PinInfo(
      id: 0,
      pinName: 'PB15',
      adjacent1: AdjacentPin(id: 1, type: AdjacentType.gpio, pinName: 'PB14'),
      adjacent2: AdjacentPin(type: AdjacentType.none),  // PD8-ID21 是感測器，不測
    ),
    1: PinInfo(
      id: 1,
      pinName: 'PB14',
      adjacent1: AdjacentPin(id: 0, type: AdjacentType.gpio, pinName: 'PB15'),
      adjacent2: AdjacentPin(type: AdjacentType.none),
    ),
    2: PinInfo(
      id: 2,
      pinName: 'PB13',
      adjacent1: AdjacentPin(id: 3, type: AdjacentType.gpio, pinName: 'PB12'),
      adjacent2: AdjacentPin(type: AdjacentType.none),
    ),
    3: PinInfo(
      id: 3,
      pinName: 'PB12',
      adjacent1: AdjacentPin(id: 2, type: AdjacentType.gpio, pinName: 'PB13'),
      adjacent2: AdjacentPin(type: AdjacentType.vdd, pinName: 'Vdd'),  // 相鄰 Vdd
    ),
    4: PinInfo(
      id: 4,
      pinName: 'PB11',
      adjacent1: AdjacentPin(id: 5, type: AdjacentType.gpio, pinName: 'PB10'),
      adjacent2: AdjacentPin(type: AdjacentType.vss, pinName: 'Vss'),  // 相鄰 Vss
    ),
    5: PinInfo(
      id: 5,
      pinName: 'PB10',
      adjacent1: AdjacentPin(id: 4, type: AdjacentType.gpio, pinName: 'PB11'),
      adjacent2: AdjacentPin(id: 6, type: AdjacentType.gpio, pinName: 'PE9'),
    ),
    6: PinInfo(
      id: 6,
      pinName: 'PE9',
      adjacent1: AdjacentPin(id: 5, type: AdjacentType.gpio, pinName: 'PB10'),
      adjacent2: AdjacentPin(id: 7, type: AdjacentType.gpio, pinName: 'PE8'),
    ),
    7: PinInfo(
      id: 7,
      pinName: 'PE8',
      adjacent1: AdjacentPin(id: 6, type: AdjacentType.gpio, pinName: 'PE9'),
      adjacent2: AdjacentPin(id: 8, type: AdjacentType.gpio, pinName: 'PE7'),
    ),
    8: PinInfo(
      id: 8,
      pinName: 'PE7',
      adjacent1: AdjacentPin(id: 7, type: AdjacentType.gpio, pinName: 'PE8'),
      adjacent2: AdjacentPin(id: 9, type: AdjacentType.gpio, pinName: 'PB2'),
    ),
    9: PinInfo(
      id: 9,
      pinName: 'PB2',
      adjacent1: AdjacentPin(id: 8, type: AdjacentType.gpio, pinName: 'PE7'),
      adjacent2: AdjacentPin(type: AdjacentType.none),
    ),
    10: PinInfo(
      id: 10,
      pinName: 'PC6',
      adjacent1: AdjacentPin(id: 17, type: AdjacentType.gpio, pinName: 'PD13'),
      adjacent2: AdjacentPin(id: 16, type: AdjacentType.gpio, pinName: 'PC7'),
    ),
    11: PinInfo(
      id: 11,
      pinName: 'PD11',
      adjacent1: AdjacentPin(id: 13, type: AdjacentType.gpio, pinName: 'PD12'),
      adjacent2: AdjacentPin(id: 12, type: AdjacentType.gpio, pinName: 'PD10'),
    ),
    12: PinInfo(
      id: 12,
      pinName: 'PD10',
      adjacent1: AdjacentPin(id: 11, type: AdjacentType.gpio, pinName: 'PD11'),
      adjacent2: AdjacentPin(type: AdjacentType.none),
    ),
    13: PinInfo(
      id: 13,
      pinName: 'PD12',
      adjacent1: AdjacentPin(id: 17, type: AdjacentType.gpio, pinName: 'PD13'),
      adjacent2: AdjacentPin(id: 11, type: AdjacentType.gpio, pinName: 'PD11'),
    ),
    14: PinInfo(
      id: 14,
      pinName: 'PC9',
      adjacent1: AdjacentPin(id: 15, type: AdjacentType.gpio, pinName: 'PC8'),
      adjacent2: AdjacentPin(type: AdjacentType.none),
    ),
    15: PinInfo(
      id: 15,
      pinName: 'PC8',
      adjacent1: AdjacentPin(id: 14, type: AdjacentType.gpio, pinName: 'PC9'),
      adjacent2: AdjacentPin(id: 16, type: AdjacentType.gpio, pinName: 'PC7'),
    ),
    16: PinInfo(
      id: 16,
      pinName: 'PC7',
      adjacent1: AdjacentPin(id: 15, type: AdjacentType.gpio, pinName: 'PC8'),
      adjacent2: AdjacentPin(id: 10, type: AdjacentType.gpio, pinName: 'PC6'),
    ),
    17: PinInfo(
      id: 17,
      pinName: 'PD13',
      adjacent1: AdjacentPin(id: 10, type: AdjacentType.gpio, pinName: 'PC6'),
      adjacent2: AdjacentPin(id: 13, type: AdjacentType.gpio, pinName: 'PD12'),
    ),
  };

  /// 取得指定 ID 的腳位資訊
  static PinInfo? getPinInfo(int id) => pinInfoMap[id];

  /// 取得指定 ID 的相鄰 GPIO ID 列表
  static List<int> getAdjacentGpioIds(int id) {
    final pinInfo = pinInfoMap[id];
    return pinInfo?.adjacentGpioIds ?? [];
  }

  /// 檢查指定 ID 是否有相鄰 Vdd
  static bool hasAdjacentVdd(int id) {
    final pinInfo = pinInfoMap[id];
    return pinInfo?.hasAdjacentVdd ?? false;
  }

  /// 檢查指定 ID 是否有相鄰 Vss
  static bool hasAdjacentVss(int id) {
    final pinInfo = pinInfoMap[id];
    return pinInfo?.hasAdjacentVss ?? false;
  }

  /// 取得相鄰 Vdd 的腳位 ID
  static int? get vddAdjacentId => 3;

  /// 取得相鄰 Vss 的腳位 ID
  static int? get vssAdjacentId => 4;

  /// 產生優化後的測試配對列表（避免重複測試）
  /// 返回 List<List<int>>，每個元素是 [主測試ID, 相鄰ID]
  static List<List<int>> generateTestPairs() {
    final testedPairs = <String>{};
    final testPairs = <List<int>>[];

    for (int id = 0; id < 18; id++) {
      final adjacentIds = getAdjacentGpioIds(id);

      for (final adjacentId in adjacentIds) {
        // 建立配對 key（小的在前，確保唯一性）
        final smallId = id < adjacentId ? id : adjacentId;
        final largeId = id < adjacentId ? adjacentId : id;
        final pairKey = '$smallId-$largeId';

        // 如果這個配對還沒測試過，加入列表
        if (!testedPairs.contains(pairKey)) {
          testedPairs.add(pairKey);
          testPairs.add([id, adjacentId]);
        }
      }
    }

    return testPairs;
  }

  /// 檢查數值是否在基準值的誤差範圍內
  /// [value] 當前數值
  /// [baseValue] 基準值（Idle 狀態的數值）
  /// [threshold] 誤差閾值
  bool isWithinThreshold(int value, int baseValue, [int? threshold]) {
    final t = threshold ?? _shortCircuitThreshold;
    return (value - baseValue).abs() <= t;
  }
}
