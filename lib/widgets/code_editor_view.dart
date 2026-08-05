import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:re_editor/re_editor.dart';
import 'package:re_highlight/languages/cpp.dart';
import 'package:re_highlight/languages/css.dart';
import 'package:re_highlight/languages/dart.dart';
import 'package:re_highlight/languages/java.dart';
import 'package:re_highlight/languages/javascript.dart';
import 'package:re_highlight/languages/json.dart';
import 'package:re_highlight/languages/markdown.dart';
import 'package:re_highlight/languages/python.dart';
import 'package:re_highlight/languages/shell.dart';
import 'package:re_highlight/languages/sql.dart';
import 'package:re_highlight/languages/typescript.dart';
import 'package:re_highlight/languages/xml.dart';
import 'package:re_highlight/languages/yaml.dart';
import 'package:re_highlight/re_highlight.dart';
import 'package:re_highlight/styles/night-owl.dart';

import '../app_theme.dart';
import 'editor_context_menu.dart';
import 'editor_find_panel.dart';
import 'ui_primitives.dart';

class CodeEditorView extends StatefulWidget {
  const CodeEditorView({
    required this.path,
    required this.controller,
    required this.findController,
    required this.scrollController,
    required this.initialScrollOffset,
    required this.onChanged,
    required this.onSave,
    this.wordWrap = false,
    this.fontScale = 1,
    super.key,
  });

  final String path;
  final CodeLineEditingController controller;
  final CodeFindController findController;
  final CodeScrollController scrollController;

  /// Scroll position to restore after the editor (re)mounts. Fed from the
  /// session so switching back to a document lands where the reader left off.
  final double initialScrollOffset;
  final ValueChanged<CodeLineEditingValue> onChanged;

  /// Invoked when the user presses the editor's built-in save shortcut
  /// (Cmd+S on macOS, Ctrl+S elsewhere). `re_editor` registers Cmd+S against
  /// its own `CodeShortcutSaveIntent` and the inner `Shortcuts` widget
  /// swallows the key event before our app-level `CallbackShortcuts` /
  /// platform menu can see it, so we have to register an override action
  /// that forwards back to the controller.
  final VoidCallback onSave;
  final bool wordWrap;
  final double fontScale;

  @override
  State<CodeEditorView> createState() => _CodeEditorViewState();
}

class _CodeEditorViewState extends State<CodeEditorView> {
  @override
  void initState() {
    super.initState();
    _restoreScroll();
  }

