import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../application/schedule_controller.dart';
import '../domain/notification_settings.dart';
import 'reminder_planner.dart';

final notificationServiceProvider = Provider<NotificationService>((ref) {
  throw StateError('NotificationService 尚未初始化');
});

class NotificationService {
  NotificationService({FlutterLocalNotificationsPlugin? plugin})
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  /// iOS 的 UNUserNotificationCenter 最多只允许挂 64 条待发通知，
  /// 超出的会被系统**静默丢弃**（Android 的 AlarmManager 没有这个上限）。
  /// 留一点余量给测试通知（id 900001）这类临时条目。
  static const int _iosPendingLimit = 60;

  final FlutterLocalNotificationsPlugin _plugin;
  final _tappedDates = StreamController<DateTime>.broadcast();
  final _planner = const ReminderPlanner();

  Stream<DateTime> get tappedDates => _tappedDates.stream;

  Future<DateTime?> initialize() async {
    tz_data.initializeTimeZones();
    final timezone = await FlutterTimezone.getLocalTimezone();
    tz.setLocalLocation(tz.getLocation(timezone.identifier));
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('ic_notification'),
        // iOS 必须显式给一份 Darwin 配置：只填 android 的话，插件在 iOS 上
        // 等于没初始化，之后请求权限、排程会全部静默失败。
        // 三个 request*Permission 都留 false —— 权限等用户主动开提醒时再要，
        // 免得一进 App 就弹授权窗（与 Android 侧的请求时机保持一致）。
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestSoundPermission: false,
          requestBadgePermission: false,
        ),
      ),
      onDidReceiveNotificationResponse: (response) {
        final date = _parsePayload(response.payload);
        if (date != null) _tappedDates.add(date);
      },
    );
    final launch = await _plugin.getNotificationAppLaunchDetails();
    if (launch?.didNotificationLaunchApp != true) return null;
    return _parsePayload(launch?.notificationResponse?.payload);
  }

  /// 平台中立的「确保拿到通知授权」入口。
  /// Android 还要额外拿精确闹钟权限（否则息屏不响）；
  /// iOS 没有这个概念，只需普通的通知授权。
  Future<void> ensurePermissions() async {
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (android != null) {
      await android.requestNotificationsPermission();
      await android.requestExactAlarmsPermission();
      return;
    }
    final ios = _plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >();
    await ios?.requestPermissions(alert: true, badge: true, sound: true);
  }

  Future<bool> canScheduleExactNotifications() async {
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    // iOS 没有「精确闹钟授权」这个概念 —— 通知由系统统一调度，本来就准时。
    // 这里必须返回 true：否则 reschedule() 的前置判断会直接放弃排程，
    // iOS 上等于一条提醒都排不出来。
    if (android == null) return true;
    return await android.canScheduleExactNotifications() ?? false;
  }

  Future<bool> notificationsEnabled() async {
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (android != null) {
      return await android.areNotificationsEnabled() ?? false;
    }
    final ios = _plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >();
    final options = await ios?.checkPermissions();
    return options?.isEnabled ?? false;
  }

  Future<int> pendingNotificationCount() async =>
      (await _plugin.pendingNotificationRequests()).length;

  Future<void> sendTestNotification(NotificationSettings settings) {
    final mode = settings.alertMode;
    return _plugin.show(
      id: 900001,
      title: 'HITable 测试提醒',
      body: '如果你看到这条消息，通知显示功能正常。',
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          'course_reminder_test_${mode.name}',
          '提醒功能测试',
          channelDescription: '用于检查通知、震动和声音设置',
          importance: Importance.high,
          priority: Priority.high,
          icon: 'ic_notification',
          playSound: mode == ReminderAlertMode.soundAndVibration,
          enableVibration: mode != ReminderAlertMode.notificationOnly,
        ),
        // iOS 侧没有「渠道」概念，只有「响不响」，跟 Android 的 alertMode 对齐
        iOS: DarwinNotificationDetails(
          presentSound: mode == ReminderAlertMode.soundAndVibration,
        ),
      ),
    );
  }

  Future<void> openNotificationSettings() =>
      _plugin.openAppNotificationSettings();

  Future<int> reschedule({
    required ScheduleData schedule,
    required NotificationSettings settings,
    DateTime? now,
  }) async {
    await _plugin.cancelAll();
    final term = schedule.term;
    if (term == null || !settings.enabled) return 0;
    if (!await canScheduleExactNotifications()) return 0;
    final currentTime = now ?? tz.TZDateTime.now(tz.local);
    var plans = _planner.createPlans(
      now: currentTime,
      term: term,
      courses: schedule.courses,
      adjustments: schedule.adjustments,
      cancellations: schedule.cancellations,
      settings: settings,
    );
    var lockScreenPlans = _planner.createLockScreenPlans(
      now: currentTime,
      term: term,
      courses: schedule.courses,
      adjustments: schedule.adjustments,
      cancellations: schedule.cancellations,
      settings: settings,
    );

    // iOS 超出 64 条的部分会被系统静默丢弃，所以先裁再排。
    // 上课提醒是主体，优先保住；锁屏提示只是锦上添花，用剩下的额度。
    // 两者都已经按时间升序，所以 sublist(0, n) 天然是「最近的那几条」。
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      final reminderRoom = math.min(plans.length, _iosPendingLimit);
      final lockRoom = math.min(
        lockScreenPlans.length,
        _iosPendingLimit - reminderRoom,
      );
      plans = plans.sublist(0, reminderRoom);
      lockScreenPlans = lockScreenPlans.sublist(0, lockRoom);
    }

    final alertMode = settings.alertMode;
    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        'course_reminders_${alertMode.name}',
        '上课提醒',
        channelDescription: '在课程开始前提醒',
        importance: Importance.high,
        priority: Priority.high,
        icon: 'ic_notification',
        playSound: alertMode == ReminderAlertMode.soundAndVibration,
        enableVibration: alertMode != ReminderAlertMode.notificationOnly,
      ),
      iOS: DarwinNotificationDetails(
        presentSound: alertMode == ReminderAlertMode.soundAndVibration,
      ),
    );
    for (final plan in plans) {
      final time = plan.scheduledAt;
      await _plugin.zonedSchedule(
        id: plan.id,
        title: plan.title,
        body: plan.body,
        scheduledDate: tz.TZDateTime(
          tz.local,
          time.year,
          time.month,
          time.day,
          time.hour,
          time.minute,
        ),
        notificationDetails: details,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        payload: plan.payload,
      );
    }
    for (final plan in lockScreenPlans) {
      final time = plan.scheduledAt;
      final details = NotificationDetails(
        android: AndroidNotificationDetails(
          'lock_screen_next_course',
          '锁屏下一节课',
          channelDescription: '上课前一小时在锁屏显示下一节课程',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
          icon: 'ic_notification',
          playSound: false,
          enableVibration: false,
          visibility: NotificationVisibility.public,
          category: AndroidNotificationCategory.event,
          timeoutAfter: plan.timeoutAfterMilliseconds,
          styleInformation: BigTextStyleInformation(plan.body),
        ),
        // iOS 没有「锁屏卡片」这种常驻样式，落到普通通知即可
        iOS: const DarwinNotificationDetails(
          presentSound: false,
          presentBadge: false,
        ),
      );
      await _plugin.zonedSchedule(
        id: plan.id,
        title: plan.title,
        body: plan.body,
        scheduledDate: tz.TZDateTime(
          tz.local,
          time.year,
          time.month,
          time.day,
          time.hour,
          time.minute,
          time.second,
        ),
        notificationDetails: details,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        payload: plan.payload,
      );
    }
    return plans.length + lockScreenPlans.length;
  }

  Future<void> dispose() => _tappedDates.close();

  DateTime? _parsePayload(String? payload) {
    if (payload == null) return null;
    final value = DateTime.tryParse(payload);
    return value == null ? null : DateTime(value.year, value.month, value.day);
  }
}
