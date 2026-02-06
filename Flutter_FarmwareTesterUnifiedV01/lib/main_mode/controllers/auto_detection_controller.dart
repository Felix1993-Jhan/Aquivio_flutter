// ============================================================================
// 自動檢測控制器 Mixin
// ============================================================================
// 功能說明：
// 將自動檢測流程相關的邏輯從 main.dart 中抽取出來
// 使用 mixin 模式保持與主狀態的互動能力
// ============================================================================

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_firmware_tester_unified/shared/services/serial_port_manager.dart';
import 'package:flutter_firmware_tester_unified/shared/services/data_storage_service.dart';
import 'package:flutter_firmware_tester_unified/shared/services/arduino_connection_service.dart';
import 'package:flutter_firmware_tester_unified/shared/services/port_filter_service.dart';
import 'package:flutter_firmware_tester_unified/shared/controllers/debug_history_mixin.dart';
import '../services/ur_command_builder.dart';
import 'package:flutter_firmware_tester_unified/shared/services/localization_service.dart';
import '../services/threshold_settings_service.dart';
import '../services/adjacent_pins_service.dart';
import '../widgets/data_storage_page.dart' show DisplayNames;
import '../widgets/auto_detection_page.dart' show AdjacentIdleData, AdjacentDataType;

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
  void setCurrentReadingState(int? id, String? section, [List<int>? secondaryIds]);
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
    List<String> failedSensorItems, {
    List<String> vddShortItems = const [],
    List<String> vssShortItems = const [],
    List<String> adjacentShortItems = const [],
    List<String> loadDisconnectedItems = const [],
    List<String> gsShortItems = const [],
    List<String> gpioStuckOnItems = const [],
    List<String> gpioStuckOffItems = const [],
    List<String> wireErrorItems = const [],
    List<String> d12vShortItems = const [],
  });

  // 相鄰腳位短路測試數據傳遞
  void setAdjacentIdleData(int runningId, List<AdjacentIdleData> data);
  void clearAdjacentIdleData();

  // ==================== 自動檢測流程 ====================

  // 注意：調試歷史相關功能（debugHistoryPrev/Next、clearDebugHistory、
  // waitIfPaused、debugDelay）已移至 DebugHistoryMixin

  /// 更新自動檢測狀態
  void updateAutoDetectionStatus(String status, double progress) {
    if (mounted) {
      setAutoDetectionState(status, progress);
    }
  }

  // ===== 短路測試結果暫存 =====
  final List<String> _vddShortItems = [];
  final List<String> _vssShortItems = [];
  final List<String> _adjacentShortItems = [];

  // ===== 診斷偵測結果暫存 =====
  final List<String> _loadDisconnectedItems = [];  // 負載未連接項目
  final List<String> _gsShortItems = [];           // G-S 短路項目
  final List<String> _gpioStuckOnItems = [];       // GPIO 卡在 ON 項目
  final List<String> _gpioStuckOffItems = [];      // GPIO 卡在 OFF 項目
  final List<String> _wireErrorItems = [];         // 線材錯誤項目
  final List<String> _d12vShortItems = [];         // D極與12V短路項目

  // ===== 最近一次檢測結果（用於隨時查看）=====
  bool? _lastTestPassed;
  List<String> _lastFailedIdleItems = [];
  List<String> _lastFailedRunningItems = [];
  List<String> _lastFailedSensorItems = [];
  List<String> _lastVddShortItems = [];
  List<String> _lastVssShortItems = [];
  List<String> _lastAdjacentShortItems = [];
  List<String> _lastLoadDisconnectedItems = [];
  List<String> _lastGsShortItems = [];
  List<String> _lastGpioStuckOnItems = [];
  List<String> _lastGpioStuckOffItems = [];
  List<String> _lastWireErrorItems = [];
  List<String> _lastD12vShortItems = [];

  /// 顯示當前/最近一次的檢測結果
  void showCurrentResult() {
    if (_lastTestPassed == null) {
      showSnackBarMessage(tr('no_test_result'));
      return;
    }

    showTestResultDialog(
      _lastTestPassed!,
      _lastFailedIdleItems,
      _lastFailedRunningItems,
      _lastFailedSensorItems,
      vddShortItems: _lastVddShortItems,
      vssShortItems: _lastVssShortItems,
      adjacentShortItems: _lastAdjacentShortItems,
      loadDisconnectedItems: _lastLoadDisconnectedItems,
      gsShortItems: _lastGsShortItems,
      gpioStuckOnItems: _lastGpioStuckOnItems,
      gpioStuckOffItems: _lastGpioStuckOffItems,
      wireErrorItems: _lastWireErrorItems,
      d12vShortItems: _lastD12vShortItems,
    );
  }

  /// 保存檢測結果（供隨時查看）
  void _saveTestResult(
    bool passed,
    List<String> failedIdleItems,
    List<String> failedRunningItems,
    List<String> failedSensorItems,
    List<String> vddShortItems,
    List<String> vssShortItems,
    List<String> adjacentShortItems,
    List<String> loadDisconnectedItems,
    List<String> gsShortItems,
    List<String> gpioStuckOnItems,
    List<String> gpioStuckOffItems,
    List<String> wireErrorItems,
    List<String> d12vShortItems,
  ) {
    _lastTestPassed = passed;
    _lastFailedIdleItems = List.from(failedIdleItems);
    _lastFailedRunningItems = List.from(failedRunningItems);
    _lastFailedSensorItems = List.from(failedSensorItems);
    _lastVddShortItems = List.from(vddShortItems);
    _lastVssShortItems = List.from(vssShortItems);
    _lastAdjacentShortItems = List.from(adjacentShortItems);
    _lastLoadDisconnectedItems = List.from(loadDisconnectedItems);
    _lastGsShortItems = List.from(gsShortItems);
    _lastGpioStuckOnItems = List.from(gpioStuckOnItems);
    _lastGpioStuckOffItems = List.from(gpioStuckOffItems);
    _lastWireErrorItems = List.from(wireErrorItems);
    _lastD12vShortItems = List.from(d12vShortItems);
  }

  // ===== GPIO 命令等待機制 =====
  Completer<void>? _gpioCommandCompleter;
  int? _expectedGpioCommand;
  int? _expectedGpioBitMask;

  /// 處理 STM32 GPIO 命令確認回應
  /// 當收到與預期相符的 GPIO 命令回應時，完成等待
  void handleGpioCommandConfirmed(int command, int bitMask) {
    if (_gpioCommandCompleter != null &&
        !_gpioCommandCompleter!.isCompleted &&
        _expectedGpioCommand == command &&
        _expectedGpioBitMask == bitMask) {
      _gpioCommandCompleter!.complete();
    }
  }

  /// 發送 GPIO 命令並等待 STM32 確認回應
  /// [payload] GPIO 命令 payload（不含 header 和 checksum）
  /// [retryIntervalMs] 單次等待超時時間（毫秒），預設 100ms，超時後會重試
  /// [maxRetries] 最大重試次數，預設 5 次
  /// 返回 true 表示收到確認，false 表示所有重試都超時
  Future<bool> sendGpioCommandAndWait(List<int> payload, {
    int retryIntervalMs = 100,
    int maxRetries = 5,
  }) async {
    if (!urManager.isConnected || payload.isEmpty) return false;

    final command = payload[0];
    if (command != 0x01 && command != 0x02) {
      // 不是 GPIO 控制命令，直接發送
      sendUrCommand(payload);
      return true;
    }

    // 計算預期的 bitMask
    final lowByte = payload.length > 1 ? payload[1] : 0;
    final midByte = payload.length > 2 ? payload[2] : 0;
    final highByte = payload.length > 3 ? payload[3] : 0;
    final expectedBitMask = lowByte | (midByte << 8) | (highByte << 16);

    // 設定預期回應
    _expectedGpioCommand = command;
    _expectedGpioBitMask = expectedBitMask;

    try {
      // 重試迴圈：每次等待 retryIntervalMs，超時則重新發送命令
      for (int retry = 0; retry <= maxRetries; retry++) {
        _gpioCommandCompleter = Completer<void>();

        // 發送命令（首次發送或重試）
        sendUrCommand(payload);

        // 等待確認或超時
        try {
          await _gpioCommandCompleter!.future.timeout(
            Duration(milliseconds: retryIntervalMs),
          );
          // 收到確認，返回成功
          return true;
        } on TimeoutException {
          // 超時，繼續重試
          if (retry < maxRetries) {
            // 還有重試機會，繼續迴圈
            continue;
          }
        }
      }

      // 所有重試都超時
      return false;
    } finally {
      _gpioCommandCompleter = null;
      _expectedGpioCommand = null;
      _expectedGpioBitMask = null;
    }
  }

  /// 開始自動檢測流程
  Future<void> startAutoDetection() async {
    if (isAutoDetecting) return;

    // 清除所有數據，初始化頁面
    dataStorage.clearAllData();

    // 清除短路測試結果
    _vddShortItems.clear();
    _vssShortItems.clear();
    _adjacentShortItems.clear();

    // 清除診斷偵測結果
    _loadDisconnectedItems.clear();
    _gsShortItems.clear();
    _gpioStuckOnItems.clear();
    _gpioStuckOffItems.clear();
    _wireErrorItems.clear();
    _d12vShortItems.clear();

    // 清除相鄰腳位數據（新模式在 Running 區域顯示）
    clearAdjacentIdleData();

    // 清除調試歷史
    clearDebugHistory();

    beginAutoDetection();

    try {
      // 步驟 1: 連接設備
      updateAutoDetectionStatus(tr('auto_detection_step_connect'), 0.0);
      final connectResult = await _autoDetectionStep1Connect();
      if (!connectResult || isAutoDetectionCancelled) {
        endAutoDetection();
        return;
      }

      // 步驟 2: 讀取無動作狀態 (Idle) - 作為短路測試基準值
      updateAutoDetectionStatus(tr('auto_detection_step_idle'), 0.15);
      final idleResult = await _autoDetectionStep2ReadIdle();
      if (!idleResult || isAutoDetectionCancelled) {
        endAutoDetection();
        return;
      }

      // 步驟 3: 相鄰腳位短路測試（同時讀取 Running 狀態）
      updateAutoDetectionStatus(tr('auto_detection_step_adjacent'), 0.30);
      await _autoDetectionStep3AdjacentShortTest();
      if (isAutoDetectionCancelled) {
        endAutoDetection();
        return;
      }

      // 步驟 4: 關閉 GPIO
      updateAutoDetectionStatus(tr('auto_detection_step_close'), 0.60);
      await _autoDetectionStep4CloseGpio();
      if (isAutoDetectionCancelled) {
        endAutoDetection();
        return;
      }

      // 步驟 5: 感測器測試
      updateAutoDetectionStatus(tr('auto_detection_step_sensor'), 0.65);
      final sensorResult = await _autoDetectionStep5SensorTest();
      if (!sensorResult || isAutoDetectionCancelled) {
        endAutoDetection();
        return;
      }

      // 步驟 6: 結果判定
      updateAutoDetectionStatus(tr('auto_detection_step_result'), 0.90);
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
  /// 會自動排除 ST-Link VCP 埠口
  Future<bool> _autoDetectionStep1Connect() async {
    // 先刷新 COM 埠列表，確保有最新的可用埠
    refreshPorts();
    await Future.delayed(const Duration(milliseconds: 300));

    // 取得可用的 COM 埠（排除 ST-Link VCP）
    final filteredPorts = PortFilterService.getAvailablePorts(excludeStLink: true);

    // 檢查是否有可用的 COM 埠
    if (filteredPorts.isEmpty) {
      showSnackBarMessage(tr('usb_not_connected'));
      return false;
    }

    // ===== 第一階段：連接 Arduino =====
    if (!arduinoManager.isConnected) {
      updateAutoDetectionStatus(tr('connecting_arduino'), 0.02);

      // 建立要嘗試的 COM 埠列表
      // 如果已選擇的埠有效，優先嘗試；否則從第一個開始
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
            // Main Arduino 連接成功
            arduinoConnected = true;
            setSelectedArduinoPort(port);
            dataStorage.clearAllData();
            break;
          case ConnectResult.wrongMode:
            // 偵測到 BodyDoor Arduino，跳過
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

      // Arduino 連接成功，發送 flowoff
      await Future.delayed(const Duration(milliseconds: 300));
      sendArduinoFlowoff();
    }

    // ===== 第二階段：連接 STM32 =====
    if (!urManager.isConnected) {
      updateAutoDetectionStatus(tr('connecting_stm32'), 0.08);

      // 取得剩餘可用的 COM 埠（排除 Arduino 使用的和 ST-Link）
      final availableForStm32 = PortFilterService.getFilteredPorts(
        excludePorts: [arduinoManager.currentPortName ?? ''],
        excludeStLink: true,
      );

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

      // 逐一嘗試每個 COM 埠，使用統一的連線驗證方法
      for (int i = 0; i < portsToTry.length && !stm32Connected; i++) {
        if (isAutoDetectionCancelled) return false;

        final port = portsToTry[i];
        updateAutoDetectionStatus(
          '${tr('connecting_stm32')} ($port, ${i + 1}/${portsToTry.length})',
          0.08 + (i * 0.02)
        );

        // 使用統一的連線驗證方法
        final result = await urManager.connectAndVerifyStm32(port);

        if (result == Stm32ConnectResult.success) {
          stm32Connected = true;
          setSelectedUrPort(port);
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
  /// 已改為在 _batchReadHardwareParallel 中針對單獨 ID 重試，不再全部重新輪詢
  Future<bool> _autoDetectionStep2ReadIdle() async {
    // 發送關閉全部 GPIO 指令（等待 STM32 確認回應）
    final closePayload = [0x02, 0xFF, 0xFF, 0x03, 0x00];
    await sendGpioCommandAndWait(closePayload);

    if (isAutoDetectionCancelled) return false;

    // 讀取 Arduino 和 STM32 硬體數據 (ID 0-17)
    // 內部會針對沒有資料的 ID 單獨重試，每個 ID 最多 5 次
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

    return allDataReceived;
  }

  /// 步驟 4: 關閉 GPIO
  Future<void> _autoDetectionStep4CloseGpio() async {
    // 發送關閉全部 GPIO 指令（等待 STM32 確認回應）
    final closePayload = [0x02, 0xFF, 0xFF, 0x03, 0x00];
    await sendGpioCommandAndWait(closePayload);
  }

  /// 步驟 3: 硬體動作中測試 + 相鄰腳位短路測試
  /// 逐一測試所有 18 個硬體腳位的 Running 狀態，同時檢測相鄰腳位是否有短路
  Future<void> _autoDetectionStep3AdjacentShortTest() async {
    final adjacentService = AdjacentPinsService();
    final thresholdService = ThresholdSettingsService();
    // 同步相鄰短路閾值
    adjacentService.shortCircuitThreshold = thresholdService.adjacentShortThreshold;

    // 確保所有 GPIO 都關閉（等待 STM32 確認回應）
    final closeAllPayload = [0x02, 0xFF, 0xFF, 0x03, 0x00];
    await sendGpioCommandAndWait(closeAllPayload);

    // 取得 Idle 狀態的基準值（用於比對相鄰腳位短路）
    // 注意：使用第一筆 Idle 數據（原始基準值），避免被後續測試數據污染
    final Map<int, int> stm32IdleValues = {};
    final Map<int, int> arduinoIdleValues = {};
    for (int id = 0; id < 18; id++) {
      final stm32Data = dataStorage.getStm32FirstIdleData(id);
      final arduinoData = dataStorage.getArduinoFirstIdleData(id);
      if (stm32Data != null) {
        stm32IdleValues[id] = stm32Data.value;
      }
      if (arduinoData != null) {
        arduinoIdleValues[id] = arduinoData.value;
      }
    }

    // Arduino 指令對應表
    final arduinoCommands = ['s0', 's1', 's2', 's3', 's4', 's5', 's6', 's7', 's8', 's9',
                             'water', 'u0', 'u1', 'u2', 'arl', 'crl', 'srl', 'o3'];

    // 記錄已測試過短路的配對（避免重複）- 只有在優化模式下使用
    final testedShortPairs = <String>{};
    final useOptimization = thresholdService.adjacentShortTestOptimization;

    // 逐一測試所有 18 個硬體腳位
    for (int testId = 0; testId < 18; testId++) {
      if (isAutoDetectionCancelled) return;

      // 取得此腳位的相鄰 GPIO ID 列表
      final adjacentIds = AdjacentPinsService.getAdjacentGpioIds(testId);

      // 更新進度顯示
      final progress = 0.30 + (0.28 * (testId + 1) / 18);
      updateAutoDetectionStatus(
        '${tr('auto_detection_step_adjacent')} (${testId + 1}/18)',
        progress,
      );

      // 設定當前測試項目高亮
      // 主要高亮：測試腳位在 Running 區域
      // 次要高亮：所有相鄰腳位在 Idle 區域（捲動以 ID 最小的優先）
      setCurrentReadingState(testId, 'running', adjacentIds.isNotEmpty ? adjacentIds : null);

      // ===== 第一步：透過 STM32 開啟測試腳位的 GPIO =====
      final openBitValue = 1 << testId;
      final openLowByte = openBitValue & 0xFF;
      final openMidByte = (openBitValue >> 8) & 0xFF;
      final openHighByte = (openBitValue >> 16) & 0xFF;
      final openPayload = [0x01, openLowByte, openMidByte, openHighByte, 0x00];

      // 發送命令並等待 STM32 確認回應（取代固定延遲）
      await sendGpioCommandAndWait(openPayload);

      // ===== 第二步：GPIO 開啟後，讀取測試腳位的 Running 狀態 =====
      dataStorage.setHardwareState(testId, HardwareState.running);

      // 記錄讀取前的數據數量（用於確認新數據到達）
      final prevArduinoRunningCount = dataStorage.getArduinoRunningData(testId).length;
      final prevStm32RunningCount = dataStorage.getStm32RunningData(testId).length;

      // 同時發送 Arduino 和 STM32 讀取指令
      if (arduinoManager.isConnected) {
        arduinoManager.sendString(arduinoCommands[testId]);
      }
      if (urManager.isConnected) {
        final readTestPayload = [0x03, testId, 0x00, 0x00, 0x00];
        final readTestCmd = URCommandBuilder.buildCommand(readTestPayload);
        urManager.sendHex(readTestCmd);
      }

      // 等待 Arduino 和 STM32 數據確實到達（最多等待 500ms）
      bool arduinoDataReceived = !arduinoManager.isConnected;
      bool stm32DataReceived = !urManager.isConnected;
      for (int wait = 0; wait < 10 && (!arduinoDataReceived || !stm32DataReceived); wait++) {
        await Future.delayed(const Duration(milliseconds: 50));

        if (!arduinoDataReceived) {
          arduinoDataReceived = dataStorage.getArduinoRunningData(testId).length > prevArduinoRunningCount;
        }
        if (!stm32DataReceived) {
          stm32DataReceived = dataStorage.getStm32RunningData(testId).length > prevStm32RunningCount;
        }
      }

      // ===== 相鄰腳位短路測試（如果有相鄰腳位）=====
      // 收集本次 Running ID 的所有相鄰測試結果（用於調試模式一次性顯示）
      final List<Map<String, dynamic>> adjacentTestResults = [];
      // 收集相鄰腳位數據（用於新模式在 Running 區域顯示）
      final List<AdjacentIdleData> adjacentIdleDataList = [];
      // 檢查是否使用新模式（在 Running 區域顯示相鄰腳位數據）
      final useNewDisplayMode = thresholdService.adjacentShortDisplayInRunning;

      // ===== 判斷測試腳位的狀態 =====
      // 1. 負載未連接：Arduino 數據不可靠，相鄰短路測試只使用 STM32 數據
      // 2. Arduino 沒有正常動作：可能是線材錯誤，跳過 Arduino 的相鄰短路判斷
      bool testIdLoadDisconnected = false;
      bool testIdArduinoNotWorking = false;  // Arduino 端沒有正常動作（可能線材錯誤）
      {
        // 閾值定義（從 ThresholdSettingsService 讀取）
        final int loadDisconnectedStm32RunningMin = thresholdService.loadDisconnectedStm32RunningMin;
        final int loadDisconnectedStm32RunningMax = thresholdService.loadDisconnectedStm32RunningMax;
        const int arduinoDiffThreshold = 100; // 相鄰短路檢測使用固定值

        // 取得測試腳位的 Idle 和 Running 數據
        // 注意：使用第一筆 Idle 數據（原始基準值），避免被相鄰短路測試的讀取數據污染
        final testArduinoIdleData = dataStorage.getArduinoFirstIdleData(testId);
        final testArduinoRunningData = dataStorage.getArduinoLatestRunningData(testId);
        final testStm32RunningData = dataStorage.getStm32LatestRunningData(testId);

        // 計算 Arduino Diff（如果數據存在）
        int? testArduinoDiff;
        if (testArduinoIdleData != null && testArduinoRunningData != null) {
          testArduinoDiff = (testArduinoIdleData.value - testArduinoRunningData.value).abs();
        }

        // 判斷 STM32 Running 是否在正常範圍（如果數據存在）
        bool? stm32RunningValid;
        if (testStm32RunningData != null) {
          stm32RunningValid = thresholdService.validateHardwareValue(
            DeviceType.stm32, StateType.running, testId, testStm32RunningData.value);
        }

        // 判斷是否為負載未連接：STM32 Running 在 40~70
        // 負載未接時 Arduino 數值會浮動，不可靠
        // 注意：這裡只檢查 STM32 Running，不檢查 STM32 Idle（避免因 Idle 數據問題而漏判）
        if (testStm32RunningData != null) {
          final testStm32Running = testStm32RunningData.value;
          if (testStm32Running >= loadDisconnectedStm32RunningMin &&
              testStm32Running <= loadDisconnectedStm32RunningMax) {
            testIdLoadDisconnected = true;
          }
        }

        // 判斷 Arduino 是否不可靠（需跳過 Arduino 相鄰短路判斷）：
        // 條件 1：負載未連接（STM32 Running 在 40~70），Arduino 數據浮動不可靠
        // 條件 2：線材錯誤（Arduino Diff < 100，但 STM32 Running 正常）
        if (testIdLoadDisconnected) {
          // 負載未連接，Arduino 數據不可靠
          testIdArduinoNotWorking = true;
        } else if (testArduinoDiff != null && stm32RunningValid == true) {
          // 線材錯誤：Arduino 沒變化，但 STM32 Running 正常
          if (testArduinoDiff < arduinoDiffThreshold) {
            testIdArduinoNotWorking = true;
          }
        }
      }

      for (final adjacentId in adjacentIds) {
        // 建立配對 key（小的在前，確保唯一性）
        final smallId = testId < adjacentId ? testId : adjacentId;
        final largeId = testId < adjacentId ? adjacentId : testId;
        final pairKey = '$smallId-$largeId';

        // 如果啟用優化模式，且這個配對已經測試過，則跳過
        if (useOptimization && testedShortPairs.contains(pairKey)) continue;
        testedShortPairs.add(pairKey);

        // 只在傳統模式下設定相鄰腳位狀態為 idle（避免影響左邊 Idle 區域的顯示）
        if (!useNewDisplayMode) {
          dataStorage.setHardwareState(adjacentId, HardwareState.idle);
        }

        // 發送讀取相鄰腳位指令（含重試機制）
        int? newStm32Value;
        int? newArduinoValue;
        const int maxSendRetries = 5; // 最多重新發送 5 次指令

        for (int sendRetry = 0; sendRetry < maxSendRetries; sendRetry++) {
          // 記錄本次發送前的數據數量（每次重試都重新記錄）
          final currentPrevAdjStm32Count = dataStorage.getStm32IdleData(adjacentId).length;
          final currentPrevAdjArduinoCount = dataStorage.getArduinoIdleData(adjacentId).length;

          // 發送讀取指令（只對尚未收到數據的設備發送）
          if (arduinoManager.isConnected && newArduinoValue == null) {
            arduinoManager.sendString(arduinoCommands[adjacentId]);
          }
          if (urManager.isConnected && newStm32Value == null) {
            final readAdjPayload = [0x03, adjacentId, 0x00, 0x00, 0x00];
            final readAdjCmd = URCommandBuilder.buildCommand(readAdjPayload);
            urManager.sendHex(readAdjCmd);
          }

          // 等待新數據到達（最多等待 800ms = 8 × 100ms）
          for (int waitRetry = 0; waitRetry < 8; waitRetry++) {
            await Future.delayed(const Duration(milliseconds: 100));

            if (newStm32Value == null) {
              final currentStm32Data = dataStorage.getStm32IdleData(adjacentId);
              if (currentStm32Data.length > currentPrevAdjStm32Count) {
                newStm32Value = currentStm32Data.last.value;
              }
            }

            if (newArduinoValue == null) {
              final currentArduinoData = dataStorage.getArduinoIdleData(adjacentId);
              if (currentArduinoData.length > currentPrevAdjArduinoCount) {
                newArduinoValue = currentArduinoData.last.value;
              }
            }

            if (newStm32Value != null && newArduinoValue != null) break;
          }

          // 如果兩邊數據都已讀取到，跳出重試迴圈
          if (newStm32Value != null && newArduinoValue != null) break;

          // 如果還有未讀取到的數據且還有重試次數，等待一小段時間後重試
          if (sendRetry < maxSendRetries - 1) {
            await Future.delayed(const Duration(milliseconds: 100));
          }
        }

        // 取得基準值並檢查短路
        final stm32BaseValue = stm32IdleValues[adjacentId];
        final arduinoBaseValue = arduinoIdleValues[adjacentId];

        // 取得腳位名稱（主要驅動的 testId 在前，被影響的 adjacentId 在後）
        final testPinInfoForResult = AdjacentPinsService.getPinInfo(testId);
        final adjPinInfoForResult = AdjacentPinsService.getPinInfo(adjacentId);
        final testNameForResult = testPinInfoForResult?.pinName ?? 'ID$testId';
        final adjNameForResult = adjPinInfoForResult?.pinName ?? 'ID$adjacentId';
        final threshold = adjacentService.shortCircuitThreshold;

        // 檢查 STM32 是否超出閾值（短路）
        bool stm32Short = false;
        if (newStm32Value != null && stm32BaseValue != null) {
          stm32Short = !adjacentService.isWithinThreshold(newStm32Value, stm32BaseValue);
          if (stm32Short) {
            _adjacentShortItems.add('STM32: $testNameForResult-$adjNameForResult (ID$testId-ID$adjacentId)');
          }
        }

        // 檢查 Arduino 是否超出閾值（短路）
        // 跳過條件：
        // 1. 測試腳位為負載未連接狀態（Arduino 數據不可靠）
        // 2. 測試腳位的 Arduino 沒有正常動作（線材錯誤，會導致相鄰腳位誤判）
        bool arduinoShort = false;
        if (!testIdLoadDisconnected && !testIdArduinoNotWorking &&
            newArduinoValue != null && arduinoBaseValue != null) {
          arduinoShort = !adjacentService.isWithinThreshold(newArduinoValue, arduinoBaseValue);
          if (arduinoShort) {
            _adjacentShortItems.add('Arduino: $testNameForResult-$adjNameForResult (ID$testId-ID$adjacentId)');
          }
        }

        // 收集測試結果（用於調試模式）
        if (isSlowDebugMode) {
          adjacentTestResults.add({
            'smallId': smallId,
            'largeId': largeId,
            'adjacentId': adjacentId,
            'stm32BaseValue': stm32BaseValue,
            'stm32NewValue': newStm32Value,
            'stm32Short': stm32Short,
            'arduinoBaseValue': arduinoBaseValue,
            'arduinoNewValue': newArduinoValue,
            'arduinoShort': arduinoShort,
            'threshold': threshold,
          });
        }

        // 收集相鄰腳位數據（用於新模式在 Running 區域顯示）
        // 使用 DisplayNames 取得 ID 對應的名稱（如 Slot6、Slot7）而非 STM32 腳位名稱（如 PE9）
        final adjDisplayName = DisplayNames.getName(adjacentId);
        adjacentIdleDataList.add(AdjacentIdleData(
          adjacentId: adjacentId,
          pinName: adjDisplayName,
          arduinoValue: newArduinoValue,
          stm32Value: newStm32Value,
          isShort: stm32Short || arduinoShort,
          dataType: AdjacentDataType.gpio,
        ));
      }

      // ===== 收集特殊類型的相鄰腳位資訊（Vdd、Vss、none）=====
      // 用於在 UI 中顯示完整的相鄰腳位資訊
      final testPinInfo = AdjacentPinsService.getPinInfo(testId);
      if (testPinInfo != null) {
        // 檢查 adjacent1 是否為特殊類型（如果不是 GPIO 且 adjacentIdleDataList 為空）
        if (!testPinInfo.adjacent1.isGpio && adjacentIdleDataList.isEmpty) {
          AdjacentDataType type;
          String typeName;
          if (testPinInfo.adjacent1.isVdd) {
            type = AdjacentDataType.vdd;
            typeName = 'Vdd';
          } else if (testPinInfo.adjacent1.isVss) {
            type = AdjacentDataType.vss;
            typeName = 'Vss';
          } else {
            type = AdjacentDataType.none;
            typeName = 'none';
          }
          adjacentIdleDataList.add(AdjacentIdleData(
            adjacentId: -1,
            pinName: testPinInfo.adjacent1.pinName.isNotEmpty ? testPinInfo.adjacent1.pinName : typeName,
            dataType: type,
          ));
        }

        // 檢查 adjacent2 是否為特殊類型
        if (!testPinInfo.adjacent2.isGpio) {
          AdjacentDataType type;
          String typeName;
          if (testPinInfo.adjacent2.isVdd) {
            type = AdjacentDataType.vdd;
            typeName = 'Vdd';
          } else if (testPinInfo.adjacent2.isVss) {
            type = AdjacentDataType.vss;
            typeName = 'Vss';
          } else {
            type = AdjacentDataType.none;
            typeName = 'none';
          }
          // 只有當 adjacentIdleDataList 少於 2 筆時才加入
          if (adjacentIdleDataList.length < 2) {
            adjacentIdleDataList.add(AdjacentIdleData(
              adjacentId: -1,
              pinName: testPinInfo.adjacent2.pinName.isNotEmpty ? testPinInfo.adjacent2.pinName : typeName,
              dataType: type,
            ));
          }
        }
      }

      // 慢速調試模式：一次性顯示本 Running ID 的所有相鄰測試結果
      if (isSlowDebugMode && adjacentTestResults.isNotEmpty) {
        final testPinInfo = AdjacentPinsService.getPinInfo(testId);
        final testPinName = testPinInfo?.pinName ?? 'ID$testId';

        // 收集所有相鄰 ID 的名稱列表
        final adjacentIdNames = adjacentTestResults.map((r) {
          final adjId = r['adjacentId'] as int;
          final adjPinInfo = AdjacentPinsService.getPinInfo(adjId);
          return '${adjPinInfo?.pinName ?? "ID$adjId"}($adjId)';
        }).toList();

        final naText = tr('debug_na');
        final shortText = tr('debug_status_short');
        final normalText = tr('debug_status_normal');

        final buffer = StringBuffer();
        buffer.writeln('════════════════════════════════════');
        buffer.writeln(trParams('debug_running_title', {'pinName': testPinName, 'id': testId}));
        buffer.writeln(trParams('debug_adjacent_ids', {'ids': adjacentIdNames.join(", ")}));
        buffer.writeln('════════════════════════════════════');

        for (int i = 0; i < adjacentTestResults.length; i++) {
          final result = adjacentTestResults[i];
          final adjacentId = result['adjacentId'] as int;
          final smallId = result['smallId'] as int;
          final largeId = result['largeId'] as int;

          // 相鄰腳位資訊
          final adjPinInfo = AdjacentPinsService.getPinInfo(adjacentId);
          final adjPinName = adjPinInfo?.pinName ?? 'ID$adjacentId';

          // 配對名稱（小的在左）
          final smallPinInfo = AdjacentPinsService.getPinInfo(smallId);
          final largePinInfo = AdjacentPinsService.getPinInfo(largeId);
          final smallName = smallPinInfo?.pinName ?? 'ID$smallId';
          final largeName = largePinInfo?.pinName ?? 'ID$largeId';

          final stm32BaseValue = result['stm32BaseValue'];
          final stm32NewValue = result['stm32NewValue'];
          final stm32Short = result['stm32Short'] as bool;
          final arduinoBaseValue = result['arduinoBaseValue'];
          final arduinoNewValue = result['arduinoNewValue'];
          final arduinoShort = result['arduinoShort'] as bool;
          final threshold = result['threshold'];

          final stm32Diff = (stm32NewValue != null && stm32BaseValue != null)
              ? (stm32NewValue - stm32BaseValue).abs()
              : 0;
          final arduinoDiff = (arduinoNewValue != null && arduinoBaseValue != null)
              ? (arduinoNewValue - arduinoBaseValue).abs()
              : 0;

          buffer.writeln(trParams('debug_test_adjacent', {'index': i + 1, 'pinName': adjPinName, 'id': adjacentId}));
          buffer.writeln('    ${trParams('debug_pair', {'smallName': smallName, 'largeName': largeName})}');
          buffer.writeln('    ${trParams('debug_stm32_result', {'base': stm32BaseValue?.toString() ?? naText, 'newVal': stm32NewValue?.toString() ?? naText, 'diff': stm32Diff, 'status': stm32Short ? shortText : normalText})}');
          buffer.writeln('    ${trParams('debug_arduino_result', {'base': arduinoBaseValue?.toString() ?? naText, 'newVal': arduinoNewValue?.toString() ?? naText, 'diff': arduinoDiff, 'status': arduinoShort ? shortText : normalText})}');
          buffer.writeln('    ${trParams('debug_threshold', {'value': threshold})}');
          if (i < adjacentTestResults.length - 1) {
            buffer.writeln('────────────────────────────────────');
          }
        }

        addDebugHistory(buffer.toString());
      }

      // 傳遞相鄰腳位數據到 UI（新模式在 Running 區域顯示）
      // 注意：必須在延遲等待之前更新 UI，讓用戶能看到完整數據
      if (adjacentIdleDataList.isNotEmpty) {
        setAdjacentIdleData(testId, adjacentIdleDataList);
      }

      // 慢速調試模式：數據顯示完成後才開始等待（支援暫停）
      if (isSlowDebugMode && adjacentTestResults.isNotEmpty) {
        await debugDelay(const Duration(seconds: 3));
      }

      // 關閉測試腳位的 GPIO（等待 STM32 確認回應）
      final closeBitValue = 1 << testId;
      final closeLowByte = closeBitValue & 0xFF;
      final closeMidByte = (closeBitValue >> 8) & 0xFF;
      final closeHighByte = (closeBitValue >> 16) & 0xFF;
      final closePayload = [0x02, closeLowByte, closeMidByte, closeHighByte, 0x00];
      await sendGpioCommandAndWait(closePayload);
    }

    // 測試完成，清除高亮
    clearCurrentReadingState();

    // 確保所有 GPIO 都關閉（等待 STM32 確認回應）
    await sendGpioCommandAndWait(closeAllPayload);
  }

  /// 步驟 5: 感測器測試
  Future<bool> _autoDetectionStep5SensorTest() async {
    final thresholdService = ThresholdSettingsService();
    final int maxRetryPerID = thresholdService.maxRetryPerID;

    // 事件驅動等待的輪詢間隔
    const int pollIntervalMs = 50;

    // 溫度感測器 (ID 21-23) 使用 DS18B20，需要較長的轉換等待時間
    const int tempSensorMinWaitMs = 1000;
    // 壓力感測器 (ID 19-20) 等待時間
    const int pressureSensorMaxWaitMs = 400;

    // ===== 第一階段：先讀取溫度和壓力感測器（不含流量計）=====
    updateAutoDetectionStatus(tr('auto_detection_step_sensor'), 0.68);

    // 先讀取 Arduino 溫度和壓力 (ID 19-21)，使用事件驅動等待
    if (arduinoManager.isConnected) {
      for (int id = 19; id <= 21; id++) {
        if (isAutoDetectionCancelled) return false;
        setCurrentReadingState(id, 'sensor');
        dataStorage.setHardwareState(id, HardwareState.running);

        final prevCount = dataStorage.getArduinoRunningData(id).length;
        arduinoManager.sendString(_getArduinoSensorCommand(id));

        // 溫度感測器需要較長等待時間
        final int maxWaitMs = id >= 21 ? tempSensorMinWaitMs : pressureSensorMaxWaitMs;
        final int maxPolls = (maxWaitMs / pollIntervalMs).ceil();

        bool dataReceived = false;
        for (int poll = 0; poll < maxPolls && !dataReceived; poll++) {
          await Future.delayed(const Duration(milliseconds: pollIntervalMs));
          dataReceived = dataStorage.getArduinoRunningData(id).length > prevCount;
        }
      }
    }

    // 讀取 STM32 溫度和壓力 (ID 19-23)，使用事件驅動等待
    // 溫度感測器 (ID 21-23) 使用 DS18B20，需要至少 1000ms 轉換時間
    if (urManager.isConnected) {
      for (int id = 19; id <= 23; id++) {
        if (isAutoDetectionCancelled) return false;
        setCurrentReadingState(id, 'sensor');
        dataStorage.setHardwareState(id, HardwareState.running);

        final prevCount = dataStorage.getStm32RunningData(id).length;
        final payload = [0x03, id, 0x00, 0x00, 0x00];
        final cmd = URCommandBuilder.buildCommand(payload);
        urManager.sendHex(cmd);

        // 溫度感測器 (ID >= 21) 必須等待足夠的轉換時間
        final int maxWaitMs = id >= 21 ? tempSensorMinWaitMs : pressureSensorMaxWaitMs;
        final int maxPolls = (maxWaitMs / pollIntervalMs).ceil();

        bool dataReceived = false;
        for (int poll = 0; poll < maxPolls && !dataReceived; poll++) {
          await Future.delayed(const Duration(milliseconds: pollIntervalMs));
          dataReceived = dataStorage.getStm32RunningData(id).length > prevCount;
        }
      }
    }

    // ===== 第一階段補充：針對沒有收到數據的感測器進行重試 =====
    // Arduino 感測器重試 (ID 19-21)
    if (arduinoManager.isConnected) {
      for (int id = 19; id <= 21; id++) {
        if (isAutoDetectionCancelled) return false;
        bool needRetry = dataStorage.getArduinoLatestRunningData(id) == null;
        if (!needRetry) continue;

        final int maxWaitMs = id >= 21 ? tempSensorMinWaitMs : pressureSensorMaxWaitMs;
        final int maxPolls = (maxWaitMs / pollIntervalMs).ceil();

        for (int retry = 0; retry < maxRetryPerID; retry++) {
          if (isAutoDetectionCancelled) return false;
          setCurrentReadingState(id, 'sensor');

          final prevCount = dataStorage.getArduinoRunningData(id).length;
          arduinoManager.sendString(_getArduinoSensorCommand(id));

          bool dataReceived = false;
          for (int poll = 0; poll < maxPolls && !dataReceived; poll++) {
            await Future.delayed(const Duration(milliseconds: pollIntervalMs));
            dataReceived = dataStorage.getArduinoRunningData(id).length > prevCount;
          }

          needRetry = dataStorage.getArduinoLatestRunningData(id) == null;
          if (!needRetry) break;
        }
      }
    }

    // STM32 感測器重試 (ID 19-23)
    if (urManager.isConnected) {
      for (int id = 19; id <= 23; id++) {
        if (isAutoDetectionCancelled) return false;
        bool needRetry = dataStorage.getStm32LatestRunningData(id) == null;
        if (!needRetry) continue;

        final int maxWaitMs = id >= 21 ? tempSensorMinWaitMs : pressureSensorMaxWaitMs;
        final int maxPolls = (maxWaitMs / pollIntervalMs).ceil();

        for (int retry = 0; retry < maxRetryPerID; retry++) {
          if (isAutoDetectionCancelled) return false;
          setCurrentReadingState(id, 'sensor');

          final prevCount = dataStorage.getStm32RunningData(id).length;
          final payload = [0x03, id, 0x00, 0x00, 0x00];
          final cmd = URCommandBuilder.buildCommand(payload);
          urManager.sendHex(cmd);

          bool dataReceived = false;
          for (int poll = 0; poll < maxPolls && !dataReceived; poll++) {
            await Future.delayed(const Duration(milliseconds: pollIntervalMs));
            dataReceived = dataStorage.getStm32RunningData(id).length > prevCount;
          }

          needRetry = dataStorage.getStm32LatestRunningData(id) == null;
          if (!needRetry) break;
        }
      }
    }

    // ===== 第二階段：流量計測試 =====
    // 發送 flowon 啟動流量計
    updateAutoDetectionStatus(tr('starting_flow_test'), 0.75);
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
      setCurrentReadingState(18, 'sensor');

      // Arduino 流量計讀取 (ID 18)，事件驅動等待
      if (arduinoManager.isConnected) {
        dataStorage.setHardwareState(18, HardwareState.running);
        final prevArduinoCount = dataStorage.getArduinoRunningData(18).length;
        arduinoManager.sendString('flowon');  // flowon 同時讀取流量

        bool arduinoReceived = false;
        for (int poll = 0; poll < 6 && !arduinoReceived; poll++) { // 最多 300ms
          await Future.delayed(const Duration(milliseconds: pollIntervalMs));
          arduinoReceived = dataStorage.getArduinoRunningData(18).length > prevArduinoCount;
        }
      }

      // STM32 流量計讀取 (ID 18)，事件驅動等待
      if (urManager.isConnected) {
        dataStorage.setHardwareState(18, HardwareState.running);
        final prevStm32Count = dataStorage.getStm32RunningData(18).length;
        final payload = [0x03, 18, 0x00, 0x00, 0x00];
        final cmd = URCommandBuilder.buildCommand(payload);
        urManager.sendHex(cmd);

        bool stm32Received = false;
        for (int poll = 0; poll < 6 && !stm32Received; poll++) { // 最多 300ms
          await Future.delayed(const Duration(milliseconds: pollIntervalMs));
          stm32Received = dataStorage.getStm32RunningData(18).length > prevStm32Count;
        }
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

    // 讀取最終流量計數值，事件驅動等待
    if (urManager.isConnected) {
      final prevCount = dataStorage.getStm32RunningData(18).length;
      final readPayload = [0x03, 18, 0x00, 0x00, 0x00];
      final readCmd = URCommandBuilder.buildCommand(readPayload);
      urManager.sendHex(readCmd);

      bool dataReceived = false;
      for (int poll = 0; poll < 6 && !dataReceived; poll++) { // 最多 300ms
        await Future.delayed(const Duration(milliseconds: pollIntervalMs));
        dataReceived = dataStorage.getStm32RunningData(18).length > prevCount;
      }
    }

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
  /// 同時檢測 Vdd/Vss 短路
  void _autoDetectionStep6ShowResult() {
    final failedIdleItems = <String>[];      // Idle 異常項目
    final failedRunningItems = <String>[];   // Running 異常項目
    final failedSensorItems = <String>[];    // 感測器異常項目
    final thresholdService = ThresholdSettingsService();

    // ===== Vdd 短路檢測 (Idle 狀態數值落入 Running 範圍) =====
    // 只有在設定開啟時才進行 VDD 短路檢測
    if (thresholdService.showVddShortTest) {
      _checkVddShortCircuit(thresholdService);
    }

    // ===== 診斷偵測（包含 MOSFET 異常偵測）=====
    _runDiagnosticDetection(thresholdService);

    // 檢查硬體數據 (ID 0-17) - Idle 狀態
    // 注意：使用第一筆 Idle 數據（原始基準值），避免被相鄰短路測試的讀取數據污染
    for (int id = 0; id < 18; id++) {
      final arduinoData = dataStorage.getArduinoFirstIdleData(id);
      final stm32Data = dataStorage.getStm32FirstIdleData(id);

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

    // 溫度感測器 (ID 21-23) - 簡化顯示
    // 當兩邊都異常時只顯示「異常+名稱」，不分 Arduino/STM32
    // 85度表示溫度感測器異常（DS18B20 預設錯誤值，可配置）
    final int tempSensorErrorValue = thresholdService.tempSensorErrorValue;

    for (int id = 21; id <= 23; id++) {
      final stm32RunningData = dataStorage.getStm32LatestRunningData(id);
      final stm32IdleData = dataStorage.getStm32LatestIdleData(id);
      final stm32Data = stm32RunningData ?? stm32IdleData;

      bool arduinoError = false;
      bool stm32Error = false;
      bool tempDiffError = false;

      // ID 21 (MCUtemp) Arduino 也有
      if (id == 21) {
        final arduinoRunningData = dataStorage.getArduinoLatestRunningData(id);
        final arduinoIdleData = dataStorage.getArduinoLatestIdleData(id);
        final arduinoData = arduinoRunningData ?? arduinoIdleData;

        if (arduinoData != null) {
          final value = arduinoData.value ~/ 10;
          final isValid = thresholdService.validateSensorValue(DeviceType.arduino, id, value);
          if (!isValid) {
            arduinoError = true;
          }
        }
      }

      if (stm32Data != null) {
        // 檢查是否為 85 度（溫度感測器異常值）
        if (stm32Data.value == tempSensorErrorValue) {
          stm32Error = true;
        } else {
          final isValid = thresholdService.validateSensorValue(DeviceType.stm32, id, stm32Data.value);
          if (!isValid) {
            stm32Error = true;
          }
        }

        // 與 Arduino MCUtemp 溫差比對
        if (arduinoMcuTemp != null) {
          final diffThreshold = thresholdService.getDiffThreshold(id);
          final tempDiff = (arduinoMcuTemp - stm32Data.value).abs();
          if (tempDiff > diffThreshold) {
            tempDiffError = true;
          }
        }
      }

      // 有任一錯誤即記錄
      final hasError = arduinoError || stm32Error || tempDiffError;
      if (hasError && !checkedSensorIds.contains(id)) {
        checkedSensorIds.add(id);
        final name = DisplayNames.getName(id);
        // 簡化顯示：只顯示名稱，不分 Arduino/STM32
        failedSensorItems.add(name);
      }
    }

    // ===== 過濾相鄰短路項目：移除與「負載未連接」腳位相關的項目 =====
    // 如果某腳位被判定為負載未連接，其相鄰短路測試結果不可靠，應移除
    final filteredAdjacentShortItems = _filterAdjacentShortByLoadDisconnected(
      List.from(_adjacentShortItems),
      _loadDisconnectedItems,
    );

    // 顯示結果對話框（包含短路測試結果）
    final passed = failedIdleItems.isEmpty &&
                   failedRunningItems.isEmpty &&
                   failedSensorItems.isEmpty &&
                   _vddShortItems.isEmpty &&
                   _vssShortItems.isEmpty &&
                   filteredAdjacentShortItems.isEmpty &&
                   _loadDisconnectedItems.isEmpty &&
                   _gsShortItems.isEmpty &&
                   _gpioStuckOnItems.isEmpty &&
                   _gpioStuckOffItems.isEmpty &&
                   _wireErrorItems.isEmpty &&
                   _d12vShortItems.isEmpty;

    // 保存結果以便隨時查看
    _saveTestResult(
      passed,
      failedIdleItems,
      failedRunningItems,
      failedSensorItems,
      List.from(_vddShortItems),
      List.from(_vssShortItems),
      filteredAdjacentShortItems,
      List.from(_loadDisconnectedItems),
      List.from(_gsShortItems),
      List.from(_gpioStuckOnItems),
      List.from(_gpioStuckOffItems),
      List.from(_wireErrorItems),
      List.from(_d12vShortItems),
    );

    showTestResultDialog(
      passed,
      failedIdleItems,
      failedRunningItems,
      failedSensorItems,
      vddShortItems: List.from(_vddShortItems),
      vssShortItems: List.from(_vssShortItems),
      adjacentShortItems: filteredAdjacentShortItems,
      loadDisconnectedItems: List.from(_loadDisconnectedItems),
      gsShortItems: List.from(_gsShortItems),
      gpioStuckOnItems: List.from(_gpioStuckOnItems),
      gpioStuckOffItems: List.from(_gpioStuckOffItems),
      wireErrorItems: List.from(_wireErrorItems),
      d12vShortItems: List.from(_d12vShortItems),
    );
  }

  /// 過濾相鄰短路項目：移除與「負載未連接」腳位相關的項目
  /// adjacentShortItems 格式: "STM32: S0-S1 (ID0-ID1)" 或 "Arduino: S0-S1 (ID0-ID1)"
  /// loadDisconnectedItems 格式: "S0 (ID0)"
  List<String> _filterAdjacentShortByLoadDisconnected(
    List<String> adjacentShortItems,
    List<String> loadDisconnectedItems,
  ) {
    if (loadDisconnectedItems.isEmpty) {
      return adjacentShortItems;
    }

    // 從負載未連接項目中提取 ID 列表
    // 格式: "S0 (ID0)" -> 提取 "ID0"
    final disconnectedIds = <String>{};
    final idRegex = RegExp(r'\(ID(\d+)\)');
    for (final item in loadDisconnectedItems) {
      final match = idRegex.firstMatch(item);
      if (match != null) {
        disconnectedIds.add('ID${match.group(1)}');
      }
    }

    if (disconnectedIds.isEmpty) {
      return adjacentShortItems;
    }

    // 過濾相鄰短路項目
    // 格式: "STM32: S0-S1 (ID0-ID1)" -> 如果 ID0 或 ID1 在 disconnectedIds 中則移除
    return adjacentShortItems.where((item) {
      // 提取括號內的 ID 對，格式: (IDx-IDy)
      final pairMatch = RegExp(r'\(ID(\d+)-ID(\d+)\)').firstMatch(item);
      if (pairMatch != null) {
        final id1 = 'ID${pairMatch.group(1)}';
        final id2 = 'ID${pairMatch.group(2)}';
        // 如果任一 ID 在負載未連接列表中，則過濾掉此項目
        if (disconnectedIds.contains(id1) || disconnectedIds.contains(id2)) {
          return false;
        }
      }
      return true;
    }).toList();
  }

  /// 檢測 Vdd 短路
  /// Idle 狀態下，數值落入 Running 範圍則可能 Vdd 短路
  void _checkVddShortCircuit(ThresholdSettingsService thresholdService) {
    // 檢查所有硬體腳位 (ID 0-17)
    // 注意：使用第一筆 Idle 數據（原始基準值），避免被相鄰短路測試的讀取數據污染
    for (int id = 0; id < 18; id++) {
      // Arduino Idle 數值檢查
      final arduinoIdleData = dataStorage.getArduinoFirstIdleData(id);
      if (arduinoIdleData != null) {
        // 如果 Idle 數值落入 Running 範圍，可能是 Vdd 短路
        final isInRunningRange = thresholdService.validateHardwareValue(
          DeviceType.arduino, StateType.running, id, arduinoIdleData.value);
        final isInIdleRange = thresholdService.validateHardwareValue(
          DeviceType.arduino, StateType.idle, id, arduinoIdleData.value);

        if (isInRunningRange && !isInIdleRange) {
          final pinInfo = AdjacentPinsService.getPinInfo(id);
          final pinName = pinInfo?.pinName ?? 'ID$id';
          _vddShortItems.add('Arduino $pinName (ID$id)');
        }
      }

      // STM32 Idle 數值檢查
      final stm32IdleData = dataStorage.getStm32FirstIdleData(id);
      if (stm32IdleData != null) {
        final isInRunningRange = thresholdService.validateHardwareValue(
          DeviceType.stm32, StateType.running, id, stm32IdleData.value);
        final isInIdleRange = thresholdService.validateHardwareValue(
          DeviceType.stm32, StateType.idle, id, stm32IdleData.value);

        if (isInRunningRange && !isInIdleRange) {
          final pinInfo = AdjacentPinsService.getPinInfo(id);
          final pinName = pinInfo?.pinName ?? 'ID$id';
          _vddShortItems.add('STM32 $pinName (ID$id)');
        }
      }
    }
  }

  /// 執行診斷偵測
  /// 根據 STM32 和 Arduino 的 Idle/Running 數值進行診斷
  /// 偵測順序：
  /// 1. 負載未連接：Arduino Idle ≈ Running（差異小），STM32 Running 40~70，STM32 Idle 正常
  /// 2. MOSFET 異常偵測：
  ///   - G-D 短路：Arduino Idle ~0, Running 380~440, STM32 Running 460~530
  ///   - D 極接地：Arduino Idle ~0, Running ~0
  ///   - D-S 短路：Arduino/STM32 Idle 落在 Running 範圍
  ///   - G 極接地：Arduino Idle 正常, Running 維持 Idle 值, STM32 Running 很低
  ///   - G-S 短路：STM32 Running > 400 且 Idle < 50
  /// - GPIO 卡在 ON：Idle > 150
  /// - GPIO 卡在 OFF：Running < 100（有負載時）
  /// - 線材錯誤：Arduino Running 維持 Idle 數值，但 STM32 Running 正常
  void _runDiagnosticDetection(ThresholdSettingsService thresholdService) {
    // MOSFET 異常偵測閾值（從 ThresholdSettingsService 讀取可配置值）
    final int arduinoVssThreshold = thresholdService.arduinoVssThreshold;
    final int arduinoIdleNormalMin = thresholdService.arduinoIdleNormalMin;
    final int stm32RunningLowThreshold = thresholdService.loadDetectionRunningThreshold;

    // G-D 短路閾值
    final int gdShortArduinoRunningMin = thresholdService.gdShortArduinoRunningMin;
    final int gdShortArduinoRunningMax = thresholdService.gdShortArduinoRunningMax;
    final int gdShortStm32RunningMin = thresholdService.gdShortStm32RunningMin;
    final int gdShortStm32RunningMax = thresholdService.gdShortStm32RunningMax;

    // D-S 短路閾值（Idle 落在 Running 範圍）
    final int dsShortArduinoIdleMin = thresholdService.dsShortArduinoIdleMin;
    final int dsShortArduinoIdleMax = thresholdService.dsShortArduinoIdleMax;
    final int dsShortStm32IdleMin = thresholdService.dsShortStm32IdleMin;
    final int dsShortStm32IdleMax = thresholdService.dsShortStm32IdleMax;

    // 只對硬體 ID (0-17) 進行診斷
    for (int id = 0; id < 18; id++) {
      // 使用第一筆 Idle 數據（原始基準值），避免被相鄰短路測試數據影響
      final stm32IdleData = dataStorage.getStm32FirstIdleData(id);
      final stm32RunningData = dataStorage.getStm32LatestRunningData(id);
      final arduinoIdleData = dataStorage.getArduinoFirstIdleData(id);
      final arduinoRunningData = dataStorage.getArduinoLatestRunningData(id);

      if (stm32IdleData == null || stm32RunningData == null) continue;

      final stm32Idle = stm32IdleData.value;
      final stm32Running = stm32RunningData.value;
      final displayName = DisplayNames.getName(id);

      // Arduino 數據（用於 MOSFET 異常和線材錯誤偵測）
      final arduinoIdle = arduinoIdleData?.value;
      final arduinoRunning = arduinoRunningData?.value;
      final arduinoDiff = (arduinoIdle != null && arduinoRunning != null)
          ? (arduinoIdle - arduinoRunning).abs()
          : 0;

      // ===== 負載偵測（優先於 MOSFET 偵測）=====
      // 條件：Arduino Idle ≈ Running（差異小）且 STM32 Running 在 40~70 範圍
      // 特徵：
      //   - Arduino Idle 和 Running 差異很小（< 100），表示沒有偵測到電流變化
      //   - STM32 Running 在 40~70（異常低，不在正常 Running 範圍 330~375）
      //   - STM32 Idle 在正常範圍內（區分 G 極接地）
      if (thresholdService.showLoadDetection) {
        if (arduinoIdle != null && arduinoRunning != null) {
          // 負載未連接閾值（從 ThresholdSettingsService 讀取）
          final int loadDisconnectedStm32RunningMin = thresholdService.loadDisconnectedStm32RunningMin;
          final int loadDisconnectedStm32RunningMax = thresholdService.loadDisconnectedStm32RunningMax;
          final int arduinoDiffThreshold = thresholdService.arduinoDiffThreshold;

          // Arduino Idle 和 Running 差異很小，且 STM32 Running 在 40~70 範圍
          // STM32 Idle 需要在正常範圍內（使用 validateHardwareValue 驗證）
          final stm32IdleValid = thresholdService.validateHardwareValue(
            DeviceType.stm32, StateType.idle, id, stm32Idle);

          if (arduinoDiff < arduinoDiffThreshold &&
              stm32Running >= loadDisconnectedStm32RunningMin &&
              stm32Running <= loadDisconnectedStm32RunningMax &&
              stm32IdleValid) {
            _loadDisconnectedItems.add('$displayName (ID$id)');
            continue; // 已判定為負載未連接，跳過後續診斷
          }
        }
      }

      // ===== MOSFET 異常偵測 =====
      if (thresholdService.showMosfetDetection) {
        // 需要 Arduino 數據來判斷 MOSFET 異常
        if (arduinoIdle != null && arduinoRunning != null) {
          // --- D極與12V短路偵測（最優先判斷）---
          // 特徵：Arduino Idle 和 Running 都接近飽和值（>1000），表示 D極被 12V 強制拉高
          // Arduino 是 10-bit ADC，最大值 1023，大於 1000 基本上就是有問題
          final int d12vShortArduinoThreshold = thresholdService.d12vShortArduinoThreshold;
          if (arduinoIdle > d12vShortArduinoThreshold &&
              arduinoRunning > d12vShortArduinoThreshold) {
            _d12vShortItems.add('$displayName (ID$id)');
            continue; // 已判定為 D極與12V短路，跳過後續診斷
          }

          // --- G-D 短路偵測（必須先於 D 極接地檢測）---
          // 特徵：Arduino Idle 接近 0，但 Running 有數值 (380~440)，STM32 Running 有數值 (460~530)
          if (arduinoIdle < arduinoVssThreshold &&
              arduinoRunning >= gdShortArduinoRunningMin &&
              arduinoRunning <= gdShortArduinoRunningMax &&
              stm32Running >= gdShortStm32RunningMin &&
              stm32Running <= gdShortStm32RunningMax) {
            _gsShortItems.add('$displayName (ID$id) - G-D短路');
            continue; // 已判定為 G-D 短路，跳過後續診斷
          }

          // --- D-S 短路偵測 ---
          // 特徵：Arduino 和 STM32 的 Idle 值落在 Running 範圍內
          // Arduino Idle 落在 Running 範圍 (25~60)，且 STM32 Idle 落在 Running 範圍 (330~375)
          if (arduinoIdle >= dsShortArduinoIdleMin &&
              arduinoIdle <= dsShortArduinoIdleMax &&
              stm32Idle >= dsShortStm32IdleMin &&
              stm32Idle <= dsShortStm32IdleMax) {
            _gsShortItems.add('$displayName (ID$id) - D-S短路');
            continue; // 已判定為 D-S 短路，跳過後續診斷
          }

          // --- D 極接地偵測 ---
          // 特徵：Arduino Idle 接近 0（優先於負載未連接判定）
          if (arduinoIdle < arduinoVssThreshold) {
            _gsShortItems.add('$displayName (ID$id) - D極接地');
            continue; // 已判定為 D 極接地，跳過後續診斷
          }

          // --- G 極接地偵測 ---
          // 特徵：Arduino Idle 正常 (~799)，Running 也維持在 Idle 附近 (~808)
          //       STM32 Idle 很低 (3)，Running 也很低 (39)
          // 與負載未連接的差異：Arduino Idle/Running 都正常，但 STM32 數值很低
          if (arduinoIdle >= arduinoIdleNormalMin &&
              arduinoRunning >= arduinoIdleNormalMin &&  // Arduino Running 也維持在正常 Idle 範圍
              stm32Idle < thresholdService.loadDetectionIdleThreshold &&
              stm32Running < stm32RunningLowThreshold) {
            _gsShortItems.add('$displayName (ID$id) - G極接地');
            continue; // 已判定為 G 極接地，跳過後續診斷
          }
        }

        // --- G-S 短路偵測 ---
        // 條件：STM32 Running > 400 且 Idle < 50 → G-S 短路
        if (stm32Running > thresholdService.gsShortRunningThreshold &&
            stm32Idle < thresholdService.loadDetectionIdleThreshold) {
          _gsShortItems.add('$displayName (ID$id) - G-S短路');
          continue; // 已判定為 G-S 短路，跳過後續診斷
        }
      }

      // ===== GPIO 狀態偵測（暫時停用）=====
      // 原因：與 MOSFET 診斷功能重疊，且缺乏實際數據驗證
      // 保留程式碼供未來使用
      // if (thresholdService.showGpioStatusDetection) {
      //   // GPIO 卡在 ON：Idle > 150
      //   if (stm32Idle > thresholdService.gpioStuckOnIdleThreshold) {
      //     _gpioStuckOnItems.add('$displayName (ID$id)');
      //   }
      //
      //   // GPIO 卡在 OFF：Running < 100（有負載時，即 Idle 在正常範圍）
      //   // 注意：這裡只有在負載正常連接時才判定（Idle 值在正常範圍內）
      //   if (stm32Running < thresholdService.gpioStuckOffRunningThreshold &&
      //       stm32Idle >= thresholdService.loadDetectionIdleThreshold) {
      //     _gpioStuckOffItems.add('$displayName (ID$id)');
      //   }
      // }

      // ===== 線材錯誤偵測 =====
      // 條件：Arduino Running 維持 Idle 數值（差異小），但 STM32 Running 正常
      // 正常情況：Arduino Idle ~790, Running ~36 (差異 > 700)
      // 線材錯誤：Arduino Idle ~790, Running ~790 (差異 < 100)，STM32 Running 正常 (330~375)
      if (thresholdService.showWireErrorDetection) {
        if (arduinoIdle != null && arduinoRunning != null) {
          // Arduino Idle 和 Running 差異很小（< 100），表示 Arduino 端沒有偵測到變化
          // 同時 STM32 Running 正常（在 Running 範圍內），表示負載確實有動作
          final stm32RunningValid = thresholdService.validateHardwareValue(
            DeviceType.stm32, StateType.running, id, stm32Running);

          if (arduinoDiff < thresholdService.wireErrorDiffThreshold &&
              stm32RunningValid) {
            _wireErrorItems.add('$displayName (ID$id)');
          }
        }
      }
    }
  }

  /// 並行批次讀取 Arduino 和 STM32 硬體數據 (ID 0-17)
  /// 使用事件驅動等待：每 50ms 檢查數據是否到達，最多等待 hardwareWaitMs
  /// 第一輪讀取所有 ID，之後針對沒有資料的 ID 單獨重試，每個 ID 最多 maxRetryPerID 次
  Future<void> _batchReadHardwareParallel(HardwareState state) async {
    final thresholdService = ThresholdSettingsService();
    // Arduino 指令對應表
    final arduinoCommands = ['s0', 's1', 's2', 's3', 's4', 's5', 's6', 's7', 's8', 's9',
                             'water', 'u0', 'u1', 'u2', 'arl', 'crl', 'srl', 'o3'];

    // 設定當前讀取的區域類型
    final sectionName = state == HardwareState.idle ? 'idle' : 'running';

    // 事件驅動等待的輪詢間隔與最大等待次數
    const int pollIntervalMs = 50;
    final int maxPollCount = (thresholdService.hardwareWaitMs / pollIntervalMs).ceil();

    // 第一輪：讀取所有 ID（事件驅動等待，數據到達即繼續）
    for (int id = 0; id < 18; id++) {
      if (isAutoDetectionCancelled) return;

      // 設定當前讀取的項目 ID 和區域（用於高亮顯示）
      setCurrentReadingState(id, sectionName);

      // 設定當前硬體狀態
      dataStorage.setHardwareState(id, state);

      // 記錄發送前的數據數量（用於確認新數據到達）
      final prevArduinoCount = state == HardwareState.idle
          ? dataStorage.getArduinoIdleData(id).length
          : dataStorage.getArduinoRunningData(id).length;
      final prevStm32Count = state == HardwareState.idle
          ? dataStorage.getStm32IdleData(id).length
          : dataStorage.getStm32RunningData(id).length;

      // 同時發送 Arduino 和 STM32 指令
      if (arduinoManager.isConnected) {
        arduinoManager.sendString(arduinoCommands[id]);
      }
      if (urManager.isConnected) {
        final payload = [0x03, id, 0x00, 0x00, 0x00];
        final cmd = URCommandBuilder.buildCommand(payload);
        urManager.sendHex(cmd);
      }

      // 事件驅動等待：每 50ms 檢查數據是否到達，最多等待 hardwareWaitMs
      bool arduinoDataReceived = !arduinoManager.isConnected;
      bool stm32DataReceived = !urManager.isConnected;
      for (int poll = 0; poll < maxPollCount && (!arduinoDataReceived || !stm32DataReceived); poll++) {
        await Future.delayed(const Duration(milliseconds: pollIntervalMs));

        if (!arduinoDataReceived) {
          final currentCount = state == HardwareState.idle
              ? dataStorage.getArduinoIdleData(id).length
              : dataStorage.getArduinoRunningData(id).length;
          arduinoDataReceived = currentCount > prevArduinoCount;
        }
        if (!stm32DataReceived) {
          final currentCount = state == HardwareState.idle
              ? dataStorage.getStm32IdleData(id).length
              : dataStorage.getStm32RunningData(id).length;
          stm32DataReceived = currentCount > prevStm32Count;
        }
      }
    }

    // 針對沒有資料的 ID 單獨重試
    final int maxRetryPerID = thresholdService.maxRetryPerID;

    for (int id = 0; id < 18; id++) {
      if (isAutoDetectionCancelled) return;

      // 檢查該 ID 是否需要重試
      bool needArduinoRetry = arduinoManager.isConnected &&
          (state == HardwareState.idle
              ? dataStorage.getArduinoLatestIdleData(id) == null
              : dataStorage.getArduinoLatestRunningData(id) == null);

      bool needStm32Retry = urManager.isConnected &&
          (state == HardwareState.idle
              ? dataStorage.getStm32LatestIdleData(id) == null
              : dataStorage.getStm32LatestRunningData(id) == null);

      if (!needArduinoRetry && !needStm32Retry) continue;

      // 對該 ID 進行重試（同樣使用事件驅動等待）
      for (int retry = 0; retry < maxRetryPerID; retry++) {
        if (isAutoDetectionCancelled) return;

        // 設定當前讀取的項目 ID（用於高亮顯示）
        setCurrentReadingState(id, sectionName);

        // 記錄重試前的數據數量
        final prevArduinoCount = state == HardwareState.idle
            ? dataStorage.getArduinoIdleData(id).length
            : dataStorage.getArduinoRunningData(id).length;
        final prevStm32Count = state == HardwareState.idle
            ? dataStorage.getStm32IdleData(id).length
            : dataStorage.getStm32RunningData(id).length;

        // 重新發送指令
        if (needArduinoRetry) {
          arduinoManager.sendString(arduinoCommands[id]);
        }
        if (needStm32Retry) {
          final payload = [0x03, id, 0x00, 0x00, 0x00];
          final cmd = URCommandBuilder.buildCommand(payload);
          urManager.sendHex(cmd);
        }

        // 事件驅動等待：每 50ms 檢查數據是否到達，最多等待 hardwareWaitMs
        bool arduinoDataReceived = !needArduinoRetry;
        bool stm32DataReceived = !needStm32Retry;
        for (int poll = 0; poll < maxPollCount && (!arduinoDataReceived || !stm32DataReceived); poll++) {
          await Future.delayed(const Duration(milliseconds: pollIntervalMs));

          if (!arduinoDataReceived) {
            final currentCount = state == HardwareState.idle
                ? dataStorage.getArduinoIdleData(id).length
                : dataStorage.getArduinoRunningData(id).length;
            arduinoDataReceived = currentCount > prevArduinoCount;
          }
          if (!stm32DataReceived) {
            final currentCount = state == HardwareState.idle
                ? dataStorage.getStm32IdleData(id).length
                : dataStorage.getStm32RunningData(id).length;
            stm32DataReceived = currentCount > prevStm32Count;
          }
        }

        // 檢查是否已收到資料
        needArduinoRetry = arduinoManager.isConnected &&
            (state == HardwareState.idle
                ? dataStorage.getArduinoLatestIdleData(id) == null
                : dataStorage.getArduinoLatestRunningData(id) == null);

        needStm32Retry = urManager.isConnected &&
            (state == HardwareState.idle
                ? dataStorage.getStm32LatestIdleData(id) == null
                : dataStorage.getStm32LatestRunningData(id) == null);

        // 兩邊都收到資料，跳出重試
        if (!needArduinoRetry && !needStm32Retry) break;
      }
    }

    // 讀取完成後清除高亮
    clearCurrentReadingState();
  }

  /// 批次讀取 Arduino 感測器數據 (ID 18-21)
  /// 針對沒有資料的 ID 單獨重試，每個 ID 最多 5 次
  Future<void> batchReadArduinoSensor() async {
    if (!arduinoManager.isConnected) return;
    final thresholdService = ThresholdSettingsService();

    final commands = ['flowon', 'prec', 'prew', 'mcutemp'];
    final ids = [18, 19, 20, 21];

    // 第一輪：讀取所有感測器
    for (int i = 0; i < commands.length; i++) {
      if (isAutoDetectionCancelled) return;

      dataStorage.setHardwareState(ids[i], HardwareState.running);
      arduinoManager.sendString(commands[i]);
      await Future.delayed(Duration(milliseconds: thresholdService.sensorWaitMs));
    }

    // 針對沒有資料的 ID 單獨重試
    final int maxRetryPerID = thresholdService.maxRetryPerID;

    for (int i = 0; i < ids.length; i++) {
      if (isAutoDetectionCancelled) return;

      final id = ids[i];
      bool needRetry = dataStorage.getArduinoLatestRunningData(id) == null;

      if (!needRetry) continue;

      for (int retry = 0; retry < maxRetryPerID; retry++) {
        if (isAutoDetectionCancelled) return;

        arduinoManager.sendString(commands[i]);
        await Future.delayed(Duration(milliseconds: thresholdService.sensorWaitMs));

        // 檢查是否已收到資料
        needRetry = dataStorage.getArduinoLatestRunningData(id) == null;
        if (!needRetry) break;
      }
    }
  }

  /// 批次讀取 STM32 感測器數據 (ID 18-23)
  /// 針對沒有資料的 ID 單獨重試，每個 ID 最多 5 次
  Future<void> batchReadStm32Sensor() async {
    if (!urManager.isConnected) return;
    final thresholdService = ThresholdSettingsService();

    // 第一輪：讀取所有感測器
    for (int id = 18; id <= 23; id++) {
      if (isAutoDetectionCancelled) return;

      dataStorage.setHardwareState(id, HardwareState.running);

      final payload = [0x03, id, 0x00, 0x00, 0x00];
      final cmd = URCommandBuilder.buildCommand(payload);
      urManager.sendHex(cmd);
      // 增加等待時間確保 STM32 有足夠時間回應
      await Future.delayed(Duration(milliseconds: thresholdService.sensorWaitMs));
    }
    // 額外等待確保最後一個回應也被接收
    await Future.delayed(Duration(milliseconds: thresholdService.hardwareWaitMs));

    // 針對沒有資料的 ID 單獨重試
    final int maxRetryPerID = thresholdService.maxRetryPerID;

    for (int id = 18; id <= 23; id++) {
      if (isAutoDetectionCancelled) return;

      bool needRetry = dataStorage.getStm32LatestRunningData(id) == null;

      if (!needRetry) continue;

      for (int retry = 0; retry < maxRetryPerID; retry++) {
        if (isAutoDetectionCancelled) return;

        final payload = [0x03, id, 0x00, 0x00, 0x00];
        final cmd = URCommandBuilder.buildCommand(payload);
        urManager.sendHex(cmd);
        await Future.delayed(Duration(milliseconds: thresholdService.sensorWaitMs));

        // 檢查是否已收到資料
        needRetry = dataStorage.getStm32LatestRunningData(id) == null;
        if (!needRetry) break;
      }
    }
  }
}
