// ============================================================================
// 串口控制器 Mixin
// ============================================================================
// 功能說明：
// 將 Arduino 和 STM32 串口操作相關的邏輯從 main.dart 中抽取出來
// 包含連接、斷開、發送指令、流量控制等功能
// ============================================================================

import 'dart:async';
import 'package:flutter/material.dart';
import '../services/serial_port_manager.dart';
import 'package:flutter_firmware_tester_unified/shared/services/data_storage_service.dart';
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

  bool get isFlowOn;
  set isFlowOn(bool value);

  Timer? get flowReadTimer;
  set flowReadTimer(Timer? value);

  Timer? get urVerificationTimer;
  set urVerificationTimer(Timer? value);

  bool get urConnectionVerified;
  set urConnectionVerified(bool value);

  int get arduinoConnectRetryCount;
  set arduinoConnectRetryCount(int value);

  int get urConnectRetryCount;
  set urConnectRetryCount(int value);

  void showSnackBarMessage(String message);
  void showErrorDialogMessage(String message);

  // ==================== 常數 ====================

  /// 連接重試最大次數
  static const int maxConnectRetry = 6;

  /// STM32 連接驗證超時時間（毫秒）
  static const int urVerificationTimeoutMs = 2000;

  // ==================== Arduino 操作 ====================

  /// 連接 Arduino
  void connectArduino() {
    if (selectedArduinoPort == null) {
      showSnackBarMessage(tr('select_arduino_port'));
      return;
    }
    if (selectedArduinoPort == selectedUrPort && urManager.isConnected) {
      showSnackBarMessage(tr('arduino_port_in_use'));
      return;
    }

    arduinoConnectRetryCount = 0;
    _tryConnectArduino();
  }

  /// 嘗試連接 Arduino（支援自動重試）
  void _tryConnectArduino() {
    if (selectedArduinoPort == null) return;

    if (arduinoManager.open(selectedArduinoPort!)) {
      arduinoManager.startHeartbeat();
      setState(() {});
      showSnackBarMessage(tr('arduino_connected'));
      arduinoConnectRetryCount = 0;
      // 連接成功後發送 flowoff
      Future.delayed(const Duration(milliseconds: 500), () {
        sendArduinoFlowoff();
      });
    } else {
      arduinoConnectRetryCount++;
      if (arduinoConnectRetryCount < maxConnectRetry) {
        showSnackBarMessage(tr('arduino_connecting')
            .replaceAll('{current}', '$arduinoConnectRetryCount')
            .replaceAll('{max}', '$maxConnectRetry'));
        Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted && !arduinoManager.isConnected) {
            _tryConnectArduino();
          }
        });
      } else {
        showSnackBarMessage(tr('arduino_connect_failed'));
        arduinoConnectRetryCount = 0;
      }
    }
  }

  /// 斷開 Arduino 連接
  void disconnectArduino() {
    sendArduinoFlowoff();
    stopAutoFlowRead();
    arduinoManager.close();
    setState(() {});
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

  /// 取消 STM32 連接驗證超時
  void cancelUrVerificationTimeout() {
    urVerificationTimer?.cancel();
    urVerificationTimer = null;
  }

  /// 啟動 STM32 連接驗證超時計時器
  void startUrVerificationTimeout() {
    cancelUrVerificationTimeout();
    urConnectionVerified = false;

    urVerificationTimer = Timer(Duration(milliseconds: urVerificationTimeoutMs), () {
      if (!urConnectionVerified && urManager.isConnected) {
        urManager.close();
        setState(() {});
        showErrorDialogMessage(tr('stm32_wrong_port'));
      }
    });
  }

  /// 連接 STM32
  void connectUr() {
    if (selectedUrPort == null) {
      showSnackBarMessage(tr('select_stm32_port'));
      return;
    }
    if (selectedUrPort == selectedArduinoPort && arduinoManager.isConnected) {
      showSnackBarMessage(tr('stm32_port_in_use'));
      return;
    }

    urConnectRetryCount = 0;
    _tryConnectUr();
  }

  /// 嘗試連接 STM32（支援自動重試）
  void _tryConnectUr() {
    if (selectedUrPort == null) return;

    if (urManager.open(selectedUrPort!)) {
      setState(() {});
      showSnackBarMessage(tr('stm32_verifying'));
      urConnectRetryCount = 0;

      // 啟動連接驗證超時（2秒內需收到正確回應）
      startUrVerificationTimeout();

      // 連接成功後自動查詢韌體版本（作為 PING）
      Future.delayed(const Duration(milliseconds: 300), () {
        if (urManager.isConnected) {
          final payload = [0x05, 0x00, 0x00, 0x00, 0x00];
          final cmd = URCommandBuilder.buildCommand(payload);
          urManager.sendHex(cmd);
        }
      });
    } else {
      urConnectRetryCount++;
      if (urConnectRetryCount < maxConnectRetry) {
        showSnackBarMessage(tr('stm32_connecting')
            .replaceAll('{current}', '$urConnectRetryCount')
            .replaceAll('{max}', '$maxConnectRetry'));
        Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted && !urManager.isConnected) {
            _tryConnectUr();
          }
        });
      } else {
        showSnackBarMessage(tr('stm32_connect_failed'));
        urConnectRetryCount = 0;
      }
    }
  }

  /// 斷開 STM32 連接
  void disconnectUr() {
    cancelUrVerificationTimeout();
    sendArduinoFlowoff();
    urManager.close();
    setState(() {});
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
