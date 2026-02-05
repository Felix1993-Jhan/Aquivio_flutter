// 基本 Widget 測試（統一韌體測試器）

import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_firmware_tester_unified/main.dart';

void main() {
  testWidgets('應用程式啟動測試', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());
    // 驗證應用程式正常啟動
    expect(find.text('Aquivio Firmware Tester Unified'), findsOneWidget);
  });
}
