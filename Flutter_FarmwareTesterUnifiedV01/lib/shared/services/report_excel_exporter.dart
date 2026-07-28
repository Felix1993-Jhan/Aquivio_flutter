// ============================================================================
// ReportExcelExporter - 檢測報告 Excel 匯出器（Main + Body&Door 共用）
// ============================================================================
// 版面 A：每片一組欄（Offset/Arduino/STM32），整張表上下分
//         Idle 區 / Running 區 / 感應區；下一片往右、重測往下疊。
// 每 50 片自動新開一個分頁。上色由外部傳入的 statusResolver 決定
// （超 max = 紅、低 min = 藍；硬體區用淡色、感應區用深色）。
//
// 輸出路徑：<桌面>/檢測報告/<modeName>/<yyyy-MM-dd>/<prefix>_HHmm_HHmm.xlsx
// ============================================================================

import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:excel/excel.dart';
import 'package:flutter_firmware_tester_unified/shared/services/test_report_service.dart';

/// 報告區塊
enum ReportSection { idle, running, sensor }

/// 報告欄位（子欄）
enum ReportDevice { offset, arduino, stm32 }

/// 儲存格狀態（決定上色）
/// - normal / high / low：一般範圍判定（低=藍、高=紅）
/// - tier1Pass / tier2Pass / fail：STM32 運轉兩段判定（深藍 / 淺藍 / 紅）
enum CellStatus { normal, high, low, tier1Pass, tier2Pass, fail }

/// 儲存格狀態判定器：(區塊, 欄位, ID, 值) → 正常 / 偏高 / 偏低
typedef CellStatusResolver = CellStatus Function(
  ReportSection section,
  ReportDevice device,
  int id,
  int value,
);

/// 依「目前」判定規則即時算出一片這輪的異常項目。
/// - Idle / Running / 感測：用與儲存格上色同一套 resolver 即時重算 →
///   改閾值後不必重測,異常列與格子顏色永遠一致。
/// - 溫差：沿用快照的 tempDiffErrorIds（與格子的溫差標紅同源）。
/// - 短路 / 診斷：報告無數值欄、無法重算 → 沿用檢測當下擷取的 snapshot.abnormalItems。
List<String> computeLiveAbnormals(
  ReportConfig config,
  TestSnapshot snap,
  CellStatusResolver? resolver,
) {
  final items = <String>[];
  String label(int id) => '${config.labels[id] ?? 'ID$id'} (ID$id)';

  bool isBad(ReportSection sec, ReportDevice dev, int id, int? v) {
    if (v == null || resolver == null) return false;
    switch (resolver(sec, dev, id, v)) {
      case CellStatus.high:
      case CellStatus.low:
      case CellStatus.fail:
        return true;
      case CellStatus.normal:
      case CellStatus.tier1Pass:
      case CellStatus.tier2Pass:
        return false;
    }
  }

  // Idle
  for (final id in config.hwIds) {
    final cv = snap.idle[id];
    if (cv == null) continue;
    if (isBad(ReportSection.idle, ReportDevice.arduino, id, cv.arduino) ||
        (config.hasStm32 &&
            isBad(ReportSection.idle, ReportDevice.stm32, id, cv.stm32))) {
      items.add('Idle:${label(id)}');
    }
  }
  // Running
  for (final id in config.hwIds) {
    final cv = snap.running[id];
    if (cv == null) continue;
    if (isBad(ReportSection.running, ReportDevice.arduino, id, cv.arduino) ||
        (config.hasStm32 &&
            isBad(ReportSection.running, ReportDevice.stm32, id, cv.stm32))) {
      items.add('Running:${label(id)}');
    }
  }
  // 感測（含溫差標紅）
  for (final id in config.sensorIds) {
    final cv = snap.sensor[id];
    final bad = cv != null &&
        (isBad(ReportSection.sensor, ReportDevice.arduino, id, cv.arduino) ||
            (config.hasStm32 &&
                isBad(ReportSection.sensor, ReportDevice.stm32, id, cv.stm32)));
    if (bad || snap.tempDiffErrorIds.contains(id)) {
      items.add('感測:${label(id)}');
    }
  }
  // 短路 / 診斷：無法重算,沿用檢測當下擷取的值
  for (final s in (snap.abnormalItems ?? const <String>[])) {
    if (s.startsWith('短路:') || s.startsWith('診斷:')) items.add(s);
  }
  return items;
}

