import 'dart:convert';

import 'package:re_highlight/languages/abnf.dart';
import 'package:re_highlight/languages/actionscript.dart';
import 'package:re_highlight/languages/angelscript.dart';
import 'package:re_highlight/languages/apache.dart';
import 'package:re_highlight/languages/applescript.dart';
import 'package:re_highlight/languages/arduino.dart';
import 'package:re_highlight/languages/armasm.dart';
import 'package:re_highlight/languages/asciidoc.dart';
import 'package:re_highlight/languages/aspectj.dart';
import 'package:re_highlight/languages/autohotkey.dart';
import 'package:re_highlight/languages/autoit.dart';
import 'package:re_highlight/languages/avrasm.dart';
import 'package:re_highlight/languages/awk.dart';
import 'package:re_highlight/languages/basic.dart';
import 'package:re_highlight/languages/bash.dart';
import 'package:re_highlight/languages/bnf.dart';
import 'package:re_highlight/languages/brainfuck.dart';
import 'package:re_highlight/languages/cal.dart';
import 'package:re_highlight/languages/c.dart';
import 'package:re_highlight/languages/cmake.dart';
import 'package:re_highlight/languages/cpp.dart';
import 'package:re_highlight/languages/cos.dart';
import 'package:re_highlight/languages/csharp.dart';
import 'package:re_highlight/languages/css.dart';
import 'package:re_highlight/languages/d.dart';
import 'package:re_highlight/languages/dart.dart';
import 'package:re_highlight/languages/delphi.dart';
import 'package:re_highlight/languages/diff.dart';
import 'package:re_highlight/languages/dockerfile.dart';
import 'package:re_highlight/languages/dsconfig.dart';
import 'package:re_highlight/languages/dust.dart';
import 'package:re_highlight/languages/elixir.dart';
import 'package:re_highlight/languages/erlang.dart';
import 'package:re_highlight/languages/erlang-repl.dart';
import 'package:re_highlight/languages/fsharp.dart';
import 'package:re_highlight/languages/fortran.dart';
import 'package:re_highlight/languages/gams.dart';
import 'package:re_highlight/languages/gauss.dart';
import 'package:re_highlight/languages/gcode.dart';
import 'package:re_highlight/languages/gherkin.dart';
import 'package:re_highlight/languages/glsl.dart';
import 'package:re_highlight/languages/gml.dart';
import 'package:re_highlight/languages/go.dart';
import 'package:re_highlight/languages/golo.dart';
import 'package:re_highlight/languages/gradle.dart';
import 'package:re_highlight/languages/graphql.dart';
import 'package:re_highlight/languages/groovy.dart';
import 'package:re_highlight/languages/haml.dart';
import 'package:re_highlight/languages/handlebars.dart';
import 'package:re_highlight/languages/haskell.dart';
import 'package:re_highlight/languages/haxe.dart';
import 'package:re_highlight/languages/hsp.dart';
import 'package:re_highlight/languages/http.dart';
import 'package:re_highlight/languages/hy.dart';
import 'package:re_highlight/languages/inform7.dart';
import 'package:re_highlight/languages/ini.dart';
import 'package:re_highlight/languages/irpf90.dart';
import 'package:re_highlight/languages/isbl.dart';
import 'package:re_highlight/languages/java.dart';
import 'package:re_highlight/languages/javascript.dart';
import 'package:re_highlight/languages/jboss-cli.dart';
import 'package:re_highlight/languages/json.dart';
import 'package:re_highlight/languages/julia.dart';
import 'package:re_highlight/languages/julia-repl.dart';
import 'package:re_highlight/languages/kotlin.dart';
import 'package:re_highlight/languages/latex.dart';
import 'package:re_highlight/languages/ldif.dart';
import 'package:re_highlight/languages/leaf.dart';
import 'package:re_highlight/languages/less.dart';
import 'package:re_highlight/languages/lisp.dart';
import 'package:re_highlight/languages/livecodeserver.dart';
import 'package:re_highlight/languages/livescript.dart';
import 'package:re_highlight/languages/lua.dart';
import 'package:re_highlight/languages/makefile.dart';
import 'package:re_highlight/languages/markdown.dart';
import 'package:re_highlight/languages/mathematica.dart';
import 'package:re_highlight/languages/matlab.dart';
import 'package:re_highlight/languages/maxima.dart';
import 'package:re_highlight/languages/mel.dart';
import 'package:re_highlight/languages/mercury.dart';
import 'package:re_highlight/languages/mipsasm.dart';
import 'package:re_highlight/languages/mizar.dart';
import 'package:re_highlight/languages/mojolicious.dart';
import 'package:re_highlight/languages/monkey.dart';
import 'package:re_highlight/languages/moonscript.dart';
import 'package:re_highlight/languages/n1ql.dart';
import 'package:re_highlight/languages/nginx.dart';
import 'package:re_highlight/languages/nix.dart';
import 'package:re_highlight/languages/nsis.dart';
import 'package:re_highlight/languages/objectivec.dart';
import 'package:re_highlight/languages/ocaml.dart';
import 'package:re_highlight/languages/openscad.dart';
import 'package:re_highlight/languages/oxygene.dart';
import 'package:re_highlight/languages/parser3.dart';
import 'package:re_highlight/languages/perl.dart';
import 'package:re_highlight/languages/php.dart';
import 'package:re_highlight/languages/php-template.dart';
import 'package:re_highlight/languages/plaintext.dart';
import 'package:re_highlight/languages/pony.dart';
import 'package:re_highlight/languages/powershell.dart';
import 'package:re_highlight/languages/processing.dart';
import 'package:re_highlight/languages/profile.dart';
import 'package:re_highlight/languages/prolog.dart';
import 'package:re_highlight/languages/properties.dart';
import 'package:re_highlight/languages/protobuf.dart';
import 'package:re_highlight/languages/puppet.dart';
import 'package:re_highlight/languages/purebasic.dart';
import 'package:re_highlight/languages/python.dart';
import 'package:re_highlight/languages/q.dart';
import 'package:re_highlight/languages/qml.dart';
import 'package:re_highlight/languages/reasonml.dart';
import 'package:re_highlight/languages/routeros.dart';
import 'package:re_highlight/languages/r.dart';
import 'package:re_highlight/languages/ruby.dart';
import 'package:re_highlight/languages/rust.dart';
import 'package:re_highlight/languages/sas.dart';
import 'package:re_highlight/languages/scala.dart';
import 'package:re_highlight/languages/scheme.dart';
import 'package:re_highlight/languages/scilab.dart';
import 'package:re_highlight/languages/scss.dart';
import 'package:re_highlight/languages/shell.dart';
import 'package:re_highlight/languages/smali.dart';
import 'package:re_highlight/languages/smalltalk.dart';
import 'package:re_highlight/languages/sml.dart';
import 'package:re_highlight/languages/sqf.dart';
import 'package:re_highlight/languages/sql.dart';
import 'package:re_highlight/languages/stan.dart';
import 'package:re_highlight/languages/stata.dart';
import 'package:re_highlight/languages/stylus.dart';
import 'package:re_highlight/languages/subunit.dart';
import 'package:re_highlight/languages/swift.dart';
import 'package:re_highlight/languages/taggerscript.dart';
import 'package:re_highlight/languages/tap.dart';
import 'package:re_highlight/languages/tcl.dart';
import 'package:re_highlight/languages/thrift.dart';
import 'package:re_highlight/languages/tp.dart';
import 'package:re_highlight/languages/twig.dart';
import 'package:re_highlight/languages/typescript.dart';
import 'package:re_highlight/languages/vala.dart';
import 'package:re_highlight/languages/vbnet.dart';
import 'package:re_highlight/languages/vbscript.dart';
import 'package:re_highlight/languages/verilog.dart';
import 'package:re_highlight/languages/vhdl.dart';
import 'package:re_highlight/languages/vue.dart';
import 'package:re_highlight/languages/x86asm.dart';
import 'package:re_highlight/languages/xl.dart';
import 'package:re_highlight/languages/xml.dart';
import 'package:re_highlight/languages/xquery.dart';
import 'package:re_highlight/languages/yaml.dart';
import 'package:re_highlight/languages/zephir.dart';

