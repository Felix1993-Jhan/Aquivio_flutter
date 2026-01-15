// ============================================================================
// DataStorageService - 數據儲存服務
// ============================================================================
// 功能：儲存 Arduino 和 STM32 回傳的數值
// - 分為「硬體無動作」和「硬體動作」兩種狀態
// - Arduino 和 STM32 的數值分開儲存
// ============================================================================

import 'package:flutter/foundation.dart';

/// 數據狀態：硬體無動作 / 硬體動作
enum HardwareState {
  /// 硬體無動作（未下 0x01 指令，或已下 0x02 停止指令）
  idle,
  /// 硬體動作中（已下 0x01 啟動指令）
  running,
}

/// ID 與名稱對照表
class IdMapping {
  static const Map<int, String> idToName = {
    0: 's0',
    1: 's1',
    2: 's2',
    3: 's3',
    4: 's4',
    5: 's5',
    6: 's6',
    7: 's7',
    8: 's8',
    9: 's9',
    10: 'water',
    11: 'u0',
    12: 'u1',
    13: 'u2',
    14: 'arl',
    15: 'crl',
    16: 'srl',
    17: 'o3',
    18: 'flow',
    19: 'prec',
    20: 'prew',
    21: 'mcutemp',
    22: 'watertemp',
    23: 'bibtemp',
  };

  static const Map<String, int> nameToId = {
    's0': 0,
    's1': 1,
    's2': 2,
    's3': 3,
    's4': 4,
    's5': 5,
    's6': 6,
    's7': 7,
    's8': 8,
    's9': 9,
    'water': 10,
    'u0': 11,
    'u1': 12,
    'u2': 13,
    'arl': 14,
    'crl': 15,
    'srl': 16,
    'o3': 17,
    'flow': 18,
    'flowon': 18,
    'flowoff': 18,
    'prec': 19,
    'prew': 20,
    'mcutemp': 21,
    'watertemp': 22,
    'bibtemp': 23,
  };

  /// 根據 Arduino 指令名稱取得 ID
  static int? getIdFromCommand(String command) {
    // 處理 flowXXXX 指令
    if (command.startsWith('flow') && command.length > 4) {
      return 18;
    }
    return nameToId[command.toLowerCase()];
  }
}

/// 單一數據點
class DataPoint {
  final int id;
  final int value;
  final DateTime timestamp;
  final HardwareState state;

