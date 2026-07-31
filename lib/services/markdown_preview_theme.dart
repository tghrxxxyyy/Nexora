import '../models/markdown_theme.dart';

abstract final class MarkdownPreviewTheme {
  static String css(MarkdownTheme theme) => switch (theme) {
    MarkdownTheme.nexora => '',
    MarkdownTheme.github => _github,
    MarkdownTheme.newsprint => _newsprint,
    MarkdownTheme.cherry ||
    MarkdownTheme.caramel ||
    MarkdownTheme.forest ||
    MarkdownTheme.mint ||
    MarkdownTheme.sky ||
    MarkdownTheme.prussian ||
    MarkdownTheme.sakura ||
    MarkdownTheme.mauve => _phycatColor(theme),
    MarkdownTheme.vampire ||
    MarkdownTheme.radiation ||
    MarkdownTheme.abyss => _phycatNeon(theme),
  };

  static String _phycatColor(MarkdownTheme theme) {
    final accent = _hex(theme.accent.toARGB32());
    final deep = _hex(theme.accentDeep.toARGB32());
    final soft = _hex(theme.accentSoft.toARGB32());
    final surface = _hex(theme.previewSurface.toARGB32());
    return '''
:root { color-scheme: light; --phycat-accent: $accent; --phycat-deep: $deep; --phycat-soft: $soft; }
html { background: $surface; }
body { color: #333333; background: $surface; font-family: "PingFang SC", "Hiragino Sans GB", "Noto Sans CJK SC", sans-serif; font-size: calc(16px * var(--nexora-font-scale)); line-height: 2; }
#nexora-document { width: min(100%, 950px); padding: 42px 50px 110px; position: relative; isolation: isolate; }
#nexora-document::before { content: ""; position: absolute; inset: 0; z-index: -1; pointer-events: none; opacity: 0.52; background-image: radial-gradient(var(--phycat-accent) 0.7px, transparent 0.8px); background-size: 19px 19px; mask-image: linear-gradient(to bottom, transparent, black 8%, black 92%, transparent); }
#nexora-document p { margin: 0 8px 14px; font-family: Optima, "Songti SC", STSong, Georgia, serif; font-size: calc(16px * var(--nexora-font-scale)); line-height: 2; }
#nexora-document h1, #nexora-document h2, #nexora-document h3, #nexora-document h4, #nexora-document h5, #nexora-document h6 { color: var(--phycat-deep); font-family: "PingFang SC", "Hiragino Sans GB", sans-serif; }
#nexora-document h1 { display: table; margin: 12px auto 30px; padding-bottom: 13px; color: #222222; font-size: calc(31px * var(--nexora-font-scale)); font-weight: 700; line-height: 1.42; text-align: center; transition: color .3s ease, transform .3s ease; }
#nexora-document h1:hover { color: var(--phycat-deep); transform: translateY(-2px); }
#nexora-document h1::after { content: ""; display: block; width: 42px; height: 4px; margin: 12px auto 0; border-radius: 99px; background: linear-gradient(90deg, var(--phycat-accent), var(--phycat-soft), var(--phycat-accent)); transition: width .35s ease; }
#nexora-document h1:hover::after { width: 100%; }
#nexora-document h2 { width: fit-content; margin: 30px 0 16px; padding: 6px 13px; color: #ffffff; font-size: calc(21px * var(--nexora-font-scale)); font-weight: 700; line-height: 1.45; background: linear-gradient(100deg, var(--phycat-accent), var(--phycat-deep), var(--phycat-accent)); background-size: 200% auto; border-radius: 8px; box-shadow: 0 5px 18px color-mix(in srgb, var(--phycat-accent), transparent 80%); transition: background-position .45s ease, transform .3s ease, box-shadow .3s ease; }
#nexora-document h2:hover { background-position: 100% center; transform: translateY(-2px); box-shadow: 0 11px 24px color-mix(in srgb, var(--phycat-accent), transparent 72%); }
#nexora-document h3 { width: fit-content; margin: 24px 0 11px; padding: 0 0 5px 10px; font-size: calc(19px * var(--nexora-font-scale)); border-bottom: 2px solid var(--phycat-soft); }
#nexora-document h3::before { content: ""; display: inline-block; width: 7px; height: 7px; margin: 0 8px 2px -10px; background: var(--phycat-accent); border-radius: 50%; box-shadow: 11px 0 0 color-mix(in srgb, var(--phycat-accent), transparent 45%); }
#nexora-document h4 { margin-top: 20px; color: var(--phycat-deep); }
#nexora-document h5, #nexora-document h6 { color: color-mix(in srgb, var(--phycat-deep), #ffffff 25%); }
#nexora-document a { color: var(--phycat-deep); font-weight: 600; text-decoration-color: color-mix(in srgb, var(--phycat-accent), transparent 50%); text-decoration-thickness: 1.5px; }
#nexora-document a:hover { color: var(--phycat-accent); }
#nexora-document strong { color: var(--phycat-deep); }
#nexora-document code { color: var(--phycat-deep); background: color-mix(in srgb, var(--phycat-soft), #ffffff 46%); border-radius: 4px; }
#nexora-document .nexora-code-block { background: color-mix(in srgb, var(--phycat-soft), #ffffff 52%); border-radius: 9px; box-shadow: 0 12px 30px color-mix(in srgb, var(--phycat-accent), transparent 88%); }
#nexora-document .nexora-code-language { color: var(--phycat-deep); background: color-mix(in srgb, var(--phycat-accent), transparent 90%); }
#nexora-document blockquote { color: color-mix(in srgb, var(--phycat-deep), #555555 30%); background: color-mix(in srgb, var(--phycat-soft), #ffffff 44%); border-left: 3px solid var(--phycat-accent); border-radius: 0 7px 7px 0; }
#nexora-document li::marker { color: var(--phycat-accent); }
#nexora-document hr { background: linear-gradient(90deg, transparent, var(--phycat-accent), transparent); }
#nexora-document thead tr { background: color-mix(in srgb, var(--phycat-soft), #ffffff 36%); }
#nexora-document tbody tr { background: color-mix(in srgb, var(--phycat-soft), #ffffff 70%); }
#nexora-document th, #nexora-document td { border-bottom: 1px solid color-mix(in srgb, var(--phycat-accent), transparent 82%); }
''';
  }

