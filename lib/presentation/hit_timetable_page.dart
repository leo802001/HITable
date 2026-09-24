/// 哈工大课表导入页：WebView 负责登录，接口负责取数据。
///
/// 工作流程（方案 C）：
/// 1. WebView 打开教务首页，用户在里面完成 CAS 统一身份认证。
///    —— 这里刻意不复刻登录逻辑：HIT 的 CAS 密码用 AES 加密提交
///    （页面里的 `pwdEncryptSalt`），而且强制走教务处自己的登录页最不容易失效。
/// 2. 用户点「读取课表」时，从 WebView 的 CookieManager 取出 `JSESSIONID` 和 `HIT`。
/// 3. 用这两个 Cookie 直接调 `POST /kbcx/queryGrkb` 拿 HTML 并解析。
///
/// 相比「注入 JS 抓 DOM」的做法，走接口的好处是：
/// - 可以一次读取任意学期，不受当前页面显示限制；
/// - 不依赖页面渲染完成、不依赖布局坐标；
/// - 拿到的 HTML 与页面一致，解析规则可单元测试。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../import/hit_jwts_client.dart';
import '../import/hit_timetable_import.dart';
import 'import_preview_page.dart';

class HitTimetablePage extends StatefulWidget {
  const HitTimetablePage({super.key});

  @override
  State<HitTimetablePage> createState() => _HitTimetablePageState();
}

class _HitTimetablePageState extends State<HitTimetablePage> {
  /// 教务首页。登录后会自动跳到工作台。
  static final _entryUri = Uri.parse(hitJwtsBaseUrl);

  static const _parser = HitTimetableImportParser();

  /// 教务系统在校内是明文 HTTP，且页面本身按桌面宽度排版。
  /// 用桌面 UA 可以让课表页和登录页都按完整宽度渲染，减少手机端布局错乱。
  static const _desktopUserAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
      'AppleWebKit/537.36 (KHTML, like Gecko) '
      'Chrome/131.0.0.0 Safari/537.36';

  late final WebViewController _controller;
  final _client = HitJwtsClient();

  var _progress = 0;
  var _reading = false;

