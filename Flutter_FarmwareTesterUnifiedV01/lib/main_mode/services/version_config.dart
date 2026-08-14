// ============================================================================
// VersionConfig - 硬體版本設定（一個硬體版本一份完整判定資料）
// ============================================================================
// 用 R_Value(電阻)偵測硬體版本,選中的版本 config 決定所有判定：
// - 完整閾值(Arduino/STM32 的 Idle/Running/Sensor + 差值)
// - STM32 運轉判定模式(單段 / 兩段 + 第二段偏移)
//
// 加新硬體版本 = 在 kVersionConfigs 再加一份完整 config 即可,
// 不需改任何判定邏輯。ID2 等差異「內建在該版本的 stm32Running 表裡」,
// 不需另外的特化欄位。
// ============================================================================

import 'package:flutter_firmware_tester_unified/shared/models/threshold_range.dart';

/// 產生 ID start~end 全部相同範圍的表
Map<int, ThresholdRange> _uniform(int lo, int hi, {int start = 0, int end = 17}) {
  return {for (int id = start; id <= end; id++) id: ThresholdRange(min: lo, max: hi)};
}

/// 運轉表：整體 lo~hi,並套用「Slot_02(ID2)硬體偏高」的共用規則（整段 +id2Offset）
/// 兩個硬體版本都走這條——1.03f 與舊版都觀察到 ID2 在高/低群都偏高,
/// 只是偏移量不同（1.03f≈+20、舊版≈+45）,規則本身共用同一段。
Map<int, ThresholdRange> _runningWithId2High(int lo, int hi, int id2Offset) => {
      ..._uniform(lo, hi),
      2: ThresholdRange(min: lo + id2Offset, max: hi + id2Offset),
    };

/// 一個硬體版本的完整判定設定
class VersionConfig {
  /// 版本名稱（顯示用，例：1.03f、舊版）
  final String name;

  /// R_Value(電阻)落在此範圍 → 判定為此版本
  final ThresholdRange rValueDetectRange;

  // ===== 完整閾值（此版本專屬）=====
  final Map<int, ThresholdRange> arduinoIdle;
  final Map<int, ThresholdRange> arduinoRunning;
  final Map<int, ThresholdRange> stm32Idle;
  final Map<int, ThresholdRange> stm32Running;
  final Map<int, ThresholdRange> arduinoSensor;
  final Map<int, ThresholdRange> stm32Sensor;
  final Map<int, int> diffThreshold;

  // ===== STM32 運轉判定模式 =====
  /// 運轉是否用「兩段判定」（第一段沒過再用第一段整段減 offset 判第二段）
  final bool twoBandRunning;

  /// 兩段判定的第二段偏移量（twoBandRunning 為 true 時使用）
  final int secondGroupOffset;

  VersionConfig({
    required this.name,
    required this.rValueDetectRange,
    required this.arduinoIdle,
    required this.arduinoRunning,
    required this.stm32Idle,
    required this.stm32Running,
    required this.arduinoSensor,
    required this.stm32Sensor,
    required this.diffThreshold,
    required this.twoBandRunning,
    required this.secondGroupOffset,
  });

  /// R_Value 是否落在此版本的偵測範圍
  bool matchesRValue(int rValue) =>
      rValue >= rValueDetectRange.min && rValue <= rValueDetectRange.max;
}

// ===== 各版本共用的預設閾值（僅作初始值,各版本仍各持一份可各自調整）=====
Map<int, ThresholdRange> _arduinoIdleDefault() => _uniform(740, 830);
Map<int, ThresholdRange> _arduinoRunningDefault() => _uniform(25, 60);
Map<int, ThresholdRange> _stm32IdleDefault() => _uniform(0, 55);
Map<int, ThresholdRange> _arduinoSensorDefault() => {
      18: const ThresholdRange(min: 0, max: 10000), // Flow
      19: const ThresholdRange(min: 190, max: 260), // PressureCO2
      20: const ThresholdRange(min: 190, max: 260), // PressureWater
      21: const ThresholdRange(min: -20, max: 100), // MCUtemp(÷10)
    };
Map<int, int> _diffDefault() => {18: 3, 21: 5, 22: 5, 23: 5};

/// 1.03f（新硬體）：STM32 運轉 228~295、兩段(−67)、有電阻(140~190)、ID2 偏高 +20
/// 註：STM32 開啟內部溫感通道後整體 ADC 上抬約 25，運轉/壓力上限一併 +25；
///     為避免兩段重疊，下限取兩群中間數 228（tier1=228~295、tier2=161~228 於 228 相接）
VersionConfig _v103f() => VersionConfig(
      name: '1.03f',
      rValueDetectRange: const ThresholdRange(min: 140, max: 190),
      arduinoIdle: _arduinoIdleDefault(),
      arduinoRunning: _arduinoRunningDefault(),
      stm32Idle: _stm32IdleDefault(),
      stm32Running: _runningWithId2High(228, 295, 20), // 上限 +25、下限取中間數
      arduinoSensor: _arduinoSensorDefault(),
      stm32Sensor: {
        18: const ThresholdRange(min: 0, max: 10000), // Flow
        19: const ThresholdRange(min: 835, max: 900), // PressureCO2（上限 +25）
        20: const ThresholdRange(min: 835, max: 900), // PressureWater（上限 +25）
        21: const ThresholdRange(min: -20, max: 100), // MCUtemp
        22: const ThresholdRange(min: -20, max: 100), // WATERtemp
        23: const ThresholdRange(min: -20, max: 100), // BIBtemp
      },
      diffThreshold: _diffDefault(),
      twoBandRunning: true,
      secondGroupOffset: 67, // 兩群在 228 相接（295−67=228）
    );

/// 舊版硬體：STM32 運轉 265~315、單段、無電阻(R_Value≈0,<10)、ID2 偏高 +45
/// 註：STM32 開啟內部溫感通道後整體 ADC 上抬約 25，運轉/壓力上限一併 +25
VersionConfig _legacy() => VersionConfig(
      name: '舊版',
      rValueDetectRange: const ThresholdRange(min: 0, max: 9),
      arduinoIdle: _arduinoIdleDefault(),
      arduinoRunning: _arduinoRunningDefault(),
      stm32Idle: _stm32IdleDefault(),
      stm32Running: _runningWithId2High(265, 315, 45), // 上限 +25
      arduinoSensor: _arduinoSensorDefault(),
      stm32Sensor: {
        18: const ThresholdRange(min: 0, max: 10000),
        19: const ThresholdRange(min: 855, max: 900), // 舊版壓力（上限 +25）
        20: const ThresholdRange(min: 855, max: 900),
        21: const ThresholdRange(min: -20, max: 100),
        22: const ThresholdRange(min: -20, max: 100),
        23: const ThresholdRange(min: -20, max: 100),
      },
      diffThreshold: _diffDefault(),
      twoBandRunning: false,
      secondGroupOffset: 0,
    );

/// 內建版本清單（比對順序 = 此清單順序）。加新版本在此加一份即可。
List<VersionConfig> buildDefaultVersionConfigs() => [_v103f(), _legacy()];

/// 未偵測到板子時的預設版本名稱（用最新的 1.03f 判定）
const String kDefaultVersionName = '1.03f';
