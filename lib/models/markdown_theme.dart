import 'package:flutter/material.dart';

enum MarkdownTheme {
  nexora,
  github,
  newsprint,
  cherry,
  caramel,
  forest,
  mint,
  sky,
  prussian,
  sakura,
  mauve,
  vampire,
  radiation,
  abyss,
}

enum MarkdownThemeFamily { standard, phycatColor, phycatNeon }

extension MarkdownThemeDetails on MarkdownTheme {
  String get label => switch (this) {
    MarkdownTheme.nexora => 'Nexora',
    MarkdownTheme.github => 'GitHub',
    MarkdownTheme.newsprint => 'Newsprint',
    MarkdownTheme.cherry => 'Cherry',
    MarkdownTheme.caramel => 'Caramel',
    MarkdownTheme.forest => 'Forest',
    MarkdownTheme.mint => 'Mint',
    MarkdownTheme.sky => 'Sky',
    MarkdownTheme.prussian => 'Prussian',
    MarkdownTheme.sakura => 'Sakura',
    MarkdownTheme.mauve => 'Mauve',
    MarkdownTheme.vampire => 'Vampire',
    MarkdownTheme.radiation => 'Radiation',
    MarkdownTheme.abyss => 'Abyss',
  };

  String get description => switch (this) {
    MarkdownTheme.nexora => 'Nexora 默认阅读体验',
    MarkdownTheme.github => 'GitHub 文档风格',
    MarkdownTheme.newsprint => '出版物般的舒展排版',
    MarkdownTheme.cherry => 'Phycat Color 樱桃红',
    MarkdownTheme.caramel => 'Phycat Color 流光蜜金',
    MarkdownTheme.forest => 'Phycat Color 森林绿',
    MarkdownTheme.mint => 'Phycat Color 薄荷青',
    MarkdownTheme.sky => 'Phycat Color 晴空蓝',
    MarkdownTheme.prussian => 'Phycat Color 普鲁士蓝',
    MarkdownTheme.sakura => 'Phycat Color 樱花粉',
    MarkdownTheme.mauve => 'Phycat Color 淡紫',
    MarkdownTheme.vampire => 'Phycat Neon 吸血鬼',
    MarkdownTheme.radiation => 'Phycat Neon 辐射',
    MarkdownTheme.abyss => 'Phycat Neon 深渊',
  };

  MarkdownThemeFamily get family => switch (this) {
    MarkdownTheme.cherry ||
    MarkdownTheme.caramel ||
    MarkdownTheme.forest ||
    MarkdownTheme.mint ||
    MarkdownTheme.sky ||
    MarkdownTheme.prussian ||
    MarkdownTheme.sakura ||
    MarkdownTheme.mauve => MarkdownThemeFamily.phycatColor,
    MarkdownTheme.vampire ||
    MarkdownTheme.radiation ||
    MarkdownTheme.abyss => MarkdownThemeFamily.phycatNeon,
    _ => MarkdownThemeFamily.standard,
  };

  bool get isDark => family == MarkdownThemeFamily.phycatNeon;

  Color get accent => switch (this) {
    MarkdownTheme.nexora => const Color(0xFF3298E0),
    MarkdownTheme.github => const Color(0xFF0969DA),
    MarkdownTheme.newsprint => const Color(0xFF9A5B32),
    MarkdownTheme.cherry => const Color(0xFFAA1141),
    MarkdownTheme.caramel => const Color(0xFFF59E0B),
    MarkdownTheme.forest => const Color(0xFF11AA63),
    MarkdownTheme.mint => const Color(0xFF3DB8BF),
    MarkdownTheme.sky => const Color(0xFF3498DB),
    MarkdownTheme.prussian => const Color(0xFF1D4E89),
    MarkdownTheme.sakura => const Color(0xFFFF7096),
    MarkdownTheme.mauve => const Color(0xFFA06EB4),
    MarkdownTheme.vampire => const Color(0xFFFF5555),
    MarkdownTheme.radiation => const Color(0xFF4CD964),
    MarkdownTheme.abyss => const Color(0xFF00F3FF),
  };

  Color get accentDeep => switch (this) {
    MarkdownTheme.cherry => const Color(0xFF9A0036),
    MarkdownTheme.caramel => const Color(0xFFB45309),
    MarkdownTheme.forest => const Color(0xFF009A52),
    MarkdownTheme.mint => const Color(0xFF089BA3),
    MarkdownTheme.sky => const Color(0xFF2980B9),
    MarkdownTheme.prussian => const Color(0xFF003153),
    MarkdownTheme.sakura => const Color(0xFFE91E63),
    MarkdownTheme.mauve => const Color(0xFF6A3F7A),
    MarkdownTheme.vampire => const Color(0xFFBD93F9),
    MarkdownTheme.radiation => const Color(0xFFFFC107),
    MarkdownTheme.abyss => const Color(0xFF2979FF),
    _ => accent,
  };

  Color get accentSoft => switch (this) {
    MarkdownTheme.cherry => const Color(0xFFFEC2D2),
    MarkdownTheme.caramel => const Color(0xFFFEF3C7),
    MarkdownTheme.forest => const Color(0xFFCCF3DE),
    MarkdownTheme.mint => const Color(0xFFC9F4F5),
    MarkdownTheme.sky => const Color(0xFFEAF2F8),
    MarkdownTheme.prussian => const Color(0xFFD6E7F5),
    MarkdownTheme.sakura => const Color(0xFFFFE1EA),
    MarkdownTheme.mauve => const Color(0xFFF0E0F4),
    MarkdownTheme.vampire => const Color(0xFF44475A),
    MarkdownTheme.radiation => const Color(0xFF344C37),
    MarkdownTheme.abyss => const Color(0xFF17233A),
    _ => const Color(0xFFF1F6FB),
  };

  Color get previewSurface => switch (this) {
    MarkdownTheme.nexora => const Color(0xFFF6F8FB),
    MarkdownTheme.github => const Color(0xFFF6F8FA),
    MarkdownTheme.newsprint => const Color(0xFFF7F1E8),
    MarkdownTheme.cherry => const Color(0xFFFFF4F7),
    MarkdownTheme.caramel => const Color(0xFFFFF8EA),
    MarkdownTheme.forest => const Color(0xFFF1FBF5),
    MarkdownTheme.mint => const Color(0xFFEFFBFB),
    MarkdownTheme.sky => const Color(0xFFF1F8FE),
    MarkdownTheme.prussian => const Color(0xFFF1F6FA),
    MarkdownTheme.sakura => const Color(0xFFFFF2F6),
    MarkdownTheme.mauve => const Color(0xFFFAF3FC),
    MarkdownTheme.vampire => const Color(0xFF282A36),
    MarkdownTheme.radiation => const Color(0xFF1B1D1B),
    MarkdownTheme.abyss => const Color(0xFF0F111A),
  };
}
