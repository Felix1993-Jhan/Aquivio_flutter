// ============================================================================
// UI 對話框元件
// ============================================================================
// 功能說明：
// 將對話框相關的 UI 元件從 main.dart 中抽取出來
// 包含錯誤對話框、測試結果對話框等
// ============================================================================

import 'package:flutter/material.dart';
import '../services/localization_service.dart';

/// 顯示錯誤提示對話框（畫面中央，2秒後自動關閉）
void showErrorDialog(BuildContext context, String message) {
  showDialog(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.black54,
    builder: (BuildContext dialogContext) {
      // 2秒後自動關閉
      Future.delayed(const Duration(seconds: 2), () {
        if (Navigator.of(dialogContext).canPop()) {
          Navigator.of(dialogContext).pop();
        }
      });

      return AlertDialog(
        backgroundColor: Colors.red.shade50,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: Colors.red.shade400, width: 2),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, color: Colors.red.shade700, size: 64),
            const SizedBox(height: 16),
            Text(
              message,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.red.shade800,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    },
  );
}

/// 顯示測試結果對話框
/// 三欄顯示：左邊 Idle、中間 Running、右邊感測器
void showTestResultDialog(
  BuildContext context, {
  required bool passed,
  required List<String> failedIdleItems,
  required List<String> failedRunningItems,
  required List<String> failedSensorItems,
}) {
  showDialog(
    context: context,
    barrierDismissible: true,
    builder: (BuildContext dialogContext) {
      return AlertDialog(
        backgroundColor: passed ? Colors.green.shade50 : Colors.red.shade50,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: passed ? Colors.green.shade400 : Colors.red.shade400,
            width: 2,
          ),
        ),
        title: Row(
          children: [
            Icon(
              passed ? Icons.check_circle : Icons.error,
              color: passed ? Colors.green : Colors.red,
              size: 32,
            ),
            const SizedBox(width: 12),
            Text(
              passed ? tr('test_result_pass') : tr('test_result_fail'),
              style: TextStyle(
                color: passed ? Colors.green.shade800 : Colors.red.shade800,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        content: passed
            ? Text(
                tr('test_all_passed'),
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.green.shade700,
                ),
              )
            : SizedBox(
                width: 600,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tr('test_failed_items'),
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.red.shade800,
                      ),
                    ),
                    const SizedBox(height: 12),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 250),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: _FailedColumn(
                              title: 'Idle',
                              items: failedIdleItems,
                              color: Colors.orange,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _FailedColumn(
                              title: 'Running',
                              items: failedRunningItems,
                              color: Colors.red,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _FailedColumn(
                              title: tr('sensor'),
                              items: failedSensorItems,
                              color: Colors.purple,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(
              tr('confirm'),
              style: TextStyle(
                color: passed ? Colors.green.shade700 : Colors.red.shade700,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      );
    },
  );
}

/// 異常項目欄位 Widget
class _FailedColumn extends StatelessWidget {
  final String title;
  final List<String> items;
  final Color color;

  const _FailedColumn({
    required this.title,
    required this.items,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: color.withValues(alpha: 0.3)),
        borderRadius: BorderRadius.circular(8),
        color: color.withValues(alpha: 0.05),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 標題
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 6),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(7),
                topRight: Radius.circular(7),
              ),
            ),
            child: Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: Color.lerp(color, Colors.black, 0.3),
              ),
            ),
          ),
          // 項目列表
          if (items.isEmpty)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.check_circle, color: Colors.green, size: 16),
                  const SizedBox(width: 4),
                  Text(
                    'OK',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.green.shade700,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            )
          else
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: items.map((item) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.warning, color: color, size: 14),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            item,
                            style: TextStyle(
                              fontSize: 11,
                              color: Color.lerp(color, Colors.black, 0.4),
                            ),
                          ),
                        ),
                      ],
                    ),
                  )).toList(),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
