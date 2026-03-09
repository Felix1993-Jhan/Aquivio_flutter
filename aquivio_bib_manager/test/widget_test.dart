// Aquivio BIB Manager 基礎測試

import 'package:flutter_test/flutter_test.dart';
import 'package:aquivio_bib_manager/main.dart';

void main() {
  testWidgets('App 啟動測試', (WidgetTester tester) async {
    // 建立 App 並觸發一幀
    await tester.pumpWidget(const AquivioBibManagerApp());

    // 驗證啟動畫面顯示
    expect(find.text('Aquivio BIB 管理'), findsOneWidget);
    expect(find.text('飲料機原料包管理系統'), findsOneWidget);
  });
}
