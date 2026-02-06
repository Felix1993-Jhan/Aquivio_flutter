// ============================================================================
// ThresholdRange - 閾值範圍類別
// ============================================================================
// 功能：定義單一 ID 的閾值範圍設定
// 使用方式：被 Main 和 BodyDoor 的 ThresholdSettingsService 引用
// ============================================================================

/// 單一 ID 的閾值範圍設定
class ThresholdRange {
  final int min;
  final int max;

  const ThresholdRange({required this.min, required this.max});

  /// 檢查數值是否在範圍內
  bool isInRange(int value) => value >= min && value <= max;

  /// 從 JSON 建立
  factory ThresholdRange.fromJson(Map<String, dynamic> json) {
    return ThresholdRange(
      min: json['min'] as int,
      max: json['max'] as int,
    );
  }

  /// 轉換為 JSON
  Map<String, dynamic> toJson() => {'min': min, 'max': max};

  @override
  String toString() => '$min ~ $max';
}
