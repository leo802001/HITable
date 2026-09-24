import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../application/schedule_controller.dart';
import '../domain/appearance_settings.dart';
import '../domain/schedule_engine.dart';
import '../domain/schedule_models.dart';
import 'widget_background_renderer.dart';

/// 桌面小组件的数据同步服务。
///
/// 按「**大节**」聚合而不是按课程条目：一个 (星期, 起止节次) 时间片
/// 就是一行，同一片里多门课合并成 `A / B`。这与用户参考的 Scriptable
/// 版小组件口径一致，也避免同一节课在列表里出现两次。
///
/// 不做倒计时：需要精确闹钟，耗电且易被省电策略打断。
class NextCourseWidgetService {
  const NextCourseWidgetService();

  static const _channel = MethodChannel('offline_course_schedule/widget');

  Future<void> sync(
    ScheduleData schedule, {
    DateTime? now,
    WidgetColorPreset colorPreset = WidgetColorPreset.iosClassic,
    CustomColorScheme? customColors,
    AppColorScheme? colorScheme,
    WidgetBackgroundSpec? background,
  }) async {
    // 背景图先在 Dart 侧算好（原生侧没有可用的模糊方案），
    // 失败就退回「无背景」，不影响课程本身的渲染。
    String? backgroundPath;
    if (background != null) {
      backgroundPath = await const WidgetBackgroundRenderer().render(
        sourcePath: background.path,
        blur: background.blur,
      );
    }
    final payload = buildPayload(
      schedule,
      now ?? DateTime.now(),
      colorPreset: colorPreset,
      customColors: customColors,
      colorScheme: colorScheme,
      background: background,
      backgroundPath: backgroundPath,
    );
    await _channel.invokeMethod<void>('update', payload);
  }

  /// 产出给原生小组件的数据。
  ///
  /// ```dart
  /// {
  ///   'dateLabel': '9月22日 周二',
  ///   'weekLabel': '第4教学周 · 双周',
  ///   'slotCount': 3,
  ///   'slots': [
  ///     {'name':'色彩美学','meta':'B108 · 刘杰','startTime':'08:00',
  ///      'endTime':'09:45','startMillis':…,'endMillis':…,
  ///      'status':'ongoing'|'upcoming'|'finished'},
  ///   ],
  ///   'palette':      {'text':…, 'sub':…, 'active':…, 'accent':…, …},
  ///   'paletteNight': {…同样 8 个键，深色用…},
  /// }
  /// ```
  ///
  /// 深浅两套都下发：小组件渲染在原生侧，拿不到 Flutter 的 Theme，
  /// 由原生按 `UI_MODE_NIGHT_MASK` 选用，切换系统深色才有效果。
  Map<String, Object> buildPayload(
    ScheduleData schedule,
    DateTime current, {
    WidgetColorPreset colorPreset = WidgetColorPreset.iosClassic,
    CustomColorScheme? customColors,
    AppColorScheme? colorScheme,
    WidgetBackgroundSpec? background,
    String? backgroundPath,
  }) {
    final light = _paletteFor(colorPreset, customColors, colorScheme);
    final palette = _encode(light);
    final nightPalette = _encode(_nightPalette(light));
    final backgroundFields = _backgroundFields(background, backgroundPath);
    final term = schedule.term;
    if (term == null) {
      return <String, Object>{
        'dateLabel': '',
        'weekLabel': '',
        'slotCount': 0,
        'slots': const <Object>[],
        'palette': palette,
        'paletteNight': nightPalette,
        ...backgroundFields,
      };
    }

    final engine = ScheduleEngine(
      term: term,
      courses: schedule.courses,
      adjustments: schedule.adjustments,
      cancellations: schedule.cancellations,
    );

    final today = DateTime(current.year, current.month, current.day);
    final slots = _slotsFor(engine, today, current);

    return <String, Object>{
      'dateLabel': _dateLabel(today),
      'weekLabel': _weekLabel(engine.getWeekForDate(today)),
      'slotCount': slots.length,
      'slots': slots,
      'palette': palette,
      'paletteNight': nightPalette,
      ...backgroundFields,
    };
  }