import 'package:re_highlight/re_highlight.dart';

/// Adds syntax markup and an editable language label to fenced Markdown code
/// blocks. The generated HTML is self-contained, so previews work offline.
class MarkdownCodeHighlighter {
  MarkdownCodeHighlighter() : _highlight = Highlight() {
    _highlight
      ..registerLanguage('abnf', langAbnf)
      ..registerLanguage('actionscript', langActionscript)
      ..registerLanguage('angelscript', langAngelscript)
      ..registerLanguage('apache', langApache)
      ..registerLanguage('applescript', langApplescript)
      ..registerLanguage('arduino', langArduino)
      ..registerLanguage('armasm', langArmasm)
      ..registerLanguage('asciidoc', langAsciidoc)
      ..registerLanguage('aspectj', langAspectj)
      ..registerLanguage('autohotkey', langAutohotkey)
      ..registerLanguage('autoit', langAutoit)
      ..registerLanguage('avrasm', langAvrasm)
      ..registerLanguage('awk', langAwk)
      ..registerLanguage('bash', langBash)
      ..registerLanguage('basic', langBasic)
      ..registerLanguage('bnf', langBnf)
      ..registerLanguage('brainfuck', langBrainfuck)
      ..registerLanguage('cal', langCal)
      ..registerLanguage('c', langC)
      ..registerLanguage('cmake', langCmake)
      ..registerLanguage('cpp', langCpp)
      ..registerLanguage('cos', langCos)
      ..registerLanguage('csharp', langCsharp)
      ..registerLanguage('css', langCss)
      ..registerLanguage('d', langD)
      ..registerLanguage('dart', langDart)
      ..registerLanguage('delphi', langDelphi)
      ..registerLanguage('diff', langDiff)
      ..registerLanguage('dockerfile', langDockerfile)
      ..registerLanguage('dsconfig', langDsconfig)
      ..registerLanguage('dust', langDust)
      ..registerLanguage('elixir', langElixir)
      ..registerLanguage('erlang', langErlang)
      ..registerLanguage('erlang-repl', langErlangRepl)
      ..registerLanguage('fsharp', langFsharp)
      ..registerLanguage('fortran', langFortran)
      ..registerLanguage('gams', langGams)
      ..registerLanguage('gauss', langGauss)
      ..registerLanguage('gcode', langGcode)
      ..registerLanguage('gherkin', langGherkin)
      ..registerLanguage('glsl', langGlsl)
      ..registerLanguage('gml', langGml)
      ..registerLanguage('go', langGo)
      ..registerLanguage('golo', langGolo)
      ..registerLanguage('gradle', langGradle)
      ..registerLanguage('graphql', langGraphql)
      ..registerLanguage('groovy', langGroovy)
      ..registerLanguage('haml', langHaml)
      ..registerLanguage('handlebars', langHandlebars)
      ..registerLanguage('haskell', langHaskell)
      ..registerLanguage('haxe', langHaxe)
      ..registerLanguage('hsp', langHsp)
      ..registerLanguage('http', langHttp)
      ..registerLanguage('hy', langHy)
      ..registerLanguage('inform7', langInform7)
      ..registerLanguage('ini', langIni)
      ..registerLanguage('irpf90', langIrpf90)
      ..registerLanguage('isbl', langIsbl)
      ..registerLanguage('java', langJava)
      ..registerLanguage('javascript', langJavascript)
      ..registerLanguage('jboss-cli', langJbossCli)
      ..registerLanguage('json', langJson)
      ..registerLanguage('julia', langJulia)
      ..registerLanguage('julia-repl', langJuliaRepl)
      ..registerLanguage('kotlin', langKotlin)
      ..registerLanguage('latex', langLatex)
      ..registerLanguage('ldif', langLdif)
      ..registerLanguage('leaf', langLeaf)
      ..registerLanguage('less', langLess)
      ..registerLanguage('lisp', langLisp)
      ..registerLanguage('livecodeserver', langLivecodeserver)
      ..registerLanguage('livescript', langLivescript)
      ..registerLanguage('lua', langLua)
      ..registerLanguage('makefile', langMakefile)
      ..registerLanguage('markdown', langMarkdown)
      ..registerLanguage('mathematica', langMathematica)
      ..registerLanguage('matlab', langMatlab)
      ..registerLanguage('maxima', langMaxima)
      ..registerLanguage('mel', langMel)
      ..registerLanguage('mercury', langMercury)
      ..registerLanguage('mipsasm', langMipsasm)
      ..registerLanguage('mizar', langMizar)
      ..registerLanguage('mojolicious', langMojolicious)
      ..registerLanguage('monkey', langMonkey)
      ..registerLanguage('moonscript', langMoonscript)
      ..registerLanguage('n1ql', langN1Ql)
      ..registerLanguage('nginx', langNginx)
      ..registerLanguage('nix', langNix)
      ..registerLanguage('nsis', langNsis)
      ..registerLanguage('objectivec', langObjectivec)
      ..registerLanguage('ocaml', langOcaml)
      ..registerLanguage('openscad', langOpenscad)
      ..registerLanguage('oxygene', langOxygene)
      ..registerLanguage('parser3', langParser3)
      ..registerLanguage('perl', langPerl)
      ..registerLanguage('php', langPhp)
      ..registerLanguage('php-template', langPhpTemplate)
      ..registerLanguage('plaintext', langPlaintext)
      ..registerLanguage('pony', langPony)
      ..registerLanguage('powershell', langPowershell)
      ..registerLanguage('processing', langProcessing)
      ..registerLanguage('profile', langProfile)
      ..registerLanguage('prolog', langProlog)
      ..registerLanguage('properties', langProperties)
      ..registerLanguage('protobuf', langProtobuf)
      ..registerLanguage('puppet', langPuppet)
      ..registerLanguage('purebasic', langPurebasic)
      ..registerLanguage('python', langPython)
      ..registerLanguage('q', langQ)
      ..registerLanguage('qml', langQml)
      ..registerLanguage('reasonml', langReasonml)
      ..registerLanguage('routeros', langRouteros)
      ..registerLanguage('r', langR)
      ..registerLanguage('ruby', langRuby)
      ..registerLanguage('rust', langRust)
      ..registerLanguage('sas', langSas)
      ..registerLanguage('scala', langScala)
      ..registerLanguage('scheme', langScheme)
      ..registerLanguage('scilab', langScilab)
      ..registerLanguage('scss', langScss)
      ..registerLanguage('shell', langShell)
      ..registerLanguage('smali', langSmali)
      ..registerLanguage('smalltalk', langSmalltalk)
      ..registerLanguage('sml', langSml)
      ..registerLanguage('sqf', langSqf)
      ..registerLanguage('sql', langSql)
      ..registerLanguage('stan', langStan)
      ..registerLanguage('stata', langStata)
      ..registerLanguage('stylus', langStylus)
      ..registerLanguage('subunit', langSubunit)
      ..registerLanguage('swift', langSwift)
      ..registerLanguage('taggerscript', langTaggerscript)
      ..registerLanguage('tap', langTap)
      ..registerLanguage('tcl', langTcl)
      ..registerLanguage('thrift', langThrift)
      ..registerLanguage('tp', langTp)
      ..registerLanguage('twig', langTwig)
      ..registerLanguage('typescript', langTypescript)
      ..registerLanguage('vala', langVala)
      ..registerLanguage('vbnet', langVbnet)
      ..registerLanguage('vbscript', langVbscript)
      ..registerLanguage('verilog', langVerilog)
      ..registerLanguage('vhdl', langVhdl)
      ..registerLanguage('vue', langVue)
      ..registerLanguage('x86asm', langX86Asm)
      ..registerLanguage('xl', langXl)
      ..registerLanguage('xml', langXml)
      ..registerLanguage('xquery', langXquery)
      ..registerLanguage('yaml', langYaml)
      ..registerLanguage('zephir', langZephir);
  }

