import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/appearance_controller.dart';
import '../feature_flags.dart';
import '../application/schedule_controller.dart';
import '../domain/appearance_settings.dart';
import '../domain/schedule_engine.dart';
import '../domain/schedule_models.dart';
import 'import_preview_page.dart';
import 'data_management_page.dart';
import 'manual_course_page.dart';
import 'notification_settings_page.dart';
import 'term_setup_page.dart';
import 'hit_timetable_page.dart';
import 'appearance_settings_page.dart';

class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final schedule = ref.watch(scheduleControllerProvider);
    return schedule.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (_, __) => Scaffold(
        body: Center(
          child: FilledButton(
            onPressed: () => ref.invalidate(scheduleControllerProvider),
            child: const Text('加载失败，点击重试'),
          ),
        ),
      ),
      data: (data) => data.term == null
          ? _WelcomePage(
              onSetup: () => Navigator.push(
                context,
                MaterialPageRoute<void>(builder: (_) => const TermSetupPage()),
              ),
            )
          : _ScheduleHome(data: data),
    );
  }
}

class _WelcomePage extends StatelessWidget {
  const _WelcomePage({required this.onSetup});

  final VoidCallback onSetup;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: const Icon(Icons.calendar_month_rounded, size: 38),
                ),
                const SizedBox(height: 24),
                Text(
                  '先设置你的学期',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 10),
                Text(
                  '只需填写开学日期、总周数和每天的节次时间，所有数据都会保存在本机。',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 28),
                FilledButton(onPressed: onSetup, child: const Text('开始设置')),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ScheduleHome extends ConsumerWidget {
  const _ScheduleHome({required this.data});

  final ScheduleData data;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final term = data.term!;
    // 顶部问候语随设置变化
    final appearance = ref.watch(appearanceProvider);
    final selectedDate = ref.watch(selectedDateProvider);
    final navigationRevision = ref.watch(
      notificationNavigationRevisionProvider,
    );
    final engine = ScheduleEngine(
      term: term,
      courses: data.courses,
      adjustments: data.adjustments,
      cancellations: data.cancellations,
    );
    return DefaultTabController(
      key: ValueKey(navigationRevision),
      length: 2,
      child: Scaffold(
        // 透明背景，让 main.dart 里的 AppBackground 露出来
        backgroundColor: Colors.transparent,
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute<void>(
              builder: (_) => ManualCoursePage(term: term),
            ),
          ),
          icon: const Icon(Icons.add_rounded),
          label: const Text('添加课程'),
        ),
        appBar: AppBar(
          title: appearance.hideGreeting
              // 隐藏问候语时不显示任何标题文字
              ? null
              : Text(
                  // 顶部显示用户自定义的问候语；留空则回退为学期名
                  appearance.greetingText.trim().isNotEmpty
                      ? appearance.greetingText
                      : term.name,
                  style: TextStyle(
                    // 加粗，让问候语更有存在感
                    fontWeight: FontWeight.bold,
                    // 字体可切换；候选族都缺失时自动回退到系统字体
                    fontFamily: _titleFontFamily(appearance.titleFont),
                    fontFamilyFallback: appearance.titleFont.fontFamilies,
                  ),
                ),
          actions: [
            // 「本地文件导入」暂时下线（xls 网格式解析尚未适配完成），
            // 保留代码与开关，待适配好再打开。
            if (kEnableLocalFileImport)
              IconButton(
                tooltip: '导入课表',
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => const ImportPreviewPage(),
                  ),
                ),
                icon: const Icon(Icons.file_upload_outlined),
              ),
            PopupMenuButton<String>(
              onSelected: (value) {
                if (value == 'term') {
                  Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => TermSetupPage(initialTerm: term),
                    ),
                  );
                } else if (value == 'notifications') {
                  Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => const NotificationSettingsPage(),
                    ),
                  );
                } else if (value == 'makeup') {
                  _checkMakeupDays(context, ref);
                } else if (value == 'hit') {
                  Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => const HitTimetablePage(),
                    ),
                  );
                } else if (value == 'appearance') {
                  Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => const AppearanceSettingsPage(),
                    ),
                  );
                } else if (value == 'undo_import') {
                  _undoImport(context, ref);
                } else if (value == 'backup') {
                  Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => const DataManagementPage(),
                    ),
                  );
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'hit', child: Text('从哈工大教务导入')),
                PopupMenuItem(value: 'appearance', child: Text('界面美化')),
                PopupMenuItem(value: 'notifications', child: Text('提醒设置')),
                PopupMenuItem(value: 'makeup', child: Text('检查国家调休')),
                PopupMenuItem(value: 'undo_import', child: Text('撤销上次导入')),
                PopupMenuItem(value: 'backup', child: Text('备份与恢复')),
                PopupMenuItem(value: 'term', child: Text('编辑学期与节次')),
              ],
            ),
          ],
          // 压缩顶部占位：默认 56 太高，44 更紧凑
          toolbarHeight: 44,
          titleSpacing: 16,
          bottom: const PreferredSize(
            preferredSize: Size.fromHeight(34),
            child: TabBar(
              // indicatorSize 收紧 + labelPadding 变小，让「今日/本周」不占地方
              indicatorSize: TabBarIndicatorSize.label,
              labelPadding: EdgeInsets.symmetric(horizontal: 12),
              labelStyle: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              unselectedLabelStyle: TextStyle(fontSize: 14),
              tabs: [
                Tab(height: 32, text: '今日'),
                Tab(height: 32, text: '本周'),
              ],
            ),
          ),
        ),
        body: Column(
          children: [
            _DateHeader(
              date: selectedDate,
              week: engine.getWeekForDate(selectedDate),
              onPrevious: () => _changeDate(ref, selectedDate, -1),
              onNext: () => _changeDate(ref, selectedDate, 1),
              onToday: () => ref.read(selectedDateProvider.notifier).state =
                  _dateOnly(DateTime.now()),
              onSelectWeek: () => _selectWeek(context, ref, term, selectedDate),
            ),
            if (engine.adjustmentForDate(selectedDate) case final adjustment?)
              _AdjustmentBanner(
                date: selectedDate,
                actualWeek: engine.getWeekForDate(selectedDate),
                adjustment: adjustment,
                term: term,
              ),
            Expanded(
              child: TabBarView(
                children: [
                  _TodayView(
                    date: selectedDate,
                    courses: engine.getCoursesForDate(selectedDate),
                  ),
                  _WeekView(
                    selectedDate: selectedDate,
                    engine: engine,
                    layout: appearance.weekLayout,
                    term: term,
                  ),
                ],
              ),
            ),
            SafeArea(
              top: false,
              minimum: const EdgeInsets.only(bottom: 6),
              child: Text(
                'Adapted by Leocy',
                style: TextStyle(
                  fontSize: 10,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _changeDate(WidgetRef ref, DateTime date, int days) {
    ref.read(selectedDateProvider.notifier).state = date.add(
      Duration(days: days),
    );
  }

  Future<void> _selectWeek(
    BuildContext context,
    WidgetRef ref,
    Term term,
    DateTime selectedDate,
  ) async {
    final selected = await showModalBottomSheet<int>(
      context: context,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(
              title: Text('快速切换教学周'),
              subtitle: Text('会跳到所选教学周中相同的星期。'),
            ),
            for (var week = 1; week <= term.totalWeeks; week++)
              ListTile(
                title: Text('第 $week 周'),
                onTap: () => Navigator.pop(context, week),
              ),
          ],
        ),
      ),
    );
    if (selected == null) return;
    final weekdayOffset = selectedDate.weekday - DateTime.monday;
    ref.read(selectedDateProvider.notifier).state = term.firstWeekMonday.add(
      Duration(days: (selected - 1) * 7 + weekdayOffset),
    );
  }

  Future<void> _checkMakeupDays(BuildContext context, WidgetRef ref) async {
    try {
      final count = await ref
          .read(scheduleControllerProvider.notifier)
          .checkNationalMakeupDays();
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            count == 0 ? '当前学期没有可更新的国家节假日数据' : '已更新国家节假日与调休，共识别 $count 个调休上班日',
          ),
        ),
      );
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('联网检查失败，已保留本机调休数据')));
    }
  }

  Future<void> _undoImport(BuildContext context, WidgetRef ref) async {
    try {
      final restored = await ref
          .read(scheduleControllerProvider.notifier)
          .undoLastImport();
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(restored ? '已恢复到导入前的课表' : '没有可以撤销的导入')),
      );
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('撤销失败，请重试')));
      }
    }
  }
}

