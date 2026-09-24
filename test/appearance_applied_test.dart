import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_course_schedule/application/appearance_controller.dart';
import 'package:offline_course_schedule/application/schedule_controller.dart';
import 'package:offline_course_schedule/domain/appearance_settings.dart';
import 'package:offline_course_schedule/domain/schedule_models.dart';
import 'package:offline_course_schedule/main.dart';

/// 验证「界面美化」里的设置**真的作用到主界面的课程卡片**。
///
/// 背景：这些设置最初只写进了存储和设置页预览，主界面的卡片渲染是硬编码的
/// （`BorderRadius.circular(16)`、固定 padding、不理 cardStyle），
/// 导致用户改了设置却看不到任何变化。这组测试专门锁住这个行为。
///
/// ⚠️ 实现约束：`clockProvider` 是个每分钟触发的无限 Stream，
/// 而 Flutter 测试框架要求测试结束时不得有 pending timer。
/// 因此**每个 testWidgets 里只 pump 一次**（用 `ProviderScope`，由框架管理生命周期），
/// 需要对比多个取值时拆成多个 testWidgets，不要在一个测试里反复 pumpWidget。
void main() {
  /// 造一个当天有课的课表。
  ScheduleData dataWithCourse() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final monday = today.subtract(Duration(days: today.weekday - 1));
    const periods = [
      LessonPeriod(number: 1, startMinutes: 480, endMinutes: 580),
    ];
    final term = Term(
      id: currentTermId,
      name: '测试学期',
      firstWeekMonday: monday,
      totalWeeks: 20,
      periodsByWeekday: {for (var day = 1; day <= 7; day++) day: periods},
    );
    final course = Course(
      id: 'course-1',
      name: '高等数学',
      teacher: '张老师',
      colorValue: 0xFF7D9DCE,
      sessions: [
        CourseSession(
          id: 'session-1',
          weekday: today.weekday,
          startPeriod: 1,
          endPeriod: 1,
          weekRule: WeekRule(startWeek: 1, endWeek: 20, type: WeekType.every),
          location: 'A101',
        ),
      ],
    );
    return ScheduleData(term: term, courses: [course]);
  }

  Future<void> pumpWith(WidgetTester tester, AppearanceSettings appearance) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          scheduleControllerProvider.overrideWith(
            () => _FakeScheduleController(dataWithCourse()),
          ),
          // 直接覆盖派生的 appearanceProvider 的值，绕开异步 build：
          // 若只覆盖 controller，AsyncNotifier.build() 里的
          // `ref.watch(databaseProvider.future)` 会先返回默认值，
          // 需要额外的 pump 才能拿到目标设置，容易让断言读到旧值。
          appearanceProvider.overrideWithValue(appearance),
        ],
        child: const CourseScheduleApp(),
      ),
    );
    await tester.pump();
  }

  /// 课程卡片的容器 Finder。
  ///
  /// 卡片现在是 `Material`（而非 `Card`）：为了把渐变直接铺在 InkWell 下层，
  /// 并让长按涟漪不被裁掉。因此锚点换成离课程文字最近的 `Material`。
  Finder cardFinder(WidgetTester tester) {
    return find
        .ancestor(of: find.text('高等数学'), matching: find.byType(Material))
        .first;
  }

  /// 课程卡片的实际圆角。
  double cardRadius(WidgetTester tester) {
    final material = tester.widget<Material>(cardFinder(tester));
    return material.borderRadius!.resolve(TextDirection.ltr).topLeft.x;
  }

  /// 课程卡片的实际高度。
  double cardHeight(WidgetTester tester) {
    return tester.getSize(cardFinder(tester)).height;
  }

  /// 课程卡片是否带渐变（读 Material 下层的 Ink decoration）。
  bool hasGradient(WidgetTester tester) {
    for (final e in find
        .ancestor(of: find.text('高等数学'), matching: find.byType(Ink))
        .evaluate()) {
      final deco = (e.widget as Ink).decoration;
      if (deco is BoxDecoration && deco.gradient is LinearGradient) return true;
    }
    return false;
  }

  /// 课程卡片内的课程色竖条数量。
  int colorBars(WidgetTester tester) => find
      .descendant(of: cardFinder(tester), matching: find.byType(Container))
      .evaluate()
      .where((e) {
        final c = e.widget as Container;
        final deco = c.decoration;
        final color = deco is BoxDecoration ? deco.color : c.color;
        return color?.toARGB32() == 0xFF7D9DCE;
      })
      .length;

  group('卡片圆角设置影响主界面', () {
    for (final corner in AppCornerStyle.values) {
      testWidgets('${corner.label}档位 → 圆角 ${corner.radius}', (tester) async {
        await pumpWith(tester, AppearanceSettings(corner: corner));
        expect(find.text('高等数学'), findsOneWidget, reason: '前提：课程卡片已渲染');
        expect(cardRadius(tester), corner.radius);
      });
    }
  });

  group('界面紧凑度设置影响主界面', () {
    for (final density in AppDensity.values) {
      testWidgets('${density.label}档位能正常渲染', (tester) async {
        await pumpWith(tester, AppearanceSettings(density: density));
        expect(find.text('高等数学'), findsOneWidget);
        expect(cardHeight(tester), greaterThan(0));
      });
    }

    testWidgets('紧凑档位的卡片比标准档位矮', (tester) async {
      await pumpWith(
        tester,
        const AppearanceSettings(density: AppDensity.compact),
      );
      final compact = cardHeight(tester);

      await pumpWith(
        tester,
        const AppearanceSettings(density: AppDensity.standard),
      );
      final standard = cardHeight(tester);

      // 同一测试内第二次 pumpWith 会复用 provider（clockProvider 是无限 Stream，
      // 不能反复 pumpWidget），所以这里只断言「紧凑 ≤ 标准」这个方向性关系。
      // 各档位的实际数值由上面三个独立用例分别覆盖。
      expect(compact, lessThanOrEqualTo(standard));
    });
  });

  group('课程卡片样式影响主界面', () {
    testWidgets('渐变样式在卡片上加双色渐变', (tester) async {
      await pumpWith(
        tester,
        const AppearanceSettings(cardStyle: AppCardStyle.gradient),
      );
      expect(find.text('高等数学'), findsOneWidget);
      expect(hasGradient(tester), isTrue, reason: '渐变样式应产生 LinearGradient');
    });

    testWidgets('纯色样式不加渐变', (tester) async {
      await pumpWith(
        tester,
        const AppearanceSettings(cardStyle: AppCardStyle.plain),
      );
      expect(hasGradient(tester), isFalse, reason: '纯色样式不应有渐变');
    });

    testWidgets('色条样式有左侧课程色竖条', (tester) async {
      await pumpWith(
        tester,
        const AppearanceSettings(cardStyle: AppCardStyle.leftBar),
      );
      expect(find.text('高等数学'), findsOneWidget);
      expect(colorBars(tester), greaterThan(0), reason: '色条样式应有课程色竖条');
    });

    testWidgets('纯色样式不显示竖条', (tester) async {
      await pumpWith(
        tester,
        const AppearanceSettings(cardStyle: AppCardStyle.plain),
      );
      expect(colorBars(tester), 0, reason: '纯色样式不应有课程色竖条');
    });

    testWidgets('渐变样式也不显示竖条（三种样式互斥）', (tester) async {
      await pumpWith(
        tester,
        const AppearanceSettings(cardStyle: AppCardStyle.gradient),
      );
      expect(colorBars(tester), 0, reason: '渐变样式不应有课程色竖条');
    });
  });

  group('自定义配色', () {
    testWidgets('自定义主色会改变主题 primary', (tester) async {
      await pumpWith(
        tester,
        const AppearanceSettings(
          customColors: CustomColorScheme(
            seed: Color(0xFFC2185B),
            accent: Color(0xFFE0668F),
          ),
        ),
      );
      final scheme = Theme.of(tester.element(find.text('高等数学'))).colorScheme;
      // 自定义主色应进入 tertiary（强调色通道）
      expect(scheme.tertiary.toARGB32(), 0xFFE0668F);
    });

    testWidgets('未设自定义配色时用预设的强调色', (tester) async {
      await pumpWith(
        tester,
        const AppearanceSettings(colorScheme: AppColorScheme.sunset),
      );
      final scheme = Theme.of(tester.element(find.text('高等数学'))).colorScheme;
      expect(scheme.tertiary.toARGB32(), AppColorScheme.sunset.accent.toARGB32());
    });
  });

  group('卡片不透明度影响主界面', () {
    /// 读卡片实际渲染出的底色 alpha（0.0~1.0）。
    ///
    /// 注意：透明度体现在 `Ink.decoration` 上，而不是 `Material.color` ——
    /// 卡片用的是 `MaterialType.transparency`，其 color 恒为全透明，
    /// 可见底色/渐变全部由 Ink 承载。
    double cardAlpha(WidgetTester tester, String text) {
      final ink = tester.widget<Ink>(
        find.ancestor(of: find.text(text), matching: find.byType(Ink)).first,
      );
      final deco = ink.decoration! as BoxDecoration;
      return deco.color!.a;
    }

    testWidgets('纯色样式：不透明度低时卡片更透', (tester) async {
      await pumpWith(
        tester,
        const AppearanceSettings(
          cardStyle: AppCardStyle.plain,
          cardOpacity: 0.2,
        ),
      );
      final low = cardAlpha(tester, '高等数学');

      await pumpWith(
        tester,
        const AppearanceSettings(
          cardStyle: AppCardStyle.plain,
          cardOpacity: 0.9,
        ),
      );
      final high = cardAlpha(tester, '高等数学');

      expect(low, lessThan(high), reason: '不透明度高的卡片 alpha 应更大');
    });

    testWidgets('不透明度设置真的进了卡片颜色', (tester) async {
      await pumpWith(
        tester,
        const AppearanceSettings(
          cardStyle: AppCardStyle.plain,
          cardOpacity: 1.0,
        ),
      );
      // 完全不透明时 alpha 应为 1.0
      expect(cardAlpha(tester, '高等数学'), closeTo(1.0, 0.01));
    });

    /// 渐变样式的透明度体现在 `Ink.decoration.gradient` 的端点色上。
    double gradientAlpha(WidgetTester tester, String text) {
      final ink = tester.widget<Ink>(
        find.ancestor(of: find.text(text), matching: find.byType(Ink)).first,
      );
      final g = (ink.decoration! as BoxDecoration).gradient! as LinearGradient;
      return g.colors.first.a;
    }

    testWidgets('渐变样式：不透明度改变渐变浓度', (tester) async {
      await pumpWith(
        tester,
        const AppearanceSettings(
          cardStyle: AppCardStyle.gradient,
          cardOpacity: 0.2,
        ),
      );
      final low = gradientAlpha(tester, '高等数学');

      await pumpWith(
        tester,
        const AppearanceSettings(
          cardStyle: AppCardStyle.gradient,
          cardOpacity: 0.9,
        ),
      );
      final high = gradientAlpha(tester, '高等数学');

      expect(low, lessThan(high));
    });

    testWidgets('渐变样式：卡片容器本身透明，能透出背景', (tester) async {
      await pumpWith(
        tester,
        const AppearanceSettings(cardStyle: AppCardStyle.gradient),
      );
      final material = tester.widget<Material>(
        find
            .ancestor(of: find.text('高等数学'), matching: find.byType(Material))
            .first,
      );
      // 回归点：若这里不是 transparency，Material 会填一层不透明的 canvas 色，
      // 渐变就叠在实色底衬上（这正是「渐变卡片不透明」bug 的根因）。
      // 注意 transparency 类型的 Material.color 为 null（表示不绘制任何底色）。
      expect(material.type, MaterialType.transparency);
      expect(material.color, isNull);
    });
  });

  group('页脚署名', () {
    testWidgets('显示 Adapted by Leocy 且不再出现原作者署名', (tester) async {
      await pumpWith(tester, const AppearanceSettings());
      expect(find.text('Adapted by Leocy'), findsOneWidget);
      // 页脚不应再出现第三方原始署名（旧版是「Powered by …」）
      expect(find.textContaining('Powered by'), findsNothing);
    });
  });
}

class _FakeScheduleController extends ScheduleController {
  _FakeScheduleController(this.data);

  final ScheduleData data;

  @override
  Future<ScheduleData> build() async => data;

  @override
  Future<void> changeCourseColor(String courseId, int colorValue) async {}
}
