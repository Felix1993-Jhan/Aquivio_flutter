// ============================================================================
// 串口控制器 Mixin
// ============================================================================
// 功能說明：
// 將 Arduino 串口操作相關的邏輯從 main.dart 中抽取出來
// 包含連接、斷開、發送指令等功能
// ============================================================================

import 'package:flutter/material.dart';
import '../services/serial_port_manager.dart';
import '../services/localization_service.dart';

/// 串口控制器 Mixin
mixin SerialController<T extends StatefulWidget> on State<T> {

  // ===== 必須由使用者實作的抽象成員 =====

  SerialPortManager get arduinoManager;

  String? get selectedArduinoPort;
  set selectedArduinoPort(String? value);

  int get arduinoConnectRetryCount;
  set arduinoConnectRetryCount(int value);

  void showSnackBarMessage(String message);
  void showErrorDialogMessage(String message);

  // ==================== 常數 ====================

  /// 連接重試最大次數
  static const int maxConnectRetry = 6;

  // ==================== Arduino 操作 ====================

  /// 連接 Arduino
  void connectArduino() {
    if (selectedArduinoPort == null) {
      showSnackBarMessage(tr('select_arduino_port'));
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
    arduinoManager.close();
    setState(() {});
    showSnackBarMessage(tr('arduino_disconnected'));
  }

  /// 發送指令到 Arduino
  void sendArduinoCommand(String command) {
    if (!arduinoManager.isConnected) {
      showSnackBarMessage(tr('connect_arduino_first'));
      return;
    }
    arduinoManager.sendString(command);
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
}
