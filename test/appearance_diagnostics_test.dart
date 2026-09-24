import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_course_schedule/domain/appearance_settings.dart';

/// 诊断用：验证用户报告的「日夜模式切换无效」「配色改不动」
/// 是否源于设置模型本身的往返 / 比较问题。
void main() {
  group('诊断：日夜模式', () {
    test('每个 themeMode 都能序列化往返', () {
      for (final mode in AppThemePreference.values) {
        final s = AppearanceSettings(themeMode: mode);
        final back = AppearanceSettings.fromKeyValues(s.toKeyValues());
        expect(back.themeMode, mode, reason: '模式 $mode 未往返');
      }
    });

    test('themeMode -> ThemeMode 映射正确', () {
      expect(AppThemePreference.system.themeMode, ThemeMode.system);
      expect(AppThemePreference.light.themeMode, ThemeMode.light);
      expect(AppThemePreference.dark.themeMode, ThemeMode.dark);
    });

    test('copyWith(themeMode:) 真的改变了值（能触发写库）', () {
      const base = AppearanceSettings();
      for (final mode in AppThemePreference.values) {
        final next = base.copyWith(themeMode: mode);
        expect(next.themeMode, mode, reason: 'copyWith 没生效: $mode');
        if (mode != base.themeMode) {
          expect(next == base, isFalse, reason: '$mode 与默认相等，apply 会提前 return');
        }
      }
    });

    test('深浅模式不会互相等于', () {
      const light = AppearanceSettings(themeMode: AppThemePreference.light);
      const dark = AppearanceSettings(themeMode: AppThemePreference.dark);
      expect(light == dark, isFalse);
    });
  });

  group('诊断：配色', () {
    test('每个预设配色都能序列化往返', () {
      for (final scheme in AppColorScheme.values) {
        final s = AppearanceSettings(colorScheme: scheme);
        final back = AppearanceSettings.fromKeyValues(s.toKeyValues());
        expect(back.colorScheme, scheme, reason: '配色 $scheme 未往返');
      }
    });

    test('copyWith(colorScheme:) 真的改变了值', () {
      const base = AppearanceSettings();
      for (final scheme in AppColorScheme.values) {
        final next = base.copyWith(colorScheme: scheme);
        expect(next.colorScheme, scheme, reason: 'copyWith 没生效: $scheme');
        if (scheme != base.colorScheme) {
          expect(next == base, isFalse, reason: '$scheme 与默认相等，apply 会提前 return');
        }
      }
    });

    test('每个配色产生不同的种子色（否则改了看不出来）', () {
      final seeds = <int>{};
      for (final scheme in AppColorScheme.values) {
        seeds.add(AppearanceSettings(colorScheme: scheme).effectiveSeed.toARGB32());
      }
      expect(seeds.length, AppColorScheme.values.length,
          reason: '有配色共用同一 seed，改了不起作用');
    });

    test('自定义配色往返 + 优先于预设', () {
      const custom = CustomColorScheme(
        seed: Color(0xFF123456),
        accent: Color(0xFFABCDEF),
      );
      final s = AppearanceSettings(
        colorScheme: AppColorScheme.slate,
        customColors: custom,
      );
      final back = AppearanceSettings.fromKeyValues(s.toKeyValues());
      expect(back.customColors, custom);
      expect(back.isCustomColors, isTrue);
      expect(back.effectiveSeed, const Color(0xFF123456));
      expect(back.effectiveAccent, const Color(0xFFABCDEF));
    });

    test('清除自定义配色后回到预设', () {
      const s = AppearanceSettings(
        colorScheme: AppColorScheme.ocean,
        customColors: CustomColorScheme(
          seed: Color(0xFF123456),
          accent: Color(0xFFABCDEF),
        ),
      );
      final cleared = s.copyWith(clearCustomColors: true);
      expect(cleared.customColors, isNull);
      expect(cleared.isCustomColors, isFalse);
      expect(cleared.effectiveSeed, AppColorScheme.ocean.seed);
    });
  });

  group('诊断：其它可能被忽略的字段', () {
    test('useAmoledBlack 往返 + copyWith 生效', () {
      const base = AppearanceSettings();
      final next = base.copyWith(useAmoledBlack: true);
      expect(next.useAmoledBlack, isTrue);
      expect(next == base, isFalse);
      expect(
        AppearanceSettings.fromKeyValues(next.toKeyValues()).useAmoledBlack,
        isTrue,
      );
    });

    test('每种背景预设往返', () {
      for (final bg in AppBackgroundPreset.values) {
        final s = AppearanceSettings(background: bg);
        expect(
          AppearanceSettings.fromKeyValues(s.toKeyValues()).background,
          bg,
          reason: '背景 $bg 未往返',
        );
      }
    });

    test('每个圆角/紧凑度值往返', () {
      for (final c in AppCornerStyle.values) {
        expect(
          AppearanceSettings.fromKeyValues(
            AppearanceSettings(corner: c).toKeyValues(),
          ).corner,
          c,
        );
      }
      for (final d in AppDensity.values) {
        expect(
          AppearanceSettings.fromKeyValues(
            AppearanceSettings(density: d).toKeyValues(),
          ).density,
          d,
        );
      }
    });

    test('全字段一起改也能往返（防止互相覆盖）', () {
      const s = AppearanceSettings(
        colorScheme: AppColorScheme.rose,
        themeMode: AppThemePreference.dark,
        corner: AppCornerStyle.pill,
        density: AppDensity.relaxed,
        cardStyle: AppCardStyle.gradient,
        cardOpacity: 0.9,
        appBarOpacity: 0.5,
        greetingText: '测试标题',
        hideGreeting: true,
        titleFont: AppTitleFont.kaiti,
        showWeekend: false,
        useAmoledBlack: true,
        weekLayout: AppWeekLayout.table,
        widgetColorPreset: WidgetColorPreset.celadon,
        background: AppBackgroundPreset.dots,
        backgroundBlur: 12,
        backgroundDim: 0.6,
      );
      final back = AppearanceSettings.fromKeyValues(s.toKeyValues());
      expect(back, s, reason: '全字段往返后不相等，说明有字段没存或没读');
    });
  });
}
