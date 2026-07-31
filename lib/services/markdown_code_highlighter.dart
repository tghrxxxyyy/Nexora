import 'dart:convert';

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

/// Adds syntax markup and an editable language label to fenced Markdown code
/// blocks. The generated HTML is self-contained, so previews work offline.
class MarkdownCodeHighlighter {
  MarkdownCodeHighlighter() : _highlight = Highlight() {
    _highlight
      ..registerLanguage('css', langCss)
      ..registerLanguage('dart', langDart)
      ..registerLanguage('java', langJava)
      ..registerLanguage('javascript', langJavascript)
      ..registerLanguage('json', langJson)
      ..registerLanguage('markdown', langMarkdown)
      ..registerLanguage('python', langPython)
      ..registerLanguage('shell', langShell)
      ..registerLanguage('sql', langSql)
      ..registerLanguage('typescript', langTypescript)
      ..registerLanguage('xml', langXml)
      ..registerLanguage('yaml', langYaml);
  }

  final Highlight _highlight;

  String decorate(String markdownHtml) {
    final codeBlockPattern = RegExp(
      r'<pre><code(?: class="([^"]*)")?>([\s\S]*?)</code></pre>',
    );
    return markdownHtml.replaceAllMapped(codeBlockPattern, (match) {
      final label = _languageFromClass(match.group(1));
      final language = _supportedLanguage(label);
      final source = _decodeHtml(match.group(2)!);
      final highlighted = _highlightSource(source, language);
      final displayLabel = label ?? 'text';
      final escapedLabel = const HtmlEscape().convert(displayLabel);
      return '<div class="nexora-code-block" '
          'data-nexora-language="$displayLabel">'
          '<span class="nexora-code-language" '
          'contenteditable="false">$escapedLabel</span>'
          '<pre><code class="hljs language-$displayLabel">$highlighted</code></pre>'
          '</div>';
    });
  }

  String _highlightSource(String source, String? language) {
    if (language == null) return const HtmlEscape().convert(source);
    try {
      return _highlight.highlight(code: source, language: language).toHtml();
    } catch (_) {
      return const HtmlEscape().convert(source);
    }
  }

  String? _languageFromClass(String? classes) {
    final languageClass = (classes ?? '')
        .split(RegExp(r'\s+'))
        .firstWhere((name) => name.startsWith('language-'), orElse: () => '');
    if (languageClass.isEmpty) return null;
    final value = languageClass.substring('language-'.length).toLowerCase();
    return switch (value) {
      'html' || 'htm' || 'svg' || 'xml' => 'xml',
      'js' || 'jsx' => 'javascript',
      'ts' || 'tsx' => 'typescript',
      'py' => 'python',
      'sh' || 'bash' || 'zsh' || 'shell' => 'shell',
      'yml' || 'yaml' => 'yaml',
      'md' || 'markdown' => 'markdown',
      _ => value,
    };
  }

  String? _supportedLanguage(String? language) {
    return switch (language) {
      'css' ||
      'dart' ||
      'java' ||
      'javascript' ||
      'json' ||
      'markdown' ||
      'python' ||
      'shell' ||
      'sql' ||
      'typescript' ||
      'xml' ||
      'yaml' => language,
      _ => null,
    };
  }

  String _decodeHtml(String value) {
    value = value.replaceAllMapped(RegExp(r'&#x([0-9a-fA-F]+);'), (match) {
      return String.fromCharCode(int.parse(match.group(1)!, radix: 16));
    });
    value = value.replaceAllMapped(RegExp(r'&#([0-9]+);'), (match) {
      return String.fromCharCode(int.parse(match.group(1)!));
    });
    return value
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&amp;', '&');
  }
}
