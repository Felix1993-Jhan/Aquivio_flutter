// ============================================================================
// ThresholdSettingsService - 閾值設定服務 (BodyDoor 版)
// ============================================================================
// 功能：管理自動檢測的閾值設定
// - BodyDoor 只有 Arduino Idle 閾值（ID 0-18，共 19 個 ADC 通道）
// - 無 Running/STM32/MOSFET/感測器/相鄰短路等閾值
// - 持久化儲存（使用 SharedPreferences）
// - 提供恢復初始設定功能
// ============================================================================

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

/// 設備類型（BodyDoor 僅使用 arduino）
enum DeviceType { arduino }

/// 硬體狀態類型（BodyDoor 僅使用 idle）
enum StateType { idle }

/// 閾值設定服務（單例模式）
class ThresholdSettingsService {
  static final ThresholdSettingsService _instance = ThresholdSettingsService._internal();
  factory ThresholdSettingsService() => _instance;
  ThresholdSettingsService._internal();

  /// 設定變更通知器
  final ValueNotifier<int> settingsUpdateNotifier = ValueNotifier(0);

  /// SharedPreferences 實例
  SharedPreferences? _prefs;

  /// 儲存鍵名前綴
  static const String _keyPrefix = 'threshold_';

  // ==================== 預設值 ====================

  /// Arduino Idle 預設範圍 (硬體 ID 0-18, 共 19 通道)
  static const Map<int, ThresholdRange> _defaultArduinoIdleThresholds = {
    0:  ThresholdRange(min: 923, max: 1023),  // AmbientRL (5.1V→1023)
    1:  ThresholdRange(min: 923, max: 1023),  // CoolRL (5.1V→1023)
    2:  ThresholdRange(min: 923, max: 1023),  // SparklingRL (5.1V→1023)
    3:  ThresholdRange(min: 923, max: 1023),  // WaterPump (5.1V→1023)
    4:  ThresholdRange(min: 923, max: 1023),  // O3 (5.1V→1023)
    5:  ThresholdRange(min: 923, max: 1023),  // MainUVC (5.1V→1023)
    6:  ThresholdRange(min: 237, max: 437),   // BibTemp (1.65V→337)
    7:  ThresholdRange(min: 923, max: 1023),  // FlowMeter (5.1V→1023)
    8:  ThresholdRange(min: 237, max: 437),   // WaterTemp (1.65V→337)
    9:  ThresholdRange(min: 237, max: 437),   // Leak (1.65V→337)
    10: ThresholdRange(min: 237, max: 437),   // WaterPressure (1.65V→337)
    11: ThresholdRange(min: 237, max: 437),   // CO2Pressure (1.65V→337)
    12: ThresholdRange(min: 923, max: 1023),  // SpoutUVC (5.1V→1023)
    13: ThresholdRange(min: 923, max: 1023),  // MixUVC (5.1V→1023)
    14: ThresholdRange(min: 923, max: 1023),  // FlowMeter2 (5.1V→1023)
    15: ThresholdRange(min: 346, max: 546),   // BP_24V (2.18V→446)
    16: ThresholdRange(min: 686, max: 886),   // BP_12V (3.84V→786)
    17: ThresholdRange(min: 686, max: 886),   // BP_UpScreen (3.84V→786)
    18: ThresholdRange(min: 686, max: 886),   // BP_LowScreen (3.84V→786)
  };

  /// 電源異常偵測預設閾值（低於此值判定異常）
  static const int defaultPower33vThreshold = 300;
  static const int defaultPowerBody12vThreshold = 300;
  static const int defaultPowerDoor24vThreshold = 300;
  static const int defaultPowerDoor12vThreshold = 300;

  /// 預設輪詢參數
  static const int defaultMaxRetryPerID = 5;
  static const int defaultHardwareWaitMs = 300;

  // ==================== 當前設定值 ====================

  Map<int, ThresholdRange> _arduinoIdleThresholds = Map.from(_defaultArduinoIdleThresholds);

  /// 電源異常閾值
  int _power33vThreshold = defaultPower33vThreshold;
  int _powerBody12vThreshold = defaultPowerBody12vThreshold;
  int _powerDoor24vThreshold = defaultPowerDoor24vThreshold;
  int _powerDoor12vThreshold = defaultPowerDoor12vThreshold;

  /// 輪詢：每個 ID 最大重試次數
  int _maxRetryPerID = defaultMaxRetryPerID;
  /// 輪詢：硬體等待時間 (ms)
  int _hardwareWaitMs = defaultHardwareWaitMs;

  // ==================== 初始化 ====================

