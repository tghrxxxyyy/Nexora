import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/services/markdown_code_highlighter.dart';

void main() {
  test(
    'renders a fenced Java block with a language badge and syntax markup',
    () {
      final html = MarkdownCodeHighlighter().decorate(
        '<pre><code class="language-java">public class App {}</code></pre>',
      );

      expect(html, contains('data-nexora-language="java"'));
      expect(html, contains('class="nexora-code-language"'));
      expect(html, contains('>java</span>'));
      expect(html, contains('hljs-keyword'));
    },
  );

  test('normalizes HTML fence aliases to XML highlighting', () {
    final html = MarkdownCodeHighlighter().decorate(
      '<pre><code class="language-html">&lt;main&gt;Hello&lt;/main&gt;</code></pre>',
    );

    expect(html, contains('data-nexora-language="xml"'));
    expect(html, contains('hljs-'));
  });

  test('keeps an unsupported fence language visible and round-trippable', () {
    final html = MarkdownCodeHighlighter().decorate(
      '<pre><code class="language-cpp">std::vector&lt;int&gt; values;</code></pre>',
    );

    expect(html, contains('data-nexora-language="cpp"'));
    expect(html, contains('>cpp</span>'));
    expect(html, contains('std::vector&lt;int&gt; values;'));
  });
}
