/// 哈工大教务（jwts.hit.edu.cn）接口层。
///
/// 已通过真实抓包验证的契约（2026-09 实测）：
///
/// ```
/// POST http://jwts.hit.edu.cn/kbcx/queryGrkb
/// Content-Type: application/x-www-form-urlencoded
/// Cookie: JSESSIONID=<session>; HIT=<token>
///
/// fhlj=kbcx/queryGrkb&xnxq=<学期码>
/// ```
///
/// 关键事实：
/// - **必须用 http**，`https://jwts.hit.edu.cn` 在校内不可达（仅 80 端口开放）。
/// - `fhlj` 字段缺失会返回空页，必须带上。
/// - 未登录时返回长度约 104 字节的脚本：`alert("页面过期，请重新登录")`。
/// - 学期码格式为 `<学年>-<学期><序号>`，例如 `2026-20271` 表示 2026 秋季。
///
/// 本文件只负责「发请求 + 拿 HTML + 切出课表网格」，**不做任何业务解析**。
/// 解析逻辑见 `hit_timetable_import.dart`，这样两者可以独立测试。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// 教务系统站点地址。校内直连走明文 HTTP，这是唯一可达的方式。
const hitJwtsBaseUrl = 'http://jwts.hit.edu.cn';

/// 个人课表查询接口路径。
const hitPersonalTimetablePath = '/kbcx/queryGrkb';

/// 课表网格表格的 CSS 选择器（用正则匹配，避免引入 HTML 解析依赖）。
const hitTimetableGridClass = 'addlist_01';

/// 课表网格在 HTML 中的正则。教务返回的是规整表格，无需完整 DOM 解析器。
final _gridPattern = RegExp(
  r'<table[^>]*class="' + hitTimetableGridClass + r'"[^>]*>([\s\S]*?)</table>',
  caseSensitive: false,
);

/// `fhlj` 字段固定为去掉前导斜杠的接口路径。
const _formFhlj = 'kbcx/queryGrkb';

/// 接口返回体里出现这个字样，说明会话已失效。
const _expiredMarker = '页面过期';

/// 读取课表时可能出现的错误。
class HitApiException implements Exception {
  const HitApiException(this.message, {this.isSessionExpired = false});

  final String message;

  /// 会话失效（Cookie 过期或从未登录），调用方应引导用户重新登录。
  final bool isSessionExpired;

  @override
  String toString() => message;
}

/// 教务会话：持有两个必需的 Cookie。
///
/// 两个 Cookie 的含义（实测）：
/// - `JSESSIONID`：Tomcat 会话，HttpOnly。
/// - `HIT`：教务自建的身份令牌，非 HttpOnly。
///
/// 二者缺一不可，且**都会在会话过期后失效**。
class HitSession {
  const HitSession({required this.jsessionId, required this.hitToken});

  final String jsessionId;
  final String hitToken;

  /// 拼成 `Cookie` 请求头的值。
  String toCookieHeader() => 'JSESSIONID=$jsessionId; HIT=$hitToken';

  /// 从 `Set-Cookie` 头列表里解析出会话。
  ///
  /// 返回 null 表示两个必需 Cookie 没有同时出现（说明这次响应不是一次成功登录）。
  static HitSession? fromSetCookieHeaders(Iterable<String> headers,
      {HitSession? merge}) {
    String? jsession = merge?.jsessionId;
    String? hit = merge?.hitToken;
    for (final header in headers) {
      final parts = header.split(';').first.trim();
      final eq = parts.indexOf('=');
      if (eq <= 0) continue;
      final name = parts.substring(0, eq).trim();
      final value = parts.substring(eq + 1).trim();
      if (value.isEmpty) continue;
      if (name == 'JSESSIONID') jsession = value;
      if (name == 'HIT') hit = value;
    }
    if (jsession == null || hit == null) return null;
    return HitSession(jsessionId: jsession, hitToken: hit);
  }

  @override
  String toString() => 'HitSession(HIT=${hitToken.substring(0, 4)}…, 已隐藏)';
}

/// 一个学期的选项。
class HitTerm {
  const HitTerm({
    required this.value,
    required this.label,
    this.isSelected = false,
  });

  /// 接口参数值，例如 `2026-20271`。
  final String value;