  static String _phycatNeon(MarkdownTheme theme) {
    final accent = _hex(theme.accent.toARGB32());
    final secondary = _hex(theme.accentDeep.toARGB32());
    final surface = _hex(theme.previewSurface.toARGB32());
    return '''
:root { color-scheme: dark; --neon-primary: $accent; --neon-secondary: $secondary; --neon-bg: $surface; }
html { background: var(--neon-bg); }
body { color: #e5e8ed; background: var(--neon-bg); font-family: "PingFang SC", "SF Pro Text", sans-serif; font-size: calc(15px * var(--nexora-font-scale)); line-height: 1.82; }
#nexora-document { width: min(100%, 950px); padding: 44px 52px 110px; position: relative; isolation: isolate; }
#nexora-document::before { content: ""; position: absolute; inset: 0; z-index: -1; pointer-events: none; background: radial-gradient(ellipse at 5% 3%, color-mix(in srgb, var(--neon-primary), transparent 91%), transparent 42%), radial-gradient(ellipse at 96% 100%, color-mix(in srgb, var(--neon-secondary), transparent 91%), transparent 40%); }
#nexora-document h1, #nexora-document h2, #nexora-document h3, #nexora-document h4 { color: #f5f7fb; }
#nexora-document h1 { width: fit-content; margin: 14px auto 30px; padding-bottom: 13px; font-size: calc(32px * var(--nexora-font-scale)); font-weight: 600; text-align: center; text-shadow: 0 0 12px color-mix(in srgb, var(--neon-primary), transparent 38%); }
#nexora-document h1::after { content: ""; display: block; width: 42px; height: 3px; margin: 12px auto 0; border-radius: 99px; background: var(--neon-primary); box-shadow: 0 0 16px var(--neon-primary); transition: width .4s ease; }
#nexora-document h1:hover::after { width: 100%; }
#nexora-document h2 { margin: 30px 0 15px; padding: 8px 12px; color: var(--neon-primary); font-size: calc(21px * var(--nexora-font-scale)); border: 1px solid color-mix(in srgb, var(--neon-primary), transparent 30%); border-radius: 7px; background: radial-gradient(ellipse at center bottom, color-mix(in srgb, var(--neon-primary), transparent 86%), transparent 72%); box-shadow: inset 0 0 20px color-mix(in srgb, var(--neon-primary), transparent 94%); }
#nexora-document h3 { color: var(--neon-secondary); font-size: calc(18px * var(--nexora-font-scale)); text-shadow: 0 0 8px color-mix(in srgb, var(--neon-secondary), transparent 48%); }
#nexora-document h5, #nexora-document h6 { color: #9aa7b8; }
#nexora-document a { color: var(--neon-primary); text-decoration-color: color-mix(in srgb, var(--neon-primary), transparent 58%); }
#nexora-document strong { color: #ffffff; }
#nexora-document code { color: var(--neon-primary); background: color-mix(in srgb, var(--neon-primary), transparent 93%); }
#nexora-document .nexora-code-block { background: rgba(0, 0, 0, 0.28); border: 1px solid color-mix(in srgb, var(--neon-primary), transparent 78%); border-radius: 8px; box-shadow: 0 12px 32px rgba(0, 0, 0, 0.18); }
#nexora-document .nexora-code-language { color: var(--neon-primary); background: color-mix(in srgb, var(--neon-primary), transparent 89%); }
#nexora-document blockquote { color: #b8c2ce; background: color-mix(in srgb, var(--neon-primary), transparent 94%); border-left: 3px solid var(--neon-primary); border-radius: 0 7px 7px 0; }
#nexora-document li::marker { color: var(--neon-primary); }
#nexora-document hr { background: linear-gradient(90deg, transparent, var(--neon-primary), transparent); box-shadow: 0 0 8px color-mix(in srgb, var(--neon-primary), transparent 45%); }
#nexora-document thead tr { background: color-mix(in srgb, var(--neon-primary), transparent 91%); }
#nexora-document tbody tr { background: color-mix(in srgb, var(--neon-primary), transparent 96%); }
#nexora-document th, #nexora-document td { color: #dce3ec; border-bottom: 1px solid color-mix(in srgb, var(--neon-primary), transparent 86%); }
''';
  }