  final Highlight _highlight;

  String decorate(String markdownHtml) {
    final codeBlockPattern = RegExp(
      r'<pre><code(?: class="([^"]*)")?>([\s\S]*?)</code></pre>',
    );
    return markdownHtml.replaceAllMapped(codeBlockPattern, (match) {
      final label = _languageFromClass(match.group(1));
      if (label == 'mermaid') {
        final source = _decodeHtml(match.group(2)!);
        final bodyEscaped = const HtmlEscape().convert(source);
        final attrEscaped =
            const HtmlEscape(HtmlEscapeMode.attribute).convert(source);
        return '<div class="nexora-mermaid" contenteditable="false" '
            'data-nexora-mermaid-source="$attrEscaped">'
            '<div class="mermaid">$bodyEscaped</div>'
            '</div>';
      }
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

  /// Normalizes aliases like `py`, `ts`, `c++` to canonical language ids.
  /// Returns null for missing language classes.
  String? _languageFromClass(String? classes) {
    final languageClass = (classes ?? '')
        .split(RegExp(r'\s+'))
        .firstWhere((name) => name.startsWith('language-'), orElse: () => '');
    if (languageClass.isEmpty) return null;
    final value = languageClass.substring('language-'.length).toLowerCase();
    return switch (value) {
      'html' || 'htm' || 'svg' || 'xml' || 'xhtml' => 'xml',
      'js' || 'jsx' => 'javascript',
      'ts' || 'tsx' => 'typescript',
      'py' || 'ipython' => 'python',
      // highlight.js's `shell` mode is *Shell Session* (terminal output with
      // `$ ` / `# ` prompts), not bash scripting. Map script aliases to
      // `bash` so users get real syntax highlighting for `#!/bin/bash` blocks.
      'sh' || 'bash' || 'zsh' || 'ksh' => 'bash',
      'shell' || 'console' || 'shellsession' => 'shell',
      'yml' || 'yaml' => 'yaml',
      'md' || 'markdown' => 'markdown',
      'c' || 'h' => 'c',
      'cc' || 'cpp' || 'c++' || 'cxx' || 'hpp' || 'hh' => 'cpp',
      'cs' || 'c#' => 'csharp',
      'objc' || 'obj-c' || 'objectivec' || 'objective-c' => 'objectivec',
      'go' || 'golang' => 'go',
      'rs' || 'rust' => 'rust',
      'rb' || 'ruby' => 'ruby',
      'kt' || 'kotlin' => 'kotlin',
      'scala' => 'scala',
      'swift' => 'swift',
      'lua' => 'lua',
      'r' => 'r',
      'php' => 'php',
      'pl' || 'perl' => 'perl',
      'make' || 'makefile' => 'makefile',
      'cmake' => 'cmake',
      'dockerfile' || 'docker' => 'dockerfile',
      'gradle' => 'gradle',
      'groovy' => 'groovy',
      'dart' => 'dart',
      'java' => 'java',
      'json' => 'json',
      'toml' || 'ini' || 'cfg' => 'ini',
      'ps1' || 'powershell' => 'powershell',
      'bat' || 'batch' || 'cmd' => 'dos',
      'fsharp' || 'fs' => 'fsharp',
      'vb' => 'vbnet',
      'asm' || 'nasm' => 'x86asm',
      'erl' => 'erlang',
      'ex' || 'exs' => 'elixir',
      'clj' => 'clojure',
      'elm' => 'elm',
      'hs' => 'haskell',
      'jl' => 'julia',
      'sql' => 'sql',
      'graphql' || 'gql' => 'graphql',
      'proto' || 'protobuf' => 'protobuf',
      'vue' => 'vue',
      'sass' => 'scss',
      _ => value,
    };
  }

  String? _supportedLanguage(String? language) {
    if (language == null) return null;
    return _registered.containsKey(language) ? language : null;
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

  static const _registered = <String, bool>{
    'abnf': true,
    'actionscript': true,
    'angelscript': true,
    'apache': true,
    'applescript': true,
    'arduino': true,
    'armasm': true,
    'asciidoc': true,
    'aspectj': true,
    'autohotkey': true,
    'autoit': true,
    'avrasm': true,
    'awk': true,
    'bash': true,
    'basic': true,
    'bnf': true,
    'brainfuck': true,
    'cal': true,
    'c': true,
    'cmake': true,
    'cpp': true,
    'cos': true,
    'csharp': true,
    'css': true,
    'd': true,
    'dart': true,
    'delphi': true,
    'diff': true,
    'dockerfile': true,
    'dsconfig': true,
    'dust': true,
    'elixir': true,
    'erlang': true,
    'erlang-repl': true,
    'fsharp': true,
    'fortran': true,
    'gams': true,
    'gauss': true,
    'gcode': true,
    'gherkin': true,
    'glsl': true,
    'gml': true,
    'go': true,
    'golo': true,
    'gradle': true,
    'graphql': true,
    'groovy': true,
    'haml': true,
    'handlebars': true,
    'haskell': true,
    'haxe': true,
    'hsp': true,
    'http': true,
    'hy': true,
    'inform7': true,
    'ini': true,
    'irpf90': true,
    'isbl': true,
    'java': true,
    'javascript': true,
    'jboss-cli': true,
    'json': true,
    'julia': true,
    'julia-repl': true,
    'kotlin': true,
    'latex': true,
    'ldif': true,
    'leaf': true,
    'less': true,
    'lisp': true,
    'livecodeserver': true,
    'livescript': true,
    'lua': true,
    'makefile': true,
    'markdown': true,
    'mathematica': true,
    'matlab': true,
    'maxima': true,
    'mel': true,
    'mercury': true,
    'mipsasm': true,
    'mizar': true,
    'mojolicious': true,
    'monkey': true,
    'moonscript': true,
    'n1ql': true,
    'nginx': true,
    'nix': true,
    'nsis': true,
    'objectivec': true,
    'ocaml': true,
    'openscad': true,
    'oxygene': true,
    'parser3': true,
    'perl': true,
    'php': true,
    'php-template': true,
    'plaintext': true,
    'pony': true,
    'powershell': true,
    'processing': true,
    'profile': true,
    'prolog': true,
    'properties': true,
    'protobuf': true,
    'puppet': true,
    'purebasic': true,
    'python': true,
    'q': true,
    'qml': true,
    'reasonml': true,
    'routeros': true,
    'r': true,
    'ruby': true,
    'rust': true,
    'sas': true,
    'scala': true,
    'scheme': true,
    'scilab': true,
    'scss': true,
    'shell': true,
    'smali': true,
    'smalltalk': true,
    'sml': true,
    'sqf': true,
    'sql': true,
    'stan': true,
    'stata': true,
    'stylus': true,
    'subunit': true,
    'swift': true,
    'taggerscript': true,
    'tap': true,
    'tcl': true,
    'thrift': true,
    'tp': true,
    'twig': true,
    'typescript': true,
    'vala': true,
    'vbnet': true,
    'vbscript': true,
    'verilog': true,
    'vhdl': true,
    'vue': true,
    'x86asm': true,
    'xl': true,
    'xml': true,
    'xquery': true,
    'yaml': true,
    'zephir': true,
  };
}
