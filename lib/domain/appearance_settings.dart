/// 界面外观设置。
///
/// 只影响呈现层，不改变任何课程数据。所有选项都持久化在
/// `app_settings` 表里（key-value），因此对已有用户是无损升级。
library;

import 'package:flutter/material.dart';

/// 首页顶部默认显示的问候语。
///
/// 用户可在「界面美化 → 首页标题」里改成任意内容。
const defaultGreeting = 'Hi，Table~';

/// 预设配色方案。
///
/// 每套方案包含三个颜色，让卡片能做出**有层次**的渐变：
/// - [seed] 主色，Material 3 据此生成完整色阶；
/// - [accent] 强调色，用于选中态与课程卡片；
/// - [accentAlt] 次强调色，与 [accent] 一起构成卡片渐变的两个端点。
enum AppColorScheme {
  slate('青灰', Color(0xFF607D8B), Color(0xFF7D9DCE), Color(0xFFA8C0D8)),
  aurora('蓝粉', Color(0xFF5B8DEF), Color(0xFF6FA8F5), Color(0xFFF0A6C8)),
  celadon('青瓷', Color(0xFF2E9E8F), Color(0xFF56B8A5), Color(0xFFA8D8B9)),
  sunset('落日', Color(0xFFE07A5F), Color(0xFFE8906F), Color(0xFFF2C879)),
  amethyst('紫檀', Color(0xFF7E57C2), Color(0xFF9575CD), Color(0xFFC9A7E8)),
  graphite('石墨', Color(0xFF546E7A), Color(0xFF78909C), Color(0xFFB0BEC5)),
  forest('苔原', Color(0xFF4E7A4A), Color(0xFF6B9E63), Color(0xFFC2C97F)),
  ocean('深海', Color(0xFF2A6F9E), Color(0xFF3E8FC4), Color(0xFF7FD4D8)),
  rose('玫瑰', Color(0xFFC2185B), Color(0xFFE0668F), Color(0xFFF3B0C3)),
  sand('沙丘', Color(0xFFA9844F), Color(0xFFC9A46A), Color(0xFFE3D3A8)),
  ink('水墨', Color(0xFF37474F), Color(0xFF546E7A), Color(0xFFB0AFA8)),
  candy('糖果', Color(0xFF8E6BE8), Color(0xFFB18FF0), Color(0xFFF5A8D5));

  const AppColorScheme(this.label, this.seed, this.accent, this.accentAlt);

  /// 设置页显示名称。
  final String label;

  /// Material 3 种子色。
  final Color seed;

  /// 强调色（用于课表卡片、选中态等）。
  final Color accent;

  /// 渐变的第二个端点色。
  final Color accentAlt;
}

/// 自定义配色（用户自选两个颜色）。
///
/// 与预设 [AppColorScheme] 互斥：`customColors != null` 时优先使用它。
@immutable
class CustomColorScheme {
  const CustomColorScheme({required this.seed, required this.accent});

  /// 默认自定义值（与「蓝粉」一致，用户一进来就能看到效果）。
  static const fallback = CustomColorScheme(
    seed: Color(0xFF5B8DEF),
    accent: Color(0xFFF0A6C8),
  );

  final Color seed;
  final Color accent;

  Map<String, String> toKeyValues() => {
        'appearance.custom.seed': seed.toARGB32().toRadixString(16),
        'appearance.custom.accent': accent.toARGB32().toRadixString(16),
      };

  static CustomColorScheme? fromKeyValues(Map<String, String> v) {
    final seed = _hex(v['appearance.custom.seed']);
    final accent = _hex(v['appearance.custom.accent']);
    if (seed == null && accent == null) return null;
    return CustomColorScheme(
      seed: seed ?? fallback.seed,
      accent: accent ?? fallback.accent,
    );
  }

  static Color? _hex(String? raw) {
    if (raw == null) return null;
    final parsed = int.tryParse(raw, radix: 16);
    return parsed == null ? null : Color(parsed);
  }