class ReportExcelExporter {
  final ReportConfig config;
  final CellStatusResolver? statusResolver;

  /// 依 R_Value 即時反推版本名（讓舊快照也能顯示版本；null 則退回快照存的 versionName）
  final String? Function(int rValue)? versionResolver;

  /// 每個分頁最多幾片
  static const int boardsPerSheet = 50;

  ReportExcelExporter(
      {required this.config, this.statusResolver, this.versionResolver});

  // ==================== 色票（ARGB Hex）====================
  static const String _hwHigh = '#F4B183'; // 硬體偏高：淡橘紅
  static const String _hwLow = '#BDD7EE'; // 硬體偏低：淡藍
  static const String _sensorHigh = '#C55A11'; // 感應偏高：深橘紅
  static const String _sensorLow = '#2E75B6'; // 感應偏低：深藍
  static const String _headerBg = '#D9D9D9'; // 標題列：灰
  static const String _sectionBg = '#404040'; // 區塊分隔：深灰
  // STM32 運轉兩段：深藍=首次通過、淺藍(_hwLow)=二次通過、紅=不良
  static const String _tier1 = '#6FA8DC';
  static const String _fail = '#E06666';

  /// 子欄清單（依模式決定）
  List<ReportDevice> get _subCols {
    final cols = <ReportDevice>[];
    if (config.hasOffset) cols.add(ReportDevice.offset);
    cols.add(ReportDevice.arduino);
    if (config.hasStm32) cols.add(ReportDevice.stm32);
    return cols;
  }

  String _subLabel(ReportDevice d) {
    switch (d) {
      case ReportDevice.offset:
        return 'Offset';
      case ReportDevice.arduino:
        return 'Arduino';
      case ReportDevice.stm32:
        return 'STM32';
    }
  }

  int? _valueOf(ChannelValues v, ReportDevice d) {
    switch (d) {
      case ReportDevice.offset:
        return v.offset;
      case ReportDevice.arduino:
        return v.arduino;
      case ReportDevice.stm32:
        return v.stm32;
    }
  }

  // ==================== 對外主方法 ====================

  /// 匯出到桌面，回傳寫出的檔案完整路徑
  Future<String> exportToDesktop(
    List<BoardRecord> boards, {
    required DateTime sessionStart,
    DateTime? endTime,
  }) async {
    final bytes = buildBytes(boards);
    final end = endTime ?? DateTime.now();

    final dir = Directory(_targetDir(sessionStart));
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }

    // 同一次執行（相同開始時間）只保留一個檔：先刪掉先前用舊「結束時間」寫出的檔，
    // 再寫入結束時間更新後的新檔，避免資料夾堆一堆 Main_1630_16xx.xlsx
    final sessionPrefix = '${config.filePrefix}_${_timeStr(sessionStart)}_';
    for (final entity in dir.listSync()) {
      if (entity is File) {
        final name = entity.path.split(Platform.pathSeparator).last;
        if (name.startsWith(sessionPrefix) && name.endsWith('.xlsx')) {
          try {
            entity.deleteSync();
          } catch (_) {}
        }
      }
    }

