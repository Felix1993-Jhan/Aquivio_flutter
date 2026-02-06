// ============================================================================
// ThresholdStorageMixin - 閾值儲存 Mixin
// ============================================================================
// 功能：提供 SharedPreferences 的儲存/載入共用邏輯
// - 被 Main 和 BodyDoor 的 ThresholdSettingsService 共用
// - 包含 ThresholdRange Map、int Map、int、bool 的載入/儲存方法
// ============================================================================

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_firmware_tester_unified/shared/models/threshold_range.dart';

/// 閾值儲存 Mixin
/// 提供 SharedPreferences 的儲存/載入共用邏輯
mixin ThresholdStorageMixin {
  // ===== 必須由使用者實作的抽象成員 =====

  /// SharedPreferences 實例
  SharedPreferences? get prefs;

  /// 儲存鍵名前綴
  String get keyPrefix;

  /// 設定變更通知器
  ValueNotifier<int> get settingsUpdateNotifier;

  // ===== 共用方法 =====

  /// 載入 ThresholdRange Map
  Map<int, ThresholdRange> loadThresholdMap(
    String key,
    Map<int, ThresholdRange> defaultValue,
  ) {
    final jsonStr = prefs?.getString('$keyPrefix$key');
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
  Future<void> saveThresholdMap(
    String key,
    Map<int, ThresholdRange> value,
  ) async {
    final jsonMap = <String, dynamic>{};
    value.forEach((k, v) {
      jsonMap[k.toString()] = v.toJson();
    });
    await prefs?.setString('$keyPrefix$key', json.encode(jsonMap));
    notifyUpdate();
  }

  /// 載入 int Map
  Map<int, int> loadIntMap(String key, Map<int, int> defaultValue) {
    final jsonStr = prefs?.getString('$keyPrefix$key');
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

  /// 儲存 int Map
  Future<void> saveIntMap(String key, Map<int, int> value) async {
    final jsonMap = <String, dynamic>{};
    value.forEach((k, v) {
      jsonMap[k.toString()] = v;
    });
    await prefs?.setString('$keyPrefix$key', json.encode(jsonMap));
    notifyUpdate();
  }

  /// 載入 int 值
  int loadInt(String key, int defaultValue) {
    return prefs?.getInt('$keyPrefix$key') ?? defaultValue;
  }

  /// 儲存 int 值
  Future<void> saveInt(String key, int value) async {
    await prefs?.setInt('$keyPrefix$key', value);
    notifyUpdate();
  }

  /// 載入 bool 值
  bool loadBool(String key, bool defaultValue) {
    return prefs?.getBool('$keyPrefix$key') ?? defaultValue;
  }

  /// 儲存 bool 值
  Future<void> saveBool(String key, bool value) async {
    await prefs?.setBool('$keyPrefix$key', value);
    notifyUpdate();
  }

  /// 通知更新
  void notifyUpdate() {
    settingsUpdateNotifier.value++;
  }

  /// 清除所有以 keyPrefix 開頭的設定
  Future<void> clearAllSettings() async {
    final keys = prefs?.getKeys()
        .where((k) => k.startsWith(keyPrefix))
        .toList() ?? [];
    for (final key in keys) {
      await prefs?.remove(key);
    }
    notifyUpdate();
  }
}