  @override
  bool operator ==(Object other) =>
      other is CustomColorScheme && other.seed == seed && other.accent == accent;

  @override
  int get hashCode => Object.hash(seed, accent);
}

/// 卡片圆角档位。
enum AppCornerStyle {
  sharp('方正', 4),
  standard('标准', 12),
  round('圆润', 20),
  pill('極圆', 28);

  const AppCornerStyle(this.label, this.radius);

  final String label;
  final double radius;
}

/// 界面紧凑度。
enum AppDensity {
  compact('紧凑', 0.85),
  standard('标准', 1.0),
  relaxed('宽松', 1.15);

  const AppDensity(this.label, this.scale);

  final String label;

  /// 间距缩放系数。
  final double scale;
}

/// 课表卡片里显示的课程块装饰风格。
///
/// 三种风格的区分度必须**一眼可辨**，所以不只是改透明度：
/// 纯色靠底色、色条靠左侧竖条、渐变靠整块斜向双色过渡。
enum AppCardStyle {
  /// 只用极淡的课程色做底，无竖条、无渐变，最克制。
  plain('纯色'),

  /// 左侧一道醒目竖条 + 几乎无色的底。
  leftBar('色条'),

  /// 斜向双色渐变铺满整块，视觉最重。
  gradient('渐变');

  const AppCardStyle(this.label);

  final String label;
}

/// 首页顶部问候语的字体。
///
/// 中文衬线/书法字体在不同设备上不一定都装了，
/// 因此这里只设 [TextStyle.fontFamily] 候选列表，缺失时系统会自动回退，
/// 不会因为字体不存在而报错或显示方框。
enum AppTitleFont {
  /// 用系统默认字体（最稳，所有设备表现一致）。
  system('跟随系统', null),

  /// 仿宋（衬线，正式文档感）。
  fangsong('仿宋', ['FangSong', '仿宋', 'STFangsong']),

  /// 楷体（手写感，偏文艺）。
  kaiti('楷体', ['KaiTi', '楷体', 'STKaiti']),

  /// 黑体（无衬线，醒目）。
  heiti('黑体', ['Heiti SC', '黑体', 'STHeiti', 'SimHei']);

  const AppTitleFont(this.label, this.fontFamilies);

  final String label;

  /// 候选字体族；`null` 表示跟随系统默认。
  final List<String>? fontFamilies;
}

/// 主页背景的预设样式。
///
/// 全部基于主题色生成，**不引入图片资源**，也**保证课程文字可读**
/// （背景一律用极低对比度的色块或纯色）。
enum AppBackgroundPreset {
  none('无'),
  plain('纯色'),
  softGradient('柔和渐变'),
  grid('网格'),
  dots('圆点'),
  paper('纸纹');

  const AppBackgroundPreset(this.label);

  final String label;
}

/// 首页「本周」页签的排布方式。
///
/// 两种布局在**形状**上有本质差异，一眼可辨：
/// - [waterfall]（瀑布流）：按天竖排，每天一张卡片列表，适合刷课、看详情；
/// - [table]（表格）：横轴星期、纵轴节次，整周一眼纵览空档。
enum AppWeekLayout {
  /// 按天分组的竖排卡片流（原有样式）。
  waterfall('瀑布流'),

  /// 星期 × 节次的二维表格。
  table('表格');

  const AppWeekLayout(this.label);

  final String label;
}

/// 小组件配色预设。
///
/// 每套是一个完整色板，与 App 内配色**独立**：
/// 用户可能想要 App 用「青瓷」而小组件用「iOS 经典」。
enum WidgetColorPreset {
  /// 跟随 App 内选定的配色方案。
  followApp('跟随应用', null),

