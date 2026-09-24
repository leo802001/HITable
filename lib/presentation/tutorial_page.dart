import 'package:flutter/material.dart';

import '../domain/appearance_settings.dart';

class TutorialPage extends StatelessWidget {
  const TutorialPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('使用教程')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: const [
          Text(
            '不用担心设置复杂，按下面顺序操作一次就可以了。'
            '课程、图片和设置都只保存在你的手机里。',
            style: TextStyle(height: 1.6),
          ),
          SizedBox(height: 18),
          _TutorialStep(
            number: '1',
            icon: Icons.school_outlined,
            title: '先添加学期',
            text:
                '填写学期名称和开学第一周的周一。第一周周一默认已填好学校公布的日期，'
                '如果不对再自行调整；总周数和每天节次也都有默认值，通常直接保存即可。',
          ),
          _TutorialStep(
            number: '2',
            icon: Icons.cloud_download_outlined,
            title: '导入课程',
            text:
                '从菜单进入“从哈工大教务导入”，在校园网环境下登录统一身份认证，'
                '即可读取个人课表，读取时可以切换学期。'
                '预览中可修改黄色单元格，也可删除误识别的整行。',
          ),
          _TutorialStep(
            number: '3',
            icon: Icons.calendar_month_outlined,
            title: '查看今天和本周',
            text:
                '日期后会显示当前教学周。点“第几周”可以快速跳到任意教学周，'
                '点左右箭头逐日切换，点日期回到今天；'
                '左右滑动“今日”和“本周”即可切换视图。',
          ),
          _TutorialStep(
            number: '4',
            icon: Icons.event_repeat_outlined,
            title: '遇到国家调休',
            text:
                'App 会检查国家公布的调休上班日。国家通知不会说明学校补哪一教学周，'
                '所以第一次遇到时，请根据学校通知同时选择目标周数和星期，'
                '例如“第 4 周周二”。之后课表、小组件和提醒会一起切换。',
          ),
          _TutorialStep(
            number: '5',
            icon: Icons.notifications_active_outlined,
            title: '设置上课提醒',
            text:
                '在“提醒设置”中点“提前时间”，可以自己输入 1 到 1440 分钟；'
                '提醒方式可选“仅通知”“通知加震动”或“通知加震动和声音”。'
                '如果提醒时间正在上另一节课，默认会延后到下课 3 分钟后。',
          ),
          _TutorialStep(
            number: '6',
            icon: Icons.palette_outlined,
            title: '换个样子（可选）',
            text:
                '菜单里的“界面美化”可以换配色、圆角、紧凑程度，'
                '也能给主页挑一张背景图并调模糊度。'
                '顶部那句问候语默认是“$defaultGreeting”，'
                '可以改成自己喜欢的任何内容，也能换字体（仿宋/楷体/黑体）'
                '或干脆隐藏起来不显示。',
          ),
          _TutorialStep(
            number: '7',
            icon: Icons.widgets_outlined,
            title: '添加桌面小组件',
            text:
                '长按手机桌面空白处，进入“小组件”或“服务卡片”，找到“HITable”，'
                '添加“下一节课”。安装或修改课表后，请打开 App 一次让小组件同步。',
          ),
          _TutorialStep(
            number: '8',
            icon: Icons.battery_saver_outlined,
            title: '完成后台放行',
            text:
                '最后到“提醒设置”打开国产 Android 后台设置教程，'
                '允许自启动和后台活动，并关闭电池优化，否则锁屏后提醒可能延迟。',
          ),
        ],
      ),
    );
  }
}

class _TutorialStep extends StatelessWidget {
  const _TutorialStep({
    required this.number,
    required this.icon,
    required this.title,
    required this.text,
  });

  final String number;
  final IconData icon;
  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(radius: 18, child: Text(number)),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(icon, size: 19),
                      const SizedBox(width: 8),
                      Text(
                        title,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    text,
                    style: const TextStyle(fontSize: 12, height: 1.55),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
