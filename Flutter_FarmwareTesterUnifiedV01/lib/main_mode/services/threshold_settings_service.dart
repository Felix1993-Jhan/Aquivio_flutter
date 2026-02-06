// ============================================================================
// ThresholdSettingsService - 閾值設定服務
// ============================================================================
// 功能：管理自動檢測的閾值設定
// - 支援 Arduino/STM32 各自的 Idle/Running 閾值範圍
// - 持久化儲存（使用 SharedPreferences）
// - 提供恢復初始設定功能
// ============================================================================

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_firmware_tester_unified/shared/models/threshold_range.dart';
import 'package:flutter_firmware_tester_unified/shared/services/threshold_storage_mixin.dart';

// ThresholdRange 類別已移至 shared/models/threshold_range.dart
export 'package:flutter_firmware_tester_unified/shared/models/threshold_range.dart';

/// 設備類型
enum DeviceType { arduino, stm32 }

/// 硬體狀態類型
enum StateType { idle, running }

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

  // ==================== 初始化狀態 ====================

  /// 是否已完成初始化
  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;

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
    0: ThresholdRange(min: 25, max: 60),
    1: ThresholdRange(min: 25, max: 60),
    2: ThresholdRange(min: 25, max: 60),
    3: ThresholdRange(min: 25, max: 60),
    4: ThresholdRange(min: 25, max: 60),
    5: ThresholdRange(min: 25, max: 60),
    6: ThresholdRange(min: 25, max: 60),
    7: ThresholdRange(min: 25, max: 60),
    8: ThresholdRange(min: 25, max: 60),
    9: ThresholdRange(min: 25, max: 60),
    10: ThresholdRange(min: 25, max: 60),
    11: ThresholdRange(min: 25, max: 60),
    12: ThresholdRange(min: 25, max: 60),
    13: ThresholdRange(min: 25, max: 60),
    14: ThresholdRange(min: 25, max: 60),
    15: ThresholdRange(min: 25, max: 60),
    16: ThresholdRange(min: 25, max: 60),
    17: ThresholdRange(min: 25, max: 60),
  };

  /// STM32 Idle 預設範圍 (硬體 ID 0-17)
  static const Map<int, ThresholdRange> _defaultStm32IdleHardware = {
    0: ThresholdRange(min: 0, max: 55),
    1: ThresholdRange(min: 0, max: 55),
    2: ThresholdRange(min: 0, max: 55),
    3: ThresholdRange(min: 0, max: 55),
    4: ThresholdRange(min: 0, max: 55),
    5: ThresholdRange(min: 0, max: 55),
    6: ThresholdRange(min: 0, max: 55),
    7: ThresholdRange(min: 0, max: 55),
    8: ThresholdRange(min: 0, max: 55),
    9: ThresholdRange(min: 0, max: 55),
    10: ThresholdRange(min: 0, max: 55),
    11: ThresholdRange(min: 0, max: 55),
    12: ThresholdRange(min: 0, max: 55),
    13: ThresholdRange(min: 0, max: 55),
    14: ThresholdRange(min: 0, max: 55),
    15: ThresholdRange(min: 0, max: 55),
    16: ThresholdRange(min: 0, max: 55),
    17: ThresholdRange(min: 0, max: 55),
  };

  /// STM32 Running 預設範圍 (硬體 ID 0-17)
  static const Map<int, ThresholdRange> _defaultStm32RunningHardware = {
    0: ThresholdRange(min: 300, max: 380),
    1: ThresholdRange(min: 300, max: 380),
    2: ThresholdRange(min: 300, max: 380),
    3: ThresholdRange(min: 300, max: 380),
    4: ThresholdRange(min: 300, max: 380),
    5: ThresholdRange(min: 300, max: 380),
    6: ThresholdRange(min: 300, max: 380),
    7: ThresholdRange(min: 300, max: 380),
    8: ThresholdRange(min: 300, max: 380),
    9: ThresholdRange(min: 300, max: 380),
    10: ThresholdRange(min: 300, max: 380),
    11: ThresholdRange(min: 300, max: 380),
    12: ThresholdRange(min: 300, max: 380),
    13: ThresholdRange(min: 300, max: 380),
    14: ThresholdRange(min: 300, max: 380),
    15: ThresholdRange(min: 300, max: 380),
    16: ThresholdRange(min: 300, max: 380),
    17: ThresholdRange(min: 300, max: 380),
  };

  /// Arduino 感測器預設範圍 (ID 18-21)
  static const Map<int, ThresholdRange> _defaultArduinoSensor = {
    18: ThresholdRange(min: 0, max: 10000),    // Flow
    19: ThresholdRange(min: 190, max: 260),    // PressureCO2
    20: ThresholdRange(min: 190, max: 260),    // PressureWater
    21: ThresholdRange(min: -20, max: 100),    // MCUtemp (除以10後，溫度範圍 -20~100)
  };

  /// STM32 感測器預設範圍 (ID 18-23)
  static const Map<int, ThresholdRange> _defaultStm32Sensor = {
    18: ThresholdRange(min: 0, max: 10000),    // Flow
    19: ThresholdRange(min: 930, max: 980),    // PressureCO2 (1V 對應 930~965)
    20: ThresholdRange(min: 930, max: 980),    // PressureWater (1V 對應 930~965)
    21: ThresholdRange(min: -20, max: 100),    // MCUtemp (溫度範圍 -20~100)
    22: ThresholdRange(min: -20, max: 100),    // WATERtemp (溫度範圍 -20~100)
    23: ThresholdRange(min: -20, max: 100),    // BIBtemp (溫度範圍 -20~100)
  };

  /// 差值比較的閾值（用於感測器中需要差值比較的項目）
  /// WATERtemp(22) 和 BIBtemp(23) 與 Arduino MCUtemp 比對，溫差超過 5 度為異常
  static const Map<int, int> _defaultDiffThreshold = {
    18: 3,     // Flow 差值閾值（Arduino 與 STM32 差異不能超過 3）
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

  // ==================== VDD/VSS 短路測試顯示設定 ====================
  /// 是否顯示 VDD 短路測試結果（預設關閉）
  bool _showVddShortTest = false;
  /// 是否顯示 VSS 短路測試結果（預設關閉）
  bool _showVssShortTest = false;

  // ==================== 相鄰短路測試優化設定 ====================
  /// 是否啟用相鄰短路測試優化（預設關閉）
  /// 優化模式：已測試過的配對會跳過
  /// 非優化模式：所有相鄰配對都會測試，不跳過
  bool _adjacentShortTestOptimization = false;

  // ==================== 相鄰短路顯示模式設定 ====================
  /// 相鄰短路測試顯示模式（預設 false）
  /// false: 傳統模式 - 相鄰腳位數值顯示在左邊 Idle 區域
  /// true: 新模式 - 相鄰腳位數值顯示在右邊 Running 區域的額外欄位
  bool _adjacentShortDisplayInRunning = false;

  // ==================== 診斷偵測設定 ====================
  /// 是否顯示負載偵測結果（預設開啟）
  /// 當 STM32 Running < 100 且 Idle < 50 時判定為負載未連接
  bool _showLoadDetection = true;

  /// 是否顯示 G-S 短路偵測結果（預設開啟）
  /// 當 STM32 Running > 400 且 Idle < 50 時判定為 G-S 短路
  bool _showGsShortDetection = true;

  /// 是否顯示 GPIO 狀態偵測結果（預設開啟）
  /// GPIO 卡在 ON: Idle > 150
  /// GPIO 卡在 OFF: Running < 100（有負載時）
  bool _showGpioStatusDetection = true;

  /// 是否顯示線材錯誤偵測結果（預設開啟）
  /// 當 Arduino Running 維持 Idle 數值，但 STM32 Running 正常時判定為線材錯誤
  bool _showWireErrorDetection = true;

  // ==================== 診斷偵測閾值（可配置） ====================

  // --- 預設值常數 ---
  static const int defaultLoadDetectionRunningThreshold = 100;
  static const int defaultLoadDetectionIdleThreshold = 50;
  static const int defaultGsShortRunningThreshold = 400;
  static const int defaultGpioStuckOnIdleThreshold = 150;
  static const int defaultGpioStuckOffRunningThreshold = 100;
  static const int defaultWireErrorDiffThreshold = 100;
  static const int defaultD12vShortArduinoThreshold = 1000;
  static const int defaultArduinoDiffThreshold = 180;
  static const int defaultLoadDisconnectedStm32RunningMin = 40;
  static const int defaultLoadDisconnectedStm32RunningMax = 70;
  static const int defaultGdShortArduinoRunningMin = 350;
  static const int defaultGdShortArduinoRunningMax = 480;
  static const int defaultGdShortStm32RunningMin = 420;
  static const int defaultGdShortStm32RunningMax = 570;
  static const int defaultDsShortArduinoIdleMin = 25;
  static const int defaultDsShortArduinoIdleMax = 60;
  static const int defaultDsShortStm32IdleMin = 330;
  static const int defaultDsShortStm32IdleMax = 375;
  static const int defaultTempSensorErrorValue = 85;
  static const int defaultAdjacentShortThreshold = 100;
  static const int defaultArduinoVssThreshold = 10;
  static const int defaultArduinoIdleNormalMin = 700;
  static const int defaultMaxRetryPerID = 5;
  static const int defaultHardwareWaitMs = 300;
  static const int defaultSensorWaitMs = 400;

  // --- 可配置欄位 ---
  /// 負載偵測：STM32 Running 低於此值視為無負載
  int _loadDetectionRunningThreshold = defaultLoadDetectionRunningThreshold;
  /// 負載偵測：STM32 Idle 低於此值視為正常（無漏電）
  int _loadDetectionIdleThreshold = defaultLoadDetectionIdleThreshold;
  /// G-S 短路偵測：STM32 Running 高於此值視為 G-S 短路
  int _gsShortRunningThreshold = defaultGsShortRunningThreshold;
  /// GPIO 卡在 ON：STM32 Idle 高於此值視為 GPIO 卡在 ON
  int _gpioStuckOnIdleThreshold = defaultGpioStuckOnIdleThreshold;
  /// GPIO 卡在 OFF：STM32 Running 低於此值視為 GPIO 卡在 OFF（需配合有負載判斷）
  int _gpioStuckOffRunningThreshold = defaultGpioStuckOffRunningThreshold;
  /// 線材錯誤偵測：Arduino Idle 與 Running 差值低於此值視為線材錯誤
  int _wireErrorDiffThreshold = defaultWireErrorDiffThreshold;
  /// D極與12V短路：Arduino 數值高於此值視為短路
  int _d12vShortArduinoThreshold = defaultD12vShortArduinoThreshold;
  /// 負載未連接：Arduino Idle-Running 差異閾值
  int _arduinoDiffThreshold = defaultArduinoDiffThreshold;
  /// 負載未連接：STM32 Running 範圍 Min
  int _loadDisconnectedStm32RunningMin = defaultLoadDisconnectedStm32RunningMin;
  /// 負載未連接：STM32 Running 範圍 Max
  int _loadDisconnectedStm32RunningMax = defaultLoadDisconnectedStm32RunningMax;
  /// G-D 短路：Arduino Running 範圍 Min
  int _gdShortArduinoRunningMin = defaultGdShortArduinoRunningMin;
  /// G-D 短路：Arduino Running 範圍 Max
  int _gdShortArduinoRunningMax = defaultGdShortArduinoRunningMax;
  /// G-D 短路：STM32 Running 範圍 Min
  int _gdShortStm32RunningMin = defaultGdShortStm32RunningMin;
  /// G-D 短路：STM32 Running 範圍 Max
  int _gdShortStm32RunningMax = defaultGdShortStm32RunningMax;
  /// D-S 短路：Arduino Idle 範圍 Min
  int _dsShortArduinoIdleMin = defaultDsShortArduinoIdleMin;
  /// D-S 短路：Arduino Idle 範圍 Max
  int _dsShortArduinoIdleMax = defaultDsShortArduinoIdleMax;
  /// D-S 短路：STM32 Idle 範圍 Min
  int _dsShortStm32IdleMin = defaultDsShortStm32IdleMin;
  /// D-S 短路：STM32 Idle 範圍 Max
  int _dsShortStm32IdleMax = defaultDsShortStm32IdleMax;
  /// 溫度感測器異常值（DS18B20 預設錯誤值）
  int _tempSensorErrorValue = defaultTempSensorErrorValue;
  /// 相鄰腳位短路閾值
  int _adjacentShortThreshold = defaultAdjacentShortThreshold;
  /// D 極接地：Arduino ADC 低於此值視為 D 極接地
  int _arduinoVssThreshold = defaultArduinoVssThreshold;
  /// G 極接地：Arduino Idle 正常最小值
  int _arduinoIdleNormalMin = defaultArduinoIdleNormalMin;
  /// 輪詢：每個 ID 最大重試次數
  int _maxRetryPerID = defaultMaxRetryPerID;
  /// 輪詢：硬體等待時間 (ms)
  int _hardwareWaitMs = defaultHardwareWaitMs;
  /// 輪詢：感測器等待時間 (ms)
  int _sensorWaitMs = defaultSensorWaitMs;

  // ==================== 初始化 ====================

  /// 初始化服務（應在 app 啟動時呼叫）
  Future<void> init() async {
    if (_isInitialized) return;
    _prefs = await SharedPreferences.getInstance();
    await _loadSettings();
    _isInitialized = true;
  }

  /// 載入設定
  Future<void> _loadSettings() async {
    // 使用 Mixin 方法載入 Map 類型設定
    _arduinoIdleHardware = loadThresholdMap('arduino_idle_hardware', _defaultArduinoIdleHardware);
    _arduinoRunningHardware = loadThresholdMap('arduino_running_hardware', _defaultArduinoRunningHardware);
    _stm32IdleHardware = loadThresholdMap('stm32_idle_hardware', _defaultStm32IdleHardware);
    _stm32RunningHardware = loadThresholdMap('stm32_running_hardware', _defaultStm32RunningHardware);
    _arduinoSensor = loadThresholdMap('arduino_sensor', _defaultArduinoSensor);
    _stm32Sensor = loadThresholdMap('stm32_sensor', _defaultStm32Sensor);
    _diffThreshold = loadIntMap('diff_threshold', _defaultDiffThreshold);
    // 使用 Mixin 方法載入 bool 類型設定
    _showVddShortTest = loadBool('show_vdd_short_test', false);
    _showVssShortTest = loadBool('show_vss_short_test', false);
    _adjacentShortTestOptimization = loadBool('adjacent_short_test_optimization', false);
    _adjacentShortDisplayInRunning = loadBool('adjacent_short_display_in_running', false);
    _showLoadDetection = loadBool('show_load_detection', true);
    _showGsShortDetection = loadBool('show_gs_short_detection', true);
    _showGpioStatusDetection = loadBool('show_gpio_status_detection', true);
    _showWireErrorDetection = loadBool('show_wire_error_detection', true);
    // 使用 Mixin 方法載入 int 類型設定
    _loadDetectionRunningThreshold = loadInt('diag_load_running', defaultLoadDetectionRunningThreshold);
    _loadDetectionIdleThreshold = loadInt('diag_load_idle', defaultLoadDetectionIdleThreshold);
    _gsShortRunningThreshold = loadInt('diag_gs_short_running', defaultGsShortRunningThreshold);
    _gpioStuckOnIdleThreshold = loadInt('diag_gpio_stuck_on', defaultGpioStuckOnIdleThreshold);
    _gpioStuckOffRunningThreshold = loadInt('diag_gpio_stuck_off', defaultGpioStuckOffRunningThreshold);
    _wireErrorDiffThreshold = loadInt('diag_wire_error_diff', defaultWireErrorDiffThreshold);
    _d12vShortArduinoThreshold = loadInt('diag_d12v_short', defaultD12vShortArduinoThreshold);
    _arduinoDiffThreshold = loadInt('diag_arduino_diff', defaultArduinoDiffThreshold);
    _loadDisconnectedStm32RunningMin = loadInt('diag_load_stm32_run_min', defaultLoadDisconnectedStm32RunningMin);
    _loadDisconnectedStm32RunningMax = loadInt('diag_load_stm32_run_max', defaultLoadDisconnectedStm32RunningMax);
    _gdShortArduinoRunningMin = loadInt('diag_gd_arduino_run_min', defaultGdShortArduinoRunningMin);
    _gdShortArduinoRunningMax = loadInt('diag_gd_arduino_run_max', defaultGdShortArduinoRunningMax);
    _gdShortStm32RunningMin = loadInt('diag_gd_stm32_run_min', defaultGdShortStm32RunningMin);
    _gdShortStm32RunningMax = loadInt('diag_gd_stm32_run_max', defaultGdShortStm32RunningMax);
    _dsShortArduinoIdleMin = loadInt('diag_ds_arduino_idle_min', defaultDsShortArduinoIdleMin);
    _dsShortArduinoIdleMax = loadInt('diag_ds_arduino_idle_max', defaultDsShortArduinoIdleMax);
    _dsShortStm32IdleMin = loadInt('diag_ds_stm32_idle_min', defaultDsShortStm32IdleMin);
    _dsShortStm32IdleMax = loadInt('diag_ds_stm32_idle_max', defaultDsShortStm32IdleMax);
    _tempSensorErrorValue = loadInt('diag_temp_error', defaultTempSensorErrorValue);
    _adjacentShortThreshold = loadInt('diag_adjacent_short', defaultAdjacentShortThreshold);
    _arduinoVssThreshold = loadInt('diag_arduino_vss', defaultArduinoVssThreshold);
    _arduinoIdleNormalMin = loadInt('diag_arduino_idle_normal_min', defaultArduinoIdleNormalMin);
    _maxRetryPerID = loadInt('polling_max_retry', defaultMaxRetryPerID);
    _hardwareWaitMs = loadInt('polling_hw_wait', defaultHardwareWaitMs);
    _sensorWaitMs = loadInt('polling_sensor_wait', defaultSensorWaitMs);
  }

  // 注意：_loadThresholdMap, _loadIntMap, _saveThresholdMap, _saveIntMap, notifyUpdate
  // 已移至 ThresholdStorageMixin，改用 loadThresholdMap, loadIntMap, saveThresholdMap,
  // saveIntMap, notifyUpdate 方法

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

  /// 取得是否顯示 VDD 短路測試結果
  bool get showVddShortTest => _showVddShortTest;

  /// 取得是否顯示 VSS 短路測試結果
  bool get showVssShortTest => _showVssShortTest;

  /// 取得是否啟用相鄰短路測試優化
  bool get adjacentShortTestOptimization => _adjacentShortTestOptimization;

  /// 取得相鄰短路顯示模式（true=Running區域顯示, false=Idle區域顯示）
  bool get adjacentShortDisplayInRunning => _adjacentShortDisplayInRunning;

  /// 取得是否顯示負載偵測結果
  bool get showLoadDetection => _showLoadDetection;

  /// 取得是否顯示 MOSFET 異常偵測結果（原 G-S 短路偵測）
  bool get showMosfetDetection => _showGsShortDetection;

  /// 取得是否顯示 GPIO 狀態偵測結果
  bool get showGpioStatusDetection => _showGpioStatusDetection;

  /// 取得是否顯示線材錯誤偵測結果
  bool get showWireErrorDetection => _showWireErrorDetection;

  // ==================== 診斷偵測閾值 Getters ====================

  int get loadDetectionRunningThreshold => _loadDetectionRunningThreshold;
  int get loadDetectionIdleThreshold => _loadDetectionIdleThreshold;
  int get gsShortRunningThreshold => _gsShortRunningThreshold;
  int get gpioStuckOnIdleThreshold => _gpioStuckOnIdleThreshold;
  int get gpioStuckOffRunningThreshold => _gpioStuckOffRunningThreshold;
  int get wireErrorDiffThreshold => _wireErrorDiffThreshold;
  int get d12vShortArduinoThreshold => _d12vShortArduinoThreshold;
  int get arduinoDiffThreshold => _arduinoDiffThreshold;
  int get loadDisconnectedStm32RunningMin => _loadDisconnectedStm32RunningMin;
  int get loadDisconnectedStm32RunningMax => _loadDisconnectedStm32RunningMax;
  int get gdShortArduinoRunningMin => _gdShortArduinoRunningMin;
  int get gdShortArduinoRunningMax => _gdShortArduinoRunningMax;
  int get gdShortStm32RunningMin => _gdShortStm32RunningMin;
  int get gdShortStm32RunningMax => _gdShortStm32RunningMax;
  int get dsShortArduinoIdleMin => _dsShortArduinoIdleMin;
  int get dsShortArduinoIdleMax => _dsShortArduinoIdleMax;
  int get dsShortStm32IdleMin => _dsShortStm32IdleMin;
  int get dsShortStm32IdleMax => _dsShortStm32IdleMax;
  int get tempSensorErrorValue => _tempSensorErrorValue;
  int get adjacentShortThreshold => _adjacentShortThreshold;
  int get arduinoVssThreshold => _arduinoVssThreshold;
  int get arduinoIdleNormalMin => _arduinoIdleNormalMin;
  int get maxRetryPerID => _maxRetryPerID;
  int get hardwareWaitMs => _hardwareWaitMs;
  int get sensorWaitMs => _sensorWaitMs;

  // ==================== 設定值 ====================

  /// 設定單一硬體閾值
  Future<void> setHardwareThreshold(DeviceType device, StateType state, int id, ThresholdRange range) async {
    if (device == DeviceType.arduino) {
      if (state == StateType.idle) {
        _arduinoIdleHardware[id] = range;
        await saveThresholdMap('arduino_idle_hardware', _arduinoIdleHardware);
      } else {
        _arduinoRunningHardware[id] = range;
        await saveThresholdMap('arduino_running_hardware', _arduinoRunningHardware);
      }
    } else {
      if (state == StateType.idle) {
        _stm32IdleHardware[id] = range;
        await saveThresholdMap('stm32_idle_hardware', _stm32IdleHardware);
      } else {
        _stm32RunningHardware[id] = range;
        await saveThresholdMap('stm32_running_hardware', _stm32RunningHardware);
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
        await saveThresholdMap('arduino_idle_hardware', _arduinoIdleHardware);
      } else {
        _arduinoRunningHardware = map;
        await saveThresholdMap('arduino_running_hardware', _arduinoRunningHardware);
      }
    } else {
      if (state == StateType.idle) {
        _stm32IdleHardware = map;
        await saveThresholdMap('stm32_idle_hardware', _stm32IdleHardware);
      } else {
        _stm32RunningHardware = map;
        await saveThresholdMap('stm32_running_hardware', _stm32RunningHardware);
      }
    }
  }

  /// 設定感測器閾值
  Future<void> setSensorThreshold(DeviceType device, int id, ThresholdRange range) async {
    if (device == DeviceType.arduino) {
      _arduinoSensor[id] = range;
      await saveThresholdMap('arduino_sensor', _arduinoSensor);
    } else {
      _stm32Sensor[id] = range;
      await saveThresholdMap('stm32_sensor', _stm32Sensor);
    }
  }

  /// 設定差值閾值
  Future<void> setDiffThreshold(int id, int threshold) async {
    _diffThreshold[id] = threshold;
    await saveIntMap('diff_threshold', _diffThreshold);
  }

  /// 設定是否顯示 VDD 短路測試結果
  Future<void> setShowVddShortTest(bool value) async {
    _showVddShortTest = value;
    await _prefs?.setBool('${_keyPrefix}show_vdd_short_test', value);
    notifyUpdate();
  }

  /// 設定是否顯示 VSS 短路測試結果
  Future<void> setShowVssShortTest(bool value) async {
    _showVssShortTest = value;
    await _prefs?.setBool('${_keyPrefix}show_vss_short_test', value);
    notifyUpdate();
  }

  /// 設定是否啟用相鄰短路測試優化
  Future<void> setAdjacentShortTestOptimization(bool value) async {
    _adjacentShortTestOptimization = value;
    await _prefs?.setBool('${_keyPrefix}adjacent_short_test_optimization', value);
    notifyUpdate();
  }

  /// 設定相鄰短路顯示模式
  Future<void> setAdjacentShortDisplayInRunning(bool value) async {
    _adjacentShortDisplayInRunning = value;
    await _prefs?.setBool('${_keyPrefix}adjacent_short_display_in_running', value);
    notifyUpdate();
  }

  /// 設定是否顯示負載偵測結果
  Future<void> setShowLoadDetection(bool value) async {
    _showLoadDetection = value;
    await _prefs?.setBool('${_keyPrefix}show_load_detection', value);
    notifyUpdate();
  }

  /// 設定是否顯示 MOSFET 異常偵測結果（原 G-S 短路偵測）
  Future<void> setShowMosfetDetection(bool value) async {
    _showGsShortDetection = value;
    await _prefs?.setBool('${_keyPrefix}show_gs_short_detection', value);
    notifyUpdate();
  }

  /// 設定是否顯示 GPIO 狀態偵測結果
  Future<void> setShowGpioStatusDetection(bool value) async {
    _showGpioStatusDetection = value;
    await _prefs?.setBool('${_keyPrefix}show_gpio_status_detection', value);
    notifyUpdate();
  }

  /// 設定是否顯示線材錯誤偵測結果
  Future<void> setShowWireErrorDetection(bool value) async {
    _showWireErrorDetection = value;
    await _prefs?.setBool('${_keyPrefix}show_wire_error_detection', value);
    notifyUpdate();
  }

  // ==================== 診斷偵測閾值 Setters ====================

  Future<void> _setDiagInt(String key, int value) async {
    await _prefs?.setInt('${_keyPrefix}diag_$key', value);
    notifyUpdate();
  }

  Future<void> setLoadDetectionRunningThreshold(int v) async { _loadDetectionRunningThreshold = v; await _setDiagInt('load_running', v); }
  Future<void> setLoadDetectionIdleThreshold(int v) async { _loadDetectionIdleThreshold = v; await _setDiagInt('load_idle', v); }
  Future<void> setGsShortRunningThreshold(int v) async { _gsShortRunningThreshold = v; await _setDiagInt('gs_short_running', v); }
  Future<void> setGpioStuckOnIdleThreshold(int v) async { _gpioStuckOnIdleThreshold = v; await _setDiagInt('gpio_stuck_on', v); }
  Future<void> setGpioStuckOffRunningThreshold(int v) async { _gpioStuckOffRunningThreshold = v; await _setDiagInt('gpio_stuck_off', v); }
  Future<void> setWireErrorDiffThreshold(int v) async { _wireErrorDiffThreshold = v; await _setDiagInt('wire_error_diff', v); }
  Future<void> setD12vShortArduinoThreshold(int v) async { _d12vShortArduinoThreshold = v; await _setDiagInt('d12v_short', v); }
  Future<void> setArduinoDiffThreshold(int v) async { _arduinoDiffThreshold = v; await _setDiagInt('arduino_diff', v); }
  Future<void> setLoadDisconnectedStm32RunningMin(int v) async { _loadDisconnectedStm32RunningMin = v; await _setDiagInt('load_stm32_run_min', v); }
  Future<void> setLoadDisconnectedStm32RunningMax(int v) async { _loadDisconnectedStm32RunningMax = v; await _setDiagInt('load_stm32_run_max', v); }
  Future<void> setGdShortArduinoRunningMin(int v) async { _gdShortArduinoRunningMin = v; await _setDiagInt('gd_arduino_run_min', v); }
  Future<void> setGdShortArduinoRunningMax(int v) async { _gdShortArduinoRunningMax = v; await _setDiagInt('gd_arduino_run_max', v); }
  Future<void> setGdShortStm32RunningMin(int v) async { _gdShortStm32RunningMin = v; await _setDiagInt('gd_stm32_run_min', v); }
  Future<void> setGdShortStm32RunningMax(int v) async { _gdShortStm32RunningMax = v; await _setDiagInt('gd_stm32_run_max', v); }
  Future<void> setDsShortArduinoIdleMin(int v) async { _dsShortArduinoIdleMin = v; await _setDiagInt('ds_arduino_idle_min', v); }
  Future<void> setDsShortArduinoIdleMax(int v) async { _dsShortArduinoIdleMax = v; await _setDiagInt('ds_arduino_idle_max', v); }
  Future<void> setDsShortStm32IdleMin(int v) async { _dsShortStm32IdleMin = v; await _setDiagInt('ds_stm32_idle_min', v); }
  Future<void> setDsShortStm32IdleMax(int v) async { _dsShortStm32IdleMax = v; await _setDiagInt('ds_stm32_idle_max', v); }
  Future<void> setTempSensorErrorValue(int v) async { _tempSensorErrorValue = v; await _setDiagInt('temp_error', v); }
  Future<void> setAdjacentShortThreshold(int v) async { _adjacentShortThreshold = v; await _setDiagInt('adjacent_short', v); }
  Future<void> setArduinoVssThreshold(int v) async { _arduinoVssThreshold = v; await _setDiagInt('arduino_vss', v); }
  Future<void> setArduinoIdleNormalMin(int v) async { _arduinoIdleNormalMin = v; await _setDiagInt('arduino_idle_normal_min', v); }
  Future<void> setMaxRetryPerID(int v) async { _maxRetryPerID = v; await _prefs?.setInt('${_keyPrefix}polling_max_retry', v); notifyUpdate(); }
  Future<void> setHardwareWaitMs(int v) async { _hardwareWaitMs = v; await _prefs?.setInt('${_keyPrefix}polling_hw_wait', v); notifyUpdate(); }
  Future<void> setSensorWaitMs(int v) async { _sensorWaitMs = v; await _prefs?.setInt('${_keyPrefix}polling_sensor_wait', v); notifyUpdate(); }

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
    // VDD/VSS 短路測試顯示設定恢復為預設值（關閉）
    _showVddShortTest = false;
    _showVssShortTest = false;
    // 相鄰短路測試優化設定恢復為預設值（關閉）
    _adjacentShortTestOptimization = false;
    // 相鄰短路顯示模式恢復為預設值（傳統模式）
    _adjacentShortDisplayInRunning = false;
    // 診斷偵測設定恢復為預設值（開啟）
    _showLoadDetection = true;
    _showGsShortDetection = true;
    _showGpioStatusDetection = true;
    _showWireErrorDetection = true;
    // 診斷偵測閾值恢復為預設值
    _resetDiagnosticValues();

    // 清除所有儲存的設定
    final keys = _prefs?.getKeys().where((k) => k.startsWith(_keyPrefix)).toList() ?? [];
    for (final key in keys) {
      await _prefs?.remove(key);
    }

    notifyUpdate();
  }

  /// 重置所有診斷閾值為預設值（內部方法，不通知）
  void _resetDiagnosticValues() {
    _loadDetectionRunningThreshold = defaultLoadDetectionRunningThreshold;
    _loadDetectionIdleThreshold = defaultLoadDetectionIdleThreshold;
    _gsShortRunningThreshold = defaultGsShortRunningThreshold;
    _gpioStuckOnIdleThreshold = defaultGpioStuckOnIdleThreshold;
    _gpioStuckOffRunningThreshold = defaultGpioStuckOffRunningThreshold;
    _wireErrorDiffThreshold = defaultWireErrorDiffThreshold;
    _d12vShortArduinoThreshold = defaultD12vShortArduinoThreshold;
    _arduinoDiffThreshold = defaultArduinoDiffThreshold;
    _loadDisconnectedStm32RunningMin = defaultLoadDisconnectedStm32RunningMin;
    _loadDisconnectedStm32RunningMax = defaultLoadDisconnectedStm32RunningMax;
    _gdShortArduinoRunningMin = defaultGdShortArduinoRunningMin;
    _gdShortArduinoRunningMax = defaultGdShortArduinoRunningMax;
    _gdShortStm32RunningMin = defaultGdShortStm32RunningMin;
    _gdShortStm32RunningMax = defaultGdShortStm32RunningMax;
    _dsShortArduinoIdleMin = defaultDsShortArduinoIdleMin;
    _dsShortArduinoIdleMax = defaultDsShortArduinoIdleMax;
    _dsShortStm32IdleMin = defaultDsShortStm32IdleMin;
    _dsShortStm32IdleMax = defaultDsShortStm32IdleMax;
    _tempSensorErrorValue = defaultTempSensorErrorValue;
    _adjacentShortThreshold = defaultAdjacentShortThreshold;
    _arduinoVssThreshold = defaultArduinoVssThreshold;
    _arduinoIdleNormalMin = defaultArduinoIdleNormalMin;
    _maxRetryPerID = defaultMaxRetryPerID;
    _hardwareWaitMs = defaultHardwareWaitMs;
    _sensorWaitMs = defaultSensorWaitMs;
  }

  /// 恢復診斷偵測閾值為預設值
  Future<void> resetDiagnosticToDefaults() async {
    _resetDiagnosticValues();
    // 清除診斷相關的儲存
    final keys = _prefs?.getKeys().where((k) => k.startsWith('${_keyPrefix}diag_')).toList() ?? [];
    for (final key in keys) {
      await _prefs?.remove(key);
    }
    notifyUpdate();
  }

  /// 恢復感測器閾值為預設值
  Future<void> resetSensorToDefaults() async {
    _arduinoSensor = Map.from(_defaultArduinoSensor);
    _stm32Sensor = Map.from(_defaultStm32Sensor);
    _diffThreshold = Map.from(_defaultDiffThreshold);
    _tempSensorErrorValue = defaultTempSensorErrorValue;
    await _prefs?.remove('${_keyPrefix}arduino_sensor');
    await _prefs?.remove('${_keyPrefix}stm32_sensor');
    await _prefs?.remove('${_keyPrefix}diff_threshold');
    await _prefs?.remove('${_keyPrefix}diag_temp_error');
    notifyUpdate();
  }

  /// 恢復硬體閾值為預設值（所有四組）
  Future<void> resetHardwareToDefaults() async {
    _arduinoIdleHardware = Map.from(_defaultArduinoIdleHardware);
    _arduinoRunningHardware = Map.from(_defaultArduinoRunningHardware);
    _stm32IdleHardware = Map.from(_defaultStm32IdleHardware);
    _stm32RunningHardware = Map.from(_defaultStm32RunningHardware);
    await _prefs?.remove('${_keyPrefix}arduino_idle_hardware');
    await _prefs?.remove('${_keyPrefix}arduino_running_hardware');
    await _prefs?.remove('${_keyPrefix}stm32_idle_hardware');
    await _prefs?.remove('${_keyPrefix}stm32_running_hardware');
    notifyUpdate();
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
    notifyUpdate();
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