  /// 缓存上次从页面读到的学期列表，读成功后填充。
  List<HitTerm> _terms = const [];
  HitTerm? _selectedTerm;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent(_desktopUserAgent)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (progress) {
            if (mounted) setState(() => _progress = progress);
          },
          onPageFinished: _onPageFinished,
          onWebResourceError: (error) {
            if (error.isForMainFrame == true && mounted) {
              _showMessage('网页加载失败，请确认已连接校园网');
            }
          },
        ),
      )
      ..loadRequest(_entryUri);
  }

  @override
  void dispose() {
    _client.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('从哈工大教务导入'),
        actions: [
          IconButton(
            tooltip: '重新加载',
            onPressed: () => _controller.reload(),
            icon: const Icon(Icons.refresh_rounded),
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'logout') _clearLogin();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'logout', child: Text('退出并清除登录信息')),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          if (_progress < 100) LinearProgressIndicator(value: _progress / 100),
          Material(
            color: Theme.of(context).colorScheme.surfaceContainerLow,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '请在下方完成哈工大统一身份认证，登录后点「读取课表」。'
                    '需要连接校园网（校外请先连 VPN）。',
                    style: TextStyle(fontSize: 12),
                  ),
                  if (_terms.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    _buildTermSelector(),
                  ],
                ],
              ),
            ),
          ),
          Expanded(child: WebViewWidget(controller: _controller)),
        ],
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(20, 8, 20, 16),
        child: FilledButton.icon(
          onPressed: _reading ? null : _readTimetable,
          icon: _reading
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.table_view_rounded),
          label: Text(_reading ? '正在读取' : '读取课表'),
        ),
      ),
    );
  }

  /// 学期下拉框。第一次读取成功后才有内容。
  Widget _buildTermSelector() {
    return Row(
      children: [
        const Text('学期：', style: TextStyle(fontSize: 12)),
        const SizedBox(width: 8),
        Expanded(
          child: DropdownButton<HitTerm>(
            isDense: true,
            isExpanded: true,
            value: _selectedTerm,
            style: const TextStyle(fontSize: 12),
            items: [
              for (final term in _terms)
                DropdownMenuItem(value: term, child: Text(term.label)),
            ],
            onChanged: (term) => setState(() => _selectedTerm = term),
          ),
        ),
      ],
    );
  }

  Future<void> _onPageFinished(String url) async {
    // 登录成功后教务会停在登录跳转页或工作台，这时顺手把学期列表读出来，
    // 让用户不用点「读取课表」就能先看到可选学期。
    if (_terms.isNotEmpty) return;
    try {
      final session = await _readSessionFromWebView();
      if (session == null) return;
      final html = await _client.fetchTimetableHtml(
        session: session,
        termValue: _probeTermValue,
      );
      final terms = parseHitTerms(html);
      if (!mounted || terms.isEmpty) return;
      setState(() {
        _terms = terms;
        _selectedTerm = _pickDefaultTerm(terms);
      });
    } catch (_) {
      // 登录前读不到学期是正常情况，静默忽略。
    }
  }

  Future<void> _readTimetable() async {
    setState(() => _reading = true);
    try {
      final session = await _readSessionFromWebView();
      if (session == null) {
        _showMessage('还没有登录，请先在下方完成统一身份认证');
        return;
      }

      // 目标学期：优先用用户在顶部选中的那个。
      var term = _selectedTerm;

      // 还没读过学期列表时，先用一个探测学期拉一次 ——
      // 目的是拿到 `select#xnxq` 里的完整学期清单（含教务标了 selected 的当前学期）。
      if (term == null || _terms.isEmpty) {
        final probeHtml = await _client.fetchTimetableHtml(
          session: session,
          termValue: _probeTermValue,
        );
        final terms = parseHitTerms(probeHtml);
        if (terms.isEmpty) {
          _showMessage('没有读到学期列表，请确认已登录且页面能正常打开');
          return;
        }
        term = _pickDefaultTerm(terms);
        if (mounted) {
          setState(() {
            _terms = terms;
            _selectedTerm = term;
          });
        }
      }

      // 用最终确定的学期取课表。
      // 若上一步已用该学期拉过，这里就是一次重复请求 —— 但保证「界面显示的学期」
      // 与「实际解析的课表」永远一致，比省一次请求更重要。
      final html = await _client.fetchTimetableHtml(
        session: session,
        termValue: term!.value,
      );

      final grid = HitTimetableGrid.fromPageHtml(html);
      if (grid == null) {
        _showMessage('没有在教务页面里找到课表，页面结构可能已变化');
        return;
      }
      final result = _parser.parse(grid.toRows());
      if (result.records.isEmpty) {
        _showMessage(
          result.warnings.isNotEmpty
              ? result.warnings.first
              : '这个学期没有课程，请在上方切换学期后重试',
        );
        return;
      }
      if (!mounted) return;

      final termLabel = term.label;
      final imported = await Navigator.push<bool>(
        context,
        MaterialPageRoute<bool>(
          builder: (_) => ImportPreviewPage(
            initialPreview: _parser.toImportPreview(result),
            title: termLabel.isEmpty ? 'HITable 预览' : 'HITable 预览（$termLabel）',
          ),
        ),
      );
      if (imported == true && mounted) {
        Navigator.pop(context);
      }
    } on HitApiException catch (error) {
      if (!mounted) return;
      if (error.isSessionExpired) {
        _showMessage('登录已过期，请重新登录');
        await _controller.reload();
      } else {
        _showMessage(error.message);
      }
    } catch (_) {
      if (mounted) {
        _showMessage('课表读取失败，请确认已连接校园网后重试');
      }
    } finally {
      if (mounted) setState(() => _reading = false);
    }
  }

  /// 从 WebView 的 Cookie 存储里取出教务会话。
  ///
  /// 注意：WebView 的 Cookie 与 Dart `HttpClient` 不共享，必须显式传递。
  /// `webview_flutter` 只提供「按域名取全部 Cookie」的 API，没有按名字取的版本，
  /// 所以这里一次性取回再挑出需要的两个。
  Future<HitSession?> _readSessionFromWebView() async {
    try {
      final cookies = await WebViewCookieManager().getCookies(
        domain: Uri.parse(hitJwtsBaseUrl),
      );
      String? valueOf(String name) {
        for (final cookie in cookies) {
          if (cookie.name == name && cookie.value.isNotEmpty) {
            return cookie.value;
          }
        }
        return null;
      }

      final jsession = valueOf(_cookieJsessionId);
      final hitToken = valueOf(_cookieHitToken);
      if (jsession == null || hitToken == null) return null;
      return HitSession(jsessionId: jsession, hitToken: hitToken);
    } catch (_) {
      return null;
    }
  }

  static const _cookieJsessionId = 'JSESSIONID';
  static const _cookieHitToken = 'HIT';

  /// 探测学期：仅用于「第一次拉取页面以拿到学期列表」。
  ///
  /// 教务的学期下拉框是页面渲染出来的，必须先请求一次才能知道有哪些学期，
  /// 所以需要一个任意合法的学期码做种子。这里的取值不影响最终结果 ——
  /// 拿到列表后会立刻改用教务标记为 `selected` 的那个学期重新拉取。
  static const _probeTermValue = '2026-20271';

  /// 从学期列表里挑最可能是「当前学期」的一项。
  ///
  /// 不能取第一项：教务把学期按最新在前排序，最前面是**未来**的学期。
  /// 教务会在当前学期那个 `<option>` 上标 `selected`，优先用它。
  HitTerm? _pickDefaultTerm(List<HitTerm> terms) => pickCurrentTerm(terms);

  Future<void> _clearLogin() async {
    await WebViewCookieManager().clearCookies();
    await _controller.clearCache();
    await _controller.clearLocalStorage();
    setState(() {
      _terms = const [];
      _selectedTerm = null;
    });
    await _controller.loadRequest(_entryUri);
    if (mounted) _showMessage('网页登录信息已清除');
  }

  void _showMessage(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }
}