  static String _hex(int value) =>
      '#${(value & 0x00ffffff).toRadixString(16).padLeft(6, '0')}';
}

const _github = r'''
:root { color-scheme: light; }
html { background: #ffffff; }
body { color: #1f2328; background: #ffffff; font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", "PingFang SC", sans-serif; font-size: calc(16px * var(--nexora-font-scale)); line-height: 1.62; }
#nexora-document { width: min(100%, 980px); padding: 40px 48px 96px; }
#nexora-document h1, #nexora-document h2 { color: #1f2328; font-weight: 600; border-bottom: 1px solid #d0d7de; }
#nexora-document h1 { margin: 12px 0 20px; padding-bottom: 9px; font-size: calc(32px * var(--nexora-font-scale)); }
#nexora-document h2 { margin: 30px 0 16px; padding-bottom: 7px; font-size: calc(24px * var(--nexora-font-scale)); }
#nexora-document h3 { color: #1f2328; margin-top: 25px; font-size: calc(20px * var(--nexora-font-scale)); }
#nexora-document h4, #nexora-document h5, #nexora-document h6 { color: #1f2328; }
#nexora-document a { color: #0969da; text-decoration-color: #54aeff; }
#nexora-document code { color: #24292f; background: #f6f8fa; border-radius: 4px; }
#nexora-document .nexora-code-block { background: #f6f8fa; border-radius: 6px; }
#nexora-document blockquote { color: #57606a; background: transparent; border-left: 4px solid #d0d7de; }
#nexora-document hr { background: #d8dee4; }
#nexora-document thead tr { background: #f6f8fa; }
#nexora-document tbody tr { background: #ffffff; }
#nexora-document td { border-top: 1px solid #d8dee4; }
''';

const _newsprint = r'''
:root { color-scheme: light; }
html { background: #f7f1e8; }
body { color: #312a22; background: #f7f1e8; font-family: Iowan Old Style, Baskerville, "Songti SC", STSong, Georgia, serif; font-size: calc(18px * var(--nexora-font-scale)); line-height: 1.88; }
#nexora-document { width: min(100%, 780px); padding: 58px 52px 110px; }
#nexora-document h1, #nexora-document h2, #nexora-document h3, #nexora-document h4, #nexora-document h5, #nexora-document h6 { color: #272019; font-family: Optima, "PingFang SC", Georgia, serif; }
#nexora-document h1 { margin: 18px 0 34px; font-size: calc(39px * var(--nexora-font-scale)); font-weight: 500; letter-spacing: 0.03em; text-align: center; }
#nexora-document h2 { margin: 46px 0 16px; font-size: calc(26px * var(--nexora-font-scale)); font-weight: 600; }
#nexora-document h3 { color: #74442a; margin-top: 34px; font-size: calc(21px * var(--nexora-font-scale)); }
#nexora-document p { margin-bottom: 16px; }
#nexora-document a { color: #9a5b32; text-decoration-color: #c99872; }
#nexora-document code { color: #714228; background: #eee2d2; font-family: "Maple Mono", "SF Mono", monospace; }
#nexora-document .nexora-code-block { background: #eee2d2; border-radius: 2px; }
#nexora-document blockquote { color: #745d4a; background: #f1e7da; border-left: 2px solid #bd8b62; font-style: italic; }
#nexora-document hr { background: #d4bda7; }
#nexora-document thead tr, #nexora-document tbody tr { background: #f3e9dc; }
#nexora-document th, #nexora-document td { border-bottom: 1px solid #dfcbb7; }
''';