  /// 界面显示文字，例如 `2026秋季`。
  final String label;

  /// 教务页面上这一个是否为当前选中的学期
  /// （HTML 里带 `selected` 属性的那个 `<option>`）。
  final bool isSelected;

  @override
  String toString() => '$label($value)${isSelected ? ' [当前]' : ''}';
}

/// 从学期列表里挑出「当前学期」。
///
/// 优先用教务标记了 `selected` 的那一项；若页面没标（或传入的是空列表），
/// 则退回最后一项 —— 因为教务把学期按**最新在前**排序，
/// 末尾是列表中最早的学期，通常是学生正在上的那个。
HitTerm? pickCurrentTerm(List<HitTerm> terms) {
  if (terms.isEmpty) return null;
  for (final term in terms) {
    if (term.isSelected) return term;
  }
  return terms.last;
}

/// 教务接口客户端。
///
/// 注意：`webview_flutter` 的 Cookie 存在 WebView 的 CookieManager 里，
/// 而接口调用走 Dart 的 HttpClient，两者**不共享存储**。
/// 所以登录后需要把 WebView 的 Cookie 显式取出，构造 [HitSession] 交给这个客户端。
class HitJwtsClient {
  HitJwtsClient({HttpClient? httpClient, this.timeout = const Duration(seconds: 20)})
      : _httpClient = httpClient ?? HttpClient() {
    _httpClient.connectionTimeout = timeout;
    // 教务用的是明文 HTTP，不允许重定向到 https（那个端口不通）。
    _httpClient.badCertificateCallback = (_, __, ___) => false;
  }

  final HttpClient _httpClient;
  final Duration timeout;

  static const _userAgent =
      'Mozilla/5.0 (Linux; Android 12) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/131.0.0.0 Mobile Safari/537.36';

  /// 拉取指定学期的个人课表 HTML 原文。
  ///
  /// 成功时返回完整 HTML；会话失效或表单错误时抛 [HitApiException]。
  Future<String> fetchTimetableHtml({
    required HitSession session,
    required String termValue,
  }) async {
    final body = 'fhlj=$_formFhlj&xnxq=${Uri.encodeQueryComponent(termValue)}';
    final request = await _httpClient
        .postUrl(Uri.parse('$hitJwtsBaseUrl$hitPersonalTimetablePath'))
        .timeout(timeout);
    request.headers
      ..set(HttpHeaders.contentTypeHeader, 'application/x-www-form-urlencoded')
      ..set(HttpHeaders.cookieHeader, session.toCookieHeader())
      ..set(HttpHeaders.userAgentHeader, _userAgent)
      ..set(HttpHeaders.refererHeader, '$hitJwtsBaseUrl$hitPersonalTimetablePath');
    request.add(utf8.encode(body));

    final response = await request.close().timeout(timeout);
    if (response.statusCode != HttpStatus.ok) {
      throw HitApiException('教务系统返回状态码 ${response.statusCode}，请稍后重试');
    }
    final html = await response.transform(utf8.decoder).join();
    _throwIfExpired(html);
    return html;
  }

  /// 只验证会话是否仍然有效，不关心课表内容。
  Future<bool> isSessionAlive(HitSession session, {String? probeTermValue}) async {
    try {
      await fetchTimetableHtml(
        session: session,
        termValue: probeTermValue ?? '2026-20271',
      );
      return true;
    } on HitApiException catch (error) {
      if (error.isSessionExpired) return false;
      rethrow;
    }
  }

  void close() => _httpClient.close(force: true);

  void _throwIfExpired(String html) {
    if (html.contains(_expiredMarker)) {
      throw const HitApiException(
        '教务登录已过期，请重新登录',
        isSessionExpired: true,
      );
    }
    if (!_gridPattern.hasMatch(html)) {
      throw const HitApiException('没有在教务页面里找到课表，页面结构可能已变化');
    }
  }
}

/// HTML 里切出来的课表网格。
class HitTimetableGrid {
  const HitTimetableGrid(this.html);

  /// 整个 `<table class="addlist_01">` 的 inner HTML。
  final String html;

  /// 从整页 HTML 中提取课表网格；找不到返回 null。
  static HitTimetableGrid? fromPageHtml(String pageHtml) {
    final match = _gridPattern.firstMatch(pageHtml);
    if (match == null) return null;
    return HitTimetableGrid(match.group(1)!);
  }

