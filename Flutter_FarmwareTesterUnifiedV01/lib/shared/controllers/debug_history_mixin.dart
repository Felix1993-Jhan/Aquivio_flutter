// ============================================================================
// DebugHistoryMixin - 調試訊息歷史記錄 Mixin
// ============================================================================
// 功能：管理自動偵測流程中的調試訊息歷史
// - 訊息歷史記錄與瀏覽（上一則/下一則）
// - 暫停機制支援（_waitIfPaused, _debugDelay）
// - 被 Main 和 BodyDoor 的 AutoDetectionController 共用
// ============================================================================

import 'package:flutter/material.dart';

/// 調試歷史記錄 Mixin
/// 使用類別需要實作抽象的 getter 和 setter
mixin DebugHistoryMixin<T extends StatefulWidget> on State<T> {

  // ===== 必須由使用者實作的抽象成員 =====

  /// 是否處於慢速調試模式
  bool get isSlowDebugMode;

  /// 設定當前調試訊息
  void setDebugMessage(String message);

  /// 設定調試歷史狀態（目前索引, 總數）
  void setDebugHistoryState(int index, int total);

  /// 是否處於暫停狀態
  bool get isDebugPaused;

  /// 設定暫停狀態
  void setDebugPaused(bool paused);

  /// 是否已取消自動偵測（用於中斷等待迴圈）
  bool get isAutoDetectionCancelled;

  // ==================== 調試訊息歷史記錄 ====================

  /// 調試訊息歷史記錄
  final List<String> _debugHistory = [];

  /// 目前顯示的歷史索引
  int _debugHistoryIndex = 0;

  /// 添加調試訊息到歷史記錄
  void addDebugHistory(String message) {
    _debugHistory.add(message);
    _debugHistoryIndex = _debugHistory.length - 1;
    setDebugMessage(message);
    setDebugHistoryState(_debugHistoryIndex + 1, _debugHistory.length);
  }

  /// 查看上一條調試訊息
  void debugHistoryPrev() {
    if (_debugHistory.isEmpty) return;
    if (_debugHistoryIndex > 0) {
      _debugHistoryIndex--;
      setDebugMessage(_debugHistory[_debugHistoryIndex]);
      setDebugHistoryState(_debugHistoryIndex + 1, _debugHistory.length);
    }
  }

  /// 查看下一條調試訊息
  void debugHistoryNext() {
    if (_debugHistory.isEmpty) return;
    if (_debugHistoryIndex < _debugHistory.length - 1) {
      _debugHistoryIndex++;
      setDebugMessage(_debugHistory[_debugHistoryIndex]);
      setDebugHistoryState(_debugHistoryIndex + 1, _debugHistory.length);
    }
  }

  /// 清除調試歷史
  void clearDebugHistory() {
    _debugHistory.clear();
    _debugHistoryIndex = 0;
    setDebugHistoryState(0, 0);
  }

  // ==================== 暫停機制 ====================

  /// 等待暫停解除（在暫停狀態時持續等待）
  Future<void> waitIfPaused() async {
    while (isDebugPaused && !isAutoDetectionCancelled) {
      await Future.delayed(const Duration(milliseconds: 100));
    }
  }

  /// 調試模式延遲（包含暫停檢查）
  Future<void> debugDelay(Duration duration) async {
    // 先檢查是否暫停
    await waitIfPaused();
    if (isAutoDetectionCancelled) return;

    // 將延遲時間分成小段，每段檢查暫停狀態
    final endTime = DateTime.now().add(duration);
    while (DateTime.now().isBefore(endTime) && !isAutoDetectionCancelled) {
      await Future.delayed(const Duration(milliseconds: 100));
      // 如果被暫停，等待解除後繼續計時
      await waitIfPaused();
    }
  }
}
