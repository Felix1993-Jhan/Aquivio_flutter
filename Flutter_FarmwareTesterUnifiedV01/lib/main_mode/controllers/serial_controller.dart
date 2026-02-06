// ============================================================================
// 串口控制器 Mixin
// ============================================================================
// 功能說明：
// 將 Arduino 和 STM32 串口操作相關的邏輯從 main.dart 中抽取出來
// 包含連接、斷開、發送指令、流量控制等功能
// ============================================================================

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_firmware_tester_unified/shared/services/serial_port_manager.dart';
import 'package:flutter_firmware_tester_unified/shared/services/data_storage_service.dart';
import 'package:flutter_firmware_tester_unified/shared/services/arduino_connection_service.dart';
import 'package:flutter_firmware_tester_unified/shared/services/port_filter_service.dart';
import '../services/ur_command_builder.dart';
import 'package:flutter_firmware_tester_unified/shared/services/localization_service.dart';

/// 串口控制器 Mixin
mixin SerialController<T extends StatefulWidget> on State<T> {

  // ===== 必須由使用者實作的抽象成員 =====

  SerialPortManager get arduinoManager;
  SerialPortManager get urManager;
  DataStorageService get dataStorage;

  String? get selectedArduinoPort;
  String? get selectedUrPort;
  set selectedArduinoPort(String? value);
  set selectedUrPort(String? value);

  /// 可用的 COM 埠列表（供自動掃描使用）
  List<String> get availablePorts;

  bool get isFlowOn;
  set isFlowOn(bool value);

  Timer? get flowReadTimer;
  set flowReadTimer(Timer? value);

  int get arduinoConnectRetryCount;
  set arduinoConnectRetryCount(int value);

  int get urConnectRetryCount;
  set urConnectRetryCount(int value);

  void showSnackBarMessage(String message);
  void showErrorDialogMessage(String message);

  /// 當偵測到錯誤模式時呼叫（顯示切換模式對話框）
  void onWrongModeDetected(String portName);

  // ==================== Arduino 操作 ====================

  /// 連接 Arduino（自動掃描所有 COM 埠尋找正確的 Arduino）
  ///
  /// 此方法會自動掃描所有可用的 COM 埠，找到正確模式的 Arduino 後連線。
  /// 與自動偵測使用相同的邏輯，不需要預先選擇 COM 埠。
  /// 會自動排除 ST-Link VCP 和已被 STM32 使用的埠口。
  Future<void> connectArduino() async {
    // 取得可用埠口（排除 ST-Link 和已連接的 STM32）
    final excludePorts = <String>[];
    if (selectedUrPort != null && urManager.isConnected) {
      excludePorts.add(selectedUrPort!);
    }

    final filteredPorts = PortFilterService.getFilteredPorts(
      excludePorts: excludePorts,
      excludeStLink: true,
    );

    if (filteredPorts.isEmpty) {
      showSnackBarMessage(tr('no_com_port'));
      return;
    }

    showSnackBarMessage(tr('arduino_verifying'));

    // 建立要嘗試的埠口列表（優先嘗試已選擇的埠口）
    final List<String> portsToScan = [];
    if (selectedArduinoPort != null && filteredPorts.contains(selectedArduinoPort)) {
      portsToScan.add(selectedArduinoPort!);
      portsToScan.addAll(filteredPorts.where((p) => p != selectedArduinoPort));
    } else {
      portsToScan.addAll(filteredPorts);
    }

    // 逐一嘗試每個 COM 埠
    for (int i = 0; i < portsToScan.length; i++) {
      if (!mounted) return;

      final port = portsToScan[i];

      // 更新下拉選單顯示目前正在測試的埠口
      selectedArduinoPort = port;
      setState(() {});

      final result = await arduinoManager.connectAndVerify(port);

      if (!mounted) return;

      switch (result) {
        case ConnectResult.success:
          // 連線成功
          setState(() {});
          showSnackBarMessage(tr('arduino_connected'));
          // 連接成功後發送 flowoff
          Future.delayed(const Duration(milliseconds: 300), () {
            if (mounted && arduinoManager.isConnected) {
              sendArduinoFlowoff();
            }
          });
          return;  // 連線成功，結束掃描

        case ConnectResult.wrongMode:
          // 偵測到 BodyDoor Arduino，顯示切換對話框
          onWrongModeDetected(port);
          return;  // 偵測到錯誤模式，結束掃描

        case ConnectResult.failed:
        case ConnectResult.portError:
          // 連線失敗，繼續嘗試下一個埠口
          break;
      }
    }

    // 所有埠口都嘗試完畢仍然失敗，清除選擇狀態
    selectedArduinoPort = null;
    setState(() {});
    showSnackBarMessage(tr('arduino_connect_failed'));
  }

  /// 斷開 Arduino 連接
  void disconnectArduino() {
    // 停止重試機制
    arduinoConnectRetryCount = 0;
    sendArduinoFlowoff();
    stopAutoFlowRead();
    arduinoManager.close();
    if (mounted) setState(() {});
    showSnackBarMessage(tr('arduino_disconnected'));
  }

  /// 發送 flowoff 指令到 Arduino（如果已連接）
  void sendArduinoFlowoff() {
    if (arduinoManager.isConnected) {
      arduinoManager.sendString('flowoff');
    }
  }

  /// 發送指令到 Arduino
  void sendArduinoCommand(String command) {
    if (!arduinoManager.isConnected) {
      showSnackBarMessage(tr('connect_arduino_first'));
      return;
    }
    arduinoManager.sendString(command);

    // 追蹤 flowon/flowoff 狀態
    final lowerCommand = command.toLowerCase();
    if (lowerCommand == 'flowon' || lowerCommand.startsWith('flowon')) {
      startAutoFlowRead();
    } else if (lowerCommand == 'flowoff') {
      stopAutoFlowReadAndClear();
    }
  }

  /// 啟動自動流量讀取（每 2 秒讀取 STM32 flow ID 18）
  void startAutoFlowRead() {
    if (isFlowOn) return;

    isFlowOn = true;
    flowReadTimer?.cancel();
    flowReadTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (urManager.isConnected && isFlowOn) {
        final payload = [0x03, 18, 0x00, 0x00, 0x00];
        final cmd = URCommandBuilder.buildCommand(payload);
        urManager.sendHex(cmd);
      }
    });
  }

  /// 停止自動流量讀取
  void stopAutoFlowRead() {
    isFlowOn = false;
    flowReadTimer?.cancel();
    flowReadTimer = null;
  }

  /// 停止自動流量讀取並執行 flowoff 後續動作
  void stopAutoFlowReadAndClear() {
    stopAutoFlowRead();

    if (urManager.isConnected) {
      // 讀取一次 flow 數值 (ID 18)
      final readPayload = [0x03, 18, 0x00, 0x00, 0x00];
      final readCmd = URCommandBuilder.buildCommand(readPayload);
      urManager.sendHex(readCmd);

      // 延遲 500ms 後發送清除 flow 指令
      Future.delayed(const Duration(milliseconds: 500), () {
        if (urManager.isConnected) {
          final clearPayload = [0x04, 0x12, 0x00, 0x00, 0x00];
          final clearCmd = URCommandBuilder.buildCommand(clearPayload);
          urManager.sendHex(clearCmd);
        }
      });
    }
  }

  // ==================== STM32 操作 ====================

  /// 連接 STM32（自動掃描所有 COM 埠尋找正確的 STM32）
  ///
  /// 此方法會自動掃描所有可用的 COM 埠，找到 STM32 後連線。
  /// 與自動偵測使用相同的邏輯，不需要預先選擇 COM 埠。
  /// 會自動排除 ST-Link VCP 和已被 Arduino 使用的埠口。
  Future<void> connectUr() async {
    // 取得可用埠口（排除 ST-Link 和已連接的 Arduino）
    final excludePorts = <String>[];
    if (selectedArduinoPort != null && arduinoManager.isConnected) {
      excludePorts.add(selectedArduinoPort!);
    }

    final filteredPorts = PortFilterService.getFilteredPorts(
      excludePorts: excludePorts,
      excludeStLink: true,
    );

    if (filteredPorts.isEmpty) {
      showSnackBarMessage(tr('no_com_port'));
      return;
    }

    showSnackBarMessage(tr('stm32_verifying'));

    // 建立要嘗試的埠口列表（優先嘗試已選擇的埠口）
    final List<String> portsToScan = [];
    if (selectedUrPort != null && filteredPorts.contains(selectedUrPort)) {
      portsToScan.add(selectedUrPort!);
      portsToScan.addAll(filteredPorts.where((p) => p != selectedUrPort));
    } else {
      portsToScan.addAll(filteredPorts);
    }

    // 逐一嘗試每個 COM 埠
    for (int i = 0; i < portsToScan.length; i++) {
      if (!mounted) return;

      final port = portsToScan[i];

      // 更新下拉選單顯示目前正在測試的埠口
      selectedUrPort = port;
      setState(() {});

      final result = await urManager.connectAndVerifyStm32(port);

      if (!mounted) return;

      if (result == Stm32ConnectResult.success) {
        // 連線成功
        setState(() {});
        showSnackBarMessage(tr('stm32_connected'));
        return;  // 連線成功，結束掃描
      }
    }

    // 所有埠口都嘗試完畢仍然失敗，清除選擇狀態
    selectedUrPort = null;
    setState(() {});
    showSnackBarMessage(tr('stm32_connect_failed'));
  }

  /// 斷開 STM32 連接
  void disconnectUr() {
    // 停止重試機制
    urConnectRetryCount = 0;
    sendArduinoFlowoff();
    urManager.close();
    if (mounted) setState(() {});
    showSnackBarMessage(tr('stm32_disconnected'));
  }

  /// 發送指令到 STM32
  void sendUrCommand(List<int> payload) {
    if (!urManager.isConnected) {
      showSnackBarMessage(tr('connect_stm32_first'));
      return;
    }
    final cmd = URCommandBuilder.buildCommand(payload);
    urManager.sendHex(cmd);

    // 根據指令類型更新硬體狀態
    if (payload.length >= 4) {
      final command = payload[0];
      if (command == 0x01 || command == 0x02) {
        final lowByte = payload[1];
        final midByte = payload[2];
        final highByte = payload[3];
        final bitMask = lowByte | (midByte << 8) | (highByte << 16);

        for (int id = 0; id < 24; id++) {
          if ((bitMask & (1 << id)) != 0) {
            final state = (command == 0x01)
                ? HardwareState.running
                : HardwareState.idle;
            dataStorage.setHardwareState(id, state);
          }
        }
      }
    }
  }

  // ==================== 快速讀取操作 ====================

  /// Arduino 快速讀取
  void onArduinoQuickRead(String command) {
    if (!arduinoManager.isConnected) {
      showSnackBarMessage(tr('connect_arduino_first'));
      return;
    }
    sendArduinoCommand(command);
    showSnackBarMessage(tr('sent_arduino_command').replaceAll('{command}', command));
  }

  /// STM32 快速讀取 (使用 0x03 指令)
  void onStm32QuickRead(int id) {
    if (!urManager.isConnected) {
      showSnackBarMessage(tr('connect_stm32_first'));
      return;
    }
    final payload = [0x03, id, 0x00, 0x00, 0x00];
    sendUrCommand(payload);
    showSnackBarMessage(tr('sent_stm32_read_command').replaceAll('{id}', '$id'));
  }

  /// STM32 發送原始指令 (直接發送完整 hex 指令)
  void onStm32SendCommand(List<int> hexCommand) {
    if (!urManager.isConnected) {
      showSnackBarMessage(tr('connect_stm32_first'));
      return;
    }
    urManager.sendHex(hexCommand);

    // 從指令中解析出 payload 以追蹤硬體狀態
    if (hexCommand.length >= 8 && hexCommand[0] == 0x40 && hexCommand[1] == 0x71 && hexCommand[2] == 0x30) {
      final command = hexCommand[3];
      if (command == 0x01 || command == 0x02) {
        final lowByte = hexCommand[4];
        final midByte = hexCommand[5];
        final highByte = hexCommand[6];
        final bitMask = lowByte | (midByte << 8) | (highByte << 16);

        for (int id = 0; id < 24; id++) {
          if ((bitMask & (1 << id)) != 0) {
            final state = (command == 0x01)
                ? HardwareState.running
                : HardwareState.idle;
            dataStorage.setHardwareState(id, state);
          }
        }

        final action = (command == 0x01) ? tr('output_opened') : tr('output_closed');
        showSnackBarMessage(tr('all_outputs_toggled').replaceAll('{action}', action));
      }
    }
  }
}
