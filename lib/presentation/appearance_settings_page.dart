/// 界面美化设置页。
///
/// 设计要点：所有选项**即时生效**（改一下立刻写库 + 刷新主题），
/// 顶部有一块「实时预览」，让用户不用退出去就能看到效果。
library;

import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart' show getDatabasesPath;

import '../application/appearance_controller.dart';
import '../domain/appearance_settings.dart';

class AppearanceSettingsPage extends ConsumerWidget {
  const AppearanceSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appearanceProvider);
    final controller = ref.read(appearanceControllerProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: const Text('界面美化'),
        actions: [
          IconButton(
            tooltip: '恢复默认',
            onPressed: () => _confirmReset(context, controller),
            icon: const Icon(Icons.restart_alt_rounded),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          _LivePreview(settings: settings),
          const SizedBox(height: 8),

          _Section(
            title: '配色方案',
            child: _ColorSchemePicker(
              current: settings.colorScheme,
              isCustom: settings.isCustomColors,
              custom: settings.customColors ?? CustomColorScheme.fallback,
              onChanged: (scheme) => controller.apply(
                settings.copyWith(
                  colorScheme: scheme,
                  clearCustomColors: true,
                ),
              ),
              onCustomChanged: (custom) => controller.apply(
                settings.copyWith(customColors: custom),
              ),
            ),
          ),

          _Section(
            title: '深浅模式',
            child: SegmentedButton<AppThemePreference>(
              segments: [
                for (final mode in AppThemePreference.values)
                  ButtonSegment(
                    value: mode,
                    label: Text(mode.label),
                    icon: Icon(switch (mode) {
                      AppThemePreference.system =>
                        Icons.brightness_auto_outlined,
                      AppThemePreference.light => Icons.light_mode_outlined,
                      AppThemePreference.dark => Icons.dark_mode_outlined,
                    }),
                  ),
              ],
              selected: {settings.themeMode},
              onSelectionChanged: (set) =>
                  controller.apply(settings.copyWith(themeMode: set.first)),
            ),
          ),

          _Section(
            title: '卡片圆角',
            child: SegmentedButton<AppCornerStyle>(
              segments: [
                for (final corner in AppCornerStyle.values)
                  ButtonSegment(value: corner, label: Text(corner.label)),
              ],
              selected: {settings.corner},
              onSelectionChanged: (set) =>
                  controller.apply(settings.copyWith(corner: set.first)),
            ),
          ),

          _Section(
            title: '界面紧凑度',
            subtitle: '紧凑可以在一屏里看到更多课程',
            child: SegmentedButton<AppDensity>(
              segments: [
                for (final density in AppDensity.values)
                  ButtonSegment(value: density, label: Text(density.label)),
              ],
              selected: {settings.density},
              onSelectionChanged: (set) =>
                  controller.apply(settings.copyWith(density: set.first)),
            ),
          ),

          _Section(
            title: '课程卡片样式',
            subtitle: '三种样式的形状不同；下方的「不透明度」统一控制卡片透出背景的程度',
            child: _CardStylePicker(
              current: settings.cardStyle,
              cardOpacity: settings.cardOpacity,
              onChanged: (style) =>
                  controller.apply(settings.copyWith(cardStyle: style)),
            ),
          ),

          _Section(
            title: '卡片不透明度',
            subtitle: '调低可以透出主页背景色/背景图，调高则卡片更实、文字更清晰',
            child: _SliderRow(
              icon: Icons.opacity_rounded,
              label: '不透明',
              value: settings.cardOpacity,
              min: 0.15,
              max: 1.0,
              suffix: '${(settings.cardOpacity * 100).round()}%',
              onChanged: (value) =>
                  controller.apply(settings.copyWith(cardOpacity: value)),
            ),
          ),

          _Section(
            title: '顶部栏不透明度',
            subtitle: '控制标题、今日/本周标签、日期行的底色；调低可让背景透出来',
            child: _SliderRow(
              icon: Icons.crop_square_rounded,
              label: '顶部',
              value: settings.appBarOpacity,
              min: 0.0,
              max: 1.0,
              suffix: settings.appBarOpacity == 0
                  ? '全透明'
                  : '${(settings.appBarOpacity * 100).round()}%',
              onChanged: (value) =>
                  controller.apply(settings.copyWith(appBarOpacity: value)),
            ),
          ),

          _Section(
            title: '主页背景',
            subtitle: '背景会自动压低对比度，不影响课程文字辨识',
            child: _BackgroundPicker(
              settings: settings,
              onPresetChanged: (preset) => controller.apply(
                settings.copyWith(
                  background: preset,
                  // 选了自定义图时再选预设，视为想用预设，清掉图片
                  clearCustomBackground: preset != AppBackgroundPreset.none,
                ),
              ),
              onPickImage: () => _pickBackgroundImage(context, controller, settings),
              onClearImage: () => controller.apply(
                settings.copyWith(clearCustomBackground: true),
              ),
              onBlurChanged: (value) =>
                  controller.apply(settings.copyWith(backgroundBlur: value)),
              onDimChanged: (value) =>
                  controller.apply(settings.copyWith(backgroundDim: value)),
            ),
          ),

          _Section(
            title: '首页标题',
            subtitle: '顶部问候语；留空则回退显示学期名',
            child: _GreetingEditor(
              settings: settings,
              onChanged: (next) => controller.apply(next),
            ),
          ),

          _Section(
            title: '课表排布',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 周视图布局：两种排布在**形状**上完全不同，用缩略示意图表达
                _WeekLayoutPicker(
                  value: settings.weekLayout,
                  onChanged: (value) => controller.apply(
                    settings.copyWith(weekLayout: value),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  settings.weekLayout == AppWeekLayout.table
                      ? '横轴为星期、纵轴为节次，一眼看出整周空档'
                      : '按天分组纵向排列，逐条看课程详情',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),

          // 桌面小组件的两项设置在 iOS 上暂时不展示：
          // iOS 端小组件（WidgetKit）靠 App Group 共享容器与主 App 通信，
          // 而 App Group 属付费开发者账号能力，免费个人签名拿不到，
          // 所以 iOS 版暂时没有小组件可配，显示了反而让人困惑。
          // 将来 iOS 端支持后，删掉这个平台判断即可恢复。
          if (defaultTargetPlatform == TargetPlatform.android) ...[
            _Section(
              title: '桌面小组件配色',
              child: _WidgetColorPicker(
                value: settings.widgetColorPreset,
                customColors: settings.customColors,
                colorScheme: settings.colorScheme,
                onChanged: (value) => controller.apply(
                  settings.copyWith(widgetColorPreset: value),
                ),
              ),
            ),

            _Section(
              title: '小组件背景',
              child: _WidgetBackgroundPicker(
                settings: settings,
                onToggle: (value) => controller.apply(
                  settings.copyWith(widgetUseBackground: value),
                ),
                onPickImage: () =>
                    _pickWidgetBackgroundImage(context, controller, settings),
                onClearImage: () => controller.apply(
                  settings.copyWith(
                    widgetUseBackground: false,
                    clearWidgetBackground: true,
                  ),
                ),
                onBlurChanged: (value) => controller.apply(
                  settings.copyWith(widgetBackgroundBlur: value),
                ),
                onDimChanged: (value) => controller.apply(
                  settings.copyWith(widgetBackgroundDim: value),
                ),
                onCardOpacityChanged: (value) => controller.apply(
                  settings.copyWith(widgetCardOpacity: value),
                ),
                onTextOpacityChanged: (value) => controller.apply(
                  settings.copyWith(widgetTextOpacity: value),
                ),
              ),
            ),
          ],

          _Section(
            title: '其它',
            child: Column(
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('显示周末'),
                  subtitle: const Text('关掉后课表只显示周一到周五'),
                  value: settings.showWeekend,
                  onChanged: (value) =>
                      controller.apply(settings.copyWith(showWeekend: value)),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('深色模式使用纯黑背景'),
                  subtitle: const Text('OLED 屏幕更省电，但对比度更高'),
                  value: settings.useAmoledBlack,
                  onChanged: (value) => controller.apply(
                    settings.copyWith(useAmoledBlack: value),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 选一张本地图片作为背景。
  ///
  /// 选完立刻复制到 App 私有目录 —— 因为用户相册里的原图可能被删除或
  /// 被系统清理，直接引用原路径会导致背景失效。复制到私有目录后长期可用。
  Future<void> _pickBackgroundImage(
    BuildContext context,
    AppearanceController controller,
    AppearanceSettings settings,
  ) async {
    // file_picker 13.x 的 API：静态方法直接返回 PlatformFile（无 .platform）
    final picked = await FilePicker.pickFile(type: FileType.image);
    final source = picked?.path;
    if (source == null) return;

    try {
      final dir = Directory(
        '${(await _appDir()).path}/backgrounds',
      );
      if (!dir.existsSync()) dir.createSync(recursive: true);

      final ext = source.contains('.') ? source.split('.').last : 'jpg';
      final target = '${dir.path}/bg_${DateTime.now().millisecondsSinceEpoch}.$ext';
      File(source).copySync(target);

      // 清掉上一次复制的背景，避免文件越积越多
      final old = settings.customBackgroundPath;
      if (old != null && old != target && File(old).existsSync()) {
        try {
          File(old).deleteSync();
        } catch (_) {
          // 删不掉也无所谓，不影响功能
        }
      }

      await controller.apply(
        settings.copyWith(
          customBackgroundPath: target,
          // 默认给一点模糊，多数生活照直接当背景会太花
          backgroundBlur: settings.backgroundBlur > 0
              ? settings.backgroundBlur
              : 8,
        ),
      );
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('设置背景失败：$error')),
        );
      }
    }
  }

  /// 选一张本地图片作为**小组件**背景。
  ///
  /// 与主页背景同样先复制到 App 私有目录 —— 相册原图被删或被系统清理后，
  /// 小组件会直接变成白板。复制到私有目录后长期可用。
  ///
  /// 选区目录与主页背景分开，两者互不干扰（用户可能只想给其中一个换图）。
  Future<void> _pickWidgetBackgroundImage(
    BuildContext context,
    AppearanceController controller,
    AppearanceSettings settings,
  ) async {
    final picked = await FilePicker.pickFile(type: FileType.image);
    final source = picked?.path;
    if (source == null) return;

    try {
      final dir = Directory('${await getDatabasesPath()}/widget_backgrounds');
      if (!dir.existsSync()) dir.createSync(recursive: true);

      final ext = source.contains('.') ? source.split('.').last : 'jpg';
      final target =
          '${dir.path}/widget_bg_${DateTime.now().millisecondsSinceEpoch}.$ext';
      File(source).copySync(target);

      // 清掉上一次复制的图，避免文件越积越多
      final old = settings.widgetBackgroundPath;
      if (old != null && old != target && File(old).existsSync()) {
        try {
          File(old).deleteSync();
        } catch (_) {
          // 删不掉也无所谓，不影响功能
        }
      }

      await controller.apply(
        settings.copyWith(
          widgetBackgroundPath: target,
          // 选完直接开启，省得用户再回头找开关
          widgetUseBackground: true,
          // 默认给一点模糊，多数生活照直接当底图会太花
          widgetBackgroundBlur: settings.widgetBackgroundBlur > 0
              ? settings.widgetBackgroundBlur
              : 8,
        ),
      );
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('设置小组件背景失败：$error')),
        );
      }
    }
  }

  /// App 私有可写目录。
  ///
  /// 用 sqflite 的 `getDatabasesPath()` —— 它在 Android 上就是 App 私有
  /// 数据目录（`/data/data/<pkg>/databases`），跨平台可靠且已在项目中依赖，
  /// 不必再引入 path_provider。
  Future<Directory> _appDir() async {
    final base = await getDatabasesPath();
    final dir = Directory(p.join(base, 'custom_backgrounds'));
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }

  Future<void> _confirmReset(
    BuildContext context,
    AppearanceController controller,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('恢复默认外观'),
        content: const Text('将把所有界面设置恢复为初始状态，课程数据不受影响。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('恢复'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await controller.reset();
    }
  }
}

/// 实时预览：展示配色、圆角、紧凑度、卡片样式、背景的综合效果。
class _LivePreview extends StatelessWidget {
  const _LivePreview({required this.settings});

  final AppearanceSettings settings;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final radius = settings.corner.radius;
    final scale = settings.density.scale;
    final accent = settings.effectiveAccent;

    return Container(
      padding: EdgeInsets.all(14 * scale),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(radius + 4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.visibility_outlined, size: 16, color: scheme.outline),
              const SizedBox(width: 6),
              Text(
                '实时预览',
                style: TextStyle(fontSize: 12, color: scheme.outline),
              ),
              const Spacer(),
              Text(
                '${settings.density.label} · ${settings.corner.label} · ${settings.cardStyle.label}',
                style: TextStyle(fontSize: 11, color: scheme.outline),
              ),
            ],
          ),
          SizedBox(height: 10 * scale),
          // 预览直接复用真实的卡片绘制逻辑，所见即所得
          _PreviewCard(
            name: '高等代数（1）',
            detail: '第1-2节 · BX22',
            color: accent,
            settings: settings,
          ),
          SizedBox(height: 8 * scale),
          _PreviewCard(
            name: '数学分析（1）',
            detail: '第3-4节 · B31',
            color: settings.effectiveAccentAlt,
            settings: settings,
          ),
        ],
      ),
    );
  }
}

