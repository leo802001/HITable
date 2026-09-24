import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/appearance_controller.dart';
import '../application/schedule_controller.dart';
import '../presentation/magic_os_guide_page.dart';
import '../presentation/tutorial_page.dart';
import '../widget/next_course_widget_service.dart';
import 'notification_service.dart';

class NotificationLifecycle extends ConsumerStatefulWidget {
  const NotificationLifecycle({
    required this.service,
    required this.child,
    this.initialDate,
    super.key,
  });

  final NotificationService service;
  final DateTime? initialDate;
  final Widget child;

  @override
  ConsumerState<NotificationLifecycle> createState() =>
      _NotificationLifecycleState();
}

class _NotificationLifecycleState extends ConsumerState<NotificationLifecycle>
    with WidgetsBindingObserver {
  StreamSubscription<DateTime>? _tapSubscription;
  bool _startupFlowOpen = false;
  bool _syncing = false;
  bool _holidayChecked = false;
  final _widgetService = const NextCourseWidgetService();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _tapSubscription = widget.service.tappedDates.listen(_openDate);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final initialDate = widget.initialDate;
      if (initialDate != null) _openDate(initialDate);
      await widget.service.requestAndroidPermissions();
      await _syncNotifications();
      // 小组件与提醒设置无关，单独同步一次。
      // 早期版本把两者绑在同一个方法里，导致「没开提醒 → 小组件永远空白」。
      await _syncWidget();
      await _checkNationalMakeupDays();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_syncNotifications());
      unawaited(_syncWidget());
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentSettings = ref.watch(notificationSettingsProvider).valueOrNull;
    if (currentSettings != null && !_startupFlowOpen) {
      if (!currentSettings.tutorialPromptCompleted) {
        _openTutorialPromptAfterBuild();
      } else if (!currentSettings.magicOsGuideCompleted) {
        _openGuideAfterBuild();
      }
    }
    ref.listen(scheduleControllerProvider, (_, __) {
      unawaited(_syncNotifications());
      unawaited(_syncWidget());
    });
    ref.listen(notificationSettingsProvider, (_, next) {
      unawaited(_syncNotifications());
    });
    // 外观变化（配色预设 / 深浅模式 / 自定义颜色）也要重推小组件，
    // 否则「界面美化 → 桌面小组件配色」改了等于没改：
    // 小组件配色是随 payload 下发的，不监听就永远不会更新。
    ref.listen(appearanceProvider, (_, __) {
      unawaited(_syncWidget());
    });
    // 课表首次加载完成时也同步一次：`ref.listen` 只在**值变化**时触发，
    // 启动瞬间课表可能正好在这一帧变成有值（不产生「变化」），会漏掉首次同步。
    ref.listen(scheduleControllerProvider.select((v) => v.hasValue), (_, has) {
      if (has) unawaited(_syncWidget());
    });
    return widget.child;
  }

  /// 同步桌面小组件数据。
  ///
  /// 与 [_syncNotifications] 解耦：小组件只需要 [scheduleControllerProvider]，
  /// **不依赖** notificationSettingsProvider。早期实现把两者写在一起，
  /// 用户若没开启任何提醒（settings 为 null）就直接 return，
  /// 小组件永远拿不到数据，表现为「今天没有课」。
  Future<void> _syncWidget() async {
    if (!mounted) return;
    final schedule = ref.read(scheduleControllerProvider).valueOrNull;
    if (schedule == null || schedule.term == null) return;
    final appearance = ref.read(appearanceProvider);
    try {
      await _widgetService.sync(
        schedule,
        colorPreset: appearance.widgetColorPreset,
        customColors: appearance.customColors,
        colorScheme: appearance.colorScheme,
        // 自定义背景：只有「开关打开 + 已选图」时才下发，
        // 否则原生走原来的不透明卡片，行为与 1.1.8 完全一致。
        background: appearance.hasWidgetBackground
            ? WidgetBackgroundSpec(
                path: appearance.widgetBackgroundPath!,
                blur: appearance.widgetBackgroundBlur,
                dim: appearance.widgetBackgroundDim,
                cardOpacity: appearance.widgetCardOpacity,
                textOpacity: appearance.widgetTextOpacity,
              )
            : null,
      );
    } catch (_) {
      // 小组件同步失败不应影响 App 主流程（例如原生侧尚未就绪）。
    }
  }

  void _openGuideAfterBuild() {
    _startupFlowOpen = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.of(context)
          .push(
            MaterialPageRoute<void>(builder: (_) => const MagicOsGuidePage()),
          )
          .then((_) {
            if (mounted) setState(() => _startupFlowOpen = false);
          });
    });
  }

  void _openTutorialPromptAfterBuild() {
    _startupFlowOpen = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final shouldView = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: const Text('第一次使用，需要看看教程吗？'),
          content: const Text('教程会用简单步骤说明怎样添加学期、导入课表、设置提醒和桌面小组件。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('暂不查看'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('查看教程'),
            ),
          ],
        ),
      );
      if (!mounted) return;
      final settings = ref.read(notificationSettingsProvider).valueOrNull;
      if (settings != null) {
        await ref
            .read(notificationSettingsProvider.notifier)
            .saveSettings(settings.copyWith(tutorialPromptCompleted: true));
      }
      if (!mounted) return;
      if (shouldView == true) {
        await Navigator.of(
          context,
        ).push(MaterialPageRoute<void>(builder: (_) => const TutorialPage()));
      }
      if (mounted) setState(() => _startupFlowOpen = false);
    });
  }

  Future<void> _syncNotifications() async {
    if (_syncing || !mounted) return;
    final schedule = ref.read(scheduleControllerProvider).valueOrNull;
    final settings = ref.read(notificationSettingsProvider).valueOrNull;
    if (schedule == null || settings == null) return;
    _syncing = true;
    try {
      await widget.service.reschedule(schedule: schedule, settings: settings);
      // 这里原来的 `_widgetService.sync(schedule)` 已删除：它不带配色与
      // 背景参数，会以默认色板覆盖用户选的配色，而且与紧随其后的
      // `_syncWidget()` 形成竞态（谁后写完谁生效，表现为配色偶尔被重置）。
      // 小组件与提醒设置本来就无关，同步统一走 [_syncWidget]。
    } finally {
      _syncing = false;
    }
  }

  Future<void> _checkNationalMakeupDays() async {
    if (_holidayChecked || !mounted) return;
    _holidayChecked = true;
    try {
      await ref
          .read(scheduleControllerProvider.notifier)
          .checkNationalMakeupDays();
    } catch (_) {
      // 网络不可用时继续使用本机已保存的调休日期。
    }
  }

  void _openDate(DateTime date) {
    if (!mounted) return;
    ref.read(selectedDateProvider.notifier).state = date;
    ref.read(notificationNavigationRevisionProvider.notifier).state++;
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_tapSubscription?.cancel());
    unawaited(widget.service.dispose());
    super.dispose();
  }
}