  DataPoint({
    required this.id,
    required this.value,
    required this.state,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  @override
  String toString() {
    final name = IdMapping.idToName[id] ?? 'ID$id';
    return 'DataPoint($name, value=$value, state=$state, time=$timestamp)';
  }
}

/// 數據儲存服務
class DataStorageService {
  // ==================== Arduino 數據 ====================

  /// Arduino 硬體無動作時的數據
  final Map<int, List<DataPoint>> _arduinoIdleData = {};

  /// Arduino 硬體動作時的數據
  final Map<int, List<DataPoint>> _arduinoRunningData = {};

  // ==================== STM32 數據 ====================

  /// STM32 硬體無動作時的數據
  final Map<int, List<DataPoint>> _stm32IdleData = {};

  /// STM32 硬體動作時的數據
  final Map<int, List<DataPoint>> _stm32RunningData = {};

  // ==================== 共用硬體狀態（由 STM32 0x01/0x02 指令控制） ====================

  /// 各 ID 的硬體狀態（Arduino 和 STM32 共用）
  /// 由 STM32 的 0x01 (啟動) 和 0x02 (停止) 指令來設定
  final Map<int, HardwareState> _hardwareStates = {};

  /// 各 ID 是否正在運行中（由 0x01 啟動，0x02 停止）
  /// true = 硬體正在運行中（已下過 0x01 指令且未下 0x02）
  /// false = 硬體未運行（未下過 0x01 或已下 0x02 停止）
  final Map<int, bool> _isRunning = {};

  // ==================== 通知器 ====================

  /// 數據更新通知器
  final ValueNotifier<int> dataUpdateNotifier = ValueNotifier(0);

  /// 硬體運行狀態通知器（當任何 ID 的運行狀態改變時通知）
  final ValueNotifier<int> runningStateNotifier = ValueNotifier(0);

  // ==================== 共用硬體狀態方法 ====================

  /// 設定指定 ID 的硬體狀態（由 STM32 0x01/0x02 指令控制）
  /// Arduino 和 STM32 共用此狀態
  void setHardwareState(int id, HardwareState state) {
    _hardwareStates[id] = state;
    // 同時更新 isRunning 狀態
    _isRunning[id] = (state == HardwareState.running);
    _notifyUpdate();
    runningStateNotifier.value++;
  }

  /// 取得指定 ID 的當前硬體狀態
  HardwareState getHardwareState(int id) {
    return _hardwareStates[id] ?? HardwareState.idle;
  }

  /// 檢查指定 ID 的硬體是否正在運行中
  /// 用於判斷是否已對該 ID 下過 0x01 啟動指令
  bool isHardwareRunning(int id) {
    return _isRunning[id] ?? false;
  }

  // ==================== Arduino 方法 ====================

  /// 儲存 Arduino 數據（使用共用硬體狀態）
  void saveArduinoData(int id, int value) {
    final state = getHardwareState(id);
    final dataPoint = DataPoint(id: id, value: value, state: state);

    if (state == HardwareState.idle) {
      _arduinoIdleData.putIfAbsent(id, () => []);
      _arduinoIdleData[id]!.add(dataPoint);
    } else {
      _arduinoRunningData.putIfAbsent(id, () => []);
      _arduinoRunningData[id]!.add(dataPoint);
    }
    _notifyUpdate();
  }

  /// 根據指令名稱儲存 Arduino 數據
  void saveArduinoDataByCommand(String command, int value) {
    final id = IdMapping.getIdFromCommand(command);
    if (id != null) {
      saveArduinoData(id, value);
    }
  }

  /// 取得 Arduino 指定 ID 的無動作數據
  List<DataPoint> getArduinoIdleData(int id) {
    return List.unmodifiable(_arduinoIdleData[id] ?? []);
  }

  /// 取得 Arduino 指定 ID 的動作中數據
  List<DataPoint> getArduinoRunningData(int id) {
    return List.unmodifiable(_arduinoRunningData[id] ?? []);
  }

  /// 取得 Arduino 指定 ID 的最新無動作數據
  DataPoint? getArduinoLatestIdleData(int id) {
    final list = _arduinoIdleData[id];
    return (list != null && list.isNotEmpty) ? list.last : null;
  }

  /// 取得 Arduino 指定 ID 的最新動作中數據
  DataPoint? getArduinoLatestRunningData(int id) {
    final list = _arduinoRunningData[id];
    return (list != null && list.isNotEmpty) ? list.last : null;
  }

  // ==================== STM32 方法 ====================

  /// 儲存 STM32 數據（使用共用硬體狀態）
  void saveStm32Data(int id, int value) {
    final state = getHardwareState(id);
    final dataPoint = DataPoint(id: id, value: value, state: state);

    if (state == HardwareState.idle) {
      _stm32IdleData.putIfAbsent(id, () => []);
      _stm32IdleData[id]!.add(dataPoint);
    } else {
      _stm32RunningData.putIfAbsent(id, () => []);
      _stm32RunningData[id]!.add(dataPoint);
    }
    _notifyUpdate();
  }

  /// 取得 STM32 指定 ID 的無動作數據
  List<DataPoint> getStm32IdleData(int id) {
    return List.unmodifiable(_stm32IdleData[id] ?? []);
  }

  /// 取得 STM32 指定 ID 的動作中數據
  List<DataPoint> getStm32RunningData(int id) {
    return List.unmodifiable(_stm32RunningData[id] ?? []);
  }

  /// 取得 STM32 指定 ID 的最新無動作數據
  DataPoint? getStm32LatestIdleData(int id) {
    final list = _stm32IdleData[id];
    return (list != null && list.isNotEmpty) ? list.last : null;
  }

  /// 取得 STM32 指定 ID 的最新動作中數據
  DataPoint? getStm32LatestRunningData(int id) {
    final list = _stm32RunningData[id];
    return (list != null && list.isNotEmpty) ? list.last : null;
  }

  // ==================== 通用方法 ====================

  /// 清除所有數據
  void clearAllData() {
    _arduinoIdleData.clear();
    _arduinoRunningData.clear();
    _stm32IdleData.clear();
    _stm32RunningData.clear();
    _hardwareStates.clear();
    _isRunning.clear();
    _notifyUpdate();
    runningStateNotifier.value++;
  }

  /// 通知數據更新
  void _notifyUpdate() {
    dataUpdateNotifier.value++;
  }

  /// 釋放資源
  void dispose() {
    dataUpdateNotifier.dispose();
    runningStateNotifier.dispose();
  }
}