// ============================================================================
// ReportViewPage - App 內檢測報告表格頁（Main + Body&Door 共用）
// ============================================================================
// Excel 式凍結窗格：
// - 上方表頭（編號 + Offset/Arduino/STM32）往下捲時固定在頂端
// - 左側名稱欄（含 Idle/Running/感應 區塊標題）往右捲時固定在左側
// - 右下資料區可雙向捲動，表頭/左欄以連動控制器同步
// 每片一組欄（Offset/Arduino/STM32），重測往下疊；上色沿用檢測規則 + 溫差標紅。
// 本頁「只看不刪」——刪除只能到桌面手動處理。
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_firmware_tester_unified/shared/services/test_report_service.dart';
import 'package:flutter_firmware_tester_unified/shared/services/report_excel_exporter.dart';

/// 一列的描述（左欄與資料區共用同一份序列，確保逐列對齊）
class _RowSpec {
  final String kind; // 'section' | 'channel' | 'scalar' | 'abnormal'
  final String label;
  final int round;
  final int? id;
  final ReportSection? section;
  final ChannelValues? Function(TestSnapshot)? pick;
  final ReportDevice? scalarDevice;
  final String? Function(TestSnapshot)? scalarPick;
  final double height;

  const _RowSpec.section(this.label)
      : kind = 'section',
        round = 0,
        id = null,
        section = null,
        pick = null,
        scalarDevice = null,
        scalarPick = null,
        height = 30;

  const _RowSpec.channel(
      this.label, this.round, this.id, this.section, this.pick)
      : kind = 'channel',
        scalarDevice = null,
        scalarPick = null,
        height = 30;

  const _RowSpec.scalar(
      this.label, this.round, this.scalarDevice, this.scalarPick)
      : kind = 'scalar',
        id = null,
        section = null,
        pick = null,
        height = 30;

  /// 每片各自的「異常」列（跨該片全部子欄合併成一格，可換行）
  const _RowSpec.abnormal(this.round)
      : kind = 'abnormal',
        label = '異常',
        id = null,
        section = null,
        pick = null,
        scalarDevice = null,
        scalarPick = null,
        height = 76;
}

class ReportViewPage extends StatefulWidget {
  final ReportConfig config;
  final List<BoardRecord> boards;
  final CellStatusResolver? statusResolver;
  final Future<void> Function()? onExport;

  /// 依 R_Value 即時反推版本名（讓舊快照也能顯示版本；null 則退回快照存的 versionName）
  final String? Function(int rValue)? versionResolver;

  const ReportViewPage({
    super.key,
    required this.config,
    required this.boards,
    this.statusResolver,
    this.onExport,
    this.versionResolver,
  });

  @override
  State<ReportViewPage> createState() => _ReportViewPageState();
}

class _ReportViewPageState extends State<ReportViewPage> {
  // 資料區雙向捲動；表頭跟著水平、左欄跟著垂直（連動）
  final ScrollController _bodyH = ScrollController();
  final ScrollController _bodyV = ScrollController();
  final ScrollController _headerH = ScrollController();
  final ScrollController _labelV = ScrollController();

  // 目前選取的列（specs 索引）；點任一格整列橫向高亮,再點同列取消
  int? _selectedRow;

  // 選取列強調色（琥珀）
  static const Color _rowHi = Color(0xFFF6A21E);
  static const Color _rowHiBg = Color(0xFFFFF2CC);

  /// 該列是否可被選取（區塊標題 / 異常列不參與）
  bool _selectable(_RowSpec spec) =>
      spec.kind == 'channel' || spec.kind == 'scalar';

  /// 若可選取則包一層點擊（點擊切換選取 / 取消）
  Widget _wrapSelectable(int index, _RowSpec spec, Widget child) {
    if (!_selectable(spec)) return child;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(
          () => _selectedRow = _selectedRow == index ? null : index),
      child: child,
    );
  }

  // 色票（與 Excel 一致）
  static const Color _hwHigh = Color(0xFFF4B183);
  static const Color _hwLow = Color(0xFFBDD7EE);
  static const Color _sensorHigh = Color(0xFFC55A11);
  static const Color _sensorLow = Color(0xFF2E75B6);
  static const Color _sectionBg = Color(0xFF404040);
  static const Color _headerBg = Color(0xFFD9D9D9);
  // STM32 運轉兩段：深藍=首次通過、淺藍(_hwLow)=二次通過、紅=不良
  static const Color _tier1 = Color(0xFF6FA8DC);
  static const Color _fail = Color(0xFFE06666);

  // 尺寸（固定行高以確保四區對齊）
  static const double _labelW = 150;
  static const double _colW = 82;
  static const double _rowH = 30;

  ReportConfig get config => widget.config;
  List<BoardRecord> get boards => widget.boards;

  @override
  void initState() {
    super.initState();
    // 資料區捲動 → 帶動凍結表頭 / 左欄（clamp 夾住捲動範圍，避免因留白越界）
    _bodyH.addListener(() {
      if (!_headerH.hasClients) return;
      final target = _bodyH.offset.clamp(
          _headerH.position.minScrollExtent, _headerH.position.maxScrollExtent);
      if (_headerH.offset != target) _headerH.jumpTo(target);
    });
    _bodyV.addListener(() {
      if (!_labelV.hasClients) return;
      final target = _bodyV.offset.clamp(
          _labelV.position.minScrollExtent, _labelV.position.maxScrollExtent);
      if (_labelV.offset != target) _labelV.jumpTo(target);
    });
  }

  @override
  void dispose() {
    _bodyH.dispose();
    _bodyV.dispose();
    _headerH.dispose();
    _labelV.dispose();
    super.dispose();
  }

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
    if (device == ReportDevice.offset || widget.statusResolver == null) {
      return null;
    }
    final sensor = section == ReportSection.sensor;
    switch (widget.statusResolver!(section, device, id, value)) {
      case CellStatus.normal:
        return null;
      case CellStatus.tier1Pass:
        return _tier1; // 深藍：首次通過
      case CellStatus.tier2Pass:
        return _hwLow; // 淺藍：二次通過
      case CellStatus.fail:
        return _fail; // 紅：不良
      case CellStatus.high:
        return sensor ? _sensorHigh : _hwHigh;
      case CellStatus.low:
        return sensor ? _sensorLow : _hwLow;
    }
  }

  /// 建立所有列的描述（左欄與資料區共用）
  List<_RowSpec> _rowSpecs(int maxRounds) {
    final specs = <_RowSpec>[];
    for (int r = 0; r < maxRounds; r++) {
      if (r > 0) specs.add(_RowSpec.section('重測 $r（同編號往下）'));
      specs.add(_RowSpec.section(
          config.hasRunningState ? '硬體無動作 (Idle)' : '硬體讀值'));
      for (final id in config.hwIds) {
        specs.add(_RowSpec.channel('${config.labels[id] ?? 'ID$id'} (ID$id)', r,
            id, ReportSection.idle, (s) => s.idle[id]));
      }
      if (config.hasRunningState) {
        specs.add(const _RowSpec.section('硬體動作中 (Running)'));
        for (final id in config.hwIds) {
          specs.add(_RowSpec.channel('${config.labels[id] ?? 'ID$id'} (ID$id)', r,
              id, ReportSection.running, (s) => s.running[id]));
        }
      }
      specs.add(const _RowSpec.section('感應偵測'));
      for (final id in config.sensorIds) {
        specs.add(_RowSpec.channel('${config.labels[id] ?? 'ID$id'} (ID$id)', r,
            id, ReportSection.sensor, (s) => s.sensor[id]));
      }
      if (config.hasResistance) {
        specs.add(_RowSpec.scalar(
            'R_Value', r, ReportDevice.stm32, (s) => s.rValue?.toString()));
      }
      if (config.hasOffset) {
        specs.add(_RowSpec.scalar('offset_平均', r, ReportDevice.offset,
            (s) => s.offsetAvg?.toStringAsFixed(1)));
      }
      // 每輪結尾：各片自己的「異常」列
      specs.add(_RowSpec.abnormal(r));
    }
    return specs;
  }

  @override
  Widget build(BuildContext context) {
    final sub = _subCols;
    final maxRounds = boards.fold<int>(
        0, (m, b) => b.rounds.length > m ? b.rounds.length : m);
    final specs = _rowSpecs(maxRounds);
    final headerH = _rowH * 2; // 編號列 + 子欄列

    return Scaffold(
      appBar: AppBar(
        title: Text('檢測報告（${config.modeName}）'),
        actions: [
          if (widget.onExport != null)
            IconButton(
              icon: const Icon(Icons.file_download),
              tooltip: '匯出到桌面',
              onPressed: () => widget.onExport!(),
            ),
        ],
      ),
      body: boards.isEmpty
          ? const Center(child: Text('尚無檢測資料'))
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ===== 上方：凍結角 + 凍結表頭 =====
                SizedBox(
                  height: headerH,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _cornerCell(headerH),
                      Expanded(
                        child: SingleChildScrollView(
                          controller: _headerH,
                          scrollDirection: Axis.horizontal,
                          physics: const NeverScrollableScrollPhysics(),
                          // 與資料區右側 18px 留白對齊，避免捲到最右錯位
                          child: Padding(
                            padding: const EdgeInsets.only(right: 18),
                            child: _columnHeaders(sub),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                // ===== 下方：凍結左欄 + 資料區 =====
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 凍結左欄（垂直連動、使用者不可直接捲）
                      SizedBox(
                        width: _labelW,
                        child: SingleChildScrollView(
                          controller: _labelV,
                          scrollDirection: Axis.vertical,
                          physics: const NeverScrollableScrollPhysics(),
                          // 與資料區底部 18px 留白對齊，避免捲到最底錯位
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: 18),
                            child: _labelColumn(specs),
                          ),
                        ),
                      ),
                      // 資料區：雙向捲動 + 明顯捲軸
                      // 用 LayoutBuilder 取得可視寬/高，強制內容至少填滿視窗，
                      // 讓捲動視圖填滿 → 垂直捲軸貼視窗最右、水平捲軸貼最底
                      Expanded(
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final minW = constraints.maxWidth;
                            final minH = constraints.maxHeight;
                            return RawScrollbar(
                              controller: _bodyV,
                              thumbVisibility: true,
                              thickness: 14,
                              radius: const Radius.circular(7),
                              thumbColor: Colors.blueGrey.shade500,
                              child: RawScrollbar(
                                controller: _bodyH,
                                thumbVisibility: true,
                                thickness: 14,
                                radius: const Radius.circular(7),
                                thumbColor: Colors.blueGrey.shade500,
                                notificationPredicate: (n) => n.depth == 1,
                                child: SingleChildScrollView(
                                  controller: _bodyV,
                                  scrollDirection: Axis.vertical,
                                  child: SingleChildScrollView(
                                    controller: _bodyH,
                                    scrollDirection: Axis.horizontal,
                                    child: ConstrainedBox(
                                      constraints: BoxConstraints(
                                          minWidth: minW, minHeight: minH),
                                      child: Padding(
                                        padding: const EdgeInsets.only(
                                            right: 18, bottom: 18),
                                        child: _dataGrid(sub, specs),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  // ==================== 凍結角 ====================
  Widget _cornerCell(double height) => _cell('名稱', _labelW,
      height: height, bg: _headerBg, bold: true, thickRight: true, thickBottom: true);

  // ==================== 凍結表頭（2 列）====================
  Widget _columnHeaders(List<ReportDevice> sub) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 編號列（編號 + 其右側跨欄顯示「韌體版本:xxx」）
        _rowWidget([
          for (final b in boards) ...[
            _cell(b.serial, _colW,
                bg: _headerBg, bold: true, thickRight: sub.length == 1),
            if (sub.length > 1)
              _cell(_versionText(b), _colW * (sub.length - 1),
                  bg: _headerBg, bold: true, thickRight: true),
          ],
        ]),
        // 子欄列
        _rowWidget([
          for (int i = 0; i < boards.length; i++)
            for (int s = 0; s < sub.length; s++)
              _cell(_subLabel(sub[s]), _colW,
                  bg: _headerBg,
                  bold: true,
                  thickRight: s == sub.length - 1,
                  thickBottom: true),
        ]),
      ],
    );
  }

  /// 該片的版本標籤。優先用 R_Value 即時反推（舊快照也能顯示）,
  /// 反推不到才退回快照擷取當下存的 versionName。
  String _versionText(BoardRecord b) {
    for (final r in b.rounds) {
      final v = (r.rValue != null ? widget.versionResolver?.call(r.rValue!) : null) ??
          r.versionName;
      if (v != null && v.isNotEmpty) return '韌體版本:$v';
    }
    return '';
  }

  // ==================== 凍結左欄 ====================
  Widget _labelColumn(List<_RowSpec> specs) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (int i = 0; i < specs.length; i++)
          _wrapSelectable(
            i,
            specs[i],
            specs[i].kind == 'section'
                ? _cell(specs[i].label, _labelW,
                    height: specs[i].height,
                    bg: _sectionBg,
                    bold: true,
                    white: true,
                    thickRight: true)
                : _cell(specs[i].label, _labelW,
                    height: specs[i].height,
                    bold: true,
                    thickRight: true,
                    highlight: _selectedRow == i),
          ),
      ],
    );
  }

  // ==================== 資料區 ====================
  Widget _dataGrid(List<ReportDevice> sub, List<_RowSpec> specs) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (int i = 0; i < specs.length; i++)
          _wrapSelectable(i, specs[i], _dataRow(specs[i], sub, _selectedRow == i)),
      ],
    );
  }

  Widget _dataRow(_RowSpec spec, List<ReportDevice> sub, bool hi) {
    if (spec.kind == 'section') {
      return _rowWidget([
        for (int i = 0; i < boards.length; i++)
          for (int s = 0; s < sub.length; s++)
            _cell('', _colW,
                height: spec.height, bg: _sectionBg, thickRight: s == sub.length - 1),
      ]);
    }

    // 異常列：每片將全部子欄合併成一格，列出該片這輪的異常項目
    if (spec.kind == 'abnormal') {
      return _rowWidget([
        for (final b in boards)
          _abnormalCell(
            spec.round < b.rounds.length ? b.rounds[spec.round] : null,
            _colW * sub.length,
          ),
      ]);
    }

    final cells = <Widget>[];
    for (final b in boards) {
      final snap = spec.round < b.rounds.length ? b.rounds[spec.round] : null;
      for (int s = 0; s < sub.length; s++) {
        final d = sub[s];
        final last = s == sub.length - 1;

        if (spec.kind == 'scalar') {
          final text = snap != null && d == spec.scalarDevice
              ? spec.scalarPick!(snap)
              : null;
          cells.add(_cell(text ?? '', _colW, thickRight: last, highlight: hi));
          continue;
        }

        // channel
        final id = spec.id!;
        final section = spec.section!;
        if (section == ReportSection.sensor && d == ReportDevice.offset) {
          cells.add(_cell('', _colW, thickRight: last, highlight: hi));
          continue;
        }
        final values = snap == null ? null : spec.pick!(snap);
        final v = values == null ? null : _valueOf(values, d);
        Color? bg = v == null ? null : _bg(section, d, id, v);
        if (section == ReportSection.sensor &&
            d == ReportDevice.stm32 &&
            snap != null &&
            snap.tempDiffErrorIds.contains(id)) {
          bg = _sensorHigh; // 溫差過大 → 強制標紅
        }
        cells.add(_cell(v?.toString() ?? '', _colW,
            bg: bg, thickRight: last, highlight: hi));
      }
    }
    return _rowWidget(cells);
  }

  /// 異常格：該片這輪的異常項目（合併子欄寬、可換行）
  /// 值類別（Idle/Running/感測）即時重算 → 與格子顏色永遠一致,改閾值不必重測。
  Widget _abnormalCell(TestSnapshot? snap, double width) {
    final items = snap == null
        ? const <String>[]
        : computeLiveAbnormals(config, snap, widget.statusResolver);
    final bool ok = snap != null && items.isEmpty;
    final String text = snap == null
        ? ''
        : (ok ? '正常' : items.join('\n'));
    final Color color = snap == null
        ? Colors.black87
        : (ok ? const Color(0xFF2E7D32) : const Color(0xFFC00000));
    return Container(
      width: width,
      height: 76,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      alignment: ok ? Alignment.center : Alignment.topLeft,
      decoration: BoxDecoration(
        color: snap == null
            ? null
            : (ok ? const Color(0x1A2E7D32) : const Color(0x14C00000)),
        border: Border(
          right: BorderSide(color: Colors.blueGrey.shade700, width: 2.5),
          bottom: BorderSide(color: Colors.blueGrey.shade700, width: 2.5),
        ),
      ),
      child: SingleChildScrollView(
        child: Text(
          text,
          style: TextStyle(
            fontSize: 10,
            height: 1.25,
            fontWeight: ok ? FontWeight.bold : FontWeight.w500,
            color: color,
          ),
        ),
      ),
    );
  }

  // ==================== 共用 ====================
  Widget _rowWidget(List<Widget> cells) =>
      Row(mainAxisSize: MainAxisSize.min, children: cells);

  Widget _cell(String text, double width,
      {double height = _rowH,
      Color? bg,
      bool bold = false,
      bool white = false,
      bool thickRight = false,
      bool thickBottom = false,
      bool highlight = false}) {
    return Container(
      width: width,
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        // 選取列：無底色的格子鋪淡琥珀；有資料色的格子保留原色（另以上下框標示）
        color: highlight && bg == null ? _rowHiBg : bg,
        border: Border(
          top: highlight
              ? const BorderSide(color: _rowHi, width: 2.5)
              : BorderSide.none,
          right: BorderSide(
            color: thickRight ? Colors.blueGrey.shade700 : Colors.grey.shade300,
            width: thickRight ? 2.5 : 0.5,
          ),
          bottom: highlight
              ? const BorderSide(color: _rowHi, width: 2.5)
              : BorderSide(
                  color:
                      thickBottom ? Colors.blueGrey.shade700 : Colors.grey.shade300,
                  width: thickBottom ? 2.5 : 0.5,
                ),
        ),
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 11,
          fontWeight: (bold || highlight) ? FontWeight.bold : FontWeight.normal,
          color: white ? Colors.white : Colors.black87,
        ),
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}
