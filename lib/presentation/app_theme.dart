import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../domain/appearance_settings.dart';

/// 根据用户的[外观设置][AppearanceSettings]构建主题。
///
/// 设计原则：
/// - 配色只用一组种子色，浅色/深色共用，保证两套模式协调；
/// - 圆角、间距、卡片样式都由设置驱动，改设置立刻体现在全局；
/// - 不引入任何图片资源，纯代码生成，包体积零增长。
class AppTheme {
  const AppTheme._();

  /// 浅色主题。
  static ThemeData light(AppearanceSettings settings) => _build(
        settings: settings,
        brightness: Brightness.light,
        background: const Color(0xFFF5F5F3),
        surface: Colors.white,
        text: const Color(0xFF202124),
      );

  /// 深色主题。开启 AMOLED 时用纯黑背景。
  static ThemeData dark(AppearanceSettings settings) => _build(
        settings: settings,
        brightness: Brightness.dark,
        background: settings.useAmoledBlack
            ? const Color(0xFF000000)
            : const Color(0xFF111214),
        surface: settings.useAmoledBlack
            ? const Color(0xFF0D0D0F)
            : const Color(0xFF1C1D20),
        text: const Color(0xFFF1F1EF),
      );

  /// 默认外观（无设置时使用）。
  static ThemeData lightDefault() => light(const AppearanceSettings());
  static ThemeData darkDefault() => dark(const AppearanceSettings());

  static ThemeData _build({
    required AppearanceSettings settings,
    required Brightness brightness,
    required Color background,
    required Color surface,
    required Color text,
  }) {
    final scheme = ColorScheme.fromSeed(
      seedColor: settings.effectiveSeed,
      brightness: brightness,
      surface: surface,
    );
    final overlayStyle =
        (brightness == Brightness.light
                ? SystemUiOverlayStyle.dark
                : SystemUiOverlayStyle.light)
            .copyWith(
              statusBarColor: Colors.transparent,
              systemNavigationBarColor: background,
              systemNavigationBarIconBrightness: brightness == Brightness.light
                  ? Brightness.dark
                  : Brightness.light,
            );

    final radius = settings.corner.radius;
    // 紧凑度直接缩放卡片内边距与列表项间距
    final scale = settings.density.scale;

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme.copyWith(
        // 强调色用在选中态、进度条等处
        tertiary: settings.effectiveAccent,
      ),
      scaffoldBackgroundColor: background,
      textTheme: ThemeData(
        brightness: brightness,
      ).textTheme.apply(bodyColor: text, displayColor: text),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius + 4)),
      ),
      appBarTheme: AppBarTheme(
        // 顶部栏背景按用户设置的不透明度渲染，让主页背景透出来。
        // alpha 为 0 时完全透明（只剩文字浮在背景上）。
        backgroundColor: background.withValues(alpha: settings.appBarOpacity),
        surfaceTintColor: Colors.transparent,
        foregroundColor: text,
        elevation: 0,
        scrolledUnderElevation: 0,
        systemOverlayStyle: overlayStyle,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius),
          borderSide: BorderSide.none,
        ),
        contentPadding: EdgeInsets.symmetric(
          horizontal: 14 * scale,
          vertical: 12 * scale,
        ),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant.withValues(alpha: 0.5),
      ),
      listTileTheme: ListTileThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius),
        ),
        contentPadding: EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 4 * scale,
        ),
      ),
      // 圆角与紧凑度也作用到对话框、底部弹层
      dialogTheme: DialogThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius + 8),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(radius + 8),
          ),
        ),
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radius),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radius),
          ),
        ),
      ),
    );
  }
}
