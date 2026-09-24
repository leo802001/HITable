/// 哈工大课表网格解析。
///
/// 已通过真实数据验证的表格结构（2026 秋季实测）：
///
/// ```
/// row 0: [空(colspan=2)] 星期一 星期二 星期三 星期四 星期五 星期六 星期日
/// row 1: 上午    第1,2节   课程…     课程…   课程…   课程…   课程…   (空)   (空)
/// row 2: 上午    第3,4节   …
/// row 3: 下午    第5,6节   …
/// row 4: 下午    第7,8节   …
/// row 5: 晚上    第9,10节  …
/// row 6: 晚上    第11,12节 …
/// row 7: [其它课程：…（colspan=9）]
/// ```
///
/// 单元格文本格式（换行用 `\n` 表示，网页里是 `<br>`）：
///
/// ```
/// 高等数学（1）
/// 张老师[4-17]周A101
/// ```
///
/// 即「课程名」一行 +「教师[周次]周地点」一行。一格内可能有多门课，依次排列。
///
/// 边界情况（均已实测）：
/// - 教师名可能含空格：`John Smith[9-16]周B918`
/// - 教师名可能只有两个字：`田径[7-14]周BX11`
/// - 周次可能不连续且用全角逗号：`李老师[3-5，7]周B108`
/// - 课程名可能带括号：`大学英语综合A(提高)`、`体育（1）(乒乓球)`
/// - 地点可能很长：`二区文体中心213乒乓球室`
library;

import 'course_import.dart';

/// 一门课在网格中的一个出现位置。
class HitTimetableRecord {
  const HitTimetableRecord({
    required this.courseName,
    required this.teacher,
    required this.location,
    required this.weekday,
    required this.startPeriod,
    required this.endPeriod,
    required this.weeks,
  });

  final String courseName;
  final String teacher;
  final String location;

  /// 1 = 周一 … 7 = 周日。
  final int weekday;

  /// 起始节次，例如 `第1,2节` → 1。
  final int startPeriod;

  /// 结束节次，例如 `第1,2节` → 2。
  final int endPeriod;

  /// 周次原文，例如 `4-17`；交给 [WeekRuleParser] 处理。
  final String weeks;

  @override
  String toString() =>
      '$courseName / $teacher / $location / 周$weekday $startPeriod-$endPeriod节 / $weeks周';
}

/// 解析结果：课表记录 + 无法自动排入网格的课程。
class HitTimetableParseResult {
  const HitTimetableParseResult({
    required this.records,
    this.unscheduled = const [],
    this.warnings = const [],
  });

  final List<HitTimetableRecord> records;

  /// 「其它课程」行里的课程（无固定时间），例如军训、军事理论。
  final List<HitUnscheduledCourse> unscheduled;

  final List<String> warnings;

  bool get isEmpty => records.isEmpty;
}

/// 「其它课程」里的条目，格式为 `【课程名◇教师◇周次◇】`。
class HitUnscheduledCourse {
  const HitUnscheduledCourse({
    required this.courseName,
    required this.teacher,
    required this.weeks,
  });

  final String courseName;
  final String teacher;

  /// 周次原文，可能是 `-` 表示未指定。
  final String weeks;

  @override
  String toString() => '$courseName / $teacher / $weeks';
}

/// 把课表网格（行 × 列的纯文本）解析成结构化记录。
class HitTimetableImportParser {
  const HitTimetableImportParser({
    this.courseImportParser = const CourseImportParser(),
  });

  final CourseImportParser courseImportParser;

  /// 节次列在第几列（第 0 列是「上午/下午/晚上」，第 1 列是节次）。
  static const _periodColumn = 1;

  /// 星期一到星期日对应的列号范围。
  static const _firstDayColumn = 2;

  /// 解析网格行，得到结构化结果。
  HitTimetableParseResult parse(List<List<String>> rows) {
    final warnings = <String>[];
    if (rows.isEmpty) {
      return const HitTimetableParseResult(records: []);
    }

    final periods = _readPeriodRows(rows, warnings);
    if (periods.isEmpty) {
      return HitTimetableParseResult(
        records: const [],
        warnings: [...warnings, '没有识别到节次行，课表结构可能已变化'],
      );
    }

    final records = <HitTimetableRecord>[];
    for (final row in periods) {
      for (var dayIndex = 0; dayIndex < 7; dayIndex++) {
        final column = _firstDayColumn + dayIndex;
        if (column >= row.cells.length) continue;
        final cellText = row.cells[column];
        if (cellText.isEmpty) continue;
        records.addAll(
          _parseCell(
            text: cellText,
            weekday: dayIndex + 1,
            period: row.period,
            warnings: warnings,
          ),
        );
      }
    }

    return HitTimetableParseResult(
      records: records,
      unscheduled: _parseUnscheduled(rows),
      warnings: warnings,
    );
  }

  /// 转成 App 通用的导入表格（`课程名/教师/地点/周几/节次/周次范围`）。
  ///
  /// 复用 [CourseImportParser.parseTable]，因此后续预览、纠错、冲突检测、
  /// 撤销导入这些能力全部沿用，不需要另写一套。
  ImportPreview toImportPreview(HitTimetableParseResult result) {
    final table = <List<String>>[
      const ['课程名', '教师', '地点', '周几', '节次', '周次范围'],
    ];
    final sorted = List<HitTimetableRecord>.of(result.records)
      ..sort((a, b) {
        final byDay = a.weekday.compareTo(b.weekday);
        if (byDay != 0) return byDay;
        final byPeriod = a.startPeriod.compareTo(b.startPeriod);
        if (byPeriod != 0) return byPeriod;
        return a.courseName.compareTo(b.courseName);
      });
    for (final record in sorted) {
      table.add([
        record.courseName,
        record.teacher,
        record.location,
        '${record.weekday}',
        '${record.startPeriod}-${record.endPeriod}',
        '${record.weeks}周',
      ]);
    }
    return courseImportParser.parseTable(table, sheetName: '哈工大教务');
  }

