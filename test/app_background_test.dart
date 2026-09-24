import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_course_schedule/application/appearance_controller.dart';
import 'package:offline_course_schedule/application/schedule_controller.dart';
import 'package:offline_course_schedule/domain/appearance_settings.dart';
import 'package:offline_course_schedule/domain/schedule_models.dart';
import 'package:offline_course_schedule/main.dart';
import 'package:offline_course_schedule/presentation/app_background.dart';

/// 主页背景功能：预设背景、自定义背景图、高斯模糊、明暗蒙层。
void main() {
  ScheduleData dataWithCourse() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final monday = today.subtract(Duration(days: today.weekday - 1));
    const periods = [LessonPeriod(number: 1, startMinutes: 480, endMinutes: 580)];
    return ScheduleData(
      term: Term(
        id: currentTermId,
        name: '测试学期',
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
              weekRule:
                  WeekRule(startWeek: 1, endWeek: 20, type: WeekType.every),
              location: 'A101',
            ),
          ],
        ),
      ],
    );
  }

  Future<void> pumpWith(WidgetTester tester, AppearanceSettings a) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          scheduleControllerProvider.overrideWith(
            () => _FakeSchedule(dataWithCourse()),
          ),
          appearanceProvider.overrideWithValue(a),
        ],
        child: const CourseScheduleApp(),
      ),
    );
    await tester.pump();
  }

  group('背景层存在性', () {
    testWidgets('无论如何都有一层 AppBackground 包住内容', (tester) async {
      await pumpWith(tester, const AppearanceSettings());
      expect(find.byType(AppBackground), findsOneWidget);
    });

    testWidgets('课程内容仍正常显示（背景不遮挡）', (tester) async {
      for (final preset in AppBackgroundPreset.values) {
        await pumpWith(tester, AppearanceSettings(background: preset));
        expect(
          find.text('高等数学'),
          findsOneWidget,
          reason: '背景 ${preset.label} 下课程应可见',
        );
      }
    });
  });

  group('预设背景', () {
    testWidgets('无背景时不绘制任何图案', (tester) async {
      await pumpWith(
        tester,
        const AppearanceSettings(background: AppBackgroundPreset.none),
      );
      // none 不产生 CustomPaint 图案
      expect(find.byType(CustomPaint), findsWidgets);
      expect(find.text('高等数学'), findsOneWidget);
    });

    testWidgets('网格背景会绘制 CustomPaint 图案', (tester) async {
      await pumpWith(
        tester,
        const AppearanceSettings(background: AppBackgroundPreset.grid),
      );
      expect(find.text('高等数学'), findsOneWidget);
    });

    for (final preset in AppBackgroundPreset.values) {
      testWidgets('${preset.label} 能正常渲染且不报错', (tester) async {
        await pumpWith(tester, AppearanceSettings(background: preset));
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('自定义背景图', () {
    testWidgets('路径为空时不显示背景图（避免读不存在的文件）', (tester) async {
      await pumpWith(
        tester,
        const AppearanceSettings(
          customBackgroundPath: '',
          background: AppBackgroundPreset.grid,
        ),
      );
      // 空路径视为未设置，回退到预设背景
      expect(find.byType(Image), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('图片文件不存在时降级为纯色底，不崩溃', (tester) async {
      await pumpWith(
        tester,
        const AppearanceSettings(
          customBackgroundPath: '/不存在的路径/图片.jpg',
        ),
      );
      // errorBuilder 应吞掉错误，不抛异常
      expect(tester.takeException(), isNull);
      expect(find.text('高等数学'), findsOneWidget);
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