class _AdjustmentBanner extends ConsumerWidget {
  const _AdjustmentBanner({
    required this.date,
    required this.actualWeek,
    required this.adjustment,
    required this.term,
  });

  final DateTime date;
  final int? actualWeek;
  final ScheduleAdjustment adjustment;
  final Term term;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final weekday = adjustment.replacementWeekday;
    final replacementWeek = adjustment.replacementWeek;
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 0, 20, 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            adjustment.isHoliday
                ? Icons.celebration_outlined
                : Icons.event_repeat_rounded,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              adjustment.isHoliday
                  ? '国家法定节假日：${adjustment.holidayName ?? '放假'}，今天不显示课程'
                  : weekday == null || replacementWeek == null
                  ? '今天是国家调休上班日，请确认补哪一周、周几的课'
                  : '调休提示：今天按第 $replacementWeek 周${_weekdayName(weekday)}课表上课'
                        '${actualWeek == null ? '' : '（实际日期是第 $actualWeek 周）'}',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),
          if (!adjustment.isHoliday)
            TextButton(
              onPressed: () => _selectReplacement(context, ref),
              child: Text(
                weekday == null || replacementWeek == null ? '设置' : '修改',
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _selectReplacement(BuildContext context, WidgetRef ref) async {
    var selectedWeek = adjustment.replacementWeek ?? actualWeek ?? 1;
    var selectedWeekday = adjustment.replacementWeekday ?? date.weekday;
    final selected = await showDialog<({int week, int weekday})>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('设置补课课表'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('请按学校通知选择目标教学周和星期。'),
              const SizedBox(height: 16),
              DropdownButtonFormField<int>(
                initialValue: selectedWeek,
                decoration: const InputDecoration(labelText: '目标教学周'),
                items: [
                  for (var week = 1; week <= term.totalWeeks; week++)
                    DropdownMenuItem(value: week, child: Text('第 $week 周')),
                ],
                onChanged: (value) {
                  if (value != null) {
                    setDialogState(() => selectedWeek = value);
                  }
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                initialValue: selectedWeekday,
                decoration: const InputDecoration(labelText: '目标星期'),
                items: [
                  for (var day = 1; day <= 7; day++)
                    DropdownMenuItem(
                      value: day,
                      child: Text(_weekdayName(day)),
                    ),
                ],
                onChanged: (value) {
                  if (value != null) {
                    setDialogState(() => selectedWeekday = value);
                  }
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, (
                week: selectedWeek,
                weekday: selectedWeekday,
              )),
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
    if (selected != null) {
      await ref
          .read(scheduleControllerProvider.notifier)
          .setReplacementSchedule(date, selected.week, selected.weekday);
    }
  }
}

class _DateHeader extends StatelessWidget {
  const _DateHeader({
    required this.date,
    required this.week,
    required this.onPrevious,
    required this.onNext,
    required this.onToday,
    required this.onSelectWeek,
  });

  final DateTime date;
  final int? week;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onToday;
  final VoidCallback onSelectWeek;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 2, 6, 6),
      child: Row(
        children: [
          IconButton(
            onPressed: onPrevious,
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.chevron_left, size: 22),
          ),
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                InkWell(
                  borderRadius: BorderRadius.circular(6),
                  onTap: onToday,
                  child: Text(
                    '${date.month}月${date.day}日',
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                InkWell(
                  borderRadius: BorderRadius.circular(6),
                  onTap: onSelectWeek,
                  child: Text(
                    week == null ? '学期外 ▾' : '第 $week 周 ▾',
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  _weekdayName(date.weekday),
                  style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: onNext,
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.chevron_right, size: 22),
          ),
        ],
      ),
    );
  }
}

class _TodayView extends ConsumerWidget {
  const _TodayView({required this.date, required this.courses});

  final DateTime date;
  final List<ScheduledCourse> courses;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = ref.watch(clockProvider).valueOrNull ?? DateTime.now();
    ScheduledCourse? next;
    if (_sameDay(date, now)) {
      for (final course in courses) {
        if (course.startTime.isAfter(now)) {
          next = course;
          break;
        }
      }
    }
    if (courses.isEmpty) {
      return const _EmptyCourses(message: '这一天没有课程');
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
      itemCount: courses.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final course = courses[index];
        final isNext = identical(course, next);
        return _CourseCard(
          item: course,
          isNext: isNext,
          countdown: isNext
              ? _countdown(course.startTime.difference(now))
              : null,
        );
      },
    );
  }
}