/// 预览用的课表卡片 —— 绘制方式与主界面 `_CourseCard` 保持一致。
class _PreviewCard extends StatelessWidget {
  const _PreviewCard({
    required this.name,
    required this.detail,
    required this.color,
    required this.settings,
  });

  final String name;
  final String detail;
  final Color color;
  final AppearanceSettings settings;

  @override
  Widget build(BuildContext context) {
    final radius = settings.corner.radius;
    final scale = settings.density.scale;
    final opacity = settings.cardOpacity;

    final Color? cardColor;
    final Gradient? gradient;
    switch (settings.cardStyle) {
      case AppCardStyle.plain:
        cardColor = color.withValues(alpha: opacity);
        gradient = null;
      case AppCardStyle.leftBar:
        cardColor = color.withValues(alpha: opacity * 0.12);
        gradient = null;
      case AppCardStyle.gradient:
        cardColor = null;
        gradient = LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            color.withValues(alpha: opacity),
            color.withValues(alpha: opacity * 0.25),
          ],
        );
    }

    return Container(
      decoration: BoxDecoration(
        color: gradient == null ? cardColor : null,
        gradient: gradient,
        borderRadius: BorderRadius.circular(radius),
      ),
      child: Row(
        children: [
          if (settings.cardStyle == AppCardStyle.leftBar)
            Container(
              width: 4,
              height: 42 * scale,
              decoration: BoxDecoration(
                color: color,
                borderRadius: const BorderRadius.horizontal(
                  left: Radius.circular(4),
                ),
              ),
            ),
          Expanded(
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: 12 * scale,
                vertical: 10 * scale,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  SizedBox(height: 3 * scale),
                  Text(
                    detail,
                    style: TextStyle(
                      fontSize: 11,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 卡片样式选择器：每项直接画出该样式的迷你卡片，所见即所得。
class _CardStylePicker extends StatelessWidget {
  const _CardStylePicker({
    required this.current,
    required this.cardOpacity,
    required this.onChanged,
  });

  final AppCardStyle current;
  final double cardOpacity;
  final ValueChanged<AppCardStyle> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = scheme.tertiary;
    return Row(
      children: [
        for (final style in AppCardStyle.values) ...[
          Expanded(
            child: InkWell(
              onTap: () => onChanged(style),
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: style == current
                        ? accent
                        : scheme.outline.withValues(alpha: 0.3),
                    width: style == current ? 2 : 1,
                  ),
                ),
                child: Column(
                  children: [
                    // 用真实绘制逻辑做的迷你样例
                    SizedBox(
                      height: 34,
                      child: _StyleSample(
                        style: style,
                        color: accent,
                        opacity: cardOpacity,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (style == current) ...[
                          Icon(Icons.check_circle, size: 12, color: accent),
                          const SizedBox(width: 3),
                        ],
                        Text(style.label, style: const TextStyle(fontSize: 12)),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (style != AppCardStyle.values.last) const SizedBox(width: 8),
        ],
      ],
    );
  }
}

/// 三种样式的迷你示意。
class _StyleSample extends StatelessWidget {
  const _StyleSample({
    required this.style,
    required this.color,
    required this.opacity,
  });

  final AppCardStyle style;
  final Color color;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    final Color? bg;
    final Gradient? gradient;
    switch (style) {
      case AppCardStyle.plain:
        bg = color.withValues(alpha: opacity);
        gradient = null;
      case AppCardStyle.leftBar:
        bg = color.withValues(alpha: opacity * 0.12);
        gradient = null;
      case AppCardStyle.gradient:
        bg = null;
        gradient = LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            color.withValues(alpha: opacity),
            color.withValues(alpha: opacity * 0.25),
          ],
        );
    }

    return Container(
      decoration: BoxDecoration(
        color: gradient == null ? bg : null,
        gradient: gradient,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          if (style == AppCardStyle.leftBar)
            Container(
              width: 3.5,
              height: 34,
              decoration: BoxDecoration(
                color: color,
                borderRadius: const BorderRadius.horizontal(
                  left: Radius.circular(3.5),
                ),
              ),
            ),
          const Spacer(),
          // 用两条色块示意文字行
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Container(
                width: 26,
                height: 4,
                decoration: BoxDecoration(
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 4),
              Container(
                width: 18,
                height: 3,
                decoration: BoxDecoration(
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ],
          ),
          const Spacer(),
        ],
      ),
    );
  }
}

/// 背景设置区。
class _BackgroundPicker extends StatelessWidget {
  const _BackgroundPicker({
    required this.settings,
    required this.onPresetChanged,
    required this.onPickImage,
    required this.onClearImage,
    required this.onBlurChanged,
    required this.onDimChanged,
  });

  final AppearanceSettings settings;
  final ValueChanged<AppBackgroundPreset> onPresetChanged;
  final VoidCallback onPickImage;
  final VoidCallback onClearImage;
  final ValueChanged<double> onBlurChanged;
  final ValueChanged<double> onDimChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hasImage = settings.hasCustomBackground;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 预设背景
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final preset in AppBackgroundPreset.values)
              _PresetChip(
                preset: preset,
                selected: !hasImage && settings.background == preset,
                enabled: !hasImage,
                onTap: () => onPresetChanged(preset),
              ),
          ],
        ),

        const SizedBox(height: 14),
        Divider(color: scheme.outlineVariant.withValues(alpha: 0.5)),
        const SizedBox(height: 10),

        // 自定义背景图
        Row(
          children: [
            Icon(
              hasImage ? Icons.image_rounded : Icons.add_photo_alternate_outlined,
              size: 18,
              color: scheme.outline,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                hasImage ? '已设置自定义背景图' : '自定义背景图',
                style: const TextStyle(fontSize: 13),
              ),
            ),
            if (hasImage)
              TextButton(
                onPressed: onClearImage,
                child: const Text('移除'),
              ),
            FilledButton.tonal(
              onPressed: onPickImage,
              child: Text(hasImage ? '更换' : '选择图片'),
            ),
          ],
        ),
        if (!hasImage)
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 26),
            child: Text(
              '选择图片后可调节模糊与明暗；设置自定义图时预设背景不生效',
              style: TextStyle(fontSize: 11, color: scheme.outline),
            ),
          ),

        // 仅在有自定义图时提供模糊/明暗调节
        if (hasImage) ...[
          const SizedBox(height: 6),
          _SliderRow(
            icon: Icons.blur_on_rounded,
            label: '高斯模糊',
            value: settings.backgroundBlur,
            min: 0,
            max: 30,
            suffix: '${settings.backgroundBlur.round()}',
            onChanged: onBlurChanged,
          ),
          _SliderRow(
            icon: Icons.brightness_6_outlined,
            label: '明暗调整',
            value: settings.backgroundDim,
            min: 0,
            max: 0.8,
            suffix: '${(settings.backgroundDim * 100).round()}%',
            onChanged: onDimChanged,
          ),
          Padding(
            padding: const EdgeInsets.only(left: 26, top: 2),
            child: Text(
              '明暗调整越高，背景越淡，课程文字越清晰',
              style: TextStyle(fontSize: 11, color: scheme.outline),
            ),
          ),
        ],
      ],
    );
  }
}

