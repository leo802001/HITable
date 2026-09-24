import 'package:flutter_test/flutter_test.dart';
import 'package:offline_course_schedule/import/term_import.dart';

void main() {
  const parser = TermImportParser();

  test('从课表文字识别最大周数并采用哈工大作息模板', () {
    final result = parser.inferFromText('高等数学 [1-16]，另一门课 2-18双周');

    expect(result.totalWeeks, 18);
    expect(result.usedDefaultPeriods, isTrue);
    // 哈工大作休：第1节 8:00~8:50，第2节 8:55~9:45（见 term_import.dart 的 hitLessonPeriods）
    expect(result.periods.first.startMinutes, 8 * 60);
    expect(result.periods[1].endMinutes, 9 * 60 + 45);
  });

  test('内置作息共 12 节，最后一节 21:25~22:15', () {
    final result = parser.inferFromText('只给一段文字 [1-16]');

    expect(result.periods.length, 12);
    expect(result.periods.last.startMinutes, 21 * 60 + 25);
    expect(result.periods.last.endMinutes, 22 * 60 + 15);
  });

  test('12 节作息与学校《学生教学活动时间安排》逐条一致', () {
    // 官方时间表（每节 50 分钟、课间 5 分钟）：
    // 第1节 08:00-08:50  第2节 08:55-09:45  第3节 10:00-10:50  第4节 10:55-11:45
    // 第5节 13:45-14:35  第6节 14:40-15:30  第7节 15:45-16:35  第8节 16:40-17:30
    // 第9节 18:30-19:20  第10节 19:25-20:15 第11节 20:30-21:20 第12节 21:25-22:15
    const expected = [
      [8, 0, 8, 50],
      [8, 55, 9, 45],
      [10, 0, 10, 50],
      [10, 55, 11, 45],
      [13, 45, 14, 35],
      [14, 40, 15, 30],
      [15, 45, 16, 35],
      [16, 40, 17, 30],
      [18, 30, 19, 20],
      [19, 25, 20, 15],
      [20, 30, 21, 20],
      [21, 25, 22, 15],
    ];

    final periods = parser.inferFromText('占位 [1-16]').periods;
    expect(periods.length, expected.length);
    for (var i = 0; i < expected.length; i++) {
      final [startH, startM, endH, endM] = expected[i];
      expect(
        periods[i].startMinutes,
        startH * 60 + startM,
        reason: '第${i + 1}节开始时间应为 $startH:${startM.toString().padLeft(2, '0')}',
      );
      expect(
        periods[i].endMinutes,
        endH * 60 + endM,
        reason: '第${i + 1}节结束时间应为 $endH:${endM.toString().padLeft(2, '0')}',
      );
    }
  });

  test('每节 50 分钟；课间 5 分钟，另有 3 处 15 分钟大课间', () {
    final periods = parser.inferFromText('占位 [1-16]').periods;

    for (final period in periods) {
      expect(
        period.endMinutes - period.startMinutes,
        50,
        reason: '第${period.number}节应为 50 分钟',
      );
    }

    // 真实间隔（已逐条核对官方表）：
    //   第2→3 节 15min（上午中场）、第6→7 节 15min（下午中场）、第10→11 节 15min（晚间中场）
    //   其余同半天连堂为 5min
    //   跨午休 120min、跨傍晚 60min
    const expectedGaps = <int, int>{
      2: 5, //
      3: 15, // 上午中场休息
      4: 5,
      5: 120, // 午休
      6: 5,
      7: 15, // 下午中场休息
      8: 5,
      9: 60, // 傍晚休息
      10: 5,
      11: 15, // 晚间中场休息
      12: 5,
    };

    for (final entry in expectedGaps.entries) {
      final number = entry.key;
      final actual = periods[number - 1].startMinutes - periods[number - 2].endMinutes;
      expect(
        actual,
        entry.value,
        reason: '第${number - 1}节到第$number节的间隔应为 ${entry.value} 分钟',
      );
    }
  });

  test('CSV 有上课时间时用文件时间覆盖模板', () {
    final result = parser.parseCsv('周次范围,节次,上课时间\n1-20周,1-2,08:10-09:45');

    expect(result.totalWeeks, 20);
    expect(result.usedDefaultPeriods, isFalse);
    expect(result.periods.first.startMinutes, 8 * 60 + 10);
    expect(result.periods[1].endMinutes, 9 * 60 + 45);
  });
}
