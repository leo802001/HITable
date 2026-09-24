import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_course_schedule/application/appearance_controller.dart';
import 'package:offline_course_schedule/application/schedule_controller.dart';
import 'package:offline_course_schedule/domain/appearance_settings.dart';
import 'package:offline_course_schedule/domain/schedule_models.dart';
import 'package:offline_course_schedule/main.dart';

/// 锁住「界面美化 → 课表排布」能真正切换首页「本周」的渲染方式。
///
/// 小组件的数据契约测试已独立到 `next_course_widget_service_test.dart`，
/// 本文件只覆盖周视图的两种布局。
///
/// ⚠️ 与 appearance_applied_test.dart 相同：`clockProvider` 是无限 Stream，
/// 每个 testWidgets 只 pump 一次，需要多组取值时拆成多个用例。
void main() {
  /// 造一份「今天有两门课」的课表：第1-2节 与 第3-4节。
  ScheduleData dataWithTwoCourses() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final monday = today.subtract(Duration(days: today.weekday - 1));
    const periods = [
      LessonPeriod(number: 1, startMinutes: 480, endMinutes: 530),
      LessonPeriod(number: 2, startMinutes: 535, endMinutes: 585),
      LessonPeriod(number: 3, startMinutes: 600, endMinutes: 650),
      LessonPeriod(number: 4, startMinutes: 655, endMinutes: 705),
    ];
    final term = Term(
      id: currentTermId,
      name: '测试学期',
      firstWeekMonday: monday,
      totalWeeks: 20,
      periodsByWeekday: {for (var day = 1; day <= 7; day++) day: periods},
    );
    return ScheduleData(
      term: term,
      courses: [
        Course(
          id: 'c1',
          name: '色彩美学',
          teacher: '刘杰',
          colorValue: 0xFF7D9DCE,
          sessions: [
            CourseSession(
              id: 's1',
              weekday: today.weekday,
              startPeriod: 1,
              endPeriod: 2,
              weekRule:
                  WeekRule(startWeek: 1, endWeek: 20, type: WeekType.every),
              location: 'B108',
            ),
          ],
        ),
        Course(
          id: 'c2',
          name: '数学分析',
          teacher: '尤超',
          colorValue: 0xFFE07A5F,
          sessions: [
            CourseSession(
              id: 's2',
              weekday: today.weekday,
              startPeriod: 3,
              endPeriod: 4,
              weekRule:
                  WeekRule(startWeek: 1, endWeek: 20, type: WeekType.every),
              location: 'B31',
            ),
          ],
        ),
      ],
    );
  }

  Future<void> pumpWith(
    WidgetTester tester,
    AppearanceSettings appearance,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          scheduleControllerProvider.overrideWith(
            () => _FakeScheduleController(dataWithTwoCourses()),
          ),
          appearanceProvider.overrideWithValue(appearance),
        ],
        child: const CourseScheduleApp(),
      ),
    );
    await tester.pump();
  }

  /// 切到「本周」页签。
  Future<void> openWeekTab(WidgetTester tester) async {
    await tester.tap(find.text('本周'));
    await tester.pumpAndSettle();
  }

  group('周视图布局设置', () {
    test('默认是瀑布流', () {
      expect(const AppearanceSettings().weekLayout, AppWeekLayout.waterfall);
    });

    test('两种布局都有中文标签', () {
      expect(AppWeekLayout.waterfall.label, '瀑布流');
      expect(AppWeekLayout.table.label, '表格');
    });

    test('能序列化并在往返后保持不变', () {
      const table = AppearanceSettings(weekLayout: AppWeekLayout.table);
      final restored = AppearanceSettings.fromKeyValues(table.toKeyValues());
      expect(restored.weekLayout, AppWeekLayout.table);

      const fallback = AppearanceSettings(weekLayout: AppWeekLayout.waterfall);
      final restored2 = AppearanceSettings.fromKeyValues(
        fallback.toKeyValues(),
      );
      expect(restored2.weekLayout, AppWeekLayout.waterfall);
    });

    test('存储里缺失或非法时回退到瀑布流（升级不炸）', () {
      final restored = AppearanceSettings.fromKeyValues(
        const {'appearance.weekLayout': '不存在的值'},
      );
      expect(restored.weekLayout, AppWeekLayout.waterfall);
    });

    test('copyWith 能单独改布局且不动其它字段', () {
      const base = AppearanceSettings(
        weekLayout: AppWeekLayout.waterfall,
        showWeekend: false,
      );
      final next = base.copyWith(weekLayout: AppWeekLayout.table);
      expect(next.weekLayout, AppWeekLayout.table);
      expect(next.showWeekend, isFalse);
    });
  });

  group('首页「本周」按设置切换渲染', () {
    testWidgets('瀑布流：课程按天分组纵向排列，显示教师与教室', (tester) async {
      await pumpWith(tester, const AppearanceSettings());
      await openWeekTab(tester);

      expect(find.text('色彩美学'), findsWidgets);
      expect(find.text('数学分析'), findsWidgets);
      expect(find.textContaining('B108'), findsWidgets);
    });

    testWidgets('表格：出现星期表头与节次列（二维矩阵）', (tester) async {
      await pumpWith(
        tester,
        const AppearanceSettings(weekLayout: AppWeekLayout.table),
      );
      await openWeekTab(tester);

      // 表头：星期（去掉「周」字后的单字）
      expect(find.text('一'), findsWidgets);
      expect(find.text('五'), findsWidgets);
      // 纵轴节次号
      expect(find.textContaining('1\n'), findsWidgets);
      // 矩阵里画了课
      expect(find.text('色彩美学'), findsWidgets);
    });

    testWidgets('表格模式显示周末与否随「显示周末」设置变化', (tester) async {
      await pumpWith(
        tester,
        const AppearanceSettings(
          weekLayout: AppWeekLayout.table,
          showWeekend: true,
        ),
      );
      await openWeekTab(tester);
      expect(find.text('六'), findsWidgets);
      expect(find.text('日'), findsWidgets);
    });
  });
}

class _FakeScheduleController extends ScheduleController {
  _FakeScheduleController(this._data);

  final ScheduleData _data;

  @override
  Future<ScheduleData> build() async => _data;
}
