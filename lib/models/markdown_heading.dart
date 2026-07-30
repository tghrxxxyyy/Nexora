class MarkdownHeading {
  const MarkdownHeading({
    required this.level,
    required this.text,
    required this.anchor,
    required this.lineNumber,
    required this.sourceOffset,
  });

  final int level;
  final String text;
  final String anchor;
  final int lineNumber;
  final int sourceOffset;
}
