// ============================================================================
// 串口控制器 Mixin
// ============================================================================
// 功能說明：
// 將 Arduino 串口操作相關的邏輯從 main.dart 中抽取出來
// 包含連接、斷開、發送指令等功能
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_firmware_tester_unified/shared/services/serial_port_manager.dart';
import 'package:flutter_firmware_tester_unified/shared/services/arduino_connection_service.dart';
import 'package:flutter_firmware_tester_unified/shared/services/port_filter_service.dart';
import 'package:flutter_firmware_tester_unified/shared/services/localization_service.dart';

/// 串口控制器 Mixin
mixin SerialController<T extends StatefulWidget> on State<T> {

  // ===== 必須由使用者實作的抽象成員 =====

  SerialPortManager get arduinoManager;

  String? get selectedArduinoPort;
  set selectedArduinoPort(String? value);

  /// 可用的 COM 埠列表（供自動掃描使用）
  List<String> get availablePorts;

  int get arduinoConnectRetryCount;
  set arduinoConnectRetryCount(int value);

  void showSnackBarMessage(String message);
  void showErrorDialogMessage(String message);

  /// 當偵測到錯誤模式時呼叫（顯示切換模式對話框）
  void onWrongModeDetected(String portName);

  // ==================== Arduino 操作 ====================

  /// 連接 Arduino（自動掃描所有 COM 埠尋找正確的 Arduino）
  ///
  /// 此方法會自動掃描所有可用的 COM 埠，找到正確模式的 Arduino 後連線。
  /// 與自動偵測使用相同的邏輯，不需要預先選擇 COM 埠。
  /// 會自動排除 ST-Link VCP 埠口。
  Future<void> connectArduino() async {
    // 取得可用埠口（排除 ST-Link）
    final filteredPorts = PortFilterService.getAvailablePorts(excludeStLink: true);

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
          return;  // 連線成功，結束掃描

        case ConnectResult.wrongMode:
          // 偵測到 Main Arduino，顯示切換對話框
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
    arduinoManager.close();
    if (mounted) setState(() {});
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