  /// 初始化服務（應在 app 啟動時呼叫）
  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    await _loadSettings();
  }

  /// 載入設定
  Future<void> _loadSettings() async {
    _arduinoIdleThresholds = _loadThresholdMap('arduino_idle_hardware', _defaultArduinoIdleThresholds);
    _power33vThreshold = _prefs?.getInt('${_keyPrefix}power_33v_threshold') ?? defaultPower33vThreshold;
    _powerBody12vThreshold = _prefs?.getInt('${_keyPrefix}power_body12v_threshold') ?? defaultPowerBody12vThreshold;
    _powerDoor24vThreshold = _prefs?.getInt('${_keyPrefix}power_door24v_threshold') ?? defaultPowerDoor24vThreshold;
    _powerDoor12vThreshold = _prefs?.getInt('${_keyPrefix}power_door12v_threshold') ?? defaultPowerDoor12vThreshold;
    _maxRetryPerID = _prefs?.getInt('${_keyPrefix}polling_max_retry') ?? defaultMaxRetryPerID;
    _hardwareWaitMs = _prefs?.getInt('${_keyPrefix}polling_hw_wait') ?? defaultHardwareWaitMs;
  }

  /// 載入 ThresholdRange Map
  Map<int, ThresholdRange> _loadThresholdMap(String key, Map<int, ThresholdRange> defaultValue) {
    final jsonStr = _prefs?.getString('$_keyPrefix$key');
    if (jsonStr == null) {
      return Map.from(defaultValue);
    }
    try {
      final Map<String, dynamic> jsonMap = json.decode(jsonStr);
      final result = <int, ThresholdRange>{};
      jsonMap.forEach((k, v) {
        result[int.parse(k)] = ThresholdRange.fromJson(v);
      });
      return result;
    } catch (e) {
      return Map.from(defaultValue);
    }
  }

  /// 儲存 ThresholdRange Map
  Future<void> _saveThresholdMap(String key, Map<int, ThresholdRange> value) async {
    final jsonMap = <String, dynamic>{};
    value.forEach((k, v) {
      jsonMap[k.toString()] = v.toJson();
    });
    await _prefs?.setString('$_keyPrefix$key', json.encode(jsonMap));
    _notifyUpdate();
  }

  /// 通知更新
  void _notifyUpdate() {
    settingsUpdateNotifier.value++;
  }

  // ==================== 取得設定值 ====================

  /// 取得硬體閾值範圍
  ThresholdRange getHardwareThreshold(DeviceType device, StateType state, int id) {
    if (id < 0 || id > 18) {
      return const ThresholdRange(min: 0, max: 1023);
    }
    return _arduinoIdleThresholds[id] ?? _defaultArduinoIdleThresholds[id]!;
  }

  /// 取得所有硬體閾值設定（用於 UI 顯示）
  Map<int, ThresholdRange> getAllHardwareThresholds(DeviceType device, StateType state) {
    return Map.from(_arduinoIdleThresholds);
  }

  /// 電源異常閾值
  int get power33vThreshold => _power33vThreshold;
  int get powerBody12vThreshold => _powerBody12vThreshold;
  int get powerDoor24vThreshold => _powerDoor24vThreshold;
  int get powerDoor12vThreshold => _powerDoor12vThreshold;

  /// 輪詢參數
  int get maxRetryPerID => _maxRetryPerID;
  int get hardwareWaitMs => _hardwareWaitMs;

  // ==================== 設定值 ====================

  /// 設定單一硬體閾值
  Future<void> setHardwareThreshold(DeviceType device, StateType state, int id, ThresholdRange range) async {
    _arduinoIdleThresholds[id] = range;
    await _saveThresholdMap('arduino_idle_hardware', _arduinoIdleThresholds);
  }

  /// 批次設定硬體閾值（所有 ID 使用相同範圍）
  Future<void> setAllHardwareThresholds(DeviceType device, StateType state, ThresholdRange range) async {
    final map = <int, ThresholdRange>{};
    for (int id = 0; id <= 18; id++) {
      map[id] = range;
    }
    _arduinoIdleThresholds = map;
    await _saveThresholdMap('arduino_idle_hardware', _arduinoIdleThresholds);
  }

  /// 設定電源異常閾值
  Future<void> setPower33vThreshold(int v) async {
    _power33vThreshold = v;
    await _prefs?.setInt('${_keyPrefix}power_33v_threshold', v);
    _notifyUpdate();
  }

  Future<void> setPowerBody12vThreshold(int v) async {
    _powerBody12vThreshold = v;
    await _prefs?.setInt('${_keyPrefix}power_body12v_threshold', v);
    _notifyUpdate();
  }

  Future<void> setPowerDoor24vThreshold(int v) async {
    _powerDoor24vThreshold = v;
    await _prefs?.setInt('${_keyPrefix}power_door24v_threshold', v);
    _notifyUpdate();
  }

  Future<void> setPowerDoor12vThreshold(int v) async {
    _powerDoor12vThreshold = v;
    await _prefs?.setInt('${_keyPrefix}power_door12v_threshold', v);
    _notifyUpdate();
  }

  /// 設定輪詢參數
  Future<void> setMaxRetryPerID(int v) async {
    _maxRetryPerID = v;
    await _prefs?.setInt('${_keyPrefix}polling_max_retry', v);
    _notifyUpdate();
  }

  Future<void> setHardwareWaitMs(int v) async {
    _hardwareWaitMs = v;
    await _prefs?.setInt('${_keyPrefix}polling_hw_wait', v);
    _notifyUpdate();
  }

  // ==================== 恢復預設值 ====================

  /// 恢復所有設定為預設值
  Future<void> resetToDefaults() async {
    _arduinoIdleThresholds = Map.from(_defaultArduinoIdleThresholds);
    _power33vThreshold = defaultPower33vThreshold;
    _powerBody12vThreshold = defaultPowerBody12vThreshold;
    _powerDoor24vThreshold = defaultPowerDoor24vThreshold;
    _powerDoor12vThreshold = defaultPowerDoor12vThreshold;
    _maxRetryPerID = defaultMaxRetryPerID;
    _hardwareWaitMs = defaultHardwareWaitMs;

    // 清除所有儲存的設定
    final keys = _prefs?.getKeys().where((k) => k.startsWith(_keyPrefix)).toList() ?? [];
    for (final key in keys) {
      await _prefs?.remove(key);
    }

    _notifyUpdate();
  }

  // ==================== 驗證方法 ====================

  /// 驗證硬體數值是否在閾值範圍內
  bool validateHardwareValue(DeviceType device, StateType state, int id, int value) {
    final range = getHardwareThreshold(device, state, id);
    return range.isInRange(value);
  }
}
