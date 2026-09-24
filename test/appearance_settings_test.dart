import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_course_schedule/domain/appearance_settings.dart';

void main() {
  group('外观设置序列化', () {
    test('默认值符合预期', () {
      const settings = AppearanceSettings();
      expect(settings.colorScheme, AppColorScheme.slate);
      expect(settings.themeMode, AppThemePreference.system);
      expect(settings.corner, AppCornerStyle.standard);
      expect(settings.density, AppDensity.standard);
      expect(settings.cardStyle, AppCardStyle.plain);
      expect(settings.showWeekend, isTrue);
      expect(settings.useAmoledBlack, isFalse);
    });

    test('往返转换不丢信息', () {
      const original = AppearanceSettings(
        colorScheme: AppColorScheme.aurora,
        themeMode: AppThemePreference.dark,
        corner: AppCornerStyle.pill,
        density: AppDensity.compact,
        cardStyle: AppCardStyle.gradient,
        showWeekend: false,
        useAmoledBlack: true,
      );
      final restored = AppearanceSettings.fromKeyValues(original.toKeyValues());
      expect(restored, original);
    });

    test('每一套配色都能往返', () {
      for (final scheme in AppColorScheme.values) {
        final settings = AppearanceSettings(colorScheme: scheme);
        final restored =
            AppearanceSettings.fromKeyValues(settings.toKeyValues());
        expect(restored.colorScheme, scheme, reason: '配色 ${scheme.label} 应能还原');
      }
    });

    test('每一个圆角档位都能往返', () {
      for (final corner in AppCornerStyle.values) {
        final restored = AppearanceSettings.fromKeyValues(
          AppearanceSettings(corner: corner).toKeyValues(),
        );
        expect(restored.corner, corner);
      }
    });
  });

  group('外观设置容错（老版本升级 / 脏数据）', () {
    test('空 map 全部退回默认', () {
      final settings = AppearanceSettings.fromKeyValues(const {});
      expect(settings, const AppearanceSettings());
    });

    test('未知枚举值退回默认而不抛异常', () {
      final settings = AppearanceSettings.fromKeyValues(const {
        'appearance.colorScheme': '不存在的配色',
        'appearance.corner': 'unknown',
        'appearance.density': 'weird',
        'appearance.cardStyle': '???',
      });
      expect(settings.colorScheme, AppColorScheme.slate);
      expect(settings.corner, AppCornerStyle.standard);
      expect(settings.density, AppDensity.standard);
      expect(settings.cardStyle, AppCardStyle.plain);
    });

    test('部分键缺失时，已有键仍生效', () {
      final settings = AppearanceSettings.fromKeyValues(const {
        'appearance.themeMode': 'dark',
      });
      expect(settings.themeMode, AppThemePreference.dark);
      // 未提供的键走默认
      expect(settings.colorScheme, AppColorScheme.slate);
      expect(settings.showWeekend, isTrue);
    });

    test('布尔值只认 "1"，其它一律 false（纯黑）', () {
      expect(
        AppearanceSettings.fromKeyValues(
          const {'appearance.useAmoledBlack': '1'},
        ).useAmoledBlack,
        isTrue,
      );
      for (final v in ['0', 'true', '', 'yes']) {
        expect(
          AppearanceSettings.fromKeyValues(
            {'appearance.useAmoledBlack': v},
          ).useAmoledBlack,
          isFalse,
          reason: 'useAmoledBlack 对 "$v" 应为 false',
        );
      }
    });

    test('显示周末默认开启，仅显式 "0" 才关闭', () {
      expect(
        AppearanceSettings.fromKeyValues(const {}).showWeekend,
        isTrue,
      );
      expect(
        AppearanceSettings.fromKeyValues(
          const {'appearance.showWeekend': '0'},
        ).showWeekend,
        isFalse,
      );
    });
  });

  group('copyWith', () {
    test('只改指定字段，其余保持不变', () {
      const base = AppearanceSettings();
      final changed = base.copyWith(colorScheme: AppColorScheme.sunset);
      expect(changed.colorScheme, AppColorScheme.sunset);
      expect(changed.themeMode, base.themeMode);
      expect(changed.corner, base.corner);
      expect(changed.density, base.density);
    });

    test('无参数时等价于原对象', () {
      const base = AppearanceSettings(
        colorScheme: AppColorScheme.celadon,
        themeMode: AppThemePreference.light,
      );
      expect(base.copyWith(), base);
    });
  });

  group('自定义配色序列化', () {
    test('往返不丢信息', () {
      const original = AppearanceSettings(
        customColors: CustomColorScheme(
          seed: Color(0xFFC2185B),
          accent: Color(0xFFE0668F),
        ),
      );
      final restored = AppearanceSettings.fromKeyValues(original.toKeyValues());
      expect(restored.customColors, original.customColors);
      expect(restored.isCustomColors, isTrue);
    });

    test('未设自定义配色时不写入相关键', () {
      final keys = const AppearanceSettings().toKeyValues().keys;
      expect(keys.any((k) => k.startsWith('appearance.custom.')), isFalse);
      expect(const AppearanceSettings().isCustomColors, isFalse);
    });

    test('只有一半色值合法时，另一半用 fallback', () {
      const partial = {'appearance.custom.seed': 'ffc2185b'};
      final restored = AppearanceSettings.fromKeyValues(partial);
      expect(restored.customColors, isNotNull);
      expect(restored.customColors!.seed.toARGB32(), 0xFFC2185B);
      expect(
        restored.customColors!.accent.toARGB32(),
        CustomColorScheme.fallback.accent.toARGB32(),
      );
    });

    test('非法色值不会抛异常', () {
      final restored = AppearanceSettings.fromKeyValues(const {
        'appearance.custom.seed': '这不是颜色',
        'appearance.custom.accent': 'zzz',
      });
      // 两个都解析失败 → 视为没设自定义
      expect(restored.customColors, isNull);
    });

    test('effectiveSeed/Accent 优先取自定义值', () {
      const custom = CustomColorScheme(
        seed: Color(0xFF111111),
        accent: Color(0xFF222222),
      );
      const settings = AppearanceSettings(
        colorScheme: AppColorScheme.sunset,
        customColors: custom,
      );
      expect(settings.effectiveSeed.toARGB32(), 0xFF111111);
      expect(settings.effectiveAccent.toARGB32(), 0xFF222222);
    });

    test('无自定义时 effective* 取预设值', () {
      const settings = AppearanceSettings(colorScheme: AppColorScheme.sunset);
      expect(settings.effectiveSeed.toARGB32(),
          AppColorScheme.sunset.seed.toARGB32());
      expect(settings.effectiveAccent.toARGB32(),
          AppColorScheme.sunset.accent.toARGB32());
      expect(settings.effectiveAccentAlt.toARGB32(),
          AppColorScheme.sunset.accentAlt.toARGB32());
    });
  });

  group('背景设置序列化', () {
    test('预设背景往返', () {
      for (final preset in AppBackgroundPreset.values) {
        final restored = AppearanceSettings.fromKeyValues(
          AppearanceSettings(background: preset).toKeyValues(),
        );
        expect(restored.background, preset, reason: preset.label);
      }
    });

    test('自定义图路径往返', () {
      const path = '/data/data/pkg/files/bg.jpg';
      final restored = AppearanceSettings.fromKeyValues(
        const AppearanceSettings(customBackgroundPath: path).toKeyValues(),
      );
      expect(restored.customBackgroundPath, path);
      expect(restored.hasCustomBackground, isTrue);
    });

    test('空路径视为未设置背景图', () {
      final restored = AppearanceSettings.fromKeyValues(
        const AppearanceSettings(customBackgroundPath: '').toKeyValues(),
      );
      expect(restored.customBackgroundPath, isNull);
      expect(restored.hasCustomBackground, isFalse);
    });

    test('模糊与明暗数值往返', () {
      const settings = AppearanceSettings(backgroundBlur: 12, backgroundDim: 0.5);
      final restored = AppearanceSettings.fromKeyValues(settings.toKeyValues());
      expect(restored.backgroundBlur, 12);
      expect(restored.backgroundDim, 0.5);
    });

    test('模糊值超范围会被夹紧', () {
      expect(
        AppearanceSettings.fromKeyValues(
          const {'appearance.backgroundBlur': '999'},
        ).backgroundBlur,
        30,
      );
      expect(
        AppearanceSettings.fromKeyValues(
          const {'appearance.backgroundBlur': '-10'},
        ).backgroundBlur,
        0,
      );
    });

    test('明暗值超范围会被夹紧', () {
      expect(
        AppearanceSettings.fromKeyValues(
          const {'appearance.backgroundDim': '5'},
        ).backgroundDim,
        0.8,
      );
      expect(
        AppearanceSettings.fromKeyValues(
          const {'appearance.backgroundDim': '-1'},
        ).backgroundDim,
        0,
      );
    });

    test('非法数值退回默认', () {
      final restored = AppearanceSettings.fromKeyValues(const {
        'appearance.backgroundBlur': 'abc',
        'appearance.backgroundDim': 'NaN',
      });
      expect(restored.backgroundBlur, const AppearanceSettings().backgroundBlur);
      expect(restored.backgroundDim, const AppearanceSettings().backgroundDim);
    });
  });

  group('copyWith 的背景语义', () {
    test('clearCustomBackground 能清掉路径', () {
      const settings = AppearanceSettings(customBackgroundPath: '/a/b.jpg');
      expect(settings.copyWith(clearCustomBackground: true).customBackgroundPath,
          isNull);
    });

    test('clearCustomColors 能清掉自定义配色', () {
      const settings = AppearanceSettings(
        customColors: CustomColorScheme(
          seed: Color(0xFF111111),
          accent: Color(0xFF222222),
        ),
      );
      expect(settings.copyWith(clearCustomColors: true).customColors, isNull);
      expect(settings.isCustomColors, isTrue, reason: '原对象不应被改动');
    });

    test('不传参数时保留原有背景图', () {
      const settings = AppearanceSettings(customBackgroundPath: '/a/b.jpg');
      expect(
        settings.copyWith(backgroundBlur: 5).customBackgroundPath,
        '/a/b.jpg',
      );
    });
  });

  group('卡片不透明度', () {
    test('默认值在合理区间内', () {
      final opacity = const AppearanceSettings().cardOpacity;
      expect(opacity, greaterThan(0.15));
      expect(opacity, lessThanOrEqualTo(1.0));
    });

    test('往返不丢信息', () {
      const settings = AppearanceSettings(cardOpacity: 0.8);
      final restored = AppearanceSettings.fromKeyValues(settings.toKeyValues());
      expect(restored.cardOpacity, 0.8);
    });

    test('超范围会被夹紧到 0.15~1.0', () {
      expect(
        AppearanceSettings.fromKeyValues(
          const {'appearance.cardOpacity': '5'},
        ).cardOpacity,
        1.0,
      );
      expect(
        AppearanceSettings.fromKeyValues(
          const {'appearance.cardOpacity': '0'},
        ).cardOpacity,
        0.15,
      );
    });

    test('非法值退回默认', () {
      expect(
        AppearanceSettings.fromKeyValues(
          const {'appearance.cardOpacity': 'abc'},
        ).cardOpacity,
        const AppearanceSettings().cardOpacity,
      );
    });

    test('不同值不相等（会触发写库）', () {
      const a = AppearanceSettings(cardOpacity: 0.5);
      const b = AppearanceSettings(cardOpacity: 0.6);
      expect(a == b, isFalse);
    });
  });

  group('相等性（决定是否会触发写库）', () {
    test('字段相同则相等', () {
      const a = AppearanceSettings(colorScheme: AppColorScheme.aurora);
      const b = AppearanceSettings(colorScheme: AppColorScheme.aurora);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('任一字段不同则不等', () {
      const a = AppearanceSettings();
      expect(a == a.copyWith(themeMode: AppThemePreference.dark), isFalse);
      expect(a == a.copyWith(showWeekend: false), isFalse);
      expect(a == a.copyWith(useAmoledBlack: true), isFalse);
    });
  });

  group('枚举属性', () {
    test('配色都带标签与三个颜色', () {
      for (final scheme in AppColorScheme.values) {
        expect(scheme.label, isNotEmpty);
        expect(scheme.seed, isA<Color>());
        expect(scheme.accent, isA<Color>());
        expect(scheme.accentAlt, isA<Color>());
        expect(scheme.seed, isNot(scheme.accent), reason: '${scheme.label} 主色与强调色应不同');
        expect(
          scheme.accent,
          isNot(scheme.accentAlt),
          reason: '${scheme.label} 两个强调色应不同，否则渐变看不出来',
        );
      }
    });

    test('配色数量足够丰富（≥10 套）', () {
      expect(AppColorScheme.values.length, greaterThanOrEqualTo(10));
    });

    test('圆角档位递增', () {
      final radii = AppCornerStyle.values.map((c) => c.radius).toList();
      final sorted = List<double>.of(radii)..sort();
      expect(radii, sorted, reason: '圆角应由小到大排列，便于设置页展示');
    });

    test('紧凑度档位递增', () {
      final scales = AppDensity.values.map((d) => d.scale).toList();
      final sorted = List<double>.of(scales)..sort();
      expect(scales, sorted);
    });

    test('深浅模式映射到正确的 ThemeMode', () {
      expect(AppThemePreference.system.themeMode, ThemeMode.system);
      expect(AppThemePreference.light.themeMode, ThemeMode.light);
      expect(AppThemePreference.dark.themeMode, ThemeMode.dark);
    });
  });

  group('持久化键名', () {
    test('全部带 appearance. 前缀，避免与通知设置撞键', () {
      final keys = const AppearanceSettings().toKeyValues().keys;
      expect(keys, isNotEmpty);
      for (final key in keys) {
        expect(key, startsWith('appearance.'));
      }
    });

    test('通知设置的键不会被覆盖', () {
      // 这两个前缀在 app_settings 表里共存，必须互不干扰
      final appearanceKeys = const AppearanceSettings().toKeyValues().keys;
      const notificationKeys = {
        'notifications_enabled',
        'advance_minutes',
        'reminder_alert_mode',
      };
      expect(appearanceKeys.toSet().intersection(notificationKeys), isEmpty);
    });
  });
}
