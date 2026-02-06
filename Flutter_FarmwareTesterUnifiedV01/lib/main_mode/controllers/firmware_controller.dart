// ============================================================================
// 韌體燒錄控制器 Mixin
// ============================================================================
// 功能說明：
// 將 ST-Link 燒錄流程相關的邏輯從 main.dart 中抽取出來
// 包含燒入並檢測的整合流程
// ============================================================================

import 'package:flutter/material.dart';
import '../services/stlink_programmer_service.dart';
import 'package:flutter_firmware_tester_unified/shared/services/localization_service.dart';

/// 韌體燒錄控制器 Mixin
mixin FirmwareController<T extends StatefulWidget> on State<T> {

  // ===== 必須由使用者實作的抽象成員 =====

  StLinkProgrammerService get stLinkService;

  bool get isProgramming;
  set isProgramming(bool value);

  bool get isAutoDetecting;

  bool get isStLinkConnected;

  String? get selectedFirmwarePath;

  int get stLinkFrequency;

  double get programProgress;
  set programProgress(double value);

  String? get programStatus;
  set programStatus(String? value);

  bool get isUrConnected;

  void showSnackBarMessage(String message);
  void disconnectUrPort();
  void startAutoDetectionProcess();

  // ==================== 燒入並檢測流程 ====================

  /// 開始燒入並檢測流程
  Future<void> startProgramAndDetect() async {
    if (isProgramming || isAutoDetecting) return;
    if (selectedFirmwarePath == null) {
      showSnackBarMessage(tr('please_select_firmware'));
      return;
    }
    if (!isStLinkConnected) {
      showSnackBarMessage(tr('stlink_not_connected'));
      return;
    }

    // 燒入前先斷開 STM32 串口連線
    if (isUrConnected) {
      showSnackBarMessage(tr('disconnecting_stm32_for_program'));
      disconnectUrPort();
      await Future.delayed(const Duration(milliseconds: 300));
    }

    setState(() {
      isProgramming = true;
      programProgress = 0.0;
      programStatus = tr('starting_program');
    });

    try {
      // 設定頻率
      stLinkService.setFrequency(stLinkFrequency);

      // 執行燒入
      final result = await stLinkService.programFirmware(
        firmwarePath: selectedFirmwarePath!,
        verify: true,
        reset: true,
      );

      if (result.success) {
        // 燒入成功，顯示翻譯後的訊息
        String message;
        if (result.messageKey != null) {
          if (result.messageParams != null && result.messageParams!.isNotEmpty) {
            message = trParams(result.messageKey!, result.messageParams!);
          } else {
            message = tr(result.messageKey!);
          }
        } else {
          message = result.message;
        }
        showSnackBarMessage(message);

        // 等待 STM32 啟動完成（STM32 重置後需要約 8 秒啟動時間）
        // 使用倒數計時讓現場人員知道程式正在等待
        // 注意：保持 isProgramming = true 以便進度條繼續顯示
        const int waitSeconds = 8;
        for (int remaining = waitSeconds; remaining > 0; remaining--) {
          setState(() {
            programStatus = trParams('waiting_stm32_startup_countdown', {'seconds': remaining.toString()});
          });
          await Future.delayed(const Duration(seconds: 1));
        }

        // 倒數完成後才關閉燒錄狀態
        setState(() {
          isProgramming = false;
        });

        // 開始自動檢測流程
        startAutoDetectionProcess();
      } else {
        // 燒入失敗，顯示錯誤訊息
        setState(() {
          isProgramming = false;
        });
        String message;
        if (result.messageKey != null) {
          message = tr(result.messageKey!);
        } else {
          message = result.message;
        }
        showSnackBarMessage(message);
      }
    } catch (e) {
      setState(() {
        isProgramming = false;
      });
      showSnackBarMessage('${tr('execution_error')}: $e');
    }
  }
}
