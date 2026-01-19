// ============================================================================
// 自動檢測控制器 Mixin
// ============================================================================
// 功能說明：
// 將自動檢測流程相關的邏輯從 main.dart 中抽取出來
// 使用 mixin 模式保持與主狀態的互動能力
// ============================================================================

import 'package:flutter/material.dart';
import '../services/serial_port_manager.dart';
import '../services/data_storage_service.dart';
import '../services/ur_command_builder.dart';
import '../services/localization_service.dart';
import '../services/threshold_settings_service.dart';
import '../widgets/data_storage_page.dart' show DisplayNames;

/// 自動檢測控制器 Mixin
/// 使用類別需要實作抽象的 getter 和 setter
mixin AutoDetectionController<T extends StatefulWidget> on State<T> {

  // ===== 必須由使用者實作的抽象成員 =====

  // 狀態存取
  bool get isAutoDetecting;
  bool get isAutoDetectionCancelled;
  DataStorageService get dataStorage;
  SerialPortManager get arduinoManager;
  SerialPortManager get urManager;
  List<String> get availablePorts;
  String? get selectedArduinoPort;
  String? get selectedUrPort;

  // 狀態設定
  void setAutoDetectionState(String status, double progress);
  void beginAutoDetection();
  void endAutoDetection();
  void setSelectedArduinoPort(String port);
  void setSelectedUrPort(String port);
  void setCurrentReadingState(int? id, String? section);
  void clearCurrentReadingState();

  // 操作方法
  void refreshPorts();
  void showSnackBarMessage(String message);
  void sendUrCommand(List<int> payload);
  void sendArduinoFlowoff();
  void showTestResultDialog(
    bool passed,
    List<String> failedIdleItems,
    List<String> failedRunningItems,
    List<String> failedSensorItems,
  );

  // ==================== 自動檢測流程 ====================

  /// 更新自動檢測狀態
  void updateAutoDetectionStatus(String status, double progress) {
    if (mounted) {
      setAutoDetectionState(status, progress);
    }
  }

  /// 開始自動檢測流程
  Future<void> startAutoDetection() async {
    if (isAutoDetecting) return;

    // 清除所有數據，初始化頁面
    dataStorage.clearAllData();

    beginAutoDetection();

    try {
      // 步驟 1: 連接設備
      updateAutoDetectionStatus(tr('auto_detection_step_connect'), 0.0);
      final connectResult = await _autoDetectionStep1Connect();
      if (!connectResult || isAutoDetectionCancelled) {
        endAutoDetection();
        return;
      }

      // 步驟 2: 讀取無動作狀態 (Idle)
      updateAutoDetectionStatus(tr('auto_detection_step_idle'), 0.17);
      final idleResult = await _autoDetectionStep2ReadIdle();
      if (!idleResult || isAutoDetectionCancelled) {
        endAutoDetection();
        return;
      }

      // 步驟 3: 讀取動作中狀態 (Running)
      updateAutoDetectionStatus(tr('auto_detection_step_running'), 0.33);
      final runningResult = await _autoDetectionStep3ReadRunning();
      if (!runningResult || isAutoDetectionCancelled) {
        endAutoDetection();
        return;
      }

      // 步驟 4: 關閉 GPIO
      updateAutoDetectionStatus(tr('auto_detection_step_close'), 0.50);
      await _autoDetectionStep4CloseGpio();
      if (isAutoDetectionCancelled) {
        endAutoDetection();
        return;
      }

      // 步驟 5: 感測器測試
      updateAutoDetectionStatus(tr('auto_detection_step_sensor'), 0.67);
      final sensorResult = await _autoDetectionStep5SensorTest();
      if (!sensorResult || isAutoDetectionCancelled) {
        endAutoDetection();
        return;
      }

      // 步驟 6: 結果判定
      updateAutoDetectionStatus(tr('auto_detection_step_result'), 0.83);
      await Future.delayed(const Duration(milliseconds: 500));
      _autoDetectionStep6ShowResult();

    } catch (e) {
      showSnackBarMessage('自動檢測錯誤: $e');
    } finally {
      endAutoDetection();
    }
  }

  /// 步驟 1: 連接設備
  /// 先逐一嘗試連接 Arduino，成功後再逐一嘗試連接 STM32
  Future<bool> _autoDetectionStep1Connect() async {
    // 先刷新 COM 埠列表，確保有最新的可用埠
    refreshPorts();
    await Future.delayed(const Duration(milliseconds: 300));

    // 檢查是否有可用的 COM 埠
    if (availablePorts.isEmpty) {
      showSnackBarMessage(tr('usb_not_connected'));
      return false;
    }

    // ===== 第一階段：連接 Arduino =====
    if (!arduinoManager.isConnected) {
      updateAutoDetectionStatus(tr('connecting_arduino'), 0.02);

      // 建立要嘗試的 COM 埠列表
      // 如果已選擇的埠有效，優先嘗試；否則從第一個開始
      final portsToTry = <String>[];
      if (selectedArduinoPort != null && availablePorts.contains(selectedArduinoPort)) {
        portsToTry.add(selectedArduinoPort!);
        portsToTry.addAll(availablePorts.where((p) => p != selectedArduinoPort));
      } else {
        portsToTry.addAll(availablePorts);
      }

      bool arduinoConnected = false;

      // 逐一嘗試每個 COM 埠
      for (int i = 0; i < portsToTry.length && !arduinoConnected; i++) {
        if (isAutoDetectionCancelled) return false;

        final port = portsToTry[i];
        updateAutoDetectionStatus(
          '${tr('connecting_arduino')} ($port, ${i + 1}/${portsToTry.length})',
          0.02 + (i * 0.02)
        );

        // 嘗試開啟連接埠
        if (arduinoManager.open(port)) {
          // 等待一下讓連接穩定（Arduino 重置後需要時間初始化）
          await Future.delayed(const Duration(milliseconds: 1000));

          // 發送測試指令驗證是否為 Arduino
          arduinoManager.sendString('s0');
          await Future.delayed(const Duration(milliseconds: 1000));

          // 檢查是否收到有效回應（Arduino 會回應數值）
          final testData = dataStorage.getArduinoLatestIdleData(0) ??
                          dataStorage.getArduinoLatestRunningData(0);

          if (testData != null) {
            // 確認是 Arduino，連接成功
            arduinoManager.startHeartbeat();
            arduinoConnected = true;
            setSelectedArduinoPort(port);

            // 清除測試數據
            dataStorage.clearAllData();
          } else {
            // 不是 Arduino，關閉連接，嘗試下一個
            arduinoManager.close();
          }
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

      // Arduino 連接成功，發送 flowoff
      await Future.delayed(const Duration(milliseconds: 300));
      sendArduinoFlowoff();
    }

    // ===== 第二階段：連接 STM32 =====
    if (!urManager.isConnected) {
      updateAutoDetectionStatus(tr('connecting_stm32'), 0.08);

      // 取得剩餘可用的 COM 埠（排除 Arduino 使用的）
      final availableForStm32 = availablePorts
          .where((p) => p != arduinoManager.currentPortName)
          .toList();

      if (availableForStm32.isEmpty) {
        showSnackBarMessage(tr('usb_not_connected'));
        return false;
      }

      // 建立要嘗試的 COM 埠列表
      final portsToTry = <String>[];
      if (selectedUrPort != null && availableForStm32.contains(selectedUrPort)) {
        portsToTry.add(selectedUrPort!);
        portsToTry.addAll(availableForStm32.where((p) => p != selectedUrPort));
      } else {
        portsToTry.addAll(availableForStm32);
      }

      bool stm32Connected = false;

      // 逐一嘗試每個 COM 埠
      for (int i = 0; i < portsToTry.length && !stm32Connected; i++) {
        if (isAutoDetectionCancelled) return false;

        final port = portsToTry[i];
        updateAutoDetectionStatus(
          '${tr('connecting_stm32')} ($port, ${i + 1}/${portsToTry.length})',
          0.08 + (i * 0.02)
        );

        // 嘗試開啟連接埠
        if (urManager.open(port)) {
          // 發送韌體版本查詢來驗證是否為 STM32
          final payload = [0x05, 0x00, 0x00, 0x00, 0x00];
          final cmd = URCommandBuilder.buildCommand(payload);
          urManager.sendHex(cmd);

          // 等待驗證回應
          await Future.delayed(const Duration(milliseconds: 1500));

          if (urManager.firmwareVersionNotifier.value != null) {
            // 確認是 STM32，連接成功
            urManager.startHeartbeat();
            stm32Connected = true;
            setSelectedUrPort(port);
          } else {
            // 不是 STM32，關閉連接，嘗試下一個
            urManager.close();
          }
        }

        // 短暫延遲再嘗試下一個
        if (!stm32Connected && i < portsToTry.length - 1) {
          await Future.delayed(const Duration(milliseconds: 200));
        }
      }

      if (!stm32Connected) {
        showSnackBarMessage(tr('stm32_connect_failed'));
        return false;
      }
    }

    // 確認兩者都已連接
    return arduinoManager.isConnected && urManager.isConnected;
  }

  /// 步驟 2: 讀取無動作狀態 (Idle)
  Future<bool> _autoDetectionStep2ReadIdle() async {
    const maxRetries = 3;

    // 發送關閉全部 GPIO 指令
    final closePayload = [0x02, 0xFF, 0xFF, 0x03, 0x00];
    sendUrCommand(closePayload);
    await Future.delayed(const Duration(milliseconds: 500));

    for (int retry = 0; retry < maxRetries; retry++) {
      if (isAutoDetectionCancelled) return false;

      if (retry > 0) {
        updateAutoDetectionStatus(
          tr('retry_step').replaceAll('{current}', '$retry').replaceAll('{max}', '$maxRetries'),
          0.20
        );
        await Future.delayed(const Duration(milliseconds: 500));
      }

      // 同時讀取 Arduino 和 STM32 硬體數據 (ID 0-17)
      updateAutoDetectionStatus(tr('reading_hardware_data'), 0.20);
      await _batchReadHardwareParallel(HardwareState.idle);

      // 檢查是否所有 ID 都有數據
      bool allDataReceived = true;
      for (int id = 0; id < 18; id++) {
        if (dataStorage.getArduinoLatestIdleData(id) == null ||
            dataStorage.getStm32LatestIdleData(id) == null) {
          allDataReceived = false;
          break;
        }
      }

      if (allDataReceived) return true;
    }

    return false;
  }

  /// 步驟 3: 讀取動作中狀態 (Running)
  Future<bool> _autoDetectionStep3ReadRunning() async {
    const maxRetries = 3;

    // 發送開啟全部 GPIO 指令
    final openPayload = [0x01, 0xFF, 0xFF, 0x03, 0x00];
    sendUrCommand(openPayload);
    await Future.delayed(const Duration(milliseconds: 500));

    for (int retry = 0; retry < maxRetries; retry++) {
      if (isAutoDetectionCancelled) return false;

      if (retry > 0) {
        updateAutoDetectionStatus(
          tr('retry_step').replaceAll('{current}', '$retry').replaceAll('{max}', '$maxRetries'),
          0.40
        );
        await Future.delayed(const Duration(milliseconds: 500));
      }

      // 同時讀取 Arduino 和 STM32 硬體數據 (ID 0-17)
      updateAutoDetectionStatus(tr('reading_hardware_data'), 0.38);
      await _batchReadHardwareParallel(HardwareState.running);

      // 檢查是否所有 ID 都有數據
      bool allDataReceived = true;
      for (int id = 0; id < 18; id++) {
        if (dataStorage.getArduinoLatestRunningData(id) == null ||
            dataStorage.getStm32LatestRunningData(id) == null) {
          allDataReceived = false;
          break;
        }
      }

      if (allDataReceived) return true;
    }

    return false;
  }

  /// 步驟 4: 關閉 GPIO
  Future<void> _autoDetectionStep4CloseGpio() async {
    // 發送關閉全部 GPIO 指令
    final closePayload = [0x02, 0xFF, 0xFF, 0x03, 0x00];
    sendUrCommand(closePayload);
    await Future.delayed(const Duration(milliseconds: 500));
  }

  /// 步驟 5: 感測器測試
  Future<bool> _autoDetectionStep5SensorTest() async {
    // ===== 第一階段：先讀取溫度和壓力感測器（不含流量計）=====
    updateAutoDetectionStatus(tr('auto_detection_step_sensor'), 0.68);

    // 先讀取 Arduino 溫度和壓力 (ID 19-21)
    if (arduinoManager.isConnected) {
      for (int id = 19; id <= 21; id++) {
        if (isAutoDetectionCancelled) return false;
        // 設定感測器區域高亮
        setCurrentReadingState(id, 'sensor');
        dataStorage.setHardwareState(id, HardwareState.running);
        arduinoManager.sendString(_getArduinoSensorCommand(id));
        await Future.delayed(const Duration(milliseconds: 400));
      }
    }

    // 讀取 STM32 溫度和壓力 (ID 19-23)
    // 使用 1000ms 間隔（與資料儲存頁面一致），確保溫度感測器有足夠時間回應
    if (urManager.isConnected) {
      for (int id = 19; id <= 23; id++) {
        if (isAutoDetectionCancelled) return false;
        // 設定感測器區域高亮
        setCurrentReadingState(id, 'sensor');
        dataStorage.setHardwareState(id, HardwareState.running);
        final payload = [0x03, id, 0x00, 0x00, 0x00];
        final cmd = URCommandBuilder.buildCommand(payload);
        urManager.sendHex(cmd);
        await Future.delayed(const Duration(milliseconds: 1000));
      }
    }

    // 額外等待確保溫度數據都收到
    await Future.delayed(const Duration(milliseconds: 500));

    // ===== 第二階段：流量計測試 =====
    // 發送 flowon 啟動流量計
    updateAutoDetectionStatus(tr('starting_flow_test'), 0.75);
    // 設定流量計高亮 (ID 18)
    setCurrentReadingState(18, 'sensor');
    if (arduinoManager.isConnected) {
      arduinoManager.sendString('flowon');
    }

    // 等待流量計啟動
    await Future.delayed(const Duration(milliseconds: 500));

    // 讀取流量計數據 3 次，每次間隔 1 秒
    for (int i = 0; i < 3; i++) {
      if (isAutoDetectionCancelled) return false;

      updateAutoDetectionStatus(tr('auto_detection_step_sensor'), 0.76 + i * 0.02);

      // 保持流量計高亮
      setCurrentReadingState(18, 'sensor');

      // Arduino 流量計讀取 (ID 18)
      if (arduinoManager.isConnected) {
        dataStorage.setHardwareState(18, HardwareState.running);
        arduinoManager.sendString('flowon');  // flowon 同時讀取流量
        await Future.delayed(const Duration(milliseconds: 300));
      }

      // STM32 流量計讀取 (ID 18)
      if (urManager.isConnected) {
        dataStorage.setHardwareState(18, HardwareState.running);
        final payload = [0x03, 18, 0x00, 0x00, 0x00];
        final cmd = URCommandBuilder.buildCommand(payload);
        urManager.sendHex(cmd);
        await Future.delayed(const Duration(milliseconds: 300));
      }

      if (i < 2) {
        await Future.delayed(const Duration(milliseconds: 700));
      }
    }

    // 清除高亮
    clearCurrentReadingState();

    // 發送 flowoff 停止流量計
    updateAutoDetectionStatus(tr('stopping_flow_test'), 0.82);
    if (arduinoManager.isConnected) {
      arduinoManager.sendString('flowoff');
    }

    await Future.delayed(const Duration(milliseconds: 500));

    // 讀取最終流量計數值
    if (urManager.isConnected) {
      final readPayload = [0x03, 18, 0x00, 0x00, 0x00];
      final readCmd = URCommandBuilder.buildCommand(readPayload);
      urManager.sendHex(readCmd);
    }

    await Future.delayed(const Duration(milliseconds: 300));

    // 清除流量計
    if (urManager.isConnected) {
      final clearPayload = [0x04, 0x12, 0x00, 0x00, 0x00];
      sendUrCommand(clearPayload);
    }

    return true;
  }

  /// 取得 Arduino 感測器指令
  String _getArduinoSensorCommand(int id) {
    switch (id) {
      case 19: return 'prec';      // PressureCO2
      case 20: return 'prew';      // PressureWater
      case 21: return 'mcutemp';   // MCUtemp
      default: return '';
    }
  }

  /// 步驟 6: 顯示結果
  /// 使用 ThresholdSettingsService 進行範圍驗證
  void _autoDetectionStep6ShowResult() {
    final failedIdleItems = <String>[];      // Idle 異常項目
    final failedRunningItems = <String>[];   // Running 異常項目
    final failedSensorItems = <String>[];    // 感測器異常項目
    final thresholdService = ThresholdSettingsService();

    // 檢查硬體數據 (ID 0-17) - Idle 狀態
    for (int id = 0; id < 18; id++) {
      final arduinoData = dataStorage.getArduinoLatestIdleData(id);
      final stm32Data = dataStorage.getStm32LatestIdleData(id);

      bool hasError = false;

      // 驗證 Arduino Idle 數值
      if (arduinoData != null) {
        final isValid = thresholdService.validateHardwareValue(
          DeviceType.arduino, StateType.idle, id, arduinoData.value);
        if (!isValid) hasError = true;
      }

      // 驗證 STM32 Idle 數值
      if (stm32Data != null) {
        final isValid = thresholdService.validateHardwareValue(
          DeviceType.stm32, StateType.idle, id, stm32Data.value);
        if (!isValid) hasError = true;
      }

      // 只要有一個異常，記錄該項目
      if (hasError) {
        failedIdleItems.add(DisplayNames.getName(id));
      }
    }

    // 檢查硬體數據 (ID 0-17) - Running 狀態
    for (int id = 0; id < 18; id++) {
      final arduinoData = dataStorage.getArduinoLatestRunningData(id);
      final stm32Data = dataStorage.getStm32LatestRunningData(id);

      bool hasError = false;

      // 驗證 Arduino Running 數值
      if (arduinoData != null) {
        final isValid = thresholdService.validateHardwareValue(
          DeviceType.arduino, StateType.running, id, arduinoData.value);
        if (!isValid) hasError = true;
      }

      // 驗證 STM32 Running 數值
      if (stm32Data != null) {
        final isValid = thresholdService.validateHardwareValue(
          DeviceType.stm32, StateType.running, id, stm32Data.value);
        if (!isValid) hasError = true;
      }

      // 只要有一個異常，記錄該項目
      if (hasError) {
        failedRunningItems.add(DisplayNames.getName(id));
      }
    }

    // 檢查感測器數據 (ID 18-23)
    final checkedSensorIds = <int>{};

    // 先取得 Arduino MCUtemp (ID 21) 用於溫度比對
    int? arduinoMcuTemp;
    {
      final runningData = dataStorage.getArduinoLatestRunningData(21);
      final idleData = dataStorage.getArduinoLatestIdleData(21);
      final data = runningData ?? idleData;
      if (data != null) {
        arduinoMcuTemp = data.value ~/ 10;  // MCUtemp 需要除以 10
      }
    }

    // Arduino 感測器 (ID 18-20) - 非溫度類
    for (int id = 18; id <= 20; id++) {
      final arduinoRunningData = dataStorage.getArduinoLatestRunningData(id);
      final arduinoIdleData = dataStorage.getArduinoLatestIdleData(id);
      final arduinoData = arduinoRunningData ?? arduinoIdleData;

      final stm32RunningData = dataStorage.getStm32LatestRunningData(id);
      final stm32IdleData = dataStorage.getStm32LatestIdleData(id);
      final stm32Data = stm32RunningData ?? stm32IdleData;

      bool hasError = false;

      if (arduinoData != null) {
        final isValid = thresholdService.validateSensorValue(DeviceType.arduino, id, arduinoData.value);
        if (!isValid) hasError = true;
      }

      if (stm32Data != null) {
        final isValid = thresholdService.validateSensorValue(DeviceType.stm32, id, stm32Data.value);
        if (!isValid) hasError = true;
      }

      if (hasError && !checkedSensorIds.contains(id)) {
        checkedSensorIds.add(id);
        failedSensorItems.add(DisplayNames.getName(id));
      }
    }

    // 溫度感測器 (ID 21-23) - 需要分別檢查並顯示詳細資訊
    for (int id = 21; id <= 23; id++) {
      final stm32RunningData = dataStorage.getStm32LatestRunningData(id);
      final stm32IdleData = dataStorage.getStm32LatestIdleData(id);
      final stm32Data = stm32RunningData ?? stm32IdleData;

      bool hasError = false;
      String errorDetail = '';

      // ID 21 (MCUtemp) Arduino 也有
      if (id == 21) {
        final arduinoRunningData = dataStorage.getArduinoLatestRunningData(id);
        final arduinoIdleData = dataStorage.getArduinoLatestIdleData(id);
        final arduinoData = arduinoRunningData ?? arduinoIdleData;

        if (arduinoData != null) {
          final value = arduinoData.value ~/ 10;
          final isValid = thresholdService.validateSensorValue(DeviceType.arduino, id, value);
          if (!isValid) {
            hasError = true;
            errorDetail = 'Arduino: $value°C';
          }
        }
      }

      if (stm32Data != null) {
        final isValid = thresholdService.validateSensorValue(DeviceType.stm32, id, stm32Data.value);
        if (!isValid) {
          hasError = true;
          if (errorDetail.isNotEmpty) errorDetail += ', ';
          errorDetail += 'STM32: ${stm32Data.value}°C';
        }

        // 與 Arduino MCUtemp 溫差比對
        if (arduinoMcuTemp != null) {
          final diffThreshold = thresholdService.getDiffThreshold(id);
          final tempDiff = (arduinoMcuTemp - stm32Data.value).abs();
          if (tempDiff > diffThreshold) {
            hasError = true;
            if (errorDetail.isNotEmpty) errorDetail += ', ';
            errorDetail += '溫差$tempDiff°C';
          }
        }
      }

      if (hasError && !checkedSensorIds.contains(id)) {
        checkedSensorIds.add(id);
        final name = DisplayNames.getName(id);
        failedSensorItems.add(errorDetail.isNotEmpty ? '$name ($errorDetail)' : name);
      }
    }

    // 顯示結果對話框
    final passed = failedIdleItems.isEmpty && failedRunningItems.isEmpty && failedSensorItems.isEmpty;
    showTestResultDialog(passed, failedIdleItems, failedRunningItems, failedSensorItems);
  }

  /// 並行批次讀取 Arduino 和 STM32 硬體數據 (ID 0-17)
  Future<void> _batchReadHardwareParallel(HardwareState state) async {
    // Arduino 指令對應表
    final arduinoCommands = ['s0', 's1', 's2', 's3', 's4', 's5', 's6', 's7', 's8', 's9',
                             'water', 'u0', 'u1', 'u2', 'arl', 'crl', 'srl', 'o3'];

    // 設定當前讀取的區域類型
    final sectionName = state == HardwareState.idle ? 'idle' : 'running';

    for (int id = 0; id < 18; id++) {
      if (isAutoDetectionCancelled) return;

      // 設定當前讀取的項目 ID 和區域（用於高亮顯示）
      setCurrentReadingState(id, sectionName);

      // 設定當前硬體狀態
      dataStorage.setHardwareState(id, state);

      // 同時發送 Arduino 和 STM32 指令
      if (arduinoManager.isConnected) {
        arduinoManager.sendString(arduinoCommands[id]);
      }
      if (urManager.isConnected) {
        final payload = [0x03, id, 0x00, 0x00, 0x00];
        final cmd = URCommandBuilder.buildCommand(payload);
        urManager.sendHex(cmd);
      }

      // 等待回應
      await Future.delayed(const Duration(milliseconds: 300));
    }

    // 讀取完成後清除高亮
    clearCurrentReadingState();
  }

  /// 批次讀取 Arduino 感測器數據 (ID 18-21)
  Future<void> batchReadArduinoSensor() async {
    if (!arduinoManager.isConnected) return;

    final commands = ['flowon', 'prec', 'prew', 'mcutemp'];
    final ids = [18, 19, 20, 21];

    for (int i = 0; i < commands.length; i++) {
      if (isAutoDetectionCancelled) return;

      dataStorage.setHardwareState(ids[i], HardwareState.running);
      arduinoManager.sendString(commands[i]);
      await Future.delayed(const Duration(milliseconds: 300));
    }
  }

  /// 批次讀取 STM32 感測器數據 (ID 18-23)
  Future<void> batchReadStm32Sensor() async {
    if (!urManager.isConnected) return;

    for (int id = 18; id <= 23; id++) {
      if (isAutoDetectionCancelled) return;

      dataStorage.setHardwareState(id, HardwareState.running);

      final payload = [0x03, id, 0x00, 0x00, 0x00];
      final cmd = URCommandBuilder.buildCommand(payload);
      urManager.sendHex(cmd);
      // 增加等待時間確保 STM32 有足夠時間回應
      await Future.delayed(const Duration(milliseconds: 400));
    }
    // 額外等待確保最後一個回應也被接收
    await Future.delayed(const Duration(milliseconds: 300));
  }
}