  /// 兼容旧调用点。
  List<Map<String, Object>> buildItems(
    ScheduleData schedule,
    DateTime current,
  ) {
    final payload = buildPayload(schedule, current);
    return (payload['slots']! as List).cast<Map<String, Object>>();
  }

  /// 自定义背景相关字段。
  ///
  /// `bgPath` 非空即代表「自定义背景模式」—— 原生据此切到**另一套元素逻辑**：
  /// 卡片底色改成带 alpha 的圆角位图、文字套用 `textAlpha`。
  /// 路径为空（未选图 / 渲染失败）时原生完全走原来的不透明卡片，行为不变。
  ///
  /// 四个字段**总是**下发：漏发会让上一轮的旧值残留在原生侧，
  /// 下次开启背景时出现「透明度还停在上次」的怪异表现。
  Map<String, Object> _backgroundFields(
    WidgetBackgroundSpec? background,
    String? backgroundPath,
  ) => <String, Object>{
    'bgPath': (backgroundPath != null && backgroundPath.isNotEmpty)
        ? backgroundPath
        : '',
    'bgDim': background?.dim ?? 0.0,
    'cardAlpha': background?.cardOpacity ?? 1.0,
    'textAlpha': background?.textOpacity ?? 1.0,
  };

  /// 把当日课程按大节聚合、判状态、排序。
  List<Map<String, Object>> _slotsFor(
    ScheduleEngine engine,
    DateTime today,
    DateTime current,
  ) {
    final grouped = <String, List<ScheduledCourse>>{};
    for (final item in engine.getCoursesForDate(today)) {
      final key = '${item.session.startPeriod}-${item.session.endPeriod}';
      grouped.putIfAbsent(key, () => <ScheduledCourse>[]).add(item);
    }

    final slots = <Map<String, Object>>[];
    for (final group in grouped.values) {
      // 组内按课程名排序，保证刷新前后顺序稳定（不会跳来跳去）
      group.sort((a, b) => a.course.name.compareTo(b.course.name));
      final first = group.first;

      // 大节起止取组内最早开始 / 最晚结束，兼容同片课时间略有差异
      var start = first.startTime;
      var end = first.endTime;
      for (final g in group) {
        if (g.startTime.isBefore(start)) start = g.startTime;
        if (g.endTime.isAfter(end)) end = g.endTime;
      }

      slots.add(<String, Object>{
        'name': group.map((g) => g.course.name).join(' / '),
        'meta': group.map(_metaOf).where((s) => s.isNotEmpty).join(' | '),
        'startTime': _time(start),
        'endTime': _time(end),
        'startMillis': start.millisecondsSinceEpoch,
        'endMillis': end.millisecondsSinceEpoch,
        'status': !end.isAfter(current)
            ? 'finished'
            : (!start.isAfter(current) ? 'ongoing' : 'upcoming'),
      });
    }

    // 未结束的按时间升序在前，已结束的沉到底部
    slots.sort((a, b) {
      final aDone = a['status'] == 'finished';
      final bDone = b['status'] == 'finished';
      if (aDone != bDone) return aDone ? 1 : -1;
      return (a['startMillis'] as int).compareTo(b['startMillis'] as int);
    });
    return slots;
  }

  /// 「地点 · 教师」，缺一不可地拼接。
  String _metaOf(ScheduledCourse item) {
    final bits = <String>[];
    if (item.session.location.trim().isNotEmpty) {
      bits.add(item.session.location.trim());
    }
    if (item.teacher.trim().isNotEmpty) bits.add(item.teacher.trim());
    return bits.join(' · ');
  }

  /// 解析出浅色色板**模型**。
  ///
  /// 由 Dart 算而不是让原生查资源：「跟随应用」要用 Flutter 侧的配色对象，
  /// 原生拿不到。
  WidgetPalette _paletteFor(
    WidgetColorPreset preset,
    CustomColorScheme? customColors,
    AppColorScheme? scheme,
  ) => preset.palette ?? _paletteFromApp(customColors, scheme);

