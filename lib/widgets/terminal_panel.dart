import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../services/terminal_session.dart';

class TerminalPanel extends StatefulWidget {
  const TerminalPanel({required this.session, super.key});

  final TerminalSession session;

  @override
  State<TerminalPanel> createState() => _TerminalPanelState();
}

class _TerminalPanelState extends State<TerminalPanel>
    with AutomaticKeepAliveClientMixin {
  static const _maxVisibleCharacters = 280000;

  final TextEditingController _inputController = TextEditingController();
  final FocusNode _inputFocusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();
  final _TerminalTextSanitizer _sanitizer = _TerminalTextSanitizer();
  StreamSubscription<String>? _outputSub;
  String _output = '';
  bool _acceptingInput = false;
  bool _followOutput = true;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    final history = widget.session.outputHistory;
    if (history.isNotEmpty) {
      _appendOutput(utf8.decode(history, allowMalformed: true), scroll: false);
    }
    _outputSub = widget.session.output
        .transform(const Utf8Decoder(allowMalformed: true))
        .listen(
          _appendOutput,
          onError: _appendError,
          onDone: () {
            if (mounted) setState(() => _acceptingInput = false);
          },
        );
    unawaited(_startSession());
  }

  Future<void> _startSession() async {
    try {
      await widget.session.start();
    } catch (error) {
      _appendOutput('\nUnable to start shell: $error\n');
    }
    if (!mounted) return;
    setState(() => _acceptingInput = widget.session.isAlive);
    _requestInputFocus();
  }

  void _appendOutput(String value, {bool scroll = true}) {
    final cleanValue = _sanitizer.sanitize(value);
    if (cleanValue.isEmpty || !mounted) return;
    setState(() {
      _output = _trimOutput('$_output$cleanValue');
    });
    if (scroll) _scrollToBottom();
  }

  void _appendError(Object error) {
    _appendOutput('\n$error\n');
  }

  void _submitInput(String value) {
    if (!_acceptingInput || !widget.session.isAlive) return;
    _inputController.clear();
    _appendOutput('$value\n');
    widget.session.writeString('$value\n');
    _requestInputFocus();
  }

  String _trimOutput(String value) {
    if (value.length <= _maxVisibleCharacters) return value;
    return value.substring(value.length - _maxVisibleCharacters);
  }

  void _requestInputFocus() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _acceptingInput) _inputFocusNode.requestFocus();
    });
  }

  void _scrollToBottom() {
    if (!_followOutput) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients || !_followOutput) return;
      _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
    });
  }

  bool _trackScroll(ScrollNotification notification) {
    if (notification.metrics.maxScrollExtent <= 0) {
      _followOutput = true;
    } else {
      _followOutput =
          notification.metrics.pixels >=
          notification.metrics.maxScrollExtent - 16;
    }
    return false;
  }

  @override
  void dispose() {
    _outputSub?.cancel();
    _inputController.dispose();
    _inputFocusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Container(
      color: AppColors.background,
      child: Column(
        children: [
          Expanded(
            child: NotificationListener<ScrollNotification>(
              onNotification: _trackScroll,
              child: Scrollbar(
                controller: _scrollController,
                child: SingleChildScrollView(
                  controller: _scrollController,
                  padding: const EdgeInsets.fromLTRB(13, 9, 13, 8),
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: SelectableText(
                      _output,
                      style: TextStyle(
                        color: AppColors.text,
                        fontSize: 12.5,
                        height: 1.45,
                        fontFamily: 'MapleMonoCN',
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Container(
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            color: AppColors.backgroundRaised,
            alignment: Alignment.center,
            child: Row(
              children: [
                Text(
                  '>',
                  style: TextStyle(
                    color: AppColors.signal,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    fontFamily: 'MapleMonoCN',
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _inputController,
                    focusNode: _inputFocusNode,
                    enabled: _acceptingInput,
                    autocorrect: false,
                    enableSuggestions: false,
                    keyboardType: TextInputType.text,
                    textInputAction: TextInputAction.done,
                    onSubmitted: _submitInput,
                    style: TextStyle(
                      color: AppColors.text,
                      fontSize: 12.5,
                      fontFamily: 'MapleMonoCN',
                    ),
                    decoration: InputDecoration(
                      hintText: _acceptingInput ? '输入命令' : '正在连接终端',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

enum _TerminalEscapeState { normal, escape, csi, osc }

class _TerminalTextSanitizer {
  _TerminalEscapeState _state = _TerminalEscapeState.normal;
  bool _oscEscape = false;

  String sanitize(String input) {
    final output = StringBuffer();
    for (final codeUnit in input.codeUnits) {
      switch (_state) {
        case _TerminalEscapeState.normal:
          if (codeUnit == 0x1b) {
            _state = _TerminalEscapeState.escape;
          } else if (codeUnit == 0x0d || codeUnit == 0x08) {
            continue;
          } else if (codeUnit == 0x09 || codeUnit == 0x0a || codeUnit >= 0x20) {
            output.writeCharCode(codeUnit);
          }
          break;
        case _TerminalEscapeState.escape:
          if (codeUnit == 0x5b) {
            _state = _TerminalEscapeState.csi;
          } else if (codeUnit == 0x5d) {
            _state = _TerminalEscapeState.osc;
            _oscEscape = false;
          } else {
            _state = _TerminalEscapeState.normal;
          }
          break;
        case _TerminalEscapeState.csi:
          if (codeUnit >= 0x40 && codeUnit <= 0x7e) {
            _state = _TerminalEscapeState.normal;
          }
          break;
        case _TerminalEscapeState.osc:
          if (codeUnit == 0x07 || (_oscEscape && codeUnit == 0x5c)) {
            _state = _TerminalEscapeState.normal;
            _oscEscape = false;
          } else {
            _oscEscape = codeUnit == 0x1b;
          }
          break;
      }
    }
    return output.toString();
  }
}
