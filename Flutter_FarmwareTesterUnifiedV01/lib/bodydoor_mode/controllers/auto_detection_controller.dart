// ============================================================================
// 自動檢測控制器 Mixin（BodyDoor 版）
// ============================================================================
// 功能說明：
// 將自動檢測流程相關的邏輯從 main.dart 中抽取出來
// BodyDoor 版：只使用 Arduino 讀取 19 個 ADC 通道 (ID 0-18)
// 只讀取 Idle 狀態數值，無 Running/MOSFET 測試
// ============================================================================

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_firmware_tester_unified/shared/services/serial_port_manager.dart';
import 'package:flutter_firmware_tester_unified/shared/services/data_storage_service.dart';
import 'package:flutter_firmware_tester_unified/shared/services/arduino_connection_service.dart';
import 'package:flutter_firmware_tester_unified/shared/services/port_filter_service.dart';
import 'package:flutter_firmware_tester_unified/shared/services/localization_service.dart';
import 'package:flutter_firmware_tester_unified/shared/controllers/debug_history_mixin.dart';
import '../services/threshold_settings_service.dart';
import '../widgets/data_storage_page.dart' show DisplayNames;

/// 自動檢測控制器 Mixin
/// 使用類別需要實作抽象的 getter 和 setter
mixin AutoDetectionController<T extends StatefulWidget> on State<T>, DebugHistoryMixin<T> {

  // ===== 必須由使用者實作的抽象成員 =====

  // 狀態存取
  bool get isAutoDetecting;
  @override
  bool get isAutoDetectionCancelled;
  DataStorageService get dataStorage;
  SerialPortManager get arduinoManager;
  List<String> get availablePorts;
  String? get selectedArduinoPort;

  // 狀態設定
  void setAutoDetectionState(String status, double progress);
  void beginAutoDetection();
  void endAutoDetection();
  void setSelectedArduinoPort(String port);
  void setCurrentReadingState(int? id, String? section);
  void clearCurrentReadingState();

  // 操作方法
  void refreshPorts();
  void showSnackBarMessage(String message);
  void showTestResultDialog(bool passed, List<String> failedItems);

  // ==================== 常數 ====================

  /// BodyDoor 總通道數 (ID 0-18)
  static const int totalChannels = 19;

  /// BodyDoor Arduino 指令對應表 (ID 0-18)
  static const List<String> arduinoCommands = [
    'ambientrl',     // ID 0  - A0
    'coolrl',        // ID 1  - A1
    'sparklingrl',   // ID 2  - A2
    'waterpump',     // ID 3  - A3
    'o3',            // ID 4  - A4
    'mainuvc',       // ID 5  - A5
    'bibtemp',       // ID 6  - A6
    'flowmeter',     // ID 7  - A7
    'watertemp',     // ID 8  - A8
    'leak',          // ID 9  - A9
    'waterpressure', // ID 10 - A10
    'co2pressure',   // ID 11 - A11
    'spoutuvc',      // ID 12 - A12
    'mixuvc',        // ID 13 - A13
    'flowmeter2',    // ID 14 - A14
    'bp24v',         // ID 15 - A15,CH5 (BodyPower 24V)
    'bp12v',         // ID 16 - A15,CH7 (BodyPower 12V)
    'bpup',          // ID 17 - A15,CH6 (BodyPower UpScreen)
    'bplow',         // ID 18 - A15,CH4 (BodyPower LowScreen)
  ];

  // ==================== 自動檢測流程 ====================

  // 注意：調試歷史相關功能（debugHistoryPrev/Next、clearDebugHistory、
  // waitIfPaused、debugDelay）已移至 DebugHistoryMixin

  /// 更新自動檢測狀態
  void updateAutoDetectionStatus(String status, double progress) {
    if (mounted) {
      setAutoDetectionState(status, progress);
    }
  }

  // ===== 最近一次檢測結果（用於隨時查看）=====
  bool? _lastTestPassed;
  List<String> _lastFailedItems = [];

  /// 顯示當前/最近一次的檢測結果
  void showCurrentResult() {
    if (_lastTestPassed == null) {
      showSnackBarMessage(tr('no_test_result'));
      return;
    }
    showTestResultDialog(_lastTestPassed!, _lastFailedItems);
  }

  /// 保存檢測結果（供隨時查看）
  void _saveTestResult(bool passed, List<String> failedItems) {
    _lastTestPassed = passed;
    _lastFailedItems = List.from(failedItems);
  }

  // ==================== 主要流程 ====================

  /// 開始自動檢測流程
  Future<void> startAutoDetection() async {
    if (isAutoDetecting) return;

    // 清除所有數據，初始化頁面
    dataStorage.clearAllData();

    // 清除調試歷史
    clearDebugHistory();

    beginAutoDetection();

    try {
      // 步驟 1: 連接 Arduino
      updateAutoDetectionStatus(tr('auto_detection_step_connect'), 0.0);
      final connectResult = await _autoDetectionStep1Connect();
      if (!connectResult || isAutoDetectionCancelled) {
        endAutoDetection();
        return;
      }

      // 步驟 2: 讀取所有通道 (Idle 數值)
      updateAutoDetectionStatus(tr('auto_detection_step_idle'), 0.15);
      final readResult = await _autoDetectionStep2ReadAll();
      if (!readResult || isAutoDetectionCancelled) {
        endAutoDetection();
        return;
      }

      // 步驟 3: 結果判定
      updateAutoDetectionStatus(tr('auto_detection_step_result'), 0.90);
      await Future.delayed(const Duration(milliseconds: 500));
      _autoDetectionStep3ShowResult();

    } catch (e) {
      showSnackBarMessage('自動檢測錯誤: $e');
    } finally {
      endAutoDetection();
    }
  }

  /// 步驟 1: 連接 Arduino
  Future<bool> _autoDetectionStep1Connect() async {
    // 先刷新 COM 埠列表
    refreshPorts();
    await Future.delayed(const Duration(milliseconds: 300));

    // 取得可用埠口（排除 ST-Link）
    final filteredPorts = PortFilterService.getAvailablePorts(excludeStLink: true);

    if (filteredPorts.isEmpty) {
      showSnackBarMessage(tr('usb_not_connected'));
      return false;
    }

    // 如果已連接，直接返回
    if (arduinoManager.isConnected) return true;

    updateAutoDetectionStatus(tr('connecting_arduino'), 0.02);

    // 建立要嘗試的 COM 埠列表（優先嘗試已選擇的埠口）
    final portsToTry = <String>[];
    if (selectedArduinoPort != null && filteredPorts.contains(selectedArduinoPort)) {
      portsToTry.add(selectedArduinoPort!);
      portsToTry.addAll(filteredPorts.where((p) => p != selectedArduinoPort));
    } else {
      portsToTry.addAll(filteredPorts);
    }

    bool arduinoConnected = false;

    // 逐一嘗試每個 COM 埠，使用統一的連線驗證方法
    for (int i = 0; i < portsToTry.length && !arduinoConnected; i++) {
      if (isAutoDetectionCancelled) return false;

      final port = portsToTry[i];
      updateAutoDetectionStatus(
        '${tr('connecting_arduino')} ($port, ${i + 1}/${portsToTry.length})',
        0.02 + (i * 0.02)
      );

      // 使用統一的連線驗證方法
      final result = await arduinoManager.connectAndVerify(port);

      switch (result) {
        case ConnectResult.success:
          // BodyDoor Arduino 連接成功
          arduinoConnected = true;
          setSelectedArduinoPort(port);
          break;
        case ConnectResult.wrongMode:
          // 偵測到 Main Arduino，跳過
          break;
        case ConnectResult.failed:
        case ConnectResult.portError:
          // 連線失敗，嘗試下一個
          break;
      }

      // 短暫延遲再嘗試下一個
      if (!arduinoConnected && i < portsToTry.length - 1) {
        await Future.delayed(const Duration(milliseconds: 200));
      }
    }

    if (!arduinoConnected) {
      showSnackBarMessage(tr('arduino_connect_failed'));
      return false;
    }

    return true;
  }

  /// 步驟 2: 讀取所有通道 (ID 0-18, Idle 狀態)
  Future<bool> _autoDetectionStep2ReadAll() async {
    if (isAutoDetectionCancelled) return false;

    updateAutoDetectionStatus(tr('reading_hardware_data'), 0.20);
    await _batchReadAllChannels();

    // 檢查是否所有 ID 都有數據
    bool allDataReceived = true;
    for (int id = 0; id < totalChannels; id++) {
      if (dataStorage.getArduinoLatestIdleData(id) == null) {
        allDataReceived = false;
        break;
      }
    }

    return allDataReceived;
  }

  /// 步驟 3: 顯示結果
  void _autoDetectionStep3ShowResult() {
    final failedItems = <String>[];
    final thresholdService = ThresholdSettingsService();

    // 先檢查 3.3V 電源異常（ID 6, 8, 9, 10, 11 全部 < 50）
    final is33vAnomaly = DisplayNames.check33vAnomaly((id) {
      final data = dataStorage.getArduinoFirstIdleData(id);
      return data?.value;
    });
    if (is33vAnomaly) {
      failedItems.add('⚠ ${tr('power_33v_anomaly')}');
    }

    // 檢查 Body 12V 電源異常（前置：3.3V 異常 + ID 0,1,2,3,4,5,7 全部 < 50）
    final isBody12vAnomaly = DisplayNames.checkBody12vAnomaly((id) {
      final data = dataStorage.getArduinoFirstIdleData(id);
      return data?.value;
    });
    if (isBody12vAnomaly) {
      failedItems.add('⚠ ${tr('power_body12v_anomaly')}');
    }

    // 檢查 Door 24V 升壓電路異常（BP_24V < 50）
    final isDoor24vAnomaly = DisplayNames.checkDoor24vAnomaly((id) {
      final data = dataStorage.getArduinoFirstIdleData(id);
      return data?.value;
    });
    if (isDoor24vAnomaly) {
      failedItems.add('⚠ ${tr('power_door24v_anomaly')}');
    }

    // 檢查 Door 12V 電源異常（ID 12,13,14,16,17,18 全部 < 50）
    final isDoor12vAnomaly = DisplayNames.checkDoor12vAnomaly((id) {
      final data = dataStorage.getArduinoFirstIdleData(id);
      return data?.value;
    });
    if (isDoor12vAnomaly) {
      failedItems.add('⚠ ${tr('power_door12v_anomaly')}');
    }

    // 檢查所有通道 (ID 0-18) 的 Idle 數值
    for (int id = 0; id < totalChannels; id++) {
      final arduinoData = dataStorage.getArduinoFirstIdleData(id);
      final group = DisplayNames.isBody(id) ? '[Body]' : '[Door]';

      if (arduinoData != null) {
        final isValid = thresholdService.validateHardwareValue(
          DeviceType.arduino, StateType.idle, id, arduinoData.value);
        if (!isValid) {
          failedItems.add('$group ${DisplayNames.getName(id)}');
        }
      } else {
        // 沒有數據也算異常
        failedItems.add('$group ${DisplayNames.getName(id)} (${tr('no_data')})');
      }
    }

    final passed = failedItems.isEmpty;

    // 保存結果
    _saveTestResult(passed, failedItems);

    // 顯示結果對話框
    showTestResultDialog(passed, failedItems);
  }

  // ==================== 批次讀取 ====================

  /// 批次讀取所有 Arduino 通道 (ID 0-18, Idle 狀態)
  /// 使用事件驅動等待：每 50ms 檢查數據是否到達
  Future<void> _batchReadAllChannels() async {
    final thresholdService = ThresholdSettingsService();

    const int pollIntervalMs = 50;
    final int maxPollCount = (thresholdService.hardwareWaitMs / pollIntervalMs).ceil();

    // 第一輪：逐一讀取所有 ID
    for (int id = 0; id < totalChannels; id++) {
      if (isAutoDetectionCancelled) return;

      setCurrentReadingState(id, 'idle');
      dataStorage.setHardwareState(id, HardwareState.idle);

      final prevArduinoCount = dataStorage.getArduinoIdleData(id).length;

      // 發送 Arduino 指令
      if (arduinoManager.isConnected) {
        arduinoManager.sendString(arduinoCommands[id]);
      }

      // 等待數據到達
      bool arduinoDataReceived = !arduinoManager.isConnected;
      for (int poll = 0; poll < maxPollCount && !arduinoDataReceived; poll++) {
        await Future.delayed(const Duration(milliseconds: pollIntervalMs));

        if (!arduinoDataReceived) {
          final currentCount = dataStorage.getArduinoIdleData(id).length;
          arduinoDataReceived = currentCount > prevArduinoCount;
        }
      }

      // 更新進度
      final progress = 0.20 + (0.65 * (id + 1) / totalChannels);
      updateAutoDetectionStatus(
        '${tr('reading_hardware_data')} (${id + 1}/$totalChannels)',
        progress,
      );

      // 調試模式：顯示讀取結果
      if (isSlowDebugMode) {
        final data = dataStorage.getArduinoLatestIdleData(id);
        final name = DisplayNames.getName(id);
        final group = DisplayNames.isBody(id) ? 'Body' : 'Door';
        final value = data?.value ?? 'N/A';
        addDebugHistory('[$group] ID$id ($name): $value');
        await debugDelay(const Duration(seconds: 1));
      }
    }

    // 針對沒有資料的 ID 單獨重試
    final int maxRetryPerID = thresholdService.maxRetryPerID;

    for (int id = 0; id < totalChannels; id++) {
      if (isAutoDetectionCancelled) return;

      bool needRetry = arduinoManager.isConnected &&
          dataStorage.getArduinoLatestIdleData(id) == null;

      if (!needRetry) continue;

      for (int retry = 0; retry < maxRetryPerID; retry++) {
        if (isAutoDetectionCancelled) return;

        setCurrentReadingState(id, 'idle');

        final prevArduinoCount = dataStorage.getArduinoIdleData(id).length;

        arduinoManager.sendString(arduinoCommands[id]);

        bool arduinoDataReceived = false;
        for (int poll = 0; poll < maxPollCount && !arduinoDataReceived; poll++) {
          await Future.delayed(const Duration(milliseconds: pollIntervalMs));
          final currentCount = dataStorage.getArduinoIdleData(id).length;
          arduinoDataReceived = currentCount > prevArduinoCount;
        }

        needRetry = dataStorage.getArduinoLatestIdleData(id) == null;
        if (!needRetry) break;
      }
    }

    // 清除高亮
    clearCurrentReadingState();
  }

  /// 批次讀取 Arduino 感測器數據（供外部呼叫，如 DataStoragePage）
  Future<void> batchReadArduinoSensor() async {
    await _batchReadAllChannels();
  }
}
