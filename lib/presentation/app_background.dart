/// 主页背景。
///
/// 两种来源：
/// 1. **预设**（[AppBackgroundPreset]）—— 纯代码绘制，不引入图片资源；
/// 2. **自定义图**（用户从相册选）—— 读取本地文件，可加高斯模糊。
///
/// 设计约束：背景**要看得见**，但**不能压过课程文字**。
/// 因此：
/// - 预设强度分档：纯色/渐变这类大面积色块用较低透明度，
///   网格/圆点/纸纹这类细纹理用稍高透明度（细线本身视觉重量小）；
/// - 课程卡片本身有不透明度设置（见 [AppearanceSettings.cardOpacity]），
///   卡片越不透明，背景对文字的干扰越小；
/// - 自定义图统一叠一层可调的「明暗」蒙层。
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../domain/appearance_settings.dart';

/// 把背景包在内容外面。
///
/// 用法：`AppBackground(settings: s, child: Scaffold(...))`
/// 注意 [Scaffold] 本身要设成透明背景，否则会盖住这层背景。
class AppBackground extends StatelessWidget {
  const AppBackground({
    super.key,
    required this.settings,
    required this.child,
  });

  final AppearanceSettings settings;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Stack(
      fit: StackFit.expand,
      children: [
        // 底层：纯色底（跟随主题）
        ColoredBox(color: theme.scaffoldBackgroundColor),

        // 第二层：预设图案 或 自定义图
        if (settings.hasCustomBackground)
          _CustomBackgroundImage(settings: settings)
        else if (settings.background != AppBackgroundPreset.none)
          _PresetBackground(
            preset: settings.background,
            tint: settings.effectiveAccent,
            isDark: isDark,
            surface: theme.colorScheme.surface,
          ),

        // 第三层：自定义图时叠蒙层，保证可读性
        if (settings.hasCustomBackground)
          _DimOverlay(dim: settings.backgroundDim, isDark: isDark),

        // 最上层：内容
        child,
      ],
    );
  }
}

/// 自定义背景图（含高斯模糊）。
class _CustomBackgroundImage extends StatelessWidget {
  const _CustomBackgroundImage({required this.settings});

  final AppearanceSettings settings;

  @override
  Widget build(BuildContext context) {
    final path = settings.customBackgroundPath!;
    final blur = settings.backgroundBlur;

    Widget image = Image.file(
      File(path),
      fit: BoxFit.cover,
      // 图片被删掉/损坏时不要崩，退回纯色底
      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
      gaplessPlayback: true,
    );

    if (blur > 0) {
      // 模糊会让边缘变透明，所以稍微放大以避免露出底色
      final over = 1 + blur / 100;
      image = ClipRect(
        child: Transform.scale(
          scale: over,
          child: ImageFiltered(
            imageFilter: ui.ImageFilter.blur(
              sigmaX: blur,
              sigmaY: blur,
              tileMode: TileMode.decal,
            ),
            child: image,
          ),
        ),
      );
    }

    return image;
  }
}

/// 压暗/提亮蒙层，保证背景上的文字清晰。
class _DimOverlay extends StatelessWidget {
  const _DimOverlay({required this.dim, required this.isDark});

  final double dim;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    if (dim <= 0) return const SizedBox.shrink();
    return ColoredBox(
      color: (isDark ? Colors.black : Colors.white).withValues(alpha: dim),
    );
  }
}

/// 预设背景：全部纯代码绘制。
///
/// 强度不再是「一律极淡」，而是按图案类型分档 ——
/// 大面积色块淡一些，细纹理浓一些，这样各种预设**都能明显看出区别**。
class _PresetBackground extends StatelessWidget {
  const _PresetBackground({
    required this.preset,
    required this.tint,
    required this.isDark,
    required this.surface,
  });

  final AppBackgroundPreset preset;
  final Color tint;
  final bool isDark;
  final Color surface;

  @override
  Widget build(BuildContext context) {
    // 大面积色块的透明度：浅色底上要淡一些，深色底上要亮一些才看得见
    final wash = isDark ? 0.22 : 0.14;
    // 细纹理（线条/圆点）的透明度：可以更高，因为线条本身很轻
    final texture = isDark ? 0.14 : 0.10;

    return switch (preset) {
      AppBackgroundPreset.none => const SizedBox.shrink(),

      // 纯色：铺满一整块主题色，用 surface 混一下避免过饱和
      AppBackgroundPreset.plain => ColoredBox(
          color: Color.alphaBlend(tint.withValues(alpha: wash), surface),
        ),

      // 柔和渐变：从主色到强调色的斜向过渡，两端都明显可见
      AppBackgroundPreset.softGradient => DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                tint.withValues(alpha: wash),
                tint.withValues(alpha: wash * 0.35),
                Colors.transparent,
              ],
              stops: const [0, 0.45, 1],
            ),
          ),
        ),

      // 网格：细线格
      AppBackgroundPreset.grid => CustomPaint(
          painter: _GridPainter(
            color: tint.withValues(alpha: texture),
          ),
        ),

      // 圆点：点阵
      AppBackgroundPreset.dots => CustomPaint(
          painter: _DotsPainter(
            color: tint.withValues(alpha: texture),
          ),
        ),

      // 纸纹：细横线
      AppBackgroundPreset.paper => CustomPaint(
          painter: _PaperPainter(
            color: tint.withValues(alpha: texture * 0.9),
          ),
        ),
    };
  }
}

/// 等距网格。
class _GridPainter extends CustomPainter {
  _GridPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    const step = 32.0;
    for (var x = 0.0; x <= size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (var y = 0.0; y <= size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(_GridPainter old) => old.color != color;
}

/// 圆点阵列。
class _DotsPainter extends CustomPainter {
  _DotsPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    const step = 26.0;
    const r = 2.0;
    for (var y = step / 2; y < size.height; y += step) {
      for (var x = step / 2; x < size.width; x += step) {
        canvas.drawCircle(Offset(x, y), r, paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DotsPainter old) => old.color != color;
}

/// 细横线，模拟纸纹。
class _PaperPainter extends CustomPainter {
  _PaperPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    const step = 20.0;
    for (var y = step; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(_PaperPainter old) => old.color != color;
}
