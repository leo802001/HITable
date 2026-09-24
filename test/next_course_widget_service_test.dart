import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_course_schedule/application/schedule_controller.dart';
import 'package:offline_course_schedule/domain/appearance_settings.dart';
import 'package:offline_course_schedule/domain/schedule_models.dart';
import 'package:offline_course_schedule/widget/next_course_widget_service.dart';

/// 小组件数据契约测试。
///
/// 2026-09-22 起按「大节」聚合（参照用户提供的 Scriptable 版实现）：
/// - 字段从 `courses` 改为 `slots`，每项含 `name` / `meta` / 起止时间 / 状态；
/// - 顶部另有 `dateLabel` 与 `weekLabel`；
/// - 同一时间片的多门课合并为一行，名称用 ` / ` 连接。
void main() {
  const service = NextCourseWidgetService();

  /// 造一个「周三」的学期，含可指定的若干课程。
  ScheduleData buildData({
    required DateTime today,
    required List<Course> courses,
    int totalWeeks = 20,
  }) {
    final monday = today.subtract(Duration(days: today.weekday - 1));
    final term = Term(
      id: currentTermId,
      name: '测试学期',
      firstWeekMonday: monday,
      totalWeeks: totalWeeks,
      periodsByWeekday: {
        for (var day = 1; day <= 7; day++)
          day: const [
            LessonPeriod(number: 1, startMinutes: 480, endMinutes: 525),
            LessonPeriod(number: 2, startMinutes: 530, endMinutes: 585),
            LessonPeriod(number: 3, startMinutes: 600, endMinutes: 645),
            LessonPeriod(number: 4, startMinutes: 650, endMinutes: 705),
          ],
      },
    );
    return ScheduleData(term: term, courses: courses);
  }

  Course courseAt({
    required String id,
    required String name,
    required int weekday,
    required int startPeriod,
    required int endPeriod,
    String teacher = '张老师',
    String location = 'A101',
  }) {
    return Course(
      id: id,
      name: name,
      teacher: teacher,
      colorValue: 0xFF7D9DCE,
      sessions: [
        CourseSession(
          id: '$id-s',
          weekday: weekday,
          startPeriod: startPeriod,
          endPeriod: endPeriod,
          weekRule: WeekRule(startWeek: 1, endWeek: 20, type: WeekType.every),
          location: location,
        ),
      ],
    );
  }

  test('输出 slots/dateLabel/weekLabel/slotCount 四个字段', () {
    final today = DateTime(2026, 9, 23); // 周三
    final moment = DateTime(2026, 9, 23, 7, 0);
    final payload = service.buildPayload(
      buildData(
        today: today,
        courses: [
          courseAt(id: 'c1', name: '色彩美学', weekday: 3, startPeriod: 1, endPeriod: 2),
        ],
      ),
      moment,
    );
    expect(payload['dateLabel'], '9月23日 周三');
    expect(payload['weekLabel'], contains('教学周'));
    expect(payload['slotCount'], 1);
    expect(payload['slots'], isA<List<Object>>());
  });

  test('同一大节的多门课合并为一行，名称用 / 连接', () {
    final today = DateTime(2026, 9, 23);
    final moment = DateTime(2026, 9, 23, 10, 30); // 第3-4节时段
    final payload = service.buildPayload(
      buildData(
        today: today,
        courses: [
          courseAt(
            id: 'c1',
            name: '大学英语',
            weekday: 3,
            startPeriod: 3,
            endPeriod: 4,
            location: 'B703',
            teacher: '赵红珊',
          ),
          courseAt(
            id: 'c2',
            name: '数学推理方法',
            weekday: 3,
            startPeriod: 3,
            endPeriod: 4,
            location: 'B918',
            teacher: 'SAVELEV',
          ),
        ],
      ),
      moment,
    );
    final slots = (payload['slots']! as List).cast<Map<String, Object>>();
    // 两门课在同一时间片 → 只有一行
    expect(slots.length, 1);
    expect(slots.single['name'], '大学英语 / 数学推理方法');
    // meta 两条用 | 分隔
    expect(slots.single['meta'], contains(' | '));
    expect(payload['slotCount'], 1);
  });

  test('不同大节各自成行，未结束按时间升序', () {
    final today = DateTime(2026, 9, 23);
    final moment = DateTime(2026, 9, 23, 7, 0);
    final payload = service.buildPayload(
      buildData(
        today: today,
        courses: [
          courseAt(id: 'c1', name: '第一节的课', weekday: 3, startPeriod: 1, endPeriod: 2),
          courseAt(id: 'c2', name: '第三节的课', weekday: 3, startPeriod: 3, endPeriod: 4),
        ],
      ),
      moment,
    );
    final slots = (payload['slots']! as List).cast<Map<String, Object>>();
    expect(slots.length, 2);
    expect(slots[0]['name'], '第一节的课');
    expect(slots[1]['name'], '第三节的课');
  });

  test('三态判定：未开始 / 进行中 / 已结束', () {
    final today = DateTime(2026, 9, 23);
    final data = buildData(
      today: today,
      courses: [
        courseAt(id: 'c1', name: '上午课', weekday: 3, startPeriod: 1, endPeriod: 2),
        courseAt(id: 'c2', name: '下午课', weekday: 3, startPeriod: 3, endPeriod: 4),
      ],
    );

    // 08:30 —— 上午课进行中（08:00~09:45），下午课未开始
    final mid = DateTime(2026, 9, 23, 8, 30);
    final slotsMid = (service.buildPayload(data, mid)['slots']! as List)
        .cast<Map<String, Object>>();
    expect(slotsMid.firstWhere((s) => s['name'] == '上午课')['status'], 'ongoing');
    expect(slotsMid.firstWhere((s) => s['name'] == '下午课')['status'], 'upcoming');

    // 11:00 —— 上午课已结束
    final late = DateTime(2026, 9, 23, 11, 0);
    final slotsLate = (service.buildPayload(data, late)['slots']! as List)
        .cast<Map<String, Object>>();
    expect(slotsLate.firstWhere((s) => s['name'] == '上午课')['status'], 'finished');
  });

  test('已结束的沉到底部，未结束的排前面', () {
    final today = DateTime(2026, 9, 23);
    final data = buildData(
      today: today,
      courses: [
        courseAt(id: 'c1', name: '上午课', weekday: 3, startPeriod: 1, endPeriod: 2),
        courseAt(id: 'c2', name: '下午课', weekday: 3, startPeriod: 3, endPeriod: 4),
      ],
    );
    // 10:30 —— 上午课已结束、下午课未开始 → 下午课应排前面
    final moment = DateTime(2026, 9, 23, 10, 30);
    final slots = (service.buildPayload(data, moment)['slots']! as List)
        .cast<Map<String, Object>>();
    expect(slots.map((s) => s['name']).toList(), ['下午课', '上午课']);
  });

  test('每项含课程名/地点教师/起止时间/状态', () {
    final today = DateTime(2026, 9, 23);
    final moment = DateTime(2026, 9, 23, 7, 0);
    final slots = (service
            .buildPayload(
              buildData(
                today: today,
                courses: [
                  courseAt(
                    id: 'c1',
                    name: '色彩美学',
                    weekday: 3,
                    startPeriod: 1,
                    endPeriod: 2,
                    location: 'B108',
                    teacher: '刘杰',
                  ),
                ],
              ),
              moment,
            )['slots']! as List)
        .cast<Map<String, Object>>();
    final s = slots.single;
    expect(s['name'], '色彩美学');
    expect(s['meta'], 'B108 · 刘杰');
    expect(s['startTime'], matches(RegExp(r'^\d{2}:\d{2}$')));
    expect(s['endTime'], matches(RegExp(r'^\d{2}:\d{2}$')));
    expect(s['status'], 'upcoming');
  });

  test('没有学期时返回空结构而不是抛异常', () {
    final payload = service.buildPayload(const ScheduleData(), DateTime(2026, 9, 23));
    expect(payload['slots'], isEmpty);
    expect(payload['slotCount'], 0);
    expect(payload['dateLabel'], '');
  });

  test('学期有值但当天无课时，dateLabel 非空（用于区分无课与未同步）', () {
    final today = DateTime(2026, 9, 23);
    // 只有周四的课，查询周三 → 空
    final data = buildData(
      today: today,
      courses: [
        courseAt(id: 'c1', name: '别天的课', weekday: 4, startPeriod: 1, endPeriod: 2),
      ],
    );
    final payload = service.buildPayload(data, DateTime(2026, 9, 23, 8, 0));
    expect(payload['slots'], isEmpty);
    expect(payload['dateLabel'], isNotEmpty);
  });

  group('小组件配色下发', () {
    /// 粗略感知亮度，用来判断「深色是否真的更暗」。
    double lum(int argb) {
      final r = (argb >> 16) & 0xFF;
      final g = (argb >> 8) & 0xFF;
      final b = argb & 0xFF;
      return 0.2126 * r + 0.7152 * g + 0.0722 * b;
    }

    Map<String, Object> paletteOf({
      WidgetColorPreset preset = WidgetColorPreset.iosClassic,
      bool night = false,
    }) {
      final payload = service.buildPayload(const ScheduleData(), DateTime(2026, 9, 23));
      return (payload[night ? 'paletteNight' : 'palette']! as Map)
          .cast<String, Object>();
    }

    test('浅色与深色两套色板都下发（否则切深色没效果）', () {
      final payload = service.buildPayload(const ScheduleData(), DateTime(2026, 9, 23));
      expect(payload['palette'], isA<Map<String, Object>>());
      expect(payload['paletteNight'], isA<Map<String, Object>>());
    });

    test('两套色板各含 8 个键，原生取色不会缺项', () {
      const keys = [
        'text', 'sub', 'active', 'accent', 'doneText', 'card', 'activeBg', 'doneBg',
      ];
      for (final night in [false, true]) {
        for (final k in keys) {
          expect(paletteOf(night: night)[k], isA<int>(), reason: '$k (night=$night)');
        }
      }
    });

    test('深色底色明显更暗、文字明显更亮', () {
      final light = paletteOf();
      final dark = paletteOf(night: true);
      for (final key in ['card', 'activeBg', 'doneBg']) {
        expect(
          lum(dark[key]! as int),
          lessThan(lum(light[key]! as int)),
          reason: '$key 深色底没有变暗',
        );
      }
      expect(
        lum(dark['text']! as int),
        greaterThan(lum(light['text']! as int)),
        reason: '深色文字没有变亮',
      );
    });

    test('深浅两套整体不相同（不是照抄）', () {
      final light = paletteOf();
      final dark = paletteOf(night: true);
      // Map 的 == 是引用比较，必须逐键比
      final diff = light.keys.where((k) => light[k] != dark[k]).length;
      expect(diff, greaterThanOrEqualTo(6), reason: '深浅两套太像了');
    });

    test('不同配色预设下发的色值不同（否则改了没反应）', () {
      final seen = <String>{};
      for (final preset in WidgetColorPreset.values) {
        final payload = service.buildPayload(
          const ScheduleData(),
          DateTime(2026, 9, 23),
          colorPreset: preset,
        );
        final p = (payload['palette']! as Map).cast<String, Object>();
        seen.add('${p['active']}-${p['accent']}-${p['card']}');
      }
      expect(seen.length, WidgetColorPreset.values.length,
          reason: '有预设下发相同色值，用户切换会看不出区别');
    });

    test('自定义配色会改变下发色值', () {
      final before = paletteOf();
      final after = service.buildPayload(
        const ScheduleData(),
        DateTime(2026, 9, 23),
        colorPreset: WidgetColorPreset.followApp,
        customColors: const CustomColorScheme(
          seed: Color(0xFF112233),
          accent: Color(0xFF445566),
        ),
      )['palette']! as Map;
      expect(after['active'] != before['active'], isTrue);
    });

    test('跟随应用与具体预设产出不同色值', () {
      final follow = service.buildPayload(
        const ScheduleData(),
        DateTime(2026, 9, 23),
        colorPreset: WidgetColorPreset.followApp,
      )['palette']! as Map;
      final ios = service.buildPayload(
        const ScheduleData(),
        DateTime(2026, 9, 23),
        colorPreset: WidgetColorPreset.iosClassic,
      )['palette']! as Map;
      expect(follow['active'] != ios['active'], isTrue);
    });
  });

  group('小组件自定义背景下发（1.1.9）', () {
    const spec = WidgetBackgroundSpec(
      path: '/data/bg.png',
      blur: 12,
      dim: 0.4,
      cardOpacity: 0.6,
      textOpacity: 0.85,
    );

    test('默认不下发背景路径，透明度为 1 —— 与 1.1.8 行为一致', () {
      final payload = service.buildPayload(
        const ScheduleData(),
        DateTime(2026, 9, 23),
      );
      expect(payload['bgPath'], '');
      expect(payload['cardAlpha'], 1.0);
      expect(payload['textAlpha'], 1.0);
    });

    test('传了 background 但没渲染出路径时，仍不进自定义背景模式', () {
      // 图被删 / 解码失败 / 只是测试 buildPayload 都会走到这条分支。
      // 必须退回普通样式，否则小组件会变成半透明的空壳。
      final payload = service.buildPayload(
        const ScheduleData(),
        DateTime(2026, 9, 23),
        background: spec,
      );
      expect(payload['bgPath'], '');
      expect(payload['bgDim'], 0.4);
      expect(payload['cardAlpha'], 0.6);
      expect(payload['textAlpha'], 0.85);
    });

    test('有了渲染路径才进入自定义背景模式', () {
      final payload = service.buildPayload(
        const ScheduleData(),
        DateTime(2026, 9, 23),
        background: spec,
        backgroundPath: '/data/user/0/pkg/files/widget_bg.png',
      );
      expect(payload['bgPath'], '/data/user/0/pkg/files/widget_bg.png');
      expect(payload['cardAlpha'], 0.6);
      expect(payload['textAlpha'], 0.85);
    });

    test('四个背景字段在「有学期」「无学期」两条分支都下发', () {
      // 漏发会让上一轮的旧值残留在原生侧，下次开启背景时透明度还停在旧值。
      final payloads = <Map<String, Object>>[
        service.buildPayload(
          buildData(today: DateTime(2026, 9, 23), courses: const []),
          DateTime(2026, 9, 23, 8),
          background: spec,
          backgroundPath: '/x.png',
        ),
        service.buildPayload(const ScheduleData(), DateTime(2026, 9, 23)),
      ];
      for (final payload in payloads) {
        expect(payload.containsKey('bgPath'), isTrue);
        expect(payload.containsKey('bgDim'), isTrue);
        expect(payload.containsKey('cardAlpha'), isTrue);
        expect(payload.containsKey('textAlpha'), isTrue);
      }
    });

    test('hasWidgetBackground 需要开关与图片同时具备', () {
      const switchOnOnly = AppearanceSettings(widgetUseBackground: true);
      expect(switchOnOnly.hasWidgetBackground, isFalse);

      const imageOnly = AppearanceSettings(widgetBackgroundPath: '/a.png');
      expect(imageOnly.hasWidgetBackground, isFalse);

      const both = AppearanceSettings(
        widgetUseBackground: true,
        widgetBackgroundPath: '/a.png',
      );
      expect(both.hasWidgetBackground, isTrue);
    });

    test('背景与透明度设置能存能读（升级不丢配置）', () {
      const original = AppearanceSettings(
        widgetUseBackground: true,
        widgetBackgroundPath: '/data/x.png',
        widgetBackgroundBlur: 21,
        widgetBackgroundDim: 0.55,
        widgetCardOpacity: 0.42,
        widgetTextOpacity: 0.77,
      );
      final restored = AppearanceSettings.fromKeyValues(original.toKeyValues());
      expect(restored.widgetUseBackground, isTrue);
      expect(restored.widgetBackgroundPath, '/data/x.png');
      expect(restored.widgetBackgroundBlur, 21);
      expect(restored.widgetBackgroundDim, 0.55);
      expect(restored.widgetCardOpacity, 0.42);
      expect(restored.widgetTextOpacity, 0.77);
      expect(restored.hasWidgetBackground, isTrue);
    });

    test('没设置过背景的旧配置读出来是安全的默认值', () {
      final fallback = AppearanceSettings();
      final restored = AppearanceSettings.fromKeyValues(const {});
      expect(restored.widgetUseBackground, isFalse);
      expect(restored.widgetBackgroundPath, isNull);
      expect(restored.widgetBackgroundBlur, fallback.widgetBackgroundBlur);
      expect(restored.widgetCardOpacity, fallback.widgetCardOpacity);
      expect(restored.widgetTextOpacity, fallback.widgetTextOpacity);
      expect(restored.hasWidgetBackground, isFalse);
    });

    test('越界的透明度/模糊会被夹到合法区间', () {
      final restored = AppearanceSettings.fromKeyValues(const {
        'appearance.widgetCardOpacity': '0',
        'appearance.widgetTextOpacity': '9',
        'appearance.widgetBackgroundBlur': '999',
        'appearance.widgetBackgroundDim': '-1',
      });
      expect(restored.widgetCardOpacity, 0.1);
      expect(restored.widgetTextOpacity, 1.0);
      expect(restored.widgetBackgroundBlur, 30);
      expect(restored.widgetBackgroundDim, 0);
    });

    test('clearWidgetBackground 能真正清掉路径', () {
      const original = AppearanceSettings(
        widgetUseBackground: true,
        widgetBackgroundPath: '/a.png',
      );
      final cleared = original.copyWith(clearWidgetBackground: true);
      expect(cleared.widgetBackgroundPath, isNull);
      expect(cleared.hasWidgetBackground, isFalse);
    });
  });
}
