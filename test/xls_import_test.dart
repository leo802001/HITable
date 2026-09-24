import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:offline_course_schedule/import/course_import.dart';
import 'package:offline_course_schedule/import/xls_reader.dart';

/// 读取真实 fixture：学校教务导出的 .xls 课表。
Uint8List fixtureBytes() {
  final file = File('test/fixtures/hit_timetable.xls');
  if (!file.existsSync()) {
    throw StateError('缺少 fixture: ${file.path}');
  }
  return file.readAsBytesSync();
}

void main() {
  group('XlsWorkbook：读取真实 .xls（OLE2/BIFF8）', () {
    late XlsWorkbook workbook;

    setUpAll(() {
      workbook = XlsWorkbook.parse(fixtureBytes());
    });

    test('能读出网格', () {
      expect(workbook.isEmpty, isFalse, reason: '真实课表不应解析为空');
      expect(workbook.grid, isNotEmpty);
    });

    test('网格是矩形（各行长度一致）', () {
      final widths = workbook.grid.map((r) => r.length).toSet();
      expect(widths.length, 1, reason: '网格应补齐为矩形，实际宽度集合: $widths');
    });

    test('第 0 行是标题行（学期 + 姓名）', () {
      final title = workbook.grid.first.join('');
      expect(title, contains('学期'));
      expect(title, contains('课表'));
    });

    test('星期表头在标题行之后', () {
      // 第 0 行是合并的标题，星期表头在其后一行
      final headerRow = workbook.grid.length > 1
          ? workbook.grid[1].join('|')
          : workbook.grid.first.join('|');
      for (final day in ['星期一', '星期二', '星期三', '星期四', '星期五']) {
        expect(headerRow, contains(day));
      }
    });

    test('含节次标签（第N,M节）', () {
      final all = workbook.grid.expand((r) => r).join('\n');
      expect(all, contains('第1,2节'));
      expect(all, contains('第3,4节'));
    });

    test('课程单元格含「课程名\\n教师[周次]周地点」格式', () {
      final cells = workbook.grid.expand((r) => r).toList();
      final withFormat = cells
          .where((c) => c.contains('\n') && c.contains(']周'))
          .toList();
      expect(
        withFormat,
        isNotEmpty,
        reason: '应存在符合教务格式的课程单元格',
      );
    });

    test('能读出课程名', () {
      final all = workbook.grid.expand((r) => r).join('\n');
      expect(all, contains('高等代数'));
      expect(all, contains('数学分析'));
    });
  });

  group('CourseImportParser.parseXls：端到端解析真实 .xls', () {
    late ImportPreview preview;

    setUpAll(() {
      preview = const CourseImportParser().parseXls(fixtureBytes());
    });

    test('解析不报错', () {
      expect(
        preview.errors,
        isEmpty,
        reason: '解析真实课表不应有错误，实际: ${preview.errors}',
      );
    });

    test('解析出课程行（不遗漏）', () {
      expect(
        preview.rows.length,
        greaterThanOrEqualTo(10),
        reason: '学校导出的课表应解析出 10 条以上课程记录，'
            '实际 ${preview.rows.length} 条',
      );
    });

    test('大部分行有效（课程名/周几/节次/周次都能识别）', () {
      final valid = preview.rows.where((r) => r.isValid).length;
      expect(
        valid,
        greaterThanOrEqualTo(10),
        reason: '有效行应≥10，实际 $valid / ${preview.rows.length}',
      );
    });

    test('能构建出 Course 对象', () {
      final result = const CourseImportParser().buildCourses(preview);
      expect(result.courses, isNotEmpty);
      expect(result.courses.length, greaterThanOrEqualTo(5));
    });

    test('课程覆盖多个星期（不是只解析出一天）', () {
      final result = const CourseImportParser().buildCourses(preview);
      final weekdays = <int>{};
      for (final c in result.courses) {
        for (final s in c.sessions) {
          weekdays.add(s.weekday);
        }
      }
      expect(
        weekdays.length,
        greaterThanOrEqualTo(3),
        reason: '课程应分布在多个星期，实际: $weekdays',
      );
    });

    test('课程含节次与地点', () {
      final result = const CourseImportParser().buildCourses(preview);
      final withPeriod = result.courses
          .expand((c) => c.sessions)
          .where((s) => s.startPeriod > 0)
          .length;
      expect(withPeriod, greaterThan(0));
      final withLocation = result.courses
          .expand((c) => c.sessions)
          .where((s) => s.location.isNotEmpty)
          .length;
      expect(withLocation, greaterThan(0));
    });

    test('课程周次规则被解析出来', () {
      final result = const CourseImportParser().buildCourses(preview);
      final sessions = result.courses.expand((c) => c.sessions).toList();
      expect(sessions, isNotEmpty);
      // 至少有一条课的周次不是「全周」（教务表格里是 4-17 周这类）
      expect(
        sessions.any((s) => s.weekRule.startWeek > 1),
        isTrue,
        reason: '应解析出非从第 1 周开始的课程',
      );
    });

    test('空字节输入给出友好错误而不是崩溃', () {
      final result = const CourseImportParser().parseXls(Uint8List(0));
      expect(result.errors, isNotEmpty);
      expect(result.canImport, isFalse);
    });

    test('非 OLE2 输入给出友好错误而不是崩溃', () {
      final garbage = Uint8List.fromList(List.generate(2048, (i) => i % 256));
      final result = const CourseImportParser().parseXls(garbage);
      expect(result.errors, isNotEmpty);
      expect(result.canImport, isFalse);
    });
  });
}