  /// 读出每个节次行：节次数字 + 该行各天的格子文本。
  List<_PeriodRow> _readPeriodRows(List<List<String>> rows, List<String> warnings) {
    final result = <_PeriodRow>[];
    for (var index = 1; index < rows.length; index++) {
      final row = rows[index];
      // 最后一行「其它课程」是整行合并的，列数不足以覆盖到星期五，跳过。
      if (row.length < _firstDayColumn + 1) continue;
      if (row.isNotEmpty && row.first.startsWith('其它课程')) continue;
      if (row.length <= _periodColumn) continue;
      final period = _parsePeriodLabel(row[_periodColumn]);
      if (period == null) {
        final label = row[_periodColumn];
        if (label.isNotEmpty) {
          warnings.add('无法识别的节次标签「$label」，已跳过该行');
        }
        continue;
      }
      result.add(_PeriodRow(period: period, cells: row));
    }
    return result;
  }

  /// 解析 `第1,2节` / `第3,4节`，返回起始节次（用于定位）。
  ///
  /// 教务把两节连排显示成一行，所以这里取该行的节次区间。
  _PeriodSpan? _parsePeriodLabel(String label) {
    final match = RegExp(r'第\s*([\d,，、]+)\s*节').firstMatch(label);
    if (match == null) return null;
    final numbers = RegExp(r'\d+')
        .allMatches(match.group(1)!)
        .map((m) => int.parse(m.group(0)!))
        .toList();
    if (numbers.isEmpty) return null;
    numbers.sort();
    return _PeriodSpan(start: numbers.first, end: numbers.last);
  }

  /// 解析单个格子里的所有课程。
  List<HitTimetableRecord> _parseCell({
    required String text,
    required int weekday,
    required _PeriodSpan period,
    required List<String> warnings,
  }) {
    final lines = text
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
    final records = <HitTimetableRecord>[];

    // 课程与教师信息成对出现：奇数行是课程名，偶数行是「教师[周次]周地点」。
    // 但课程名本身可能折行，所以用「能匹配教师行」来定位，而不是死板的奇偶配对。
    var pendingName = <String>[];
    for (final line in lines) {
      final detail = _parseTeacherDetail(line);
      if (detail == null) {
        pendingName.add(line);
        continue;
      }
      if (pendingName.isEmpty) {
        warnings.add('课程信息缺少课程名，已跳过：「$line」');
        continue;
      }
      // 多行课程名合并（教务偶尔会把长课名折行）
      final courseName = pendingName.join(' ').trim();
      pendingName = <String>[];
      records.add(
        HitTimetableRecord(
          courseName: courseName,
          teacher: detail.teacher,
          location: detail.location,
          weekday: weekday,
          startPeriod: period.start,
          endPeriod: period.end,
          weeks: detail.weeks,
        ),
      );
    }
    if (pendingName.isNotEmpty) {
      warnings.add('课程「${pendingName.join(' ')}」缺少教师与周次信息，已跳过');
    }
    return records;
  }

  /// 解析 `张老师[4-17]周A101` 这种教师明细行。
  ///
  /// 规则：`教师名` + `[周次]周` + `地点`。
  /// 周次里可能出现全角逗号（`[3-5，7]周`），教师名里可能出现空格。
  _TeacherDetail? _parseTeacherDetail(String line) {
    final match =
        RegExp(r'^(.+?)\[([\d\s,，、\-－—–~～至]+)\]\s*周\s*(.*)$').firstMatch(line);
    if (match == null) return null;
    final teacher = match.group(1)!.trim();
    final weeks = match.group(2)!.replaceAll(RegExp(r'\s+'), '').trim();
    final location = match.group(3)!.trim();
    if (teacher.isEmpty || weeks.isEmpty) return null;
    return _TeacherDetail(teacher: teacher, weeks: weeks, location: location);
  }

  /// 解析最后一行「其它课程」：`【课程名◇教师◇周次◇】`。
  List<HitUnscheduledCourse> _parseUnscheduled(List<List<String>> rows) {
    if (rows.isEmpty) return const [];
    final last = rows.last;
    // 整行合并时只有一格
    if (last.length != 1) return const [];
    final text = last.first;
    if (!text.startsWith('其它课程')) return const [];
    return RegExp(r'【([^】]*)】')
        .allMatches(text)
        .map((match) {
          // 用长度为 1 的分隔符切分，避免「课名里本来就有 ◇」的极端情况
          final fields = match.group(1)!.split('◇');
          return HitUnscheduledCourse(
            courseName: fields.isNotEmpty ? fields[0].trim() : '',
            teacher: fields.length > 1 ? fields[1].trim() : '',
            weeks: fields.length > 2 ? fields[2].trim() : '',
          );
        })
        .where((course) => course.courseName.isNotEmpty)
        .toList();
  }
}

class _PeriodRow {
  const _PeriodRow({required this.period, required this.cells});
  final _PeriodSpan period;
  final List<String> cells;
}

class _PeriodSpan {
  const _PeriodSpan({required this.start, required this.end});
  final int start;
  final int end;
}

class _TeacherDetail {
  const _TeacherDetail({
    required this.teacher,
    required this.weeks,
    required this.location,
  });
  final String teacher;
  final String weeks;
  final String location;
}
