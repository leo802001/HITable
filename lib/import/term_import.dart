import 'dart:typed_data';

import 'package:csv/csv.dart';
import 'package:excel/excel.dart';

import 'xls_reader.dart';

import '../domain/schedule_models.dart';
import '../domain/week_rule_parser.dart';

class TermImportSuggestion {
  const TermImportSuggestion({
    required this.totalWeeks,
    required this.periods,
    required this.usedDefaultPeriods,
  });

  final int? totalWeeks;
  final List<LessonPeriod> periods;
  final bool usedDefaultPeriods;
}

/// 从课表文件中提取“学期设置”所需的周数与作息时间。
class TermImportParser {
  const TermImportParser({this.weekRuleParser = const WeekRuleParser()});

  final WeekRuleParser weekRuleParser;

  TermImportSuggestion parseCsv(String content) {
    final normalized = content.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final table = const CsvToListConverter(eol: '\n', shouldParseNumbers: false)
        .convert(normalized)
        .map((row) => row.map((cell) => cell.toString()).toList())
        .toList();
    return _parseTable(table);
  }

  TermImportSuggestion parseXlsx(Uint8List bytes) {
    final workbook = Excel.decodeBytes(bytes);
    for (final sheet in workbook.tables.values) {
      final table = sheet.rows
          .map(
            (row) => row.map((cell) => cell?.value?.toString() ?? '').toList(),
          )
          .toList();
      if (table.any((row) => row.any((cell) => cell.trim().isNotEmpty))) {
        return _parseTable(table);
      }
    }
    return _suggestion(null, const []);
  }

  /// 解析老版 `.xls`（OLE2 / BIFF8）。
  ///
  /// pub 的 `excel` 包不支持 .xls，这里用自研读取器取出网格后复用同一套分析。
  TermImportSuggestion parseXls(Uint8List bytes) {
    final workbook = XlsWorkbook.parse(bytes);
    if (workbook.isEmpty) return _suggestion(null, const []);
    return _parseTable(workbook.grid);
  }

  TermImportSuggestion inferFromText(String text) {
    final candidates = <String>[];
    final pattern = RegExp(
      r'\[([0-9,，、\-－—–\s单双周]+)\]|((?:第)?\d+(?:\s*[-－—–]\s*\d+)?(?:周(?:\s*[（(]?[单双][）)]?)?|[单双]周))',
    );
    for (final match in pattern.allMatches(text)) {
      candidates.add(match.group(1) ?? match.group(2)!);
    }
    return _suggestion(_maxWeek(candidates), const []);
  }

  TermImportSuggestion _parseTable(List<List<String>> table) {
    if (table.isEmpty) return _suggestion(null, const []);
    final headerIndex = table.indexWhere(
      (row) => row.any((cell) {
        final name = _header(cell);
        return _weekHeaders.contains(name) || _periodHeaders.contains(name);
      }),
    );
    if (headerIndex < 0) {
      return inferFromText(table.expand((row) => row).join('\n'));
    }
    final header = table[headerIndex].map(_header).toList();
    final weekColumn = header.indexWhere(_weekHeaders.contains);
    final periodColumn = header.indexWhere(_periodHeaders.contains);
    final timeColumn = header.indexWhere(_timeHeaders.contains);
    final weekTexts = <String>[];
    final timeRows = <({String period, String time})>[];
    for (final row in table.skip(headerIndex + 1)) {
      if (weekColumn >= 0 && weekColumn < row.length) {
        weekTexts.add(row[weekColumn]);
      }
      if (periodColumn >= 0 &&
          timeColumn >= 0 &&
          periodColumn < row.length &&
          timeColumn < row.length) {
        timeRows.add((period: row[periodColumn], time: row[timeColumn]));
      }
    }
    return _suggestion(_maxWeek(weekTexts), timeRows);
  }

  TermImportSuggestion _suggestion(
    int? totalWeeks,
    List<({String period, String time})> timeRows,
  ) {
    final periods = List<LessonPeriod>.of(hitLessonPeriods);
    var usedFileTime = false;
    for (final row in timeRows) {
      final periodMatch = RegExp(
        r'(\d+)\s*(?:[-－—–~至]\s*(\d+))?',
      ).firstMatch(row.period);
      final timeMatch = RegExp(
        r'(\d{1,2}):(\d{2})\s*[-－—–~至]\s*(\d{1,2}):(\d{2})',
      ).firstMatch(row.time);
      if (periodMatch == null || timeMatch == null) continue;
      final startPeriod = int.parse(periodMatch.group(1)!);
      final endPeriod = int.parse(
        periodMatch.group(2) ?? periodMatch.group(1)!,
      );
      if (startPeriod < 1 ||
          endPeriod > periods.length ||
          endPeriod < startPeriod) {
        continue;
      }
      final startMinutes =
          int.parse(timeMatch.group(1)!) * 60 + int.parse(timeMatch.group(2)!);
      final endMinutes =
          int.parse(timeMatch.group(3)!) * 60 + int.parse(timeMatch.group(4)!);
      if (startMinutes >= endMinutes || endMinutes > 24 * 60) continue;
      if (startPeriod == endPeriod) {
        periods[startPeriod - 1] = LessonPeriod(
          number: startPeriod,
          startMinutes: startMinutes,
          endMinutes: endMinutes,
        );
        usedFileTime = true;
        continue;
      }
      final first = periods[startPeriod - 1];
      final last = periods[endPeriod - 1];
      periods[startPeriod - 1] = LessonPeriod(
        number: startPeriod,
        startMinutes: startMinutes,
        endMinutes: first.endMinutes > startMinutes
            ? first.endMinutes
            : endMinutes,
      );
      periods[endPeriod - 1] = LessonPeriod(
        number: endPeriod,
        startMinutes: last.startMinutes < endMinutes
            ? last.startMinutes
            : startMinutes,
        endMinutes: endMinutes,
      );
      usedFileTime = true;
    }
    return TermImportSuggestion(
      totalWeeks: totalWeeks,
      periods: List<LessonPeriod>.unmodifiable(periods),
      usedDefaultPeriods: !usedFileTime,
    );
  }

