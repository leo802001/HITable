/// 界面外观设置的状态管理。
///
/// 用 `AsyncNotifier` 而不是 `Notifier`，因为初始值要从 SQLite 读；
/// 界面在加载完成前用默认主题渲染，不会有闪烁。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/schedule_database.dart';
import '../domain/appearance_settings.dart';
import 'schedule_controller.dart';

/// 当前外观设置。读取失败时退回默认值，不让设置页把整个 App 卡住。
final appearanceControllerProvider =
    AsyncNotifierProvider<AppearanceController, AppearanceSettings>(
  AppearanceController.new,
);

class AppearanceController extends AsyncNotifier<AppearanceSettings> {
  late final ScheduleDatabase _database;

  @override
  Future<AppearanceSettings> build() async {
    _database = await ref.watch(databaseProvider.future);
    try {
      return await _database.loadAppearanceSettings();
    } catch (_) {
      // 数据库异常不应导致主题加载失败，退回默认外观。
      return const AppearanceSettings();
    }
  }

  /// 更新设置并立即持久化。
  ///
  /// 采用「乐观更新」：先改内存状态让界面立刻响应，再写库。
  /// 写库失败时回滚，避免界面显示与实际存储不一致。
  ///
  /// 注意：方法名不能叫 `update` —— 会与 `AsyncNotifier.update` 冲突。
  Future<void> apply(AppearanceSettings next) async {
    final previous = state.valueOrNull ?? const AppearanceSettings();
    if (previous == next) return;
    state = AsyncData(next);
    try {
      await _database.saveAppearanceSettings(next);
    } catch (_) {
      state = AsyncData(previous);
      rethrow;
    }
  }

  /// 恢复默认外观。
  Future<void> reset() => apply(const AppearanceSettings());
}

/// 当前外观设置的便捷读取：界面用 `ref.watch(appearanceProvider)` 拿到
/// 已解析好的值（未加载完时给默认值），避免每处都处理 AsyncValue。
final appearanceProvider = Provider<AppearanceSettings>((ref) {
  return ref.watch(appearanceControllerProvider).valueOrNull ??
      const AppearanceSettings();
});
