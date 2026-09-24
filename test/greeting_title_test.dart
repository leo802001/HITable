import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_course_schedule/application/appearance_controller.dart';
import 'package:offline_course_schedule/application/schedule_controller.dart';
import 'package:offline_course_schedule/domain/appearance_settings.dart';
import 'package:offline_course_schedule/domain/schedule_models.dart';
import 'package:offline_course_schedule/main.dart';

void main() {
  ScheduleData data() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final monday = today.subtract(Duration(days: today.weekday - 1));
    const periods = [LessonPeriod(number: 1, startMinutes: 480, endMinutes: 580)];
    return ScheduleData(
      term: Term(
        id: currentTermId,
        name: '2026秋季',
        firstWeekMonday: monday,
        totalWeeks: 20,
        periodsByWeekday: {for (var d = 1; d <= 7; d++) d: periods},
      ),
      courses: [
        Course(
          id: 'c1',
          name: '高等数学',
          teacher: '张老师',
          colorValue: 0xFF7D9DCE,
          sessions: [
            CourseSession(
              id: 's1',
              weekday: today.weekday,
              startPeriod: 1,
              endPeriod: 1,
              weekRule: WeekRule(startWeek: 1, endWeek: 20, type: WeekType.every),
              location: 'A101',
            ),
          ],
        ),
      ],
    );
  }

  Future<void> pump(WidgetTester t, AppearanceSettings a) async {
    await t.pumpWidget(
      ProviderScope(
        overrides: [
          scheduleControllerProvider.overrideWith(() => _FakeSchedule(data())),
          appearanceProvider.overrideWithValue(a),
        ],
        child: const CourseScheduleApp(),
      ),
    );
    await t.pump();
  }

  group('首页标题（问候语）', () {
    test('默认值是 Hi，Table~', () {
      expect(const AppearanceSettings().greetingText, defaultGreeting);
      expect(defaultGreeting, 'Hi，Table~');
    });

    for (final text in [defaultGreeting, '我的课表', 'Hi~']) {
      test('序列化往返「$text」', () {
        final restored = AppearanceSettings.fromKeyValues(
          AppearanceSettings(greetingText: text).toKeyValues(),
        );
        expect(restored.greetingText, text);
      });
    }

    test('空字符串会回退为默认值（不把标题弄丢）', () {
      final restored = AppearanceSettings.fromKeyValues(
        const {'appearance.greetingText': '   '},
      );
      expect(restored.greetingText, defaultGreeting);
    });

    test('不同问候语不相等（能触发写库）', () {
      expect(
        const AppearanceSettings(greetingText: 'A') ==
            const AppearanceSettings(greetingText: 'B'),
        isFalse,
      );
    });

    testWidgets('默认显示 Hi，Table~（而不是学期名）', (t) async {
      await pump(t, const AppearanceSettings());
      expect(find.text(defaultGreeting), findsOneWidget);
      expect(find.text('2026秋季'), findsNothing);
    });

    testWidgets('自定义问候语会显示在首页顶部', (t) async {
      await pump(t, const AppearanceSettings(greetingText: '我的课表'));
      expect(find.text('我的课表'), findsOneWidget);
      expect(find.text(defaultGreeting), findsNothing);
    });

    testWidgets('问候语清空后回退显示学期名', (t) async {
      await pump(t, const AppearanceSettings(greetingText: ''));
      expect(find.text('2026秋季'), findsOneWidget);
    });

    testWidgets('问候语默认加粗', (t) async {
      await pump(t, const AppearanceSettings());
      final text = t.widget<Text>(find.text(defaultGreeting));
      expect(text.style?.fontWeight, FontWeight.bold);
    });
  });

  group('标题字体', () {
    test('四种字体都在列表里', () {
      expect(AppTitleFont.values.length, 4);
      expect(AppTitleFont.values.map((f) => f.label).toList(),
          ['跟随系统', '仿宋', '楷体', '黑体']);
    });

    test('跟随系统没有指定字体族', () {
      expect(AppTitleFont.system.fontFamilies, isNull);
    });

    test('其它字体都有候选族（缺失时可回退）', () {
      for (final f in AppTitleFont.values) {
        if (f == AppTitleFont.system) continue;
        expect(f.fontFamilies, isNotNull);
        expect(f.fontFamilies, isNotEmpty);
      }
    });

    for (final font in AppTitleFont.values) {
      test('字体「${font.label}」序列化往返', () {
        final restored = AppearanceSettings.fromKeyValues(
          AppearanceSettings(titleFont: font).toKeyValues(),
        );
        expect(restored.titleFont, font);
      });
    }

    test('未知字体名回退到默认（不抛异常）', () {
      final restored = AppearanceSettings.fromKeyValues(
        const {'appearance.titleFont': '不存在的字体'},
      );
      expect(restored.titleFont, AppTitleFont.system);
    });

    testWidgets('选仿宋时标题真的带上字体族', (t) async {
      await pump(t, const AppearanceSettings(titleFont: AppTitleFont.fangsong));
      final text = t.widget<Text>(find.text(defaultGreeting));
      expect(text.style?.fontFamily, 'FangSong');
      expect(text.style?.fontFamilyFallback, contains('仿宋'));
    });

    testWidgets('跟随系统时标题不指定字体族', (t) async {
      await pump(t, const AppearanceSettings(titleFont: AppTitleFont.system));
      final text = t.widget<Text>(find.text(defaultGreeting));
      expect(text.style?.fontFamily, isNull);
    });
  });

  group('标题隐藏', () {
    test('默认不隐藏', () {
      expect(const AppearanceSettings().hideGreeting, isFalse);
    });

    test('序列化往返', () {
      for (final hide in [true, false]) {
        final restored = AppearanceSettings.fromKeyValues(
          AppearanceSettings(hideGreeting: hide).toKeyValues(),
        );
        expect(restored.hideGreeting, hide);
      }
    });

    test('隐藏与否不相等（能触发写库）', () {
      expect(
        const AppearanceSettings(hideGreeting: true) ==
            const AppearanceSettings(hideGreeting: false),
        isFalse,
      );
    });

    testWidgets('开启隐藏后首页顶部不显示标题文字', (t) async {
      await pump(t, const AppearanceSettings(hideGreeting: true));
      expect(find.text(defaultGreeting), findsNothing);
      expect(find.text('2026秋季'), findsNothing);
      // 但页面主体仍正常（课程照常显示）
      expect(find.text('高等数学'), findsOneWidget);
    });

    testWidgets('关闭隐藏后标题回来', (t) async {
      await pump(t, const AppearanceSettings(hideGreeting: false));
      expect(find.text(defaultGreeting), findsOneWidget);
    });
  });
}

class _FakeSchedule extends ScheduleController {
  _FakeSchedule(this.data);
  final ScheduleData data;
  @override
  Future<ScheduleData> build() async => data;
  @override
  Future<void> changeCourseColor(String courseId, int colorValue) async {}
}