  /// iOS 经典：系统蓝 + 橙，参考 Scriptable 版默认配色。
  iosClassic('iOS 经典', WidgetPalette(
    card: Color(0xFFF2F2F7),
    accent: Color(0xFFFF9500),
    active: Color(0xFF0A84FF),
    activeBg: Color(0xFFE3F0FF),
    doneBg: Color(0xFFEFEFF4),
    doneText: Color(0xFFA0A0A5),
    text: Color(0xFF111111),
    sub: Color(0xFF8A8A8E),
  )),

  /// 静谧蓝：冷色调，整体偏灰蓝，适合长时间注视。
  calmBlue('静谧蓝', WidgetPalette(
    card: Color(0xFFEDF2F7),
    accent: Color(0xFF5B8DEF),
    active: Color(0xFF2A6F9E),
    activeBg: Color(0xFFDCE9F5),
    doneBg: Color(0xFFEDEFF2),
    doneText: Color(0xFF9BA6B2),
    text: Color(0xFF1A2028),
    sub: Color(0xFF7A8794),
  )),

  /// 暖阳：橙棕系，温暖醒目。
  warmSun('暖阳', WidgetPalette(
    card: Color(0xFFFDF3E7),
    accent: Color(0xFFE8820C),
    active: Color(0xFFD2691E),
    activeBg: Color(0xFFFBE8D3),
    doneBg: Color(0xFFF2EDE6),
    doneText: Color(0xFFADA49A),
    text: Color(0xFF2B2118),
    sub: Color(0xFF8D8177),
  )),

  /// 青瓷：绿松石色调，清冷雅致。
  celadon('青瓷', WidgetPalette(
    card: Color(0xFFEBF4F1),
    accent: Color(0xFF56B8A5),
    active: Color(0xFF2E9E8F),
    activeBg: Color(0xFFD9EFEA),
    doneBg: Color(0xFFEDF2F0),
    doneText: Color(0xFF9AA8A4),
    text: Color(0xFF17211F),
    sub: Color(0xFF74847F),
  )),

  /// 石墨：低饱和灰阶，极简。
  graphite('石墨', WidgetPalette(
    card: Color(0xFFF0F1F3),
    accent: Color(0xFF78909C),
    active: Color(0xFF546E7A),
    activeBg: Color(0xFFE1E6E9),
    doneBg: Color(0xFFEFF0F1),
    doneText: Color(0xFFA5AAAF),
    text: Color(0xFF1B1F22),
    sub: Color(0xFF7B838A),
  ));

  const WidgetColorPreset(this.label, this.palette);

  final String label;

  /// 色板；为 null 表示跟随 App 配色。
  final WidgetPalette? palette;
}

/// 小组件的一套具体色板。
///
/// 只定义浅色态；深色由原生 `values-night/` 资源提供 ——
/// 小组件渲染发生在原生侧，拿不到 Flutter 的 Theme。
@immutable
class WidgetPalette {
  const WidgetPalette({
    required this.card,
    required this.accent,
    required this.active,
    required this.activeBg,
    required this.doneBg,
    required this.doneText,
    required this.text,
    required this.sub,
  });

  /// 普通课程块底色。
  final Color card;

  /// 未开始（右侧时间）的强调色。
  final Color accent;

  /// 进行中主色。
  final Color active;

  /// 进行中块底色。
  final Color activeBg;

  /// 已结束块底色。
  final Color doneBg;

  /// 已结束文字色。
  final Color doneText;

  /// 主文字色。
  final Color text;

  /// 次要文字色。
  final Color sub;
}

/// 深浅模式偏好。
enum AppThemePreference {
  system('跟随系统'),
  light('浅色'),
  dark('深色');

  const AppThemePreference(this.label);

  final String label;

  ThemeMode get themeMode => switch (this) {
        AppThemePreference.system => ThemeMode.system,
        AppThemePreference.light => ThemeMode.light,
        AppThemePreference.dark => ThemeMode.dark,
      };
}

/// 完整的界面外观设置。
@immutable
class AppearanceSettings {
  const AppearanceSettings({
    this.colorScheme = AppColorScheme.slate,
    this.customColors,
    this.themeMode = AppThemePreference.system,
    this.corner = AppCornerStyle.standard,
    this.density = AppDensity.standard,
    this.cardStyle = AppCardStyle.plain,
    this.cardOpacity = 0.55,
    this.appBarOpacity = 0.0,
    this.greetingText = defaultGreeting,
    this.hideGreeting = false,
    this.titleFont = AppTitleFont.system,
    this.showWeekend = true,
    this.useAmoledBlack = false,
    this.weekLayout = AppWeekLayout.waterfall,
    this.widgetColorPreset = WidgetColorPreset.iosClassic,
    this.background = AppBackgroundPreset.none,
    this.customBackgroundPath,
    this.backgroundBlur = 0,
    this.backgroundDim = 0.35,
    this.widgetUseBackground = false,
    this.widgetBackgroundPath,
    this.widgetBackgroundBlur = 8,
    this.widgetBackgroundDim = 0.35,
    this.widgetCardOpacity = 0.75,
    this.widgetTextOpacity = 1,
  });

  /// 预设配色（[customColors] 非空时被忽略）。
  final AppColorScheme colorScheme;

  /// 自定义配色，非空时优先于 [colorScheme]。
  final CustomColorScheme? customColors;

  final AppThemePreference themeMode;
  final AppCornerStyle corner;
  final AppDensity density;
  final AppCardStyle cardStyle;

  /// 课程卡片的不透明度（0.15~1.0）。
  final double cardOpacity;

  /// 顶部栏的不透明度（0~1）。
  final double appBarOpacity;

  /// 首页顶部显示的问候语。
  final String greetingText;

  /// 是否隐藏首页顶部的问候语。
  final bool hideGreeting;

  /// 问候语字体。
  final AppTitleFont titleFont;

  /// 是否在课表中显示周六周日。
  final bool showWeekend;

  /// 深色模式下是否使用纯黑背景（OLED 省电）。
  final bool useAmoledBlack;

  /// 「本周」页签的排布方式（瀑布流 / 表格）。
  final AppWeekLayout weekLayout;

  /// 桌面小组件的配色预设（独立于 App 配色）。
  final WidgetColorPreset widgetColorPreset;

  /// 主页背景样式（预设）。
  final AppBackgroundPreset background;

  /// 自定义背景图的本地文件路径（null 表示未设置）。
  final String? customBackgroundPath;

  /// 自定义背景图的高斯模糊强度（0~30）。
  final double backgroundBlur;

  /// 背景变暗/变淡程度（0~0.8），用于压低背景保证文字可读。
  final double backgroundDim;

  /// 桌面小组件是否启用自定义背景。
  ///
  /// 与主页背景**同一套策略**（自定义图 + 高斯模糊 + 明暗蒙层），
  /// 但字段独立：用户可能希望主页清爽、小组件有底图，反之亦然。
  final bool widgetUseBackground;

  /// 小组件背景图的本地文件路径（null 表示未选择）。
  final String? widgetBackgroundPath;

  /// 小组件背景图的高斯模糊强度（0~30），语义同 [backgroundBlur]。
  final double widgetBackgroundBlur;

  /// 小组件背景的明暗蒙层（0~0.8），语义同 [backgroundDim]。
  final double widgetBackgroundDim;

  /// **自定义背景模式下**课程卡片的不透明度（0.1~1.0）。
  ///
  /// 只在 [hasWidgetBackground] 为真时生效 —— 无背景时卡片不透明才好看。
  final double widgetCardOpacity;

  /// **自定义背景模式下**文字内容的不透明度（0.1~1.0）。
  ///
  /// 与 [widgetCardOpacity] 相互独立：卡片可以很透，文字仍然清楚。
  /// 只作用于文字，不影响左侧色条（色条是视觉强调，不该跟着变淡）。
  final double widgetTextOpacity;