class _WeekView extends ConsumerWidget {
  const _WeekView({
    required this.selectedDate,
    required this.engine,
    required this.layout,
    required this.term,
  });

  final DateTime selectedDate;
  final ScheduleEngine engine;

  /// 由「界面美化 → 周视图布局」决定用哪种排布。
  final AppWeekLayout layout;

  final Term term;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 表格视图是完全独立的二维矩阵渲染，直接切换走
    if (layout == AppWeekLayout.table) {
      return _WeekTableView(
        selectedDate: selectedDate,
        engine: engine,
        term: term,
      );
    }
    return _buildWaterfall(context);
  }

  /// 原有的瀑布流：按天分组、纵向排列。
  Widget _buildWaterfall(BuildContext context) {
    final monday = selectedDate.subtract(
      Duration(days: selectedDate.weekday - 1),
    );
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
      itemCount: 7,
      itemBuilder: (context, index) {
        final date = monday.add(Duration(days: index));
        final courses = engine.getCoursesForDate(date);
        return Padding(
          padding: const EdgeInsets.only(bottom: 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 8),
                child: Text(
                  '${_weekdayName(date.weekday)}  ${date.month}/${date.day}',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (courses.isEmpty)
                Text(
                  '没有课程',
                  style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                )
              else
                ...courses.map(
                  (course) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _CourseCard(item: course),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// 表格视图的一格内容：一门课在某个 (星期, 节次) 上的占位。
///
/// 只保留渲染必需的数据，避免把 [ScheduledCourse] 直接塞进表格后
/// 无法判断“这节课是否已被上方跨节课程合并”。
class _TableCourseCell {
  const _TableCourseCell({
    required this.course,
    required this.startPeriod,
    required this.endPeriod,
  });

  final ScheduledCourse course;

  /// 该课在当前星期的起始/结束节次。
  final int startPeriod;
  final int endPeriod;
}

/// 首页「本周」的**表格视图**。
///
/// 布局约定（与常见教务课表一致）：
/// ```
///        周一  周二  周三  周四  周五  周六  周日
/// 第1节  ┌────┬────┬────┬────┬────┬────┬────┐
///        │ 课 │    │ 课 │    │    │    │    │
/// 第2节  ├────┼────┼────┼────┼────┼────┼────┤
///        ...
/// ```
/// - **横轴**：星期（受「显示周末」设置影响）；
/// - **纵轴**：节次（从 `term.periodsByWeekday` 取全周并集，按节次号升序）；
/// - 跨节课程（如第3-4节）在纵向上**合并成一块**，内部标注起止节次。
///
/// 与瀑布流的本质差异：表格是**二维矩阵**，能一眼看出哪些时段空着；
/// 瀑布流是**按天分组的一维列表**，适合逐条读详情。
class _WeekTableView extends ConsumerWidget {
  const _WeekTableView({
    required this.selectedDate,
    required this.engine,
    required this.term,
  });

  final DateTime selectedDate;
  final ScheduleEngine engine;
  final Term term;

  /// 表格行高（单节）。紧凑度会在此基础上缩放。
  static const double _baseRowHeight = 62;

  /// 左侧节次列宽。
  static const double _timeColumnWidth = 46;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appearance = ref.watch(appearanceProvider);
    final scheme = Theme.of(context).colorScheme;
    final monday = selectedDate.subtract(
      Duration(days: selectedDate.weekday - 1),
    );

    // 要显示的星期：1~5，或 1~7（含周末）
    final weekdays = appearance.showWeekend
        ? const [1, 2, 3, 4, 5, 6, 7]
        : const [1, 2, 3, 4, 5];

    // 纵轴节次：取全周并集并按节次号升序，避免某天缺节次导致行错位
    final periodNumbers = <int>{};
    for (final day in weekdays) {
      final periods =
          term.periodsByWeekday[day] ?? term.periodsByWeekday[1] ?? const [];
      for (final p in periods) {
        periodNumbers.add(p.number);
      }
    }
    final rows = periodNumbers.toList()..sort();

    if (rows.isEmpty) {
      return const _EmptyCourses(message: '本节次表为空，请检查学期设置');
    }

    // 预先把整周的课取出来，按 (星期, 起始节次) 建索引，
    // 这样渲染每个格子时是 O(1) 查表，不用反复调 engine。
    final coursesByDay = <int, List<ScheduledCourse>>{};
    for (final day in weekdays) {
      final date = monday.add(Duration(days: day - 1));
      coursesByDay[day] = engine.getCoursesForDate(date);
    }

    // 每个格子要画的课程；被跨节合并覆盖的格子填 null。
    final cellMap = <String, _TableCourseCell?>{};
    final spanMap = <String, int>{};
    for (final day in weekdays) {
      for (final course in coursesByDay[day] ?? const <ScheduledCourse>[]) {
        final start = course.session.startPeriod;
        final end = course.session.endPeriod;
        for (var n = start; n <= end; n++) {
          final key = '$day:$n';
          if (n == start) {
            cellMap[key] = _TableCourseCell(
              course: course,
              startPeriod: start,
              endPeriod: end,
            );
            spanMap[key] = end - start + 1;
          } else {
            cellMap[key] = null;
          }
        }
      }
    }

    final rowHeight = _baseRowHeight * appearance.density.scale;
    final radius = appearance.corner.radius;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 表头：星期
          Row(
            children: [
              const SizedBox(width: _timeColumnWidth),
              for (final day in weekdays)
                Expanded(
                  child: _TableHeaderCell(
                    weekday: day,
                    date: monday.add(Duration(days: day - 1)),
                    isSelected: _sameDay(
                      monday.add(Duration(days: day - 1)),
                      selectedDate,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          // 表体：节次 × 星期
          for (var i = 0; i < rows.length; i++)
            _TableRow(
              periodNumber: rows[i],
              periodLabel: _periodLabel(term, rows[i]),
              weekdays: weekdays,
              rowHeight: rowHeight,
              radius: radius,
              cellMap: cellMap,
              spanMap: spanMap,
              isLast: i == rows.length - 1,
              scheme: scheme,
              appearance: appearance,
            ),
        ],
      ),
    );
  }

  /// 左侧节次列显示「节次号 + 起始时间」，时间取第一条可用记录。
  String _periodLabel(Term term, int number) {
    for (final day in const [1, 2, 3, 4, 5, 6, 7]) {
      final period = term.periodFor(day, number);
      if (period != null) {
        final h = period.startMinutes ~/ 60;
        final m = period.startMinutes % 60;
        return '$number\n${h.toString().padLeft(2, '0')}:'
            '${m.toString().padLeft(2, '0')}';
      }
    }
    return '$number';
  }
}

/// 表格表头的一个星期格。
class _TableHeaderCell extends StatelessWidget {
  const _TableHeaderCell({
    required this.weekday,
    required this.date,
    required this.isSelected,
  });

  final int weekday;
  final DateTime date;
  final bool isSelected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        children: [
          Text(
            _weekdayName(weekday).replaceFirst('周', ''),
            style: TextStyle(
              fontSize: 12,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
              color: isSelected ? scheme.primary : scheme.onSurface,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '${date.month}/${date.day}',
            style: TextStyle(
              fontSize: 9,
              color: isSelected ? scheme.primary : scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// 表格的一行（一个节次横跨所有星期）。
class _TableRow extends StatelessWidget {
  const _TableRow({
    required this.periodNumber,
    required this.periodLabel,
    required this.weekdays,
    required this.rowHeight,
    required this.radius,
    required this.cellMap,
    required this.spanMap,
    required this.isLast,
    required this.scheme,
    required this.appearance,
  });

  final int periodNumber;
  final String periodLabel;
  final List<int> weekdays;
  final double rowHeight;
  final double radius;
  final Map<String, _TableCourseCell?> cellMap;
  final Map<String, int> spanMap;
  final bool isLast;
  final ColorScheme scheme;
  final AppearanceSettings appearance;

  @override
  Widget build(BuildContext context) {
    return Row(
      // 让格子在纵向拉伸时按顶部对齐，避免跨节课程的标题垂直居中
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: _WeekTableView._timeColumnWidth,
          height: rowHeight,
          child: Center(
            child: Text(
              periodLabel,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 10,
                height: 1.25,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
        for (final day in weekdays)
          Expanded(
            child: SizedBox(
              height: rowHeight,
              child: _buildCell(context, day),
            ),
          ),
      ],
    );
  }

  Widget _buildCell(BuildContext context, int day) {
    final key = '$day:$periodNumber';
    final hasEntry = cellMap.containsKey(key);

    // 这个格子属于「被合并的下半部分」：直接留空，
    // 由起始格通过 span 撑高覆盖，避免重复画课程名。
    if (!hasEntry || cellMap[key] == null) {
      return Padding(
        padding: const EdgeInsets.all(1.5),
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(
              color: scheme.outlineVariant.withValues(alpha: 0.4),
              width: 0.5,
            ),
            borderRadius: BorderRadius.circular(
              (radius * 0.4).clamp(2, 8).toDouble(),
            ),
          ),
        ),
      );
    }

    final cell = cellMap[key]!;
    final span = (spanMap[key] ?? 1).clamp(1, 12).toInt();
    // 跨节课程整体高度 = 行高 × 节数（"+0.5" 补上格子间距）
    final totalHeight = rowHeight * span - 3;

    return _TableCourseTile(
      cell: cell,
      height: totalHeight,
      radius: radius,
      appearance: appearance,
    );
  }
}

/// 表格里的一个课程块（可能跨多节）。
class _TableCourseTile extends StatelessWidget {
  const _TableCourseTile({
    required this.cell,
    required this.height,
    required this.radius,
    required this.appearance,
  });

  final _TableCourseCell cell;
  final double height;
  final double radius;
  final AppearanceSettings appearance;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final courseColor = Color(cell.course.course.colorValue);
    final opacity = appearance.cardOpacity;
    final scale = appearance.density.scale;

    final Color? cardColor;
    final Gradient? gradient;
    switch (appearance.cardStyle) {
      case AppCardStyle.plain:
        cardColor = courseColor.withValues(alpha: opacity);
        gradient = null;
      case AppCardStyle.leftBar:
        cardColor = courseColor.withValues(alpha: 0.06);
        gradient = null;
      case AppCardStyle.gradient:
        cardColor = null;
        gradient = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            courseColor.withValues(alpha: (opacity + 0.15).clamp(0.0, 1.0)),
            courseColor.withValues(alpha: (opacity * 0.35).clamp(0.0, 1.0)),
          ],
        );
    }

    // 跨节课程用一个小号字号显示节次范围，窄格子也不会挤爆
    final periodText = cell.startPeriod == cell.endPeriod
        ? '第${cell.startPeriod}节'
        : '第${cell.startPeriod}-${cell.endPeriod}节';

    return Padding(
      padding: const EdgeInsets.all(1.5),
      child: Container(
        height: height,
        decoration: BoxDecoration(
          color: cardColor,
          gradient: gradient,
          borderRadius: BorderRadius.circular(radius * 0.6),
          border: Border(
            left: appearance.cardStyle == AppCardStyle.leftBar
                ? BorderSide(color: courseColor, width: 3)
                : BorderSide.none,
          ),
        ),
        padding: EdgeInsets.symmetric(
          horizontal: 4 * scale,
          vertical: 4 * scale,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Flexible(
              child: Text(
                cell.course.course.name,
                maxLines: height < 50 ? 2 : 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10.5,
                  height: 1.2,
                  fontWeight: FontWeight.w600,
                  color: scheme.onSurface,
                ),
              ),
            ),
            if (height >= 46) ...[
              const SizedBox(height: 1),
              Text(
                periodText,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 8.5,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
            if (height >= 58) ...[
              const SizedBox(height: 1),
              Text(
                cell.course.session.location,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 8.5,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CourseCard extends ConsumerWidget {
  const _CourseCard({
    required this.item,
    this.isNext = false,
    this.countdown,
  });

  final ScheduledCourse item;
  final bool isNext;
  final String? countdown;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appearance = ref.watch(appearanceProvider);
    final scheme = Theme.of(context).colorScheme;
    final courseColor = Color(item.course.colorValue);
    final radius = appearance.corner.radius;
    final scale = appearance.density.scale;
    final vPad = 14.0 * scale;
    final hPad = 14.0 * scale;

    // 卡片不透明度由用户控制（0.15~1.0）。
    // 三种样式的差别在**形状**，透明度是统一的：
    //   纯色  —— 整块铺课程色
    //   色条  —— 只左侧一道竖条着色，其余近乎透明
    //   渐变  —— 从左到右由浓到淡的课程色过渡
    final opacity = appearance.cardOpacity;

    final Color? cardColor;
    final Gradient? gradient;
    switch (appearance.cardStyle) {
      case AppCardStyle.plain:
        cardColor = courseColor.withValues(alpha: opacity);
        gradient = null;
      case AppCardStyle.leftBar:
        // 只有极淡的底，靠左侧竖条撑起识别度
        cardColor = courseColor.withValues(alpha: opacity * 0.12);
        gradient = null;
      case AppCardStyle.gradient:
        cardColor = null;
        gradient = LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            courseColor.withValues(alpha: opacity),
            courseColor.withValues(alpha: opacity * 0.25),
          ],
        );
    }

    final showBar = appearance.cardStyle == AppCardStyle.leftBar;

    final body = Row(
      children: [
        if (showBar) Container(width: 4, color: courseColor),
        Expanded(
          child: Padding(
            padding: EdgeInsets.fromLTRB(hPad, vPad, 6 * scale, vPad),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 82,
                  child: Text(
                    '${_timeText(item.startTime)}\n${_timeText(item.endTime)}',
                    style: const TextStyle(
                      fontSize: 11,
                      height: 1.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              item.course.name,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          if (countdown != null)
                            Text(
                              countdown!,
                              style: TextStyle(
                                fontSize: 11,
                                color: courseColor,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                        ],
                      ),
                      SizedBox(height: 5 * scale),
                      Text(
                        [item.session.location, item.teacher]
                            .where((value) => value.isNotEmpty)
                            .join(' · '),
                        style: TextStyle(
                          fontSize: 11,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: '更改课程颜色',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _pickColor(context, ref),
                  icon: Icon(
                    Icons.palette_outlined,
                    size: 18,
                    color: courseColor,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );

    // 卡片容器。
    //
    // ⚠️ 关键：渐变样式必须用「透明的 Material + Ink 承载渐变」。
    // 如果让 `Material.color` 为 null，Material 会用主题的 canvas 色**填充一层
    // 不透明底色**，导致渐变看起来永远不透明（调不透明度只改变渐变深浅）。
    // 因此这里统一用 `MaterialType.transparency`（不填充），
    // 由下面的 `Ink.decoration` 负责所有可见的底色/渐变。
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Material(
        type: MaterialType.transparency,
        borderRadius: BorderRadius.circular(radius),
        clipBehavior: Clip.antiAlias,
        child: Ink(
          decoration: BoxDecoration(
            // 纯色/色条样式用纯色底；渐变样式把渐变铺满整块。
            // 两者都带 alpha，因此能一致地透出主页背景。
            color: cardColor,
            gradient: gradient,
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(
              color: isNext
                  ? courseColor.withValues(alpha: 0.9)
                  : Colors.transparent,
              width: isNext ? 1.4 : 0,
            ),
          ),
          child: InkWell(
            onLongPress: () => _editCourse(context, ref),
            child: IntrinsicHeight(child: body),
          ),
        ),
      ),
    );
  }

  Future<void> _editCourse(BuildContext context, WidgetRef ref) async {
    final term = ref.read(scheduleControllerProvider).valueOrNull?.term;
    if (term == null) return;
    await Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (_) => ManualCoursePage(
          term: term,
          course: item.course,
          session: item.session,
          date: item.startTime,
        ),
      ),
    );
  }

  Future<void> _pickColor(BuildContext context, WidgetRef ref) async {
    const colors = [
      0xFF7D9DCE,
      0xFF7FB69D,
      0xFFD19A8A,
      0xFFB497C9,
      0xFFD0B36C,
      0xFF6FAFB5,
    ];
    final selected = await showModalBottomSheet<int>(
      context: context,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('选择课程颜色', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 18),
              Wrap(
                spacing: 16,
                children: colors
                    .map(
                      (value) => InkWell(
                        borderRadius: BorderRadius.circular(24),
                        onTap: () => Navigator.pop(context, value),
                        child: Padding(
                          padding: const EdgeInsets.all(4),
                          child: CircleAvatar(
                            backgroundColor: Color(value),
                            radius: 18,
                          ),
                        ),
                      ),
                    )
                    .toList(),
              ),
            ],
          ),
        ),
      ),
    );
    if (selected != null) {
      await ref
          .read(scheduleControllerProvider.notifier)
          .changeCourseColor(item.course.id, selected);
    }
  }
}

class _EmptyCourses extends StatelessWidget {
  const _EmptyCourses({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.free_breakfast_outlined,
            size: 42,
            color: Theme.of(context).colorScheme.outline,
          ),
          const SizedBox(height: 12),
          Text(
            message,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

String _weekdayName(int weekday) =>
    const ['周一', '周二', '周三', '周四', '周五', '周六', '周日'][weekday - 1];
String _timeText(DateTime time) =>
    '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
String _countdown(Duration duration) {
  final minutes = duration.inMinutes + (duration.inSeconds % 60 == 0 ? 0 : 1);
  if (minutes < 60) return '还有 $minutes 分钟';
  final hours = minutes ~/ 60;
  final rest = minutes % 60;
  return rest == 0 ? '还有 $hours 小时' : '还有 $hours 小时 $rest 分';
}

DateTime _dateOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);
bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;


/// 取问候语的首选字体族。
///
/// [AppTitleFont.system] 返回 `null`（跟随系统）；
/// 其它字体返回候选列表的第一项，配合 `fontFamilyFallback` 使用，
/// 设备上没装该字体时会自动回退，不会显示方框。
String? _titleFontFamily(AppTitleFont font) {
  final families = font.fontFamilies;
  if (families == null || families.isEmpty) return null;
  return families.first;
}