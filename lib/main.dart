import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'application/appearance_controller.dart';
import 'notifications/notification_lifecycle.dart';
import 'notifications/notification_service.dart';
import 'presentation/app_background.dart';
import 'presentation/app_theme.dart';
import 'presentation/home_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final notificationService = NotificationService();
  final initialDate = await notificationService.initialize();
  runApp(
    ProviderScope(
      overrides: [
        notificationServiceProvider.overrideWithValue(notificationService),
      ],
      child: CourseScheduleApp(
        notificationService: notificationService,
        initialDate: initialDate,
      ),
    ),
  );
}

class CourseScheduleApp extends ConsumerWidget {
  const CourseScheduleApp({
    super.key,
    this.notificationService,
    this.initialDate,
  });

  final NotificationService? notificationService;
  final DateTime? initialDate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 外观设置加载完成前用默认主题渲染，避免主题闪一下再变
    final appearance = ref.watch(appearanceProvider);

    return MaterialApp(
      title: 'HITable',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(appearance),
      darkTheme: AppTheme.dark(appearance),
      themeMode: appearance.themeMode.themeMode,
      home: AppBackground(
        settings: appearance,
        child: notificationService == null
            ? const HomePage()
            : NotificationLifecycle(
                service: notificationService!,
                initialDate: initialDate,
                child: const HomePage(),
              ),
      ),
    );
  }
}
