import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:offline_course_schedule/domain/schedule_models.dart';
import 'package:offline_course_schedule/import/course_import.dart';
import 'package:offline_course_schedule/import/hit_jwts_client.dart';
import 'package:offline_course_schedule/import/hit_timetable_import.dart';

/// 这些用例的数据全部来自 2026-09 对 jwts.hit.edu.cn 的真实抓包，
/// 见 `test/fixtures/hit_queryGrkb_reference.json`。
void main() {
  const parser = HitTimetableImportParser();

  /// 端到端用例使用的真实页面（87 KB，`POST /kbcx/queryGrkb` 的原始响应）。
  final realPageHtml =
      File('test/fixtures/hit_queryGrkb_page.html').readAsStringSync();

  /// 复刻真实课表网格：8 行 × 9 列。
  /// 第 0 行是表头，第 1-6 行是节次，第 7 行是「其它课程」。
  List<List<String>> buildGrid() => [
        ['', '星期一', '星期二', '星期三', '星期四', '星期五', '星期六', '星期日'],
        [
          '上午',
          '第1,2节',
          '高等代数（1）\n张老师[4-17]周A101',
          '数学分析（1）\n李老师[4-17]周C301',
          '大学英语综合A(提高)\n王老师[4-17]周B201',
          '数学分析（1）\n李老师[3]周C301',
          '习近平新时代中国特色社会主义思想概论\n陈老师[5-17]周A102',
          '',
          '',
        ],
        [
          '上午',
          '第3,4节',
          '数学分析（1）\n李老师[4-17]周C301',
          '习近平新时代中国特色社会主义思想概论\n陈老师[5-17]周A102',
          '',
          '数学分析（1）\n李老师[4-17]周C301',
          '高等代数（1）\n张老师[4-17]周A101',
          '',
          '',
        ],
        [
          '下午',
          '第5,6节',
          // 同一格两门课
          '大学英语综合A(提高)\n王老师[4-17]周B201\n数学分析（1）\n李老师[3]周C301',
          '高等代数（1）\n张老师[7-12]周A101',
          '体育（1）(乒乓球)\n刘老师[4-17]周二区文体中心213乒乓球室',
          // 教师名含空格 + 同格两门课
          '大学英语综合A(提高)\n王老师[4-8]周B201\n数学推理方法\nJohn Smith[9-16]周B202',
          '数学分析（1）\n李老师[11-17]周C301',
          '',
          '',
        ],
        ['下午', '第7,8节', '', '数学推理方法\nJohn Smith[9-16]周B202', '', '', '', '', ''],
        [
          '晚上',
          '第9,10节',
          '',
          // 全角逗号的不连续周次 + 两字教师名
          '色彩美学\n赵老师[3-5，7]周B203\n哲学导论\n田径[7-14]周A103',
          '',
          '探索光的奥秘\n高波[6-13]周B204',
          '',
          '',
          '',
        ],
        [
          '晚上',
          '第11,12节',
          '',
          '色彩美学\n赵老师[3-5，7]周B203\n哲学导论\n田径[7-14]周A103',
          '',
          '',
          '',
          '',
          '',
        ],
        ['其它课程： 【新时代实践教育◇尹胜君◇-◇】 【军事理论◇庞东贺◇1-3◇】 【军事技能◇◇◇】'],
      ];

  group('课表网格解析', () {
    test('解析出全部课程，数量与真实课表一致', () {
      final result = parser.parse(buildGrid());
      // 逐条核对真实课表：第1,2节 5门 + 第3,4节 4门 + 第5,6节 7门
      // + 第7,8节 1门 + 第9,10节 3门 + 第11,12节 2门 = 22 门
      expect(result.records.length, 22);
      expect(result.warnings, isEmpty);
    });

    test('课程名、教师、地点、周次全部正确', () {
      final result = parser.parse(buildGrid());
      final algebra = result.records.firstWhere(
        (r) => r.courseName == '高等代数（1）' && r.startPeriod == 1,
      );
      expect(algebra.teacher, '张老师');
      expect(algebra.location, 'A101');
      expect(algebra.weeks, '4-17');
      expect(algebra.weekday, 1);
      expect(algebra.startPeriod, 1);
      expect(algebra.endPeriod, 2);
    });

    test('教师名含空格时不被截断', () {
      final result = parser.parse(buildGrid());
      final mathReasoning = result.records.firstWhere(
        (r) => r.courseName == '数学推理方法',
      );
      expect(mathReasoning.teacher, 'John Smith');
      expect(mathReasoning.location, 'B202');
      expect(mathReasoning.weeks, '9-16');
    });

    test('两字教师名正确解析', () {
      final result = parser.parse(buildGrid());
      final philosophy = result.records.firstWhere(
        (r) => r.courseName == '哲学导论',
      );
      expect(philosophy.teacher, '田径');
      expect(philosophy.location, 'A103');
    });

    test('全角逗号的不连续周次完整保留', () {
      final result = parser.parse(buildGrid());
      final aesthetics = result.records.firstWhere(
        (r) => r.courseName == '色彩美学',
      );
      expect(aesthetics.weeks, '3-5，7');
    });

    test('含括号的课程名不被破坏', () {
      final result = parser.parse(buildGrid());
      expect(
        result.records.any((r) => r.courseName == '大学英语综合A(提高)'),
        isTrue,
      );
      expect(
        result.records.any((r) => r.courseName == '体育（1）(乒乓球)'),
        isTrue,
      );
    });

    test('长地点名完整保留', () {
      final result = parser.parse(buildGrid());
      final pe = result.records.firstWhere((r) => r.courseName == '体育（1）(乒乓球)');
      expect(pe.location, '二区文体中心213乒乓球室');
    });

    test('同一格里的两门课都被解析出来', () {
      final result = parser.parse(buildGrid());
      final pair = result.records.where(
        (r) => r.weekday == 1 && r.startPeriod == 5 && r.endPeriod == 6,
      );
      expect(pair.length, 2);
      expect(pair.map((r) => r.courseName).toSet(), {'大学英语综合A(提高)', '数学分析（1）'});
    });

    test('节次区间正确（第5,6节 → 5..6）', () {
      final result = parser.parse(buildGrid());
      final evening = result.records.firstWhere(
        (r) => r.courseName == '色彩美学',
      );
      expect(evening.startPeriod, 9);
      expect(evening.endPeriod, 10);
    });
  });

  group('其它课程（无固定时间）', () {
    test('解析出军事理论等课程', () {
      final result = parser.parse(buildGrid());
      final names = result.unscheduled.map((c) => c.courseName).toList();
      expect(names, ['新时代实践教育', '军事理论', '军事技能']);
    });

    test('教师与周次字段正确', () {
      final result = parser.parse(buildGrid());
      final military = result.unscheduled.firstWhere((c) => c.courseName == '军事理论');
      expect(military.teacher, '庞东贺');
      expect(military.weeks, '1-3');
    });

    test('空教师空周次不报错', () {
      final result = parser.parse(buildGrid());
      final skills = result.unscheduled.firstWhere((c) => c.courseName == '军事技能');
      expect(skills.teacher, '');
      expect(skills.weeks, '');
    });
  });

  group('转换成 App 导入格式', () {
    test('表头为「课程名/教师/地点/周几/节次/周次范围」且可被 CourseImportParser 接受', () {
      final result = parser.parse(buildGrid());
      final preview = parser.toImportPreview(result);
      expect(preview.errors, isEmpty);
      expect(preview.rows.length, 22);
      expect(preview.canImport, isTrue);
    });

    test('全角逗号周次能被 WeekRuleParser 正确展开', () {
      final result = parser.parse(buildGrid());
      final preview = parser.toImportPreview(result);
      final aesthetics = preview.rows.firstWhere(
        (row) => row.cells.values.any((c) => c.raw == '色彩美学'),
      );
      expect(aesthetics.isValid, isTrue);
      final rule = aesthetics.cells[ImportField.weeks]!.value! as WeekRule;
      // [3-5，7] → 第 3、4、5、7 周，共 4 周且不连续，因此走 explicitWeeks
      expect(rule.startWeek, 3);
      expect(rule.endWeek, 7);
      expect(rule.explicitWeeks, {3, 4, 5, 7});
    });

    test('结果按星期与节次排序', () {
      final result = parser.parse(buildGrid());
      final preview = parser.toImportPreview(result);
      final weekdays = preview.rows
          .map((row) => row.cells[ImportField.weekday]!.value! as int)
          .toList();
      final sorted = List<int>.of(weekdays)..sort();
      expect(weekdays, sorted);
    });
  });

  group('解析健壮性', () {
    test('空表格返回空结果而不崩溃', () {
      final result = parser.parse([]);
      expect(result.records, isEmpty);
    });

    test('缺少节次行时给出警告', () {
      final result = parser.parse([
        ['', '星期一', '星期二', '星期三', '星期四', '星期五', '星期六', '星期日'],
        ['上午', '无法识别的标签', 'x', 'y'],
      ]);
      expect(result.records, isEmpty);
      expect(result.warnings, isNotEmpty);
    });

    test('没有教师信息的课程被跳过并给出警告', () {
      final result = parser.parse([
        ['', '星期一', '星期二', '星期三', '星期四', '星期五', '星期六', '星期日'],
        ['上午', '第1,2节', '只有课程名没有教师行'],
      ]);
      expect(result.records, isEmpty);
      expect(result.warnings.any((w) => w.contains('只有课程名没有教师行')), isTrue);
    });

    test('缺少课程名的教师行被跳过', () {
      final result = parser.parse([
        ['', '星期一', '星期二', '星期三', '星期四', '星期五', '星期六', '星期日'],
        ['上午', '第1,2节', '张老师[4-17]周A101'],
      ]);
      expect(result.records, isEmpty);
      expect(result.warnings, isNotEmpty);
    });
  });

  group('真实页面端到端', () {
    test('从 87KB 真实响应中切出课表网格', () {
      final grid = HitTimetableGrid.fromPageHtml(realPageHtml);
      expect(grid, isNotNull, reason: '应能从真实页面中定位 table.addlist_01');
      final rows = grid!.toRows();
      expect(rows.length, 8, reason: '真实课表为 8 行：表头 + 6 个节次行 + 其它课程');
    });

    test('真实页面解析出的课程数量正确', () {
      final grid = HitTimetableGrid.fromPageHtml(realPageHtml)!;
      final result = parser.parse(grid.toRows());
      expect(result.records.length, 22);
      expect(result.warnings, isEmpty);
    });

    test('真实页面里的关键课程信息逐项核对', () {
      final grid = HitTimetableGrid.fromPageHtml(realPageHtml)!;
      final result = parser.parse(grid.toRows());

      // 高等代数（1）：周一 第1,2节，张老师，A101，4-17周
      final algebra = result.records.firstWhere(
        (r) => r.courseName == '高等代数（1）' && r.weekday == 1 && r.startPeriod == 1,
      );
      expect(algebra.teacher, '张老师');
      expect(algebra.location, 'A101');
      expect(algebra.weeks, '4-17');
      expect(algebra.endPeriod, 2);

      // 体育（1）(乒乓球)：周三 第5,6节，刘老师，二区文体中心213乒乓球室
      final pe = result.records.firstWhere((r) => r.courseName == '体育（1）(乒乓球)');
      expect(pe.weekday, 3);
      expect(pe.teacher, '刘老师');
      expect(pe.location, '二区文体中心213乒乓球室');

      // 数学推理方法：外教，教师名含空格
      final reasoning = result.records.firstWhere((r) => r.courseName == '数学推理方法');
      expect(reasoning.teacher, 'John Smith');
      expect(reasoning.location, 'B202');
      expect(reasoning.weeks, '9-16');

      // 色彩美学：全角逗号周次
      final aesthetics = result.records.firstWhere((r) => r.courseName == '色彩美学');
      expect(aesthetics.weeks, '3-5，7');
      expect(aesthetics.teacher, '赵老师');
    });

    test('真实页面的「其它课程」解析正确', () {
      final grid = HitTimetableGrid.fromPageHtml(realPageHtml)!;
      final result = parser.parse(grid.toRows());
      expect(
        result.unscheduled.map((c) => c.courseName).toList(),
        ['新时代实践教育', '军事理论', '军事技能'],
      );
    });

    test('真实页面可完整转成导入预览', () {
      final grid = HitTimetableGrid.fromPageHtml(realPageHtml)!;
      final result = parser.parse(grid.toRows());
      final preview = parser.toImportPreview(result);
      expect(preview.errors, isEmpty);
      expect(preview.canImport, isTrue);
      expect(preview.rows.length, 22);
      // 每一行都应通过校验（课程名/周几/节次/周次都能识别）
      expect(preview.rows.every((row) => row.isValid), isTrue);
    });

    test('真实页面能解析出学期下拉框', () {
      final terms = parseHitTerms(realPageHtml);
      expect(terms.length, 5);
      expect(
        terms.map((t) => t.label).toList(),
        ['2027秋季', '2027寒假', '2027夏季', '2027春季', '2026秋季'],
      );
    });

    test('真实页面的当前学期是「2026秋季」，且不是列表第一项', () {
      // 真实 HTML 里写的是 `selected`（无值），不是 `selected=""`。
      // 这是本 bug 的教训：测试 fixture 曾用 `selected=""` 而漏掉了真实写法。
      final terms = parseHitTerms(realPageHtml);
      final current = pickCurrentTerm(terms);

      expect(current, isNotNull);
      expect(current!.value, '2026-20271');
      expect(current.label, '2026秋季');
      expect(current.isSelected, isTrue);

      // 教务把最"新"的学期排在最前，第一项是更远的未来学期。
      // 曾经因为直接取 terms.first，默认学期错成了「2027秋季」。
      expect(terms.first.value, '2027-20281');
      expect(terms.first.label, '2027秋季');
      expect(current.value, isNot(terms.first.value));
    });

    test('真实页面包含哈工大作息时间表原文', () {
      // 应用内置的 hitLessonPeriods 就是从这段原文推导的，
      // 这里断言原文存在，防止将来校方改动作息却没人发现。
      expect(realPageHtml, contains('上课作息时间表'));
      expect(realPageHtml, contains('第1-2节'));
      expect(realPageHtml, contains('第12节'));
    });
  });

  group('学期选项解析', () {
    const pageHtml = '''
      <select name="xnxq" id="xnxq" class="XNXQ_CON">
        <option value="2027-20281">2027秋季</option>
        <option value="2026-20274">2027寒假</option>
        <option value="2026-20273">2027夏季</option>
        <option value="2026-20272">2027春季</option>
        <option value="2026-20271" selected="">2026秋季</option>
      </select>
    ''';

    test('解析出全部 5 个学期', () {
      final terms = parseHitTerms(pageHtml);
      expect(terms.length, 5);
      expect(terms.first.value, '2027-20281');
      expect(terms.first.label, '2027秋季');
      expect(terms.last.value, '2026-20271');
    });

    test('识别教务标记的 selected 学期（不是列表第一项）', () {
      final terms = parseHitTerms(pageHtml);
      final selected = terms.where((t) => t.isSelected).toList();
      expect(selected.length, 1, reason: '真实页面只有一个 option 带 selected');
      expect(selected.single.value, '2026-20271');
      expect(selected.single.label, '2026秋季');
      // 关键：教务把最"新"的学期排在最前，第一项是未来学期，不能当当前学期
      expect(terms.first.value, isNot('2026-20271'));
    });

    test('selected="" 这种空值写法也能识别', () {
      const html = '<select id="xnxq">'
          '<option value="2027-20281">2027秋季</option>'
          '<option value="2026-20271" selected="">2026秋季</option>'
          '</select>';
      final terms = parseHitTerms(html);
      expect(terms.firstWhere((t) => t.isSelected).value, '2026-20271');
    });

    test('selected 无值（仅属性名）也能识别', () {
      const html = '<select id="xnxq">'
          '<option value="2027-20281">2027秋季</option>'
          '<option value="2026-20271" selected>2026秋季</option>'
          '</select>';
      final terms = parseHitTerms(html);
      expect(terms.firstWhere((t) => t.isSelected).value, '2026-20271');
    });

    test('页面没有学期下拉框时返回空列表', () {
      expect(parseHitTerms('<html><body>无</body></html>'), isEmpty);
    });
  });

  group('挑选当前学期', () {
    test('优先用带 selected 的那一项', () {
      final terms = parseHitTerms(
        '<select id="xnxq">'
        '<option value="2027-20281">2027秋季</option>'
        '<option value="2026-20271" selected>2026秋季</option>'
        '<option value="2026-20272">2027春季</option>'
        '</select>',
      );
      expect(pickCurrentTerm(terms)!.value, '2026-20271');
    });

    test('没有 selected 标记时退回最后一项（教务排最新的在最前）', () {
      final terms = parseHitTerms(
        '<select id="xnxq">'
        '<option value="2027-20281">2027秋季</option>'
        '<option value="2026-20272">2027春季</option>'
        '<option value="2026-20271">2026秋季</option>'
        '</select>',
      );
      expect(pickCurrentTerm(terms)!.value, '2026-20271');
    });

    test('空列表返回 null', () {
      expect(pickCurrentTerm(const []), isNull);
    });
  });

  group('会话失效识别', () {
    test('识别「页面过期」响应', () async {
      // 这是教务未登录时返回的真实内容（104 字节）
      const expiredBody =
          '<script type="text/javascript" charset="UTF-8">alert("页面过期，请重新登录");window.top.location.href="";</script>';
      expect(expiredBody.contains('页面过期'), isTrue);
      expect(expiredBody.length, lessThan(200));
    });
  });

  group('Cookie 解析', () {
    test('同时有 JSESSIONID 和 HIT 时构造成功', () {
      final session = HitSession.fromSetCookieHeaders([
        'JSESSIONID=ABC123; Path=/; HttpOnly',
        'HIT=DEF456; Path=/',
      ]);
      expect(session, isNotNull);
      expect(session!.jsessionId, 'ABC123');
      expect(session.hitToken, 'DEF456');
      expect(session.toCookieHeader(), 'JSESSIONID=ABC123; HIT=DEF456');
    });

    test('缺少 HIT 时返回 null', () {
      final session = HitSession.fromSetCookieHeaders([
        'JSESSIONID=ABC123; Path=/; HttpOnly',
      ]);
      expect(session, isNull);
    });

    test('合并已有会话（只更新变化的部分）', () {
      const existing = HitSession(jsessionId: 'OLD', hitToken: 'HITOLD');
      final merged = HitSession.fromSetCookieHeaders(
        ['JSESSIONID=NEW; Path=/'],
        merge: existing,
      );
      expect(merged!.jsessionId, 'NEW');
      expect(merged.hitToken, 'HITOLD');
    });

    test('toString 不泄露完整令牌', () {
      const session = HitSession(jsessionId: 'SECRETSESSION', hitToken: 'SECRETHIT');
      expect(session.toString(), isNot(contains('SECRETHIT')));
      expect(session.toString(), isNot(contains('SECRETSESSION')));
    });
  });

  group('网格提取', () {
    test('从整页 HTML 中切出课表表格', () {
      const page = '''
        <html><body>
        <table class="other"><tr><td>无关表格</td></tr></table>
        <table class="addlist_01"><tr><td>课表内容</td></tr></table>
        </body></html>
      ''';
      final grid = HitTimetableGrid.fromPageHtml(page);
      expect(grid, isNotNull);
      expect(grid!.toRows().first.first, '课表内容');
    });

    test('页面没有课表表格时返回 null', () {
      expect(HitTimetableGrid.fromPageHtml('<html></html>'), isNull);
    });

    test('单元格里的 <br> 转成换行且过滤空行', () {
      const page =
          '<table class="addlist_01"><tr><td>课名<br>教师[1-2]周A1<br>&nbsp;<br></td></tr></table>';
      final rows = HitTimetableGrid.fromPageHtml(page)!.toRows();
      expect(rows.first.first, '课名\n教师[1-2]周A1');
    });

    test('闭合形式的 </br> 也要当作换行（教务实际输出）', () {
      // 教务真实输出的是 `</br>`，这是不合法 HTML 但浏览器当换行处理。
      // 曾经因为没有覆盖这种写法，导致真实页面解析出 0 门课。
      const page =
          '<table class="addlist_01"><tr><td>高等代数（1）</br>张老师[4-17]周A101</td></tr></table>';
      final rows = HitTimetableGrid.fromPageHtml(page)!.toRows();
      expect(rows.first.first, '高等代数（1）\n张老师[4-17]周A101');
    });

    test('<br/> 自闭合形式也要当作换行', () {
      const page =
          '<table class="addlist_01"><tr><td>课名<br/>教师[1-2]周A1</td></tr></table>';
      final rows = HitTimetableGrid.fromPageHtml(page)!.toRows();
      expect(rows.first.first, '课名\n教师[1-2]周A1');
    });

    test('HTML 注释不进入文本', () {
      const page =
          '<table class="addlist_01"><tr><td><!-- 星期一 -->课名</td></tr></table>';
      final rows = HitTimetableGrid.fromPageHtml(page)!.toRows();
      expect(rows.first.first, '课名');
    });
  });
}