/// 桌面小组件的「自定义背景」设置。
///
/// 与主页背景**同一套策略**（选图 → 高斯模糊 → 明暗蒙层），字段独立；
/// 另外多出两个**只在自定义背景模式下生效**的透明度滑杆。
class _WidgetBackgroundPicker extends StatelessWidget {
  const _WidgetBackgroundPicker({
    required this.settings,
    required this.onToggle,
    required this.onPickImage,
    required this.onClearImage,
    required this.onBlurChanged,
    required this.onDimChanged,
    required this.onCardOpacityChanged,
    required this.onTextOpacityChanged,
  });

  final AppearanceSettings settings;
  final ValueChanged<bool> onToggle;
  final VoidCallback onPickImage;
  final VoidCallback onClearImage;
  final ValueChanged<double> onBlurChanged;
  final ValueChanged<double> onDimChanged;
  final ValueChanged<double> onCardOpacityChanged;
  final ValueChanged<double> onTextOpacityChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final path = settings.widgetBackgroundPath;
    final hasImage = path != null && path.isNotEmpty;
    final active = settings.hasWidgetBackground;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('使用自定义背景'),
          subtitle: const Text('给桌面小组件铺一张底图，玩法与主页背景一致'),
          value: settings.widgetUseBackground,
          onChanged: onToggle,
        ),

        // 选图 / 换图
        Row(
          children: [
            Icon(
              hasImage
                  ? Icons.image_rounded
                  : Icons.add_photo_alternate_outlined,
              size: 18,
              color: scheme.outline,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                hasImage ? '已设置小组件背景图' : '还没有选择图片',
                style: const TextStyle(fontSize: 13),
              ),
            ),
            if (hasImage)
              TextButton(onPressed: onClearImage, child: const Text('移除')),
            FilledButton.tonal(
              onPressed: onPickImage,
              child: Text(hasImage ? '更换' : '选择图片'),
            ),
          ],
        ),

        if (settings.widgetUseBackground && !hasImage)
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 26),
            child: Text(
              '还没选图，小组件仍按普通样式显示',
              style: TextStyle(fontSize: 11, color: scheme.error),
            ),
          ),

        if (active) ...[
          const SizedBox(height: 6),
          _SliderRow(
            icon: Icons.blur_on_rounded,
            label: '高斯模糊',
            value: settings.widgetBackgroundBlur,
            min: 0,
            max: 30,
            suffix: '${settings.widgetBackgroundBlur.round()}',
            onChanged: onBlurChanged,
          ),
          _SliderRow(
            icon: Icons.brightness_6_outlined,
            label: '明暗调整',
            value: settings.widgetBackgroundDim,
            min: 0,
            max: 0.8,
            suffix: '${(settings.widgetBackgroundDim * 100).round()}%',
            onChanged: onDimChanged,
          ),
          Padding(
            padding: const EdgeInsets.only(left: 26, top: 2),
            child: Text(
              '明暗调整越高，底图越淡，文字越清楚',
              style: TextStyle(fontSize: 11, color: scheme.outline),
            ),
          ),

          const SizedBox(height: 10),
          Divider(color: scheme.outlineVariant.withValues(alpha: 0.5)),
          const SizedBox(height: 6),
          Text(
            '元素透明度（仅自定义背景模式下生效）',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          _SliderRow(
            icon: Icons.rounded_corner_rounded,
            label: '卡片',
            value: settings.widgetCardOpacity,
            min: 0.1,
            max: 1,
            suffix: '${(settings.widgetCardOpacity * 100).round()}%',
            onChanged: onCardOpacityChanged,
          ),
          _SliderRow(
            icon: Icons.format_color_text_rounded,
            label: '文字',
            value: settings.widgetTextOpacity,
            min: 0.1,
            max: 1,
            suffix: '${(settings.widgetTextOpacity * 100).round()}%',
            onChanged: onTextOpacityChanged,
          ),
          Padding(
            padding: const EdgeInsets.only(left: 26, top: 2),
            child: Text(
              '卡片调低能透出底图；文字单独控制，两者互不影响，左侧色条不跟着变淡。',
              style: TextStyle(fontSize: 11, color: scheme.outline),
            ),
          ),
        ],
      ],
    );
  }
}