  /// 小组件是否真的有可用的自定义背景（开关 + 已选图）。
  bool get hasWidgetBackground =>
      widgetUseBackground &&
      widgetBackgroundPath != null &&
      widgetBackgroundPath!.isNotEmpty;

  /// 当前实际生效的种子色。
  Color get effectiveSeed => customColors?.seed ?? colorScheme.seed;

  /// 当前实际生效的强调色。
  Color get effectiveAccent => customColors?.accent ?? colorScheme.accent;

  /// 当前实际生效的渐变第二端点色。
  Color get effectiveAccentAlt => customColors == null
      ? colorScheme.accentAlt
      : Color.lerp(customColors!.accent, Colors.white, 0.45)!;

  /// 是否使用自定义配色。
  bool get isCustomColors => customColors != null;

  /// 是否有可用的背景（预设非 none 或设了自定义图）。
  bool get hasCustomBackground =>
      customBackgroundPath != null && customBackgroundPath!.isNotEmpty;

  AppearanceSettings copyWith({
    AppColorScheme? colorScheme,
    CustomColorScheme? customColors,
    bool clearCustomColors = false,
    AppThemePreference? themeMode,
    AppCornerStyle? corner,
    AppDensity? density,
    AppCardStyle? cardStyle,
    double? cardOpacity,
    double? appBarOpacity,
    String? greetingText,
    bool? hideGreeting,
    AppTitleFont? titleFont,
    bool? showWeekend,
    bool? useAmoledBlack,
    AppWeekLayout? weekLayout,
    WidgetColorPreset? widgetColorPreset,
    AppBackgroundPreset? background,
    String? customBackgroundPath,
    bool clearCustomBackground = false,
    double? backgroundBlur,
    double? backgroundDim,
    bool? widgetUseBackground,
    String? widgetBackgroundPath,
    bool clearWidgetBackground = false,
    double? widgetBackgroundBlur,
    double? widgetBackgroundDim,
    double? widgetCardOpacity,
    double? widgetTextOpacity,
  }) {
    return AppearanceSettings(
      colorScheme: colorScheme ?? this.colorScheme,
      customColors: clearCustomColors
          ? null
          : (customColors ?? this.customColors),
      themeMode: themeMode ?? this.themeMode,
      corner: corner ?? this.corner,
      density: density ?? this.density,
      cardStyle: cardStyle ?? this.cardStyle,
      cardOpacity: cardOpacity ?? this.cardOpacity,
      appBarOpacity: appBarOpacity ?? this.appBarOpacity,
      greetingText: greetingText ?? this.greetingText,
      hideGreeting: hideGreeting ?? this.hideGreeting,
      titleFont: titleFont ?? this.titleFont,
      showWeekend: showWeekend ?? this.showWeekend,
      useAmoledBlack: useAmoledBlack ?? this.useAmoledBlack,
      weekLayout: weekLayout ?? this.weekLayout,
      widgetColorPreset: widgetColorPreset ?? this.widgetColorPreset,
      background: background ?? this.background,
      customBackgroundPath: clearCustomBackground
          ? null
          : (customBackgroundPath ?? this.customBackgroundPath),
      backgroundBlur: backgroundBlur ?? this.backgroundBlur,
      backgroundDim: backgroundDim ?? this.backgroundDim,
      widgetUseBackground: widgetUseBackground ?? this.widgetUseBackground,
      widgetBackgroundPath: clearWidgetBackground
          ? null
          : (widgetBackgroundPath ?? this.widgetBackgroundPath),
      widgetBackgroundBlur:
          widgetBackgroundBlur ?? this.widgetBackgroundBlur,
      widgetBackgroundDim: widgetBackgroundDim ?? this.widgetBackgroundDim,
      widgetCardOpacity: widgetCardOpacity ?? this.widgetCardOpacity,
      widgetTextOpacity: widgetTextOpacity ?? this.widgetTextOpacity,
    );
  }