  /// 按 `<tr>` 切分成行，每行再按 `<td>` 切分成格子。
  ///
  /// 教务返回的表格没有 rowspan，`colspan` 只出现在第 0 行第 0 格和最后一行的
  /// 「其它课程」格，因此这里不做 span 展开，由业务层按列号取值。
  List<List<String>> toRows() {
    return _trPattern
        .allMatches(html)
        .map(
          (rowMatch) => _tdPattern
              .allMatches(rowMatch.group(1)!)
              .map((cell) => _cellToText(cell.group(1)!))
              .toList(),
        )
        .where((row) => row.isNotEmpty)
        .toList();
  }
}

/// 提取学期下拉框里的所有选项（`<option value="…">…</option>`）。
///
/// 教务把可查询的学期直接渲染在页面上，用它比硬编码学期码更稳。
///
/// 列表顺序是「**最新的学期在最前**」（未来学期也在里面），
/// 所以**不能取第一项当当前学期** —— 教务会在真正选中的那个 `<option>`
/// 上标 `selected`，用 [HitTerm.isSelected] 判断才准。
List<HitTerm> parseHitTerms(String pageHtml) {
  final match = RegExp(
    r'<select[^>]*id="xnxq"[^>]*>([\s\S]*?)</select>',
    caseSensitive: false,
  ).firstMatch(pageHtml);
  if (match == null) return const [];
  return RegExp(
    r'<option([^>]*)>([\s\S]*?)</option>',
    caseSensitive: false,
  )
      .allMatches(match.group(1)!)
      .map((option) {
        final attributes = option.group(1)!;
        final value =
            RegExp(r'value="([^"]*)"').firstMatch(attributes)?.group(1) ?? '';
        return HitTerm(
          value: value.trim(),
          label: _stripTags(option.group(2)!),
          isSelected: RegExp(
            r'\bselected\b',
            caseSensitive: false,
          ).hasMatch(attributes),
        );
      })
      .where((term) => term.value.isNotEmpty && term.label.isNotEmpty)
      .toList();
}

final _trPattern = RegExp(r'<tr[^>]*>([\s\S]*?)</tr>', caseSensitive: false);
final _tdPattern = RegExp(r'<t[dh][^>]*>([\s\S]*?)</t[dh]>', caseSensitive: false);
final _commentPattern = RegExp(r'<!--[\s\S]*?-->');
final _scriptPattern = RegExp(r'<script[\s\S]*?</script>', caseSensitive: false);
final _tagPattern = RegExp(r'<[^>]+>');

/// 把格子里的 HTML 转成纯文本，**保留 `<br>` 作为换行**。
///
/// 保留换行很关键：一格里的多门课是用 `<br>` 分隔的
/// （前两行是课程名、教师信息，后续课程继续接着排），丢掉换行就无法切分。
String _cellToText(String cellHtml) {
  return cellHtml
      .replaceAll(_commentPattern, '')
      .replaceAll(_scriptPattern, '')
      // 教务输出的换行标签是 `</br>`（闭合形式，虽不合法但浏览器会当换行处理），
      // 同时也可能输出 `<br>` / `<br/>`，三种都要覆盖。
      .replaceAll(RegExp(r'</?br\s*/?>', caseSensitive: false), '\n')
      // 教务输出的占位符是 `&nbsp`（**没有结尾分号**，也不止一处），
      // 标准写法 `&nbsp;` 和非断行空格字符也要一并处理。
      .replaceAll(RegExp(r'&nbsp;?', caseSensitive: false), ' ')
      .replaceAll('\u00a0', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll(_tagPattern, '')
      .split('\n')
      .map((line) => line.replaceAll(RegExp(r'[ \t\u3000]+'), ' ').trim())
      // 去掉 HTML 里用来占位的空行（教务常用 `&nbsp;` 填充，转成空格后为空），
      // 它们没有语义，保留会把课程名和教师信息错开。
      .where((line) => line.isNotEmpty)
      .join('\n');
}

String _stripTags(String html) =>
    html.replaceAll(_commentPattern, '').replaceAll(_tagPattern, '').trim();