/// 背景预设的色块选项。
class _PresetChip extends StatelessWidget {
  const _PresetChip({
    required this.preset,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final AppBackgroundPreset preset;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tint = scheme.tertiary;

    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: 84,
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected
                  ? tint
                  : scheme.outline.withValues(alpha: 0.3),
              width: selected ? 2 : 1,
            ),
          ),
          child: Column(
            children: [
              // 迷你示意图
              Container(
                width: 56,
                height: 34,
                decoration: BoxDecoration(
                  color: scheme.surface,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: CustomPaint(
                  painter: _PresetThumbPainter(preset: preset, tint: tint),
                ),
              ),
              const SizedBox(height: 5),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (selected) ...[
                    Icon(Icons.check_circle, size: 11, color: tint),
                    const SizedBox(width: 2),
                  ],
                  Text(preset.label, style: const TextStyle(fontSize: 11)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 在迷你色块里画出各预设的代表性纹理。
class _PresetThumbPainter extends CustomPainter {
  _PresetThumbPainter({required this.preset, required this.tint});

  final AppBackgroundPreset preset;
  final Color tint;

  @override
  void paint(Canvas canvas, Size size) {
    final rrect =
        RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(6));
    canvas.clipRRect(rrect);

    switch (preset) {
      case AppBackgroundPreset.none:
        break;
      case AppBackgroundPreset.plain:
        canvas.drawRect(
          Offset.zero & size,
          Paint()..color = tint.withValues(alpha: 0.18),
        );
      case AppBackgroundPreset.softGradient:
        canvas.drawRect(
          Offset.zero & size,
          Paint()
            ..shader = LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                tint.withValues(alpha: 0.3),
                tint.withValues(alpha: 0.06),
              ],
            ).createShader(Offset.zero & size),
        );
      case AppBackgroundPreset.grid:
        final p = Paint()
          ..color = tint.withValues(alpha: 0.35)
          ..strokeWidth = 1;
        for (var x = 8.0; x < size.width; x += 10) {
          canvas.drawLine(Offset(x, 0), Offset(x, size.height), p);
        }
        for (var y = 8.0; y < size.height; y += 10) {
          canvas.drawLine(Offset(0, y), Offset(size.width, y), p);
        }
      case AppBackgroundPreset.dots:
        final p = Paint()..color = tint.withValues(alpha: 0.4);
        for (var y = 6.0; y < size.height; y += 9) {
          for (var x = 6.0; x < size.width; x += 9) {
            canvas.drawCircle(Offset(x, y), 1.5, p);
          }
        }
      case AppBackgroundPreset.paper:
        final p = Paint()
          ..color = tint.withValues(alpha: 0.3)
          ..strokeWidth = 1;
        for (var y = 6.0; y < size.height; y += 7) {
          canvas.drawLine(Offset(0, y), Offset(size.width, y), p);
        }
    }
  }

  @override
  bool shouldRepaint(_PresetThumbPainter old) =>
      old.preset != preset || old.tint != tint;
}

/// 一行带图标与数值的滑杆。
class _SliderRow extends StatelessWidget {
  const _SliderRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.suffix,
    required this.onChanged,
  });