  /// 把色板编码成原生直接可用的 ARGB 整数 Map。
  Map<String, Object> _encode(WidgetPalette p) => <String, Object>{
    'text': p.text.toARGB32(),
    'sub': p.sub.toARGB32(),
    'active': p.active.toARGB32(),
    'accent': p.accent.toARGB32(),
    'doneText': p.doneText.toARGB32(),
    'card': p.card.toARGB32(),
    'activeBg': p.activeBg.toARGB32(),
    'doneBg': p.doneBg.toARGB32(),
  };

  /// 「跟随应用」：用 App 当前配色推导，观感与 App 一致。
  WidgetPalette _paletteFromApp(
    CustomColorScheme? customColors,
    AppColorScheme? scheme,
  ) {
    final accent =
        customColors?.accent ?? scheme?.accent ?? const Color(0xFF7D9DCE);
    final seed = customColors?.seed ?? scheme?.seed ?? const Color(0xFF607D8B);
    return WidgetPalette(
      card: Color.lerp(accent, Colors.white, 0.88)!,
      accent: seed,
      active: accent,
      activeBg: Color.lerp(accent, Colors.white, 0.82)!,
      doneBg: const Color(0xFFEFEFF4),
      doneText: const Color(0xFFA0A0A5),
      text: const Color(0xFF111111),
      sub: const Color(0xFF8A8A8E),
    );
  }

  /// 深色版色板：由浅色版推导，保留饱和的强调色（暗底上更醒目），
  /// 只把文字、底色换成深色系。
  ///
  /// 这样新增配色预设时**不用再手写一套深色值**，一处定义两处生效。
  WidgetPalette _nightPalette(WidgetPalette light) => WidgetPalette(
    // 底色：从强调色往黑里压，保留一点色相，避免死灰
    card: Color.lerp(light.active, const Color(0xFF000000), 0.84)!,
    activeBg: Color.lerp(light.active, const Color(0xFF000000), 0.72)!,
    doneBg: Color.lerp(light.active, const Color(0xFF000000), 0.86)!,
    // 文字：近白 / 中灰
    text: const Color(0xFFF5F5F7),
    sub: const Color(0xFF9A9AA0),
    doneText: const Color(0xFF7C7C82),
    // 强调色保持原样：这些色本身就饱和，暗底上照样清楚
    active: light.active,
    accent: light.accent,
  );

  String _time(DateTime value) =>
      '${value.hour.toString().padLeft(2, '0')}:'
      '${value.minute.toString().padLeft(2, '0')}';

  String _dateLabel(DateTime date) =>
      '${date.month}月${date.day}日 '
      '${const ['周一', '周二', '周三', '周四', '周五', '周六', '周日'][date.weekday - 1]}';

  String _weekLabel(int? week) =>
      week == null ? '学期未开始' : '第$week教学周 · ${week.isOdd ? '单周' : '双周'}';
}

/// 小组件自定义背景的参数（`AppearanceSettings` → 数据下发层的桥）。
///
/// 只在**已选图且开关打开**时构造；为 null 即「自定义背景模式关闭」，
/// 原生走原来的不透明卡片。
class WidgetBackgroundSpec {
  const WidgetBackgroundSpec({
    required this.path,
    required this.blur,
    required this.dim,
    required this.cardOpacity,
    required this.textOpacity,
  });

  /// 背景图源文件路径（App 私有目录里的副本）。
  final String path;

  /// 高斯模糊强度（0~30）。
  final double blur;

  /// 明暗蒙层（0~0.8）—— 由原生合成时叠加，不烘焙进 PNG。
  final double dim;

  /// 课程卡片不透明度（0.1~1.0）。
  final double cardOpacity;

  /// 文字内容不透明度（0.1~1.0）。
  final double textOpacity;
}