  /// 序列化为 `app_settings` 里的多条 key-value。
  Map<String, String> toKeyValues() => {
        'appearance.colorScheme': colorScheme.name,
        'appearance.themeMode': themeMode.name,
        'appearance.corner': corner.name,
        'appearance.density': density.name,
        'appearance.cardStyle': cardStyle.name,
        'appearance.cardOpacity': cardOpacity.toStringAsFixed(2),
        'appearance.appBarOpacity': appBarOpacity.toStringAsFixed(2),
        'appearance.greetingText': greetingText,
        'appearance.hideGreeting': hideGreeting ? '1' : '0',
        'appearance.titleFont': titleFont.name,
        'appearance.showWeekend': showWeekend ? '1' : '0',
        'appearance.useAmoledBlack': useAmoledBlack ? '1' : '0',
        'appearance.weekLayout': weekLayout.name,
        'appearance.widgetColorPreset': widgetColorPreset.name,
        'appearance.background': background.name,
        'appearance.backgroundBlur': backgroundBlur.toStringAsFixed(1),
        'appearance.backgroundDim': backgroundDim.toStringAsFixed(2),
        if (customBackgroundPath != null)
          'appearance.customBackground': customBackgroundPath!,
        'appearance.widgetUseBackground': widgetUseBackground ? '1' : '0',
        'appearance.widgetBackgroundBlur':
            widgetBackgroundBlur.toStringAsFixed(1),
        'appearance.widgetBackgroundDim': widgetBackgroundDim.toStringAsFixed(2),
        'appearance.widgetCardOpacity': widgetCardOpacity.toStringAsFixed(2),
        'appearance.widgetTextOpacity': widgetTextOpacity.toStringAsFixed(2),
        if (widgetBackgroundPath != null)
          'appearance.widgetBackground': widgetBackgroundPath!,
        if (customColors != null) ...customColors!.toKeyValues(),
      };

  /// 从 `app_settings` 读出的键值对还原设置。
  /// 任何未知或缺失的值都回退到默认，保证升级不炸。
  factory AppearanceSettings.fromKeyValues(Map<String, String> values) {
    const fallback = AppearanceSettings();
    final path = values['appearance.customBackground'];
    final widgetPath = values['appearance.widgetBackground'];
    return AppearanceSettings(
      colorScheme: _enumByName(
        AppColorScheme.values,
        values['appearance.colorScheme'],
        fallback.colorScheme,
      ),
      customColors: CustomColorScheme.fromKeyValues(values),
      themeMode: _enumByName(
        AppThemePreference.values,
        values['appearance.themeMode'],
        fallback.themeMode,
      ),
      corner: _enumByName(
        AppCornerStyle.values,
        values['appearance.corner'],
        fallback.corner,
      ),
      density: _enumByName(
        AppDensity.values,
        values['appearance.density'],
        fallback.density,
      ),
      cardStyle: _enumByName(
        AppCardStyle.values,
        values['appearance.cardStyle'],
        fallback.cardStyle,
      ),
      hideGreeting: values['appearance.hideGreeting'] == '1',
      titleFont: _enumByName(
        AppTitleFont.values,
        values['appearance.titleFont'],
        fallback.titleFont,
      ),
      greetingText: (values['appearance.greetingText']?.trim().isNotEmpty ??
              false)
          ? values['appearance.greetingText']!
          : fallback.greetingText,
      appBarOpacity: _double(values['appearance.appBarOpacity'],
          fallback.appBarOpacity, min: 0, max: 1),
      cardOpacity: _double(values['appearance.cardOpacity'],
          fallback.cardOpacity, min: 0.15, max: 1),
      showWeekend: values['appearance.showWeekend'] != '0',
      useAmoledBlack: values['appearance.useAmoledBlack'] == '1',
      weekLayout: _enumByName(
        AppWeekLayout.values,
        values['appearance.weekLayout'],
        fallback.weekLayout,
      ),
      widgetColorPreset: _enumByName(
        WidgetColorPreset.values,
        values['appearance.widgetColorPreset'],
        fallback.widgetColorPreset,
      ),
      background: _enumByName(
        AppBackgroundPreset.values,
        values['appearance.background'],
        fallback.background,
      ),
      customBackgroundPath: (path == null || path.isEmpty) ? null : path,
      backgroundBlur: _double(values['appearance.backgroundBlur'],
          fallback.backgroundBlur, min: 0, max: 30),
      backgroundDim:
          _double(values['appearance.backgroundDim'], fallback.backgroundDim,
              min: 0, max: 0.8),
      widgetUseBackground: values['appearance.widgetUseBackground'] == '1',
      widgetBackgroundPath:
          (widgetPath == null || widgetPath.isEmpty) ? null : widgetPath,
      widgetBackgroundBlur: _double(values['appearance.widgetBackgroundBlur'],
          fallback.widgetBackgroundBlur, min: 0, max: 30),
      widgetBackgroundDim: _double(values['appearance.widgetBackgroundDim'],
          fallback.widgetBackgroundDim, min: 0, max: 0.8),
      widgetCardOpacity: _double(values['appearance.widgetCardOpacity'],
          fallback.widgetCardOpacity, min: 0.1, max: 1),
      widgetTextOpacity: _double(values['appearance.widgetTextOpacity'],
          fallback.widgetTextOpacity, min: 0.1, max: 1),
    );
  }