  final IconData icon;
  final String label;
  final double value;
  final double min;
  final double max;
  final String suffix;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: Theme.of(context).colorScheme.outline),
        const SizedBox(width: 8),
        SizedBox(
          width: 64,
          child: Text(label, style: const TextStyle(fontSize: 13)),
        ),
        Expanded(
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            onChanged: onChanged,
          ),
        ),
        SizedBox(
          width: 44,
          child: Text(
            suffix,
            textAlign: TextAlign.end,
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.outline,
            ),
          ),
        ),
      ],
    );
  }
}

/// 配色选择器：预设色块 + 自定义。
class _ColorSchemePicker extends StatelessWidget {
  const _ColorSchemePicker({
    required this.current,
    required this.isCustom,
    required this.custom,
    required this.onChanged,
    required this.onCustomChanged,
  });

  final AppColorScheme current;
  final bool isCustom;
  final CustomColorScheme custom;
  final ValueChanged<AppColorScheme> onChanged;
  final ValueChanged<CustomColorScheme> onCustomChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 讲清「主色」与「强调色」的分工，避免用户困惑
        const _ColorRolesHint(),
        const SizedBox(height: 14),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final scheme in AppColorScheme.values)
              _SchemeChip(
                label: scheme.label,
                primary: scheme.seed,
                secondary: scheme.accent,
                selected: !isCustom && scheme == current,
                onTap: () => onChanged(scheme),
              ),
            // 自定义入口
            _CustomChip(
              custom: custom,
              selected: isCustom,
              onTap: () => onCustomChanged(custom),
            ),
          ],
        ),
        if (isCustom) ...[
          const SizedBox(height: 14),
          _CustomColorEditor(
            custom: custom,
            onChanged: onCustomChanged,
          ),
        ],
      ],
    );
  }
}

