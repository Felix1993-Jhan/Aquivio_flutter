// ============================================================================
// ReportViewPage - App 內檢測報告表格頁（Main + Body&Door 共用）
// ============================================================================
// 以與 Excel 相同的版面呈現累積的檢測結果：
// 每片一組欄（Offset/Arduino/STM32），上下分 Idle / Running / 感應區，
// 重測往下疊。上色沿用檢測規則（statusResolver）。
// 本頁「只看不刪」——刪除只能到桌面手動處理。
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_firmware_tester_unified/shared/services/test_report_service.dart';
import 'package:flutter_firmware_tester_unified/shared/services/report_excel_exporter.dart';

class ReportViewPage extends StatelessWidget {
  final ReportConfig config;
  final List<BoardRecord> boards;
  final CellStatusResolver? statusResolver;

  /// 手動匯出回調（可選）
  final Future<void> Function()? onExport;

  const ReportViewPage({
    super.key,
    required this.config,
    required this.boards,
    this.statusResolver,
    this.onExport,
  });

  // 色票（與 Excel 一致）
  static const Color _hwHigh = Color(0xFFF4B183);
  static const Color _hwLow = Color(0xFFBDD7EE);
  static const Color _sensorHigh = Color(0xFFC55A11);
  static const Color _sensorLow = Color(0xFF2E75B6);
  static const Color _sectionBg = Color(0xFF404040);
  static const Color _headerBg = Color(0xFFD9D9D9);

  List<ReportDevice> get _subCols {
    final cols = <ReportDevice>[];
    if (config.hasOffset) cols.add(ReportDevice.offset);
    cols.add(ReportDevice.arduino);
    if (config.hasStm32) cols.add(ReportDevice.stm32);
    return cols;
  }

  String _subLabel(ReportDevice d) => d == ReportDevice.offset
      ? 'Offset'
      : d == ReportDevice.arduino
          ? 'Arduino'
          : 'STM32';

  int? _valueOf(ChannelValues v, ReportDevice d) => d == ReportDevice.offset
      ? v.offset
      : d == ReportDevice.arduino
          ? v.arduino
          : v.stm32;

  Color? _bg(ReportSection section, ReportDevice device, int id, int value) {
    if (device == ReportDevice.offset || statusResolver == null) return null;
    final s = statusResolver!(section, device, id, value);
    if (s == CellStatus.normal) return null;
    final sensor = section == ReportSection.sensor;
    if (s == CellStatus.high) return sensor ? _sensorHigh : _hwHigh;
    return sensor ? _sensorLow : _hwLow;
  }

  @override
  Widget build(BuildContext context) {
    final sub = _subCols;
    final maxRounds = boards.fold<int>(
        0, (m, b) => b.rounds.length > m ? b.rounds.length : m);

    return Scaffold(
      appBar: AppBar(
        title: Text('檢測報告（${config.modeName}）'),
        actions: [
          if (onExport != null)
            IconButton(
              icon: const Icon(Icons.file_download),
              tooltip: '匯出到桌面',
              onPressed: () => onExport!(),
            ),
        ],
      ),
      body: boards.isEmpty
          ? const Center(child: Text('尚無檢測資料'))
          : SingleChildScrollView(
              scrollDirection: Axis.vertical,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: _buildTable(sub, maxRounds),
              ),
            ),
    );
  }

  Widget _buildTable(List<ReportDevice> sub, int maxRounds) {
    final rows = <TableRow>[];

    // 表頭：編號列
    rows.add(_row([
      _cell('名稱', bg: _headerBg, bold: true),
      for (final b in boards)
        ...List.generate(
          sub.length,
          (s) => _cell(s == 0 ? b.serial : '', bg: _headerBg, bold: true),
        ),
    ]));
    // 子欄列
    rows.add(_row([
      _cell('', bg: _headerBg),
      for (int i = 0; i < boards.length; i++)
        for (final d in sub) _cell(_subLabel(d), bg: _headerBg, bold: true),
    ]));

    for (int r = 0; r < maxRounds; r++) {
      if (r > 0) {
        rows.add(_sectionRow('重測 $r（同編號往下）', sub));
      }
      _addRound(rows, r, sub);
    }

    return Table(
      defaultColumnWidth: const FixedColumnWidth(72),
      columnWidths: const {0: FixedColumnWidth(120)},
      border: TableBorder.all(color: Colors.grey.shade300),
      children: rows,
    );
  }

  void _addRound(List<TableRow> rows, int round, List<ReportDevice> sub) {
    rows.add(_sectionRow('硬體無動作 (Idle)', sub));
    for (final id in config.hwIds) {
      rows.add(_channelRow(id, round, sub, ReportSection.idle, (s) => s.idle[id]));
    }
    rows.add(_sectionRow('硬體動作中 (Running)', sub));
    for (final id in config.hwIds) {
      rows.add(
          _channelRow(id, round, sub, ReportSection.running, (s) => s.running[id]));
    }
    rows.add(_sectionRow('感應偵測', sub));
    for (final id in config.sensorIds) {
      rows.add(
          _channelRow(id, round, sub, ReportSection.sensor, (s) => s.sensor[id]));
    }
    if (config.hasResistance) {
      rows.add(_scalarRow('R_Value', round, sub, ReportDevice.stm32,
          (s) => s.rValue?.toString()));
    }
    if (config.hasOffset) {
      rows.add(_scalarRow('offset_平均', round, sub, ReportDevice.offset,
          (s) => s.offsetAvg?.toStringAsFixed(1)));
    }
  }

  TableRow _channelRow(int id, int round, List<ReportDevice> sub,
      ReportSection section, ChannelValues? Function(TestSnapshot) pick) {
    final label = config.labels[id] ?? 'ID$id';
    final cells = <Widget>[_cell('$label (ID$id)', bold: true)];
    for (final b in boards) {
      final snap = round < b.rounds.length ? b.rounds[round] : null;
      final values = snap == null ? null : pick(snap);
      for (final d in sub) {
        if (section == ReportSection.sensor && d == ReportDevice.offset) {
          cells.add(_cell(''));
          continue;
        }
        final v = values == null ? null : _valueOf(values, d);
        cells.add(_cell(v?.toString() ?? '',
            bg: v == null ? null : _bg(section, d, id, v)));
      }
    }
    return _row(cells);
  }

  TableRow _scalarRow(String label, int round, List<ReportDevice> sub,
      ReportDevice targetDevice, String? Function(TestSnapshot) pick) {
    final cells = <Widget>[_cell(label, bold: true)];
    for (final b in boards) {
      final snap = round < b.rounds.length ? b.rounds[round] : null;
      final text = snap == null ? null : pick(snap);
      for (final d in sub) {
        cells.add(_cell(d == targetDevice ? (text ?? '') : ''));
      }
    }
    return _row(cells);
  }

  TableRow _sectionRow(String title, List<ReportDevice> sub) {
    final total = 1 + boards.length * sub.length;
    return _row([
      _cell(title, bg: _sectionBg, bold: true, white: true),
      for (int i = 1; i < total; i++) _cell('', bg: _sectionBg),
    ]);
  }

  TableRow _row(List<Widget> cells) => TableRow(children: cells);

  Widget _cell(String text,
      {Color? bg, bool bold = false, bool white = false}) {
    return Container(
      color: bg,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      alignment: Alignment.center,
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: bold ? FontWeight.bold : FontWeight.normal,
          color: white ? Colors.white : Colors.black87,
        ),
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}