  static double _double(
    String? raw,
    double fallback, {
    required double min,
    required double max,
  }) {
    final parsed = double.tryParse(raw ?? '');
    if (parsed == null || parsed.isNaN) return fallback;
    if (parsed < min) return min;
    if (parsed > max) return max;
    return parsed;
  }

  static T _enumByName<T extends Enum>(List<T> values, String? name, T fallback) {
    if (name == null) return fallback;
    for (final value in values) {
      if (value.name == name) return value;
    }
    return fallback;
  }

  @override
  bool operator ==(Object other) =>
      other is AppearanceSettings &&
      other.colorScheme == colorScheme &&
      other.customColors == customColors &&
      other.themeMode == themeMode &&
      other.corner == corner &&
      other.density == density &&
      other.cardStyle == cardStyle &&
      other.cardOpacity == cardOpacity &&
      other.appBarOpacity == appBarOpacity &&
      other.greetingText == greetingText &&
      other.hideGreeting == hideGreeting &&
      other.titleFont == titleFont &&
      other.showWeekend == showWeekend &&
      other.useAmoledBlack == useAmoledBlack &&
      other.weekLayout == weekLayout &&
      other.widgetColorPreset == widgetColorPreset &&
      other.background == background &&
      other.customBackgroundPath == customBackgroundPath &&
      other.backgroundBlur == backgroundBlur &&
      other.backgroundDim == backgroundDim &&
      other.widgetUseBackground == widgetUseBackground &&
      other.widgetBackgroundPath == widgetBackgroundPath &&
      other.widgetBackgroundBlur == widgetBackgroundBlur &&
      other.widgetBackgroundDim == widgetBackgroundDim &&
      other.widgetCardOpacity == widgetCardOpacity &&
      other.widgetTextOpacity == widgetTextOpacity;

  @override
  int get hashCode => Object.hashAll(<Object?>[
    colorScheme,
    customColors,
    themeMode,
    corner,
    density,
    cardStyle,
    cardOpacity,
    appBarOpacity,
    greetingText,
    hideGreeting,
    titleFont,
    showWeekend,
    useAmoledBlack,
    weekLayout,
    widgetColorPreset,
    background,
    customBackgroundPath,
    backgroundBlur,
    backgroundDim,
    widgetUseBackground,
    widgetBackgroundPath,
    widgetBackgroundBlur,
    widgetBackgroundDim,
    widgetCardOpacity,
    widgetTextOpacity,
  ]);
}
