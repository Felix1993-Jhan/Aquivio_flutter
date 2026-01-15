// ============================================================================
// ThresholdSettingsService - 閾值設定服務
// ============================================================================
// 功能：管理自動檢測的閾值設定
// - 支援 Arduino/STM32 各自的 Idle/Running 閾值範圍
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

/// 設備類型
enum DeviceType { arduino, stm32 }

/// 硬體狀態類型
enum StateType { idle, running }

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
  // 這些是初始預設值，可以被恢復

  /// Arduino Idle 預設範圍 (硬體 ID 0-17)
  static const Map<int, ThresholdRange> _defaultArduinoIdleHardware = {
    0: ThresholdRange(min: 770, max: 830),
    1: ThresholdRange(min: 770, max: 830),
    2: ThresholdRange(min: 770, max: 830),
    3: ThresholdRange(min: 770, max: 830),
    4: ThresholdRange(min: 770, max: 830),
    5: ThresholdRange(min: 770, max: 830),
    6: ThresholdRange(min: 770, max: 830),
    7: ThresholdRange(min: 770, max: 830),
    8: ThresholdRange(min: 770, max: 830),
    9: ThresholdRange(min: 770, max: 830),
    10: ThresholdRange(min: 770, max: 830),
    11: ThresholdRange(min: 770, max: 830),
    12: ThresholdRange(min: 770, max: 830),
    13: ThresholdRange(min: 770, max: 830),
    14: ThresholdRange(min: 770, max: 830),
    15: ThresholdRange(min: 770, max: 830),
    16: ThresholdRange(min: 770, max: 830),
    17: ThresholdRange(min: 770, max: 830),
  };

  /// Arduino Running 預設範圍 (硬體 ID 0-17)
  static const Map<int, ThresholdRange> _defaultArduinoRunningHardware = {
    0: ThresholdRange(min: 30, max: 60),
    1: ThresholdRange(min: 30, max: 60),
    2: ThresholdRange(min: 30, max: 60),
    3: ThresholdRange(min: 30, max: 60),
    4: ThresholdRange(min: 30, max: 60),
    5: ThresholdRange(min: 30, max: 60),
    6: ThresholdRange(min: 30, max: 60),
    7: ThresholdRange(min: 30, max: 60),
    8: ThresholdRange(min: 30, max: 60),
    9: ThresholdRange(min: 30, max: 60),
    10: ThresholdRange(min: 30, max: 60),
    11: ThresholdRange(min: 30, max: 60),
    12: ThresholdRange(min: 30, max: 60),
    13: ThresholdRange(min: 30, max: 60),
    14: ThresholdRange(min: 30, max: 60),
    15: ThresholdRange(min: 30, max: 60),
    16: ThresholdRange(min: 30, max: 60),
    17: ThresholdRange(min: 30, max: 60),
  };

  /// STM32 Idle 預設範圍 (硬體 ID 0-17)
  static const Map<int, ThresholdRange> _defaultStm32IdleHardware = {
    0: ThresholdRange(min: 0, max: 35),
    1: ThresholdRange(min: 0, max: 35),
    2: ThresholdRange(min: 0, max: 35),
    3: ThresholdRange(min: 0, max: 35),
    4: ThresholdRange(min: 0, max: 35),
    5: ThresholdRange(min: 0, max: 35),
    6: ThresholdRange(min: 0, max: 35),
    7: ThresholdRange(min: 0, max: 35),
    8: ThresholdRange(min: 0, max: 35),
    9: ThresholdRange(min: 0, max: 35),
    10: ThresholdRange(min: 0, max: 35),
    11: ThresholdRange(min: 0, max: 35),
    12: ThresholdRange(min: 0, max: 35),
    13: ThresholdRange(min: 0, max: 35),
    14: ThresholdRange(min: 0, max: 35),
    15: ThresholdRange(min: 0, max: 35),
    16: ThresholdRange(min: 0, max: 35),
    17: ThresholdRange(min: 0, max: 35),
  };

  /// STM32 Running 預設範圍 (硬體 ID 0-17)
  static const Map<int, ThresholdRange> _defaultStm32RunningHardware = {
    0: ThresholdRange(min: 330, max: 350),
    1: ThresholdRange(min: 330, max: 350),
    2: ThresholdRange(min: 330, max: 350),
    3: ThresholdRange(min: 330, max: 350),
    4: ThresholdRange(min: 330, max: 350),
    5: ThresholdRange(min: 330, max: 350),
    6: ThresholdRange(min: 330, max: 350),
    7: ThresholdRange(min: 330, max: 350),
    8: ThresholdRange(min: 330, max: 350),
    9: ThresholdRange(min: 330, max: 350),
    10: ThresholdRange(min: 330, max: 350),
    11: ThresholdRange(min: 330, max: 350),
    12: ThresholdRange(min: 330, max: 350),
    13: ThresholdRange(min: 330, max: 350),
    14: ThresholdRange(min: 330, max: 350),
    15: ThresholdRange(min: 330, max: 350),
    16: ThresholdRange(min: 330, max: 350),
    17: ThresholdRange(min: 330, max: 350),
  };

  /// Arduino 感測器預設範圍 (ID 18-21)
  static const Map<int, ThresholdRange> _defaultArduinoSensor = {
    18: ThresholdRange(min: 0, max: 10000),    // Flow
    19: ThresholdRange(min: 200, max: 260),    // PressureCO2
    20: ThresholdRange(min: 200, max: 260),    // PressureWater
    21: ThresholdRange(min: -20, max: 100),    // MCUtemp (除以10後，溫度範圍 -20~100)
  };

  /// STM32 感測器預設範圍 (ID 18-23)
  static const Map<int, ThresholdRange> _defaultStm32Sensor = {
    18: ThresholdRange(min: 0, max: 10000),    // Flow
    19: ThresholdRange(min: 930, max: 965),    // PressureCO2 (1V 對應 930~965)
    20: ThresholdRange(min: 930, max: 965),    // PressureWater (1V 對應 930~965)
    21: ThresholdRange(min: -20, max: 100),    // MCUtemp (溫度範圍 -20~100)
    22: ThresholdRange(min: -20, max: 100),    // WATERtemp (溫度範圍 -20~100)
    23: ThresholdRange(min: -20, max: 100),    // BIBtemp (溫度範圍 -20~100)
  };

  /// 差值比較的閾值（用於感測器中需要差值比較的項目）
  /// WATERtemp(22) 和 BIBtemp(23) 與 Arduino MCUtemp 比對，溫差超過 5 度為異常
  static const Map<int, int> _defaultDiffThreshold = {
    18: 50,    // Flow 差值閾值
    21: 5,     // MCUtemp 差值閾值 (與 Arduino 比對)
    22: 5,     // WATERtemp 與 Arduino MCUtemp 溫差閾值
    23: 5,     // BIBtemp 與 Arduino MCUtemp 溫差閾值
  };

  // ==================== 當前設定值 ====================

  late Map<int, ThresholdRange> _arduinoIdleHardware;
  late Map<int, ThresholdRange> _arduinoRunningHardware;
  late Map<int, ThresholdRange> _stm32IdleHardware;
  late Map<int, ThresholdRange> _stm32RunningHardware;
  late Map<int, ThresholdRange> _arduinoSensor;
  late Map<int, ThresholdRange> _stm32Sensor;
  late Map<int, int> _diffThreshold;

  // ==================== 初始化 ====================

  /// 初始化服務（應在 app 啟動時呼叫）
  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    await _loadSettings();
  }

  /// 載入設定
  Future<void> _loadSettings() async {
    _arduinoIdleHardware = _loadThresholdMap('arduino_idle_hardware', _defaultArduinoIdleHardware);
    _arduinoRunningHardware = _loadThresholdMap('arduino_running_hardware', _defaultArduinoRunningHardware);
    _stm32IdleHardware = _loadThresholdMap('stm32_idle_hardware', _defaultStm32IdleHardware);
    _stm32RunningHardware = _loadThresholdMap('stm32_running_hardware', _defaultStm32RunningHardware);
    _arduinoSensor = _loadThresholdMap('arduino_sensor', _defaultArduinoSensor);
    _stm32Sensor = _loadThresholdMap('stm32_sensor', _defaultStm32Sensor);
    _diffThreshold = _loadIntMap('diff_threshold', _defaultDiffThreshold);
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

  /// 載入 int Map
  Map<int, int> _loadIntMap(String key, Map<int, int> defaultValue) {
    final jsonStr = _prefs?.getString('$_keyPrefix$key');
    if (jsonStr == null) {
      return Map.from(defaultValue);
    }
    try {
      final Map<String, dynamic> jsonMap = json.decode(jsonStr);
      final result = <int, int>{};
      jsonMap.forEach((k, v) {
        result[int.parse(k)] = v as int;
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

  /// 儲存 int Map
  Future<void> _saveIntMap(String key, Map<int, int> value) async {
    final jsonMap = <String, dynamic>{};
    value.forEach((k, v) {
      jsonMap[k.toString()] = v;
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
    if (id < 0 || id > 17) {
      return const ThresholdRange(min: 0, max: 1000);
    }

    if (device == DeviceType.arduino) {
      if (state == StateType.idle) {
        return _arduinoIdleHardware[id] ?? _defaultArduinoIdleHardware[id]!;
      } else {
        return _arduinoRunningHardware[id] ?? _defaultArduinoRunningHardware[id]!;
      }
    } else {
      if (state == StateType.idle) {
        return _stm32IdleHardware[id] ?? _defaultStm32IdleHardware[id]!;
      } else {
        return _stm32RunningHardware[id] ?? _defaultStm32RunningHardware[id]!;
      }
    }
  }

  /// 取得感測器閾值範圍
  ThresholdRange getSensorThreshold(DeviceType device, int id) {
    if (device == DeviceType.arduino) {
      return _arduinoSensor[id] ?? const ThresholdRange(min: 0, max: 10000);
    } else {
      return _stm32Sensor[id] ?? const ThresholdRange(min: 0, max: 10000);
    }
  }

  /// 取得差值閾值
  int getDiffThreshold(int id) {
    return _diffThreshold[id] ?? 250;
  }

  /// 取得所有硬體閾值設定（用於 UI 顯示）
  Map<int, ThresholdRange> getAllHardwareThresholds(DeviceType device, StateType state) {
    if (device == DeviceType.arduino) {
      return state == StateType.idle ? Map.from(_arduinoIdleHardware) : Map.from(_arduinoRunningHardware);
    } else {
      return state == StateType.idle ? Map.from(_stm32IdleHardware) : Map.from(_stm32RunningHardware);
    }
  }

  /// 取得所有感測器閾值設定
  Map<int, ThresholdRange> getAllSensorThresholds(DeviceType device) {
    return device == DeviceType.arduino ? Map.from(_arduinoSensor) : Map.from(_stm32Sensor);
  }

  /// 取得所有差值閾值
  Map<int, int> getAllDiffThresholds() {
    return Map.from(_diffThreshold);
  }

  // ==================== 設定值 ====================

  /// 設定單一硬體閾值
  Future<void> setHardwareThreshold(DeviceType device, StateType state, int id, ThresholdRange range) async {
    if (device == DeviceType.arduino) {
      if (state == StateType.idle) {
        _arduinoIdleHardware[id] = range;
        await _saveThresholdMap('arduino_idle_hardware', _arduinoIdleHardware);
      } else {
        _arduinoRunningHardware[id] = range;
        await _saveThresholdMap('arduino_running_hardware', _arduinoRunningHardware);
      }
    } else {
      if (state == StateType.idle) {
        _stm32IdleHardware[id] = range;
        await _saveThresholdMap('stm32_idle_hardware', _stm32IdleHardware);
      } else {
        _stm32RunningHardware[id] = range;
        await _saveThresholdMap('stm32_running_hardware', _stm32RunningHardware);
      }
    }
  }

  /// 批次設定硬體閾值（同一設備/狀態的所有 ID 使用相同範圍）
  Future<void> setAllHardwareThresholds(DeviceType device, StateType state, ThresholdRange range) async {
    final map = <int, ThresholdRange>{};
    for (int id = 0; id < 18; id++) {
      map[id] = range;
    }

    if (device == DeviceType.arduino) {
      if (state == StateType.idle) {
        _arduinoIdleHardware = map;
        await _saveThresholdMap('arduino_idle_hardware', _arduinoIdleHardware);
      } else {
        _arduinoRunningHardware = map;
        await _saveThresholdMap('arduino_running_hardware', _arduinoRunningHardware);
      }
    } else {
      if (state == StateType.idle) {
        _stm32IdleHardware = map;
        await _saveThresholdMap('stm32_idle_hardware', _stm32IdleHardware);
      } else {
        _stm32RunningHardware = map;
        await _saveThresholdMap('stm32_running_hardware', _stm32RunningHardware);
      }
    }
  }

  /// 設定感測器閾值
  Future<void> setSensorThreshold(DeviceType device, int id, ThresholdRange range) async {
    if (device == DeviceType.arduino) {
      _arduinoSensor[id] = range;
      await _saveThresholdMap('arduino_sensor', _arduinoSensor);
    } else {
      _stm32Sensor[id] = range;
      await _saveThresholdMap('stm32_sensor', _stm32Sensor);
    }
  }

  /// 設定差值閾值
  Future<void> setDiffThreshold(int id, int threshold) async {
    _diffThreshold[id] = threshold;
    await _saveIntMap('diff_threshold', _diffThreshold);
  }

  // ==================== 恢復預設值 ====================

  /// 恢復所有設定為預設值
  Future<void> resetToDefaults() async {
    _arduinoIdleHardware = Map.from(_defaultArduinoIdleHardware);
    _arduinoRunningHardware = Map.from(_defaultArduinoRunningHardware);
    _stm32IdleHardware = Map.from(_defaultStm32IdleHardware);
    _stm32RunningHardware = Map.from(_defaultStm32RunningHardware);
    _arduinoSensor = Map.from(_defaultArduinoSensor);
    _stm32Sensor = Map.from(_defaultStm32Sensor);
    _diffThreshold = Map.from(_defaultDiffThreshold);

    // 清除所有儲存的設定
    final keys = _prefs?.getKeys().where((k) => k.startsWith(_keyPrefix)).toList() ?? [];
    for (final key in keys) {
      await _prefs?.remove(key);
    }

    _notifyUpdate();
  }

  /// 恢復特定類型的設定為預設值
  Future<void> resetCategoryToDefaults(DeviceType device, StateType state) async {
    if (device == DeviceType.arduino) {
      if (state == StateType.idle) {
        _arduinoIdleHardware = Map.from(_defaultArduinoIdleHardware);
        await _prefs?.remove('${_keyPrefix}arduino_idle_hardware');
      } else {
        _arduinoRunningHardware = Map.from(_defaultArduinoRunningHardware);
        await _prefs?.remove('${_keyPrefix}arduino_running_hardware');
      }
    } else {
      if (state == StateType.idle) {
        _stm32IdleHardware = Map.from(_defaultStm32IdleHardware);
        await _prefs?.remove('${_keyPrefix}stm32_idle_hardware');
      } else {
        _stm32RunningHardware = Map.from(_defaultStm32RunningHardware);
        await _prefs?.remove('${_keyPrefix}stm32_running_hardware');
      }
    }
    _notifyUpdate();
  }

  // ==================== 驗證方法 ====================

  /// 驗證硬體數值是否在閾值範圍內
  bool validateHardwareValue(DeviceType device, StateType state, int id, int value) {
    final range = getHardwareThreshold(device, state, id);
    return range.isInRange(value);
  }

  /// 驗證感測器數值是否在閾值範圍內
  bool validateSensorValue(DeviceType device, int id, int value) {
    final range = getSensorThreshold(device, id);
    return range.isInRange(value);
  }

  /// 驗證差值是否在閾值範圍內
  bool validateDiff(int id, int diff) {
    final threshold = getDiffThreshold(id);
    return diff.abs() <= threshold;
  }
}