  @override
  void didUpdateWidget(CodeEditorView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path ||
        oldWidget.initialScrollOffset != widget.initialScrollOffset) {
      _restoreScroll();
    }
  }

  /// Restores the session's saved scroll offset after the editor mounts. The
  /// editor rebuilds with a fresh ScrollPosition whenever `CodeEditor`'s key
  /// (path) changes, so we jump back to the saved offset on the first frame —
  /// retrying once in case the scroller hasn't attached yet.
  void _restoreScroll([int attempt = 0]) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || widget.initialScrollOffset <= 0) return;
      final scroller = widget.scrollController.verticalScroller;
      if (!scroller.hasClients) {
        if (attempt < 1) _restoreScroll(attempt + 1);
        return;
      }
      try {
        scroller.jumpTo(widget.initialScrollOffset);
      } catch (_) {}
    });
  }

  @override
  Widget build(BuildContext context) {
    final mode = _languageMode(widget.path);
    final languageName = _languageName(widget.path);
    final commentFormatter = _commentFormatter(widget.path);
    final editorTheme = <String, TextStyle>{
      ...nightOwlTheme,
      'root': TextStyle(color: AppColors.text),
      'comment': const TextStyle(
        color: Color(0xFF697A76),
        fontStyle: FontStyle.italic,
      ),
      'keyword': const TextStyle(color: Color(0xFFFF78C6)),
      'string': TextStyle(color: AppColors.acid),
      'number': const TextStyle(color: Color(0xFFFFA86A)),
      'title': TextStyle(color: AppColors.signal),
      'function': const TextStyle(color: Color(0xFF8CB8FF)),
      'tag': TextStyle(color: AppColors.signal),
    };

    return ColoredBox(
      color: AppColors.backgroundRaised,
      child: CodeEditor(
        key: ValueKey(widget.path),
        controller: widget.controller,
        scrollController: widget.scrollController,
        findController: widget.findController,
        onChanged: widget.onChanged,
        shortcutOverrideActions: {
          CodeShortcutSaveIntent: CallbackAction<CodeShortcutSaveIntent>(
            onInvoke: (_) {
              widget.onSave();
              return null;
            },
          ),
        },
        wordWrap: widget.wordWrap,
        autofocus: true,
        padding: const EdgeInsets.fromLTRB(12, 14, 12, 28),
        style: CodeEditorStyle(
          fontFamily: 'MapleMonoCN',
          fontFamilyFallback: const ['monospace'],
          fontSize: 13.5 * widget.fontScale,
          fontHeight: 1.62,
          textColor: AppColors.text,
          backgroundColor: AppColors.backgroundRaised,
          selectionColor: AppColors.selection,
          highlightColor: AppColors.amber.withValues(alpha: 0.2),
          cursorColor: AppColors.signal,
          cursorWidth: 1.5,
          cursorLineColor: AppColors.signal.withValues(alpha: 0.11),
          chunkIndicatorColor: AppColors.textDim,
          codeTheme: mode == null
              ? null
              : CodeHighlightTheme(
                  languages: {languageName: CodeHighlightThemeMode(mode: mode)},
                  theme: editorTheme,
                ),
        ),
        indicatorBuilder:
            (context, editingController, chunkController, notifier) {
              return ColoredBox(
                color: AppColors.background,
                child: Row(
                  children: [
                    const SizedBox(width: 8),
                    DefaultCodeLineNumber(
                      controller: editingController,
                      notifier: notifier,
                      textStyle: TextStyle(
                        color: AppColors.textDim,
                        fontSize: 11.5 * widget.fontScale,
                        fontFamily: 'MapleMonoCN',
                        height: 1.62,
                      ),
                      focusedTextStyle: TextStyle(
                        color: AppColors.signal,
                        fontSize: 11.5 * widget.fontScale,
                        fontFamily: 'MapleMonoCN',
                        height: 1.62,
                      ),
                    ),
                    DefaultCodeChunkIndicator(
                      width: 18,
                      controller: chunkController,
                      notifier: notifier,
                    ),
                  ],
                ),
              );
            },
        leadingDivider: SignalDivider(vertical: true),
        findBuilder: (context, findController, readOnly) =>
            EditorFindPanel(controller: findController, readOnly: readOnly),
        toolbarController: const EditorContextMenuController(),
        commentFormatter: commentFormatter,
      ),
    );
  }

  String _languageName(String path) {
    final extension = p.extension(path).toLowerCase();
    return switch (extension) {
      '.md' || '.markdown' => 'markdown',
      '.sql' => 'sql',
      '.java' => 'java',
      '.py' => 'python',
      '.ts' || '.tsx' => 'typescript',
      '.js' || '.jsx' => 'javascript',
      '.html' || '.htm' || '.xml' => 'html',
      '.css' || '.scss' => 'css',
      '.json' => 'json',
      '.yaml' || '.yml' => 'yaml',
      '.sh' || '.zsh' || '.bash' => 'shell',
      '.dart' => 'dart',
      '.cpp' ||
      '.cc' ||
      '.cxx' ||
      '.C' ||
      '.h' ||
      '.hpp' ||
      '.hh' ||
      '.hxx' => 'cpp',
      _ => 'plain',
    };
  }

  Mode? _languageMode(String path) {
    return switch (_languageName(path)) {
      'markdown' => langMarkdown,
      'sql' => langSql,
      'java' => langJava,
      'python' => langPython,
      'typescript' => langTypescript,
      'javascript' => langJavascript,
      'html' => langXml,
      'css' => langCss,
      'json' => langJson,
      'yaml' => langYaml,
      'shell' => langShell,
      'dart' => langDart,
      'cpp' => langCpp,
      _ => null,
    };
  }

  CodeCommentFormatter? _commentFormatter(String path) {
    return switch (_languageName(path)) {
      'markdown' => DefaultCodeCommentFormatter(
        multiLinePrefix: '<!--',
        multiLineSuffix: '-->',
      ),
      'python' ||
      'shell' ||
      'yaml' => DefaultCodeCommentFormatter(singleLinePrefix: '#'),
      'html' => DefaultCodeCommentFormatter(
        multiLinePrefix: '<!--',
        multiLineSuffix: '-->',
      ),
      'sql' => DefaultCodeCommentFormatter(
        singleLinePrefix: '--',
        multiLinePrefix: '/*',
        multiLineSuffix: '*/',
      ),
      'plain' => null,
      _ => DefaultCodeCommentFormatter(
        singleLinePrefix: '//',
        multiLinePrefix: '/*',
        multiLineSuffix: '*/',
      ),
    };
  }
}
