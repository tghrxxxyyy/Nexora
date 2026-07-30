import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:webview_flutter/webview_flutter.dart';

import '../app_theme.dart';

class HtmlPreview extends StatefulWidget {
  const HtmlPreview({required this.path, required this.content, super.key});

  final String path;
  final String content;

  @override
  State<HtmlPreview> createState() => _HtmlPreviewState();
}

class _HtmlPreviewState extends State<HtmlPreview> {
  late final WebViewController _controller;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) {
            if (mounted) setState(() => _loading = true);
          },
          onPageFinished: (_) {
            if (mounted) setState(() => _loading = false);
          },
          onWebResourceError: (error) {
            if (mounted) setState(() => _error = error.description);
          },
        ),
      );
    _loadContent();
  }

  @override
  void didUpdateWidget(HtmlPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.content != oldWidget.content || widget.path != oldWidget.path) {
      _loadContent();
    }
  }

  Future<void> _loadContent() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      await _controller.loadHtmlString(
        widget.content.isEmpty
            ? '<!doctype html><html><body></body></html>'
            : widget.content,
        baseUrl: Uri.directory(
          '${p.dirname(widget.path)}${Platform.pathSeparator}',
        ).toString(),
      );
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.backgroundRaised,
      child: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_loading)
            const Align(
              alignment: Alignment.topCenter,
              child: LinearProgressIndicator(minHeight: 2),
            ),
          if (_error != null)
            Align(
              alignment: Alignment.bottomCenter,
              child: Container(
                margin: const EdgeInsets.all(12),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 7,
                ),
                color: AppColors.coral.withValues(alpha: 0.13),
                child: Text(
                  _error!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: AppColors.coral, fontSize: 10),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