/// 解释配色里「主色」和「强调色」各自负责什么。
class _ColorRolesHint extends StatelessWidget {
  const _ColorRolesHint();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.info_outline, size: 15, color: scheme.outline),
              const SizedBox(width: 6),
              Text(
                '这套配色由两个颜色组成',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: scheme.outline,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _RoleRow(
            color: scheme.primary,
            title: '主色',
            desc: '界面的整体基调 —— 顶部栏、按钮、标签页选中态、开关等大面积元素',
          ),
          const SizedBox(height: 6),
          _RoleRow(
            color: scheme.tertiary,
            title: '强调色',
            desc: '点缀与高亮 —— 主页背景色、设置页选中框、进度条等小面积元素',
          ),
        ],
      ),
    );
  }
}

/// 说明里的单行：色块 + 名称 + 用途。
class _RoleRow extends StatelessWidget {
  const _RoleRow({
    required this.color,
    required this.title,
    required this.desc,
  });

  final Color color;
  final String title;
  final String desc;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 14,
          height: 14,
          margin: const EdgeInsets.only(top: 2),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: '$title　',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                TextSpan(
                  text: desc,
                  style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// 自定义配色的两个调色入口。
class _CustomColorEditor extends StatelessWidget {
  const _CustomColorEditor({required this.custom, required this.onChanged});

  final CustomColorScheme custom;
  final ValueChanged<CustomColorScheme> onChanged;

  /// 可选色板：覆盖常见色域，避免用户面对 RGB 滑杆无从下手。
  static const _palette = <Color>[
    Color(0xFF5B8DEF), Color(0xFF3E8FC4), Color(0xFF2A6F9E),
    Color(0xFF2E9E8F), Color(0xFF4E7A4A), Color(0xFFA9844F),
    Color(0xFFE07A5F), Color(0xFFC2185B), Color(0xFFE0668F),
    Color(0xFF7E57C2), Color(0xFF8E6BE8), Color(0xFF9061C2),
    Color(0xFFF0A6C8), Color(0xFFF2C879), Color(0xFF7FD4D8),
    Color(0xFF546E7A), Color(0xFF37474F), Color(0xFF202124),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _PaletteRow(
          title: '主色',
          current: custom.seed,
          palette: _palette,
          onPick: (c) => onChanged(
            CustomColorScheme(seed: c, accent: custom.accent),
          ),
        ),
        const SizedBox(height: 10),
        _PaletteRow(
          title: '强调色',
          current: custom.accent,
          palette: _palette,
          onPick: (c) => onChanged(
            CustomColorScheme(seed: custom.seed, accent: c),
          ),
        ),
      ],
    );
  }
}

/// 一行色板，点一下即选中。
class _PaletteRow extends StatelessWidget {
  const _PaletteRow({
    required this.title,
    required this.current,
    required this.palette,
    required this.onPick,
  });

  final String title;
  final Color current;
  final List<Color> palette;
  final ValueChanged<Color> onPick;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(title, style: const TextStyle(fontSize: 12)),
            const SizedBox(width: 8),
            Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                color: current,
                shape: BoxShape.circle,
                border: Border.all(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final color in palette)
              GestureDetector(
                onTap: () => onPick(color),
                child: Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: color.toARGB32() == current.toARGB32()
                          ? Theme.of(context).colorScheme.onSurface
                          : Colors.transparent,
                      width: 2,
                    ),
                  ),
                  child: color.toARGB32() == current.toARGB32()
                      ? const Icon(Icons.check, size: 14, color: Colors.white)
                      : null,
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/// 自定义配色的入口色块。
class _CustomChip extends StatelessWidget {
  const _CustomChip({
    required this.custom,
    required this.selected,
    required this.onTap,
  });