  int? _maxWeek(Iterable<String> values) {
    int? maximum;
    for (final value in values) {
      final result = weekRuleParser.parse(value);
      final end = result.value?.endWeek;
      if (end != null && (maximum == null || end > maximum)) maximum = end;
    }
    return maximum;
  }

  String _header(String value) =>
      value.trim().toLowerCase().replaceAll(RegExp(r'[\s_（）()]'), '');
}

const _weekHeaders = {'周次', '周次范围', '教学周', '上课周次'};
const _periodHeaders = {'节次', '上课节次', '课程节次'};
const _timeHeaders = {'上课时间', '时间', '节次时间', '起止时间'};

/// 哈尔滨工业大学作息时间表。
///
/// 数据来源（**已核实**）：
/// 1. 教务系统「学生个人课表查询」页面上印的原文
///    （`上课作息时间表：(每节50分钟)`，2026-09 抓取）；
/// 2. 学校《学生教学活动时间安排》表（用户提供的官方文档）。
///
/// 两份材料**逐分钟完全一致**，每节 50 分钟、课间 5 分钟：
/// ```
/// 第1节 08:00-08:50   第2节 08:55-09:45   第3节 10:00-10:50   第4节 10:55-11:45
/// 第5节 13:45-14:35   第6节 14:40-15:30   第7节 15:45-16:35   第8节 16:40-17:30
/// 第9节 18:30-19:20   第10节 19:25-20:15  第11节 20:30-21:20  第12节 21:25-22:15
/// ```
///
/// 注：教务页面按「两节连排」给出区间（如 `第1-2节 8:00~9:45`），
/// 此处拆成单节存放，方便按节次精确计算上下课时间与倒计时。
///
/// 另有两个**仅在特殊场景使用**的时间表，暂不参与课表计算，供参考：
/// - **考试**：第1-2节 08:00-10:00、第3-4节 10:00-12:00、第5-6节 13:00-15:00、
///   第7-8节 15:45-17:45、第9-10节 18:30-20:30（每场 2 小时）
/// - **实验/上机三节连排**：第1-2节 07:20-09:50、第3-4节 10:00-12:30、
///   第5-6节 13:00-15:30、第7-8节 15:40-18:10、第9-10节 18:30-21:00
///   （注：该表所标的「两节」实为三节，每场 2.5 小时）
const hitLessonPeriods = [
  // 上午
  LessonPeriod(number: 1, startMinutes: 480, endMinutes: 530), // 8:00~8:50
  LessonPeriod(number: 2, startMinutes: 535, endMinutes: 585), // 8:55~9:45
  LessonPeriod(number: 3, startMinutes: 600, endMinutes: 650), // 10:00~10:50
  LessonPeriod(number: 4, startMinutes: 655, endMinutes: 705), // 10:55~11:45
  // 下午
  LessonPeriod(number: 5, startMinutes: 825, endMinutes: 875), // 13:45~14:35
  LessonPeriod(number: 6, startMinutes: 880, endMinutes: 930), // 14:40~15:30
  LessonPeriod(number: 7, startMinutes: 945, endMinutes: 995), // 15:45~16:35
  LessonPeriod(number: 8, startMinutes: 1000, endMinutes: 1050), // 16:40~17:30
  // 晚上
  LessonPeriod(number: 9, startMinutes: 1110, endMinutes: 1160), // 18:30~19:20
  LessonPeriod(number: 10, startMinutes: 1165, endMinutes: 1215), // 19:25~20:15
  LessonPeriod(number: 11, startMinutes: 1230, endMinutes: 1280), // 20:30~21:20
  LessonPeriod(number: 12, startMinutes: 1285, endMinutes: 1335), // 21:25~22:15
];



/// 新建学期时默认的「第一周周一」。
///
/// 用学校公布的 2026-2027 秋季学期开学第一周周一（2026-08-31），
/// 省得同学填错；用户仍可在学期设置里改成任意日期。
final defaultFirstWeekMonday = DateTime(2026, 8, 31);