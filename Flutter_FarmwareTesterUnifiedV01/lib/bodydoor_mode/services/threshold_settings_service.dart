// ============================================================================
// ThresholdSettingsService - 閾值設定服務 (BodyDoor 版)
// ============================================================================
// 功能：管理自動檢測的閾值設定
// - BodyDoor 只有 Arduino Idle 閾值（ID 0-18，共 19 個 ADC 通道）
// - 無 Running/STM32/MOSFET/感測器/相鄰短路等閾值
// - 持久化儲存（使用 SharedPreferences）
// - 提供恢復初始設定功能
// ============================================================================

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_firmware_tester_unified/shared/models/threshold_range.dart';
import 'package:flutter_firmware_tester_unified/shared/services/threshold_storage_mixin.dart';

// ThresholdRange 類別已移至 shared/models/threshold_range.dart
export 'package:flutter_firmware_tester_unified/shared/models/threshold_range.dart';

/// 設備類型（BodyDoor 僅使用 arduino）
enum DeviceType { arduino }

/// 硬體狀態類型（BodyDoor 僅使用 idle）
enum StateType { idle }

/// 閾值設定服務（單例模式）
class ThresholdSettingsService with ThresholdStorageMixin {
  static final ThresholdSettingsService _instance = ThresholdSettingsService._internal();
  factory ThresholdSettingsService() => _instance;
  ThresholdSettingsService._internal();

  // ==================== Mixin 實作 ====================

  /// 設定變更通知器
  @override
  final ValueNotifier<int> settingsUpdateNotifier = ValueNotifier(0);

  /// SharedPreferences 實例
  SharedPreferences? _prefs;

  @override
  SharedPreferences? get prefs => _prefs;

  /// 儲存鍵名前綴
  static const String _keyPrefix = 'threshold_';

  @override
  String get keyPrefix => _keyPrefix;

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

  /// 載入設定（使用 Mixin 提供的方法）
  Future<void> _loadSettings() async {
    _arduinoIdleThresholds = loadThresholdMap('arduino_idle_hardware', _defaultArduinoIdleThresholds);
    _power33vThreshold = loadInt('power_33v_threshold', defaultPower33vThreshold);
    _powerBody12vThreshold = loadInt('power_body12v_threshold', defaultPowerBody12vThreshold);
    _powerDoor24vThreshold = loadInt('power_door24v_threshold', defaultPowerDoor24vThreshold);
    _powerDoor12vThreshold = loadInt('power_door12v_threshold', defaultPowerDoor12vThreshold);
    _maxRetryPerID = loadInt('polling_max_retry', defaultMaxRetryPerID);
    _hardwareWaitMs = loadInt('polling_hw_wait', defaultHardwareWaitMs);
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
    await saveThresholdMap('arduino_idle_hardware', _arduinoIdleThresholds);
  }

  /// 批次設定硬體閾值（所有 ID 使用相同範圍）
  Future<void> setAllHardwareThresholds(DeviceType device, StateType state, ThresholdRange range) async {
    final map = <int, ThresholdRange>{};
    for (int id = 0; id <= 18; id++) {
      map[id] = range;
    }
    _arduinoIdleThresholds = map;
    await saveThresholdMap('arduino_idle_hardware', _arduinoIdleThresholds);
  }

  /// 設定電源異常閾值
  Future<void> setPower33vThreshold(int v) async {
    _power33vThreshold = v;
    await _prefs?.setInt('${_keyPrefix}power_33v_threshold', v);
    notifyUpdate();
  }

  Future<void> setPowerBody12vThreshold(int v) async {
    _powerBody12vThreshold = v;
    await _prefs?.setInt('${_keyPrefix}power_body12v_threshold', v);
    notifyUpdate();
  }

  Future<void> setPowerDoor24vThreshold(int v) async {
    _powerDoor24vThreshold = v;
    await _prefs?.setInt('${_keyPrefix}power_door24v_threshold', v);
    notifyUpdate();
  }

  Future<void> setPowerDoor12vThreshold(int v) async {
    _powerDoor12vThreshold = v;
    await _prefs?.setInt('${_keyPrefix}power_door12v_threshold', v);
    notifyUpdate();
  }

  /// 設定輪詢參數
  Future<void> setMaxRetryPerID(int v) async {
    _maxRetryPerID = v;
    await _prefs?.setInt('${_keyPrefix}polling_max_retry', v);
    notifyUpdate();
  }

  Future<void> setHardwareWaitMs(int v) async {
    _hardwareWaitMs = v;
    await _prefs?.setInt('${_keyPrefix}polling_hw_wait', v);
    notifyUpdate();
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

    notifyUpdate();
  }

  // ==================== 驗證方法 ====================

  /// 驗證硬體數值是否在閾值範圍內
  bool validateHardwareValue(DeviceType device, StateType state, int id, int value) {
    final range = getHardwareThreshold(device, state, id);
    return range.isInRange(value);
  }
}