  final CustomColorScheme custom;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 96,
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? custom.seed : scheme.outline.withValues(alpha: 0.3),
            width: selected ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            // 用渐变圆示意「自定义」：不像预设那样固定双色
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [custom.seed, custom.accent],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (selected) ...[
                  Icon(Icons.check_circle, size: 12, color: custom.seed),
                  const SizedBox(width: 3),
                ],
                const Text('自定义', style: TextStyle(fontSize: 12)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 预设配色的色块。
class _SchemeChip extends StatelessWidget {
  const _SchemeChip({
    required this.label,
    required this.primary,
    required this.secondary,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final Color primary;
  final Color secondary;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final outline = Theme.of(context).colorScheme.outline;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 96,
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? primary : outline.withValues(alpha: 0.3),
            width: selected ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            // 双色圆点示意该方案的主色与强调色
            Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: primary,
                    shape: BoxShape.circle,
                  ),
                ),
                Positioned(
                  right: 20,
                  bottom: 0,
                  child: Container(
                    width: 18,
                    height: 18,
                    decoration: BoxDecoration(
                      color: secondary,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Theme.of(context).colorScheme.surface,
                        width: 2,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (selected) ...[
                  Icon(Icons.check_circle, size: 12, color: primary),
                  const SizedBox(width: 3),
                ],
                Text(label, style: const TextStyle(fontSize: 12)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 周视图布局选择器。
///
/// 每个选项画一张**缩略示意图**，直观表达两种排布的形状差异：
/// - 瀑布流：横向长条**纵向堆叠**（按天分组的一维列表）；
/// - 表格：格子组成的**二维网格**（星期 × 节次）。
class _WeekLayoutPicker extends StatelessWidget {
  const _WeekLayoutPicker({required this.value, required this.onChanged});

  final AppWeekLayout value;
  final ValueChanged<AppWeekLayout> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (final layout in AppWeekLayout.values) ...[
          Expanded(
            child: _WeekLayoutOption(
              layout: layout,
              selected: layout == value,
              onTap: () => onChanged(layout),
            ),
          ),
          if (layout != AppWeekLayout.values.last) const SizedBox(width: 12),
        ],
      ],
    );
  }
}

class _WeekLayoutOption extends StatelessWidget {
  const _WeekLayoutOption({
    required this.layout,
    required this.selected,
    required this.onTap,
  });

  final AppWeekLayout layout;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? scheme.primary : scheme.outlineVariant,
            width: selected ? 2 : 1,
          ),
          color: selected
              ? scheme.primary.withValues(alpha: 0.08)
              : Colors.transparent,
        ),
        child: Column(
          children: [
            SizedBox(
              height: 54,
              child: CustomPaint(
                painter: _WeekLayoutThumbPainter(
                  layout: layout,
                  color: selected ? scheme.primary : scheme.onSurfaceVariant,
                ),
                size: Size.infinite,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              layout.label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: selected ? FontWeight.bold : FontWeight.w500,
                color: selected ? scheme.primary : scheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 画出两种布局的缩略示意。
///
/// 刻意让几何形状完全不同（长条堆叠 vs 方格矩阵），而非靠颜色区分。
class _WeekLayoutThumbPainter extends CustomPainter {
  _WeekLayoutThumbPainter({required this.layout, required this.color});

  final AppWeekLayout layout;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withValues(alpha: 0.75)
      ..style = PaintingStyle.fill;
    final stroke = Paint()
      ..color = color.withValues(alpha: 0.35)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    switch (layout) {
      case AppWeekLayout.waterfall:
        // 四条长短不一的横向长条，纵向堆叠
        const widths = [1.0, 0.62, 0.85, 0.48];
        const barH = 8.0;
        const gap = 4.0;
        for (var i = 0; i < widths.length; i++) {
          final rect = RRect.fromRectAndRadius(
            Rect.fromLTWH(0, i * (barH + gap), size.width * widths[i], barH),
            const Radius.circular(2.5),
          );
          canvas.drawRRect(rect, paint);
        }
      case AppWeekLayout.table:
        // 5 列 × 4 行的方格矩阵
        const cols = 5;
        const rows = 4;
        final cellW = size.width / cols;
        final cellH = size.height / rows;
        for (var r = 0; r < rows; r++) {
          for (var c = 0; c < cols; c++) {
            final rect = Rect.fromLTWH(
              c * cellW,
              r * cellH,
              cellW - 2,
              cellH - 2,
            );
            canvas.drawRRect(
              RRect.fromRectAndRadius(rect, const Radius.circular(2)),
              (r + c).isEven ? paint : stroke,
            );
          }
        }
    }
  }

  @override
  bool shouldRepaint(_WeekLayoutThumbPainter oldDelegate) =>
      oldDelegate.layout != layout || oldDelegate.color != color;
}

/// 小组件配色选择器。
///
/// 每个选项画一张**迷你小组件预览**（头部 + 两条课程行），
/// 用该配色真实的色值 —— 用户不用切回桌面就能判断效果。
class _WidgetColorPicker extends StatelessWidget {
  const _WidgetColorPicker({
    required this.value,
    required this.customColors,
    required this.colorScheme,
    required this.onChanged,
  });

  final WidgetColorPreset value;
  final CustomColorScheme? customColors;
  final AppColorScheme colorScheme;
  final ValueChanged<WidgetColorPreset> onChanged;

  /// 解析某预设实际生效的色板；「跟随应用」时用 App 当前配色推导。
  WidgetPalette _paletteFor(WidgetColorPreset preset) {
    final own = preset.palette;
    if (own != null) return own;

    final accent = customColors?.accent ?? colorScheme.accent;
    final seed = customColors?.seed ?? colorScheme.seed;
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

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final preset in WidgetColorPreset.values)
              _WidgetColorOption(
                preset: preset,
                palette: _paletteFor(preset),
                selected: preset == value,
                onTap: () => onChanged(preset),
              ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          '小组件配色与应用配色相互独立，切换后需重新添加一次小组件才会生效',
          style: TextStyle(
            fontSize: 11,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _WidgetColorOption extends StatelessWidget {
  const _WidgetColorOption({
    required this.preset,
    required this.palette,
    required this.selected,
    required this.onTap,
  });

  final WidgetColorPreset preset;
  final WidgetPalette palette;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 104,
            height: 62,
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: selected ? scheme.primary : scheme.outlineVariant,
                width: selected ? 2 : 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 30,
                      height: 6,
                      decoration: BoxDecoration(
                        color: palette.text.withValues(alpha: 0.75),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                    const Spacer(),
                    Container(
                      width: 10,
                      height: 6,
                      decoration: BoxDecoration(
                        color: palette.active,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                // 一条「进行中」、一条「未开始」
                _miniRow(palette.activeBg, palette.active),
                const SizedBox(height: 3),
                _miniRow(palette.card, palette.accent),
              ],
            ),
          ),
          const SizedBox(height: 5),
          Text(
            preset.label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: selected ? FontWeight.bold : FontWeight.w500,
              color: selected ? scheme.primary : scheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }

  /// 迷你课程行：左侧色条 + 文字条 + 右侧状态点。
  Widget _miniRow(Color bg, Color barColor) {
    return Container(
      height: 15,
      padding: const EdgeInsets.symmetric(horizontal: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        children: [
          Container(
            width: 2.5,
            height: 9,
            decoration: BoxDecoration(
              color: barColor,
              borderRadius: BorderRadius.circular(1.5),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Container(
              height: 4,
              decoration: BoxDecoration(
                color: palette.text.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(width: 4),
          Container(
            width: 8,
            height: 4,
            decoration: BoxDecoration(
              color: barColor,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ],
      ),
    );
  }
}

/// 首页标题编辑器。
///
/// 用 [TextFormField] 而非受控 [TextField]：输入过程中不立刻写库，
/// 而是「停止输入 400ms」或「失焦」时才提交，避免每敲一个字都写一次数据库。
/// 同时用 [_controller] 保持光标位置，不因外部重建而跳动。
class _GreetingEditor extends StatefulWidget {
  const _GreetingEditor({required this.settings, required this.onChanged});

  final AppearanceSettings settings;
  final ValueChanged<AppearanceSettings> onChanged;

  @override
  State<_GreetingEditor> createState() => _GreetingEditorState();
}

class _GreetingEditorState extends State<_GreetingEditor> {
  late final TextEditingController _controller;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.settings.greetingText);
  }

  @override
  void didUpdateWidget(_GreetingEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 仅在外部值确实变化、且没有正在进行的输入时同步，避免打断用户
    final incoming = widget.settings.greetingText;
    if (incoming != _controller.text && _debounce?.isActive != true) {
      _controller.text = incoming;
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  /// 延迟提交：停止输入 400ms 后落库。
  void _scheduleCommit(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      if (!mounted) return;
      widget.onChanged(widget.settings.copyWith(greetingText: value.trim()));
    });
  }

  /// 立即提交（失焦时调用，保证不丢最后一次输入）。
  void _commitNow() {
    _debounce?.cancel();
    final value = _controller.text.trim();
    if (value != widget.settings.greetingText) {
      widget.onChanged(widget.settings.copyWith(greetingText: value));
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = widget.settings;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextFormField(
          controller: _controller,
          decoration: const InputDecoration(
            hintText: defaultGreeting,
            border: OutlineInputBorder(),
            isDense: true,
          ),
          onChanged: _scheduleCommit,
          onTapOutside: (_) => _commitNow(),
        ),
        const SizedBox(height: 8),
        // 字体选择：只在显示问候语时才需要
        if (!settings.hideGreeting) ...[
          Text(
            '字体',
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 6),
          _TitleFontPicker(
            value: settings.titleFont,
            onChanged: (font) =>
                widget.onChanged(settings.copyWith(titleFont: font)),
          ),
          const SizedBox(height: 4),
        ],
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('隐藏首页标题'),
          subtitle: const Text('打开后顶部不显示任何文字，适合极简观感'),
          value: settings.hideGreeting,
          onChanged: (value) =>
              widget.onChanged(settings.copyWith(hideGreeting: value)),
        ),
      ],
    );
  }
}

/// 首页标题字体选择器。
///
/// 每个选项**用它自己的字体渲染**，方便直接看到效果；
/// 设备没装该字体时会回退，此时预览与系统字体一致（属正常）。
class _TitleFontPicker extends StatelessWidget {
  const _TitleFontPicker({required this.value, required this.onChanged});

  final AppTitleFont value;
  final ValueChanged<AppTitleFont> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final font in AppTitleFont.values)
          GestureDetector(
            onTap: () => onChanged(font),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: font == value ? scheme.primary : scheme.outlineVariant,
                  width: font == value ? 2 : 1,
                ),
                color: font == value
                    ? scheme.primary.withValues(alpha: 0.08)
                    : Colors.transparent,
              ),
              child: Text(
                font.label,
                style: TextStyle(
                  fontSize: 13,
                  // 用候选字体族渲染自身，所见即所得；缺失时自动回退
                  fontFamily: font.fontFamilies?.firstOrNull,
                  fontFamilyFallback: font.fontFamilies,
                  fontWeight: font == value ? FontWeight.bold : FontWeight.w500,
                  color: font == value ? scheme.primary : scheme.onSurface,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// 带标题与说明的分组。
class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child, this.subtitle});

  final String title;
  final String? subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 2),
            Text(
              subtitle!,
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.outline,
              ),
            ),
          ],
          const SizedBox(height: 10),
          SizedBox(width: double.infinity, child: child),
        ],
      ),
    );
  }
}