    final path = '${dir.path}${Platform.pathSeparator}'
        '${_fileName(sessionStart, end)}';
    final file = File(path);
    file.writeAsBytesSync(bytes);
    return path;
  }

  /// 目標資料夾：<桌面>/檢測報告/<modeName>/<yyyy-MM-dd>
  String _targetDir(DateTime start) {
    final sep = Platform.pathSeparator;
    return '${_desktopPath()}$sep檢測報告$sep${config.modeName}$sep${_dateStr(start)}';
  }

  /// 檔名：<prefix>_HHmm_HHmm.xlsx
  String _fileName(DateTime start, DateTime end) {
    return '${config.filePrefix}_${_timeStr(start)}_${_timeStr(end)}.xlsx';
  }

  String _desktopPath() {
    final home = Platform.isWindows
        ? Platform.environment['USERPROFILE']
        : Platform.environment['HOME'];
    final base = home ?? Directory.current.path;
    return '$base${Platform.pathSeparator}Desktop';
  }

  String _dateStr(DateTime t) =>
      '${t.year.toString().padLeft(4, '0')}-'
      '${t.month.toString().padLeft(2, '0')}-'
      '${t.day.toString().padLeft(2, '0')}';

  String _timeStr(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}${t.minute.toString().padLeft(2, '0')}';

  // ==================== 產生 xlsx bytes ====================

  List<int> buildBytes(List<BoardRecord> boards) {
    final excel = Excel.createExcel();
    final defaultSheet = excel.getDefaultSheet();

    // 依 50 片切分頁
    final chunks = <List<BoardRecord>>[];
    for (int i = 0; i < boards.length; i += boardsPerSheet) {
      chunks.add(boards.sublist(
          i, (i + boardsPerSheet).clamp(0, boards.length)));
    }
    if (chunks.isEmpty) chunks.add(<BoardRecord>[]);

    for (int p = 0; p < chunks.length; p++) {
      final sheet = excel['Page${p + 1}'];
      _writeSheet(sheet, chunks[p]);
    }

    // 移除套件預設空白分頁
    if (defaultSheet != null && defaultSheet != 'Page1') {
      excel.delete(defaultSheet);
    }

    final bytes = excel.save();
    if (bytes == null || bytes.isEmpty) return <int>[];
    // 套件無凍結 API → 存檔後對 xlsx(zip)注入凍結窗格
    return _withFreezePanes(bytes);
  }

  /// 對 xlsx(zip)每個 worksheet 的 <sheetView> 注入凍結：
  /// 凍結上方 2 列（編號列 + 子欄列）與左側 1 欄（名稱欄），
  /// 與 App 報告頁的凍結窗格一致。失敗則回傳原始 bytes（不影響匯出）。
  List<int> _withFreezePanes(List<int> bytes) {
    try {
      final archive = ZipDecoder().decodeBytes(bytes);
      final out = Archive();
      for (final file in archive.files) {
        final content = file.content as List<int>;
        if (file.isFile &&
            file.name.startsWith('xl/worksheets/sheet') &&
            file.name.endsWith('.xml')) {
          final patched = utf8.encode(_injectPane(utf8.decode(content)));
          out.addFile(ArchiveFile(file.name, patched.length, patched));
        } else {
          out.addFile(ArchiveFile(file.name, content.length, content));
        }
      }
      final encoded = ZipEncoder().encode(out);
      return encoded ?? bytes;
    } catch (_) {
      return bytes; // 任何解析/壓縮異常都不影響原本匯出
    }
  }

  /// 在 worksheet XML 的 <sheetView> 內插入凍結 <pane>（凍結 2 列 1 欄）
  String _injectPane(String xml) {
    const pane =
        '<pane xSplit="1" ySplit="2" topLeftCell="B3" activePane="bottomRight" state="frozen"/>'
        '<selection pane="bottomRight" activeCell="B3" sqref="B3"/>';
    // 情況一：自閉合 <sheetView .../> → 展開並塞入 pane
    final selfClosing = RegExp(r'<sheetView([^>]*?)/>');
    if (selfClosing.hasMatch(xml)) {
      return xml.replaceFirstMapped(
          selfClosing, (m) => '<sheetView${m[1]}>$pane</sheetView>');
    }
    // 情況二：已有子節點 <sheetView ...> → 在開頭插入 pane
    final open = RegExp(r'(<sheetView[^>]*>)');
    if (open.hasMatch(xml)) {
      return xml.replaceFirstMapped(open, (m) => '${m[1]}$pane');
    }
    return xml;
  }

  /// 寫入單一分頁（一批板子）
  void _writeSheet(Sheet sheet, List<BoardRecord> boards) {
    final sub = _subCols;
    final subN = sub.length;

    // ---- 表頭：編號列 + 子欄列 ----
    // col 0 保留給列標籤
    for (int b = 0; b < boards.length; b++) {
      final baseCol = 1 + b * subN;
      _set(sheet, baseCol, 0, boards[b].serial, bg: _headerBg, bold: true);
      // 編號右邊一格標明韌體版本（由電阻偵測；無版本則留空）
      final ver = _versionOf(boards[b]);
      if (ver.isNotEmpty && subN > 1) {
        _set(sheet, baseCol + 1, 0, '韌體版本:$ver', bg: _headerBg, bold: true);
      }
      for (int s = 0; s < subN; s++) {
        _set(sheet, baseCol + s, 1, _subLabel(sub[s]), bg: _headerBg, bold: true);
      }
    }
    _set(sheet, 0, 1, '名稱', bg: _headerBg, bold: true);

    // ---- 每個 round（主測 + 重測）往下疊 ----
    final maxRounds =
        boards.fold<int>(0, (m, b) => b.rounds.length > m ? b.rounds.length : m);

    int row = 2;
    for (int r = 0; r < maxRounds; r++) {
      if (r > 0) {
        _sectionRow(sheet, row, subN * boards.length,
            '重測 $r（同編號往下）');
        row++;
      }
      row = _writeRound(sheet, boards, r, row, sub);
    }
  }

  /// 寫入一個 round 的完整區塊，回傳下一個可用的 row
  int _writeRound(
    Sheet sheet,
    List<BoardRecord> boards,
    int roundIndex,
    int startRow,
    List<ReportDevice> sub,
  ) {
    final subN = sub.length;
    int row = startRow;

    // Idle 區
    _sectionRow(sheet, row++, subN * boards.length, '硬體無動作 (Idle)');
    for (final id in config.hwIds) {
      _channelRow(sheet, boards, roundIndex, row++, id, sub,
          ReportSection.idle, (snap) => snap.idle[id]);
    }

    // Running 區
    _sectionRow(sheet, row++, subN * boards.length, '硬體動作中 (Running)');
    for (final id in config.hwIds) {
      _channelRow(sheet, boards, roundIndex, row++, id, sub,
          ReportSection.running, (snap) => snap.running[id]);
    }

    // 感應區
    _sectionRow(sheet, row++, subN * boards.length, '感應偵測');
    for (final id in config.sensorIds) {
      _channelRow(sheet, boards, roundIndex, row++, id, sub,
          ReportSection.sensor, (snap) => snap.sensor[id]);
    }

    // R_Value / offset_平均（Main 才有）
    if (config.hasResistance) {
      _set(sheet, 0, row, 'R_Value', bold: true);
      for (int b = 0; b < boards.length; b++) {
        final snap = _roundOf(boards[b], roundIndex);
        if (snap?.rValue != null) {
          _setNum(sheet, _colForDevice(b, sub, ReportDevice.stm32), row,
              snap!.rValue!);
        }
      }
      row++;
    }
    if (config.hasOffset) {
      _set(sheet, 0, row, 'offset_平均', bold: true);
      for (int b = 0; b < boards.length; b++) {
        final snap = _roundOf(boards[b], roundIndex);
        if (snap?.offsetAvg != null) {
          _setDouble(sheet, _colForDevice(b, sub, ReportDevice.offset), row,
              snap!.offsetAvg!);
        }
      }
      row++;
    }

    // 異常列：每片列出這輪的異常項目（寫在該片首欄；正常則標「正常」）
    _set(sheet, 0, row, '異常', bold: true);
    for (int b = 0; b < boards.length; b++) {
      final snap = _roundOf(boards[b], roundIndex);
      if (snap == null) continue;
      final items = computeLiveAbnormals(config, snap, statusResolver);
      final baseCol = 1 + b * subN;
      if (items.isEmpty) {
        _set(sheet, baseCol, row, '正常', bg: _hwLow, bold: true);
      } else {
        _set(sheet, baseCol, row, items.join('\n'), bg: _fail);
      }
    }
    row++;

    return row;
  }

  /// 寫入一列通道資料（所有板子在此 round 的值）
  void _channelRow(
    Sheet sheet,
    List<BoardRecord> boards,
    int roundIndex,
    int row,
    int id,
    List<ReportDevice> sub,
    ReportSection section,
    ChannelValues? Function(TestSnapshot snap) pick,
  ) {
    final label = config.labels[id] ?? 'ID$id';
    _set(sheet, 0, row, '$label (ID$id)', bold: true);

    for (int b = 0; b < boards.length; b++) {
      final snap = _roundOf(boards[b], roundIndex);
      if (snap == null) continue;
      final values = pick(snap);
      if (values == null) continue;

      final baseCol = 1 + b * sub.length;
      for (int s = 0; s < sub.length; s++) {
        final device = sub[s];
        // 感應區沒有 offset 欄
        if (section == ReportSection.sensor && device == ReportDevice.offset) {
          continue;
        }
        final v = _valueOf(values, device);
        if (v == null) continue;

        var bg = _bgFor(section, device, id, v);
        // 溫差過大：STM32 溫度值強制標紅（高機率感測器故障）
        if (section == ReportSection.sensor &&
            device == ReportDevice.stm32 &&
            snap.tempDiffErrorIds.contains(id)) {
          bg = _sensorHigh;
        }
        _setNum(sheet, baseCol + s, row, v, bg: bg);
      }
    }
  }

  /// 依狀態判定器決定背景色（offset 欄不上色）
  String? _bgFor(ReportSection section, ReportDevice device, int id, int value) {
    if (device == ReportDevice.offset) return null;
    if (statusResolver == null) return null;
    final isSensor = section == ReportSection.sensor;
    switch (statusResolver!(section, device, id, value)) {
      case CellStatus.normal:
        return null;
      case CellStatus.tier1Pass:
        return _tier1; // 深藍：首次通過
      case CellStatus.tier2Pass:
        return _hwLow; // 淺藍：二次通過
      case CellStatus.fail:
        return _fail; // 紅：不良
      case CellStatus.high:
        return isSensor ? _sensorHigh : _hwHigh;
      case CellStatus.low:
        return isSensor ? _sensorLow : _hwLow;
    }
  }

  /// 該片的版本名。優先用 R_Value 即時反推（舊快照也能顯示）,
  /// 反推不到才退回快照擷取當下存的 versionName。
  String _versionOf(BoardRecord board) {
    for (final r in board.rounds) {
      final v = (r.rValue != null ? versionResolver?.call(r.rValue!) : null) ??
          r.versionName;
      if (v != null && v.isNotEmpty) return v;
    }
    return '';
  }

  TestSnapshot? _roundOf(BoardRecord board, int roundIndex) =>
      roundIndex < board.rounds.length ? board.rounds[roundIndex] : null;

  int _colForDevice(int boardIndex, List<ReportDevice> sub, ReportDevice d) {
    final idx = sub.indexOf(d);
    final s = idx < 0 ? 0 : idx;
    return 1 + boardIndex * sub.length + s;
  }

  // ==================== 儲存格工具 ====================

  void _sectionRow(Sheet sheet, int row, int span, String title) {
    _set(sheet, 0, row, title, bg: _sectionBg, bold: true, white: true);
    for (int c = 1; c <= span; c++) {
      _set(sheet, c, row, '', bg: _sectionBg);
    }
  }

  void _set(Sheet sheet, int col, int row, String text,
      {String? bg, bool bold = false, bool white = false}) {
    final cell =
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row));
    cell.value = TextCellValue(text);
    cell.cellStyle = _style(bg: bg, bold: bold, white: white);
  }

  void _setNum(Sheet sheet, int col, int row, int value, {String? bg}) {
    final cell =
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row));
    cell.value = IntCellValue(value);
    cell.cellStyle = _style(bg: bg);
  }

  void _setDouble(Sheet sheet, int col, int row, double value, {String? bg}) {
    final cell =
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row));
    cell.value = DoubleCellValue(double.parse(value.toStringAsFixed(1)));
    cell.cellStyle = _style(bg: bg);
  }

  CellStyle _style({String? bg, bool bold = false, bool white = false}) {
    return CellStyle(
      bold: bold,
      backgroundColorHex:
          bg != null ? ExcelColor.fromHexString(bg) : ExcelColor.none,
      fontColorHex: white ? ExcelColor.white : ExcelColor.black,
    );
  }
}
