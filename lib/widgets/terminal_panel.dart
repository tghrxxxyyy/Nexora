import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../app_theme.dart';
import '../services/terminal_session.dart';

/// Embedded terminal panel that renders xterm.js in a WebView,
/// bridged to a live shell process.
class TerminalPanel extends StatefulWidget {
  const TerminalPanel({required this.session, super.key});

  final TerminalSession session;

  @override
  State<TerminalPanel> createState() => _TerminalPanelState();
}

class _TerminalPanelState extends State<TerminalPanel>
    with AutomaticKeepAliveClientMixin {
  WebViewController? _webviewCtrl;
  bool _ready = false;
  bool _started = false;
  StreamSubscription<List<int>>? _outputSub;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _initWebView();
  }

  Future<void> _initWebView() async {
    final html = await rootBundle.loadString(
      'assets/terminal/xterm_shell.html',
    );

    late final WebViewController controller;
    controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel(
        'TerminalChannel',
        onMessageReceived: _onTerminalInput,
      )
      ..addJavaScriptChannel(
        'ResizeChannel',
        onMessageReceived: _onTerminalResize,
      )
      ..addJavaScriptChannel(
        'TerminalReady',
        onMessageReceived: (_) => unawaited(_onPageReady(controller)),
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onWebResourceError: (error) {
            debugPrint('Terminal WebView error: $error');
          },
        ),
      );

    // Set a base URL so xterm.js CDN requests work
    await controller.loadHtmlString(html, baseUrl: 'https://cdn.jsdelivr.net/');

    if (mounted) {
      setState(() => _webviewCtrl = controller);
    }
  }

  Future<void> _onPageReady(WebViewController controller) async {
    _ready = true;

    // Start the shell session and connect output
    if (!_started) {
      _started = true;
      _outputSub = widget.session.output.listen(
        (data) => _sendOutputToTerminal(controller, data),
        onError: (e) => debugPrint('Terminal output error: $e'),
      );
      await widget.session.start();
    }

    // Focus the terminal
    await controller.runJavaScript('try { terminalFocus(); } catch(e) {}');
  }

  void _onTerminalInput(JavaScriptMessage message) {
    if (!widget.session.isAlive) return;
    final data = message.message;
    // Send raw keystrokes to the shell stdin
    widget.session.writeInput(utf8.encode(data));
  }

  void _onTerminalResize(JavaScriptMessage message) {
    try {
      final json = jsonDecode(message.message) as Map<String, dynamic>;
      final cols = (json['cols'] as num).toInt();
      final rows = (json['rows'] as num).toInt();
      widget.session.resize(cols, rows);
    } catch (_) {}
  }

  Future<void> _sendOutputToTerminal(
    WebViewController ctrl,
    List<int> data,
  ) async {
    if (!_ready) return;
    try {
      final b64 = base64Encode(data);
      await ctrl.runJavaScript('writeB64("$b64")');
    } catch (e) {
      debugPrint('sendOutput error: $e');
    }
  }

  @override
  void dispose() {
    _outputSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_webviewCtrl == null) {
      return const SizedBox.shrink();
    }

    return ClipRect(
      child: Container(
        color: AppColors.background,
        child: WebViewWidget(controller: _webviewCtrl!),
      ),
    );
  }
}
