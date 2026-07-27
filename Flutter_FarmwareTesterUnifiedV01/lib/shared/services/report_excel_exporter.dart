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

import 'dart:io';
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

class ReportExcelExporter {
  final ReportConfig config;
  final CellStatusResolver? statusResolver;

  /// 每個分頁最多幾片
  static const int boardsPerSheet = 50;

  ReportExcelExporter({required this.config, this.statusResolver});

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
    return bytes ?? <int>[];
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
