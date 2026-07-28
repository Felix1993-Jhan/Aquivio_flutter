import 'dart:convert';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_firmware_tester_unified/shared/services/report_excel_exporter.dart';
import 'package:flutter_firmware_tester_unified/shared/services/test_report_service.dart';

void main() {
  test('匯出的 xlsx 每個 worksheet 都注入凍結窗格，且 zip 仍可解析', () {
    final exporter = ReportExcelExporter(config: ReportConfig.main());
    final board = BoardRecord('T001');
    board.rounds.add(TestSnapshot(
      idle: const {},
      running: const {},
      sensor: const {},
      rValue: 157,
      offsetAvg: null,
      tempDiffErrorIds: const {},
      time: DateTime(2026, 1, 1),
    ));

    final bytes = exporter.buildBytes([board]);
    expect(bytes, isNotEmpty);

    final archive = ZipDecoder().decodeBytes(bytes);
    final sheets = archive.files
        .where((f) =>
            f.name.startsWith('xl/worksheets/sheet') && f.name.endsWith('.xml'))
        .toList();
    expect(sheets, isNotEmpty);

    for (final s in sheets) {
      final xml = utf8.decode(s.content as List<int>);
      expect(xml.contains('state="frozen"'), true, reason: '${s.name} 缺 frozen');
      expect(xml.contains('ySplit="2"'), true, reason: '${s.name} 缺 ySplit');
      expect(xml.contains('xSplit="1"'), true, reason: '${s.name} 缺 xSplit');
    }
  });
}
