class DocumentModel {
  const DocumentModel({
    required this.path,
    required this.name,
    required this.content,
    required this.savedContent,
    required this.size,
    this.modifiedAt,
    this.hasUtf8Bom = false,
  });

  final String path;
  final String name;
  final String content;
  final String savedContent;
  final int size;
  final DateTime? modifiedAt;
  final bool hasUtf8Bom;

  bool get isDirty => content != savedContent;

  bool get isMarkdown {
    final lowerName = name.toLowerCase();
    return lowerName.endsWith('.md') || lowerName.endsWith('.markdown');
  }

  bool get isHtml {
    final lowerName = name.toLowerCase();
    return lowerName.endsWith('.html') || lowerName.endsWith('.htm');
  }

  int get lineCount => '\n'.allMatches(content).length + 1;

  int get characterCount => content.runes.length;

  DocumentModel copyWith({
    String? path,
    String? name,
    String? content,
    String? savedContent,
    int? size,
    DateTime? modifiedAt,
    bool? hasUtf8Bom,
  }) {
    return DocumentModel(
      path: path ?? this.path,
      name: name ?? this.name,
      content: content ?? this.content,
      savedContent: savedContent ?? this.savedContent,
      size: size ?? this.size,
      modifiedAt: modifiedAt ?? this.modifiedAt,
      hasUtf8Bom: hasUtf8Bom ?? this.hasUtf8Bom,
    );
  }

  DocumentModel markSaved({DateTime? modifiedAt, int? size}) {
    return copyWith(savedContent: content, modifiedAt: modifiedAt, size: size);
  }
}
