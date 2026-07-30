enum FileNodeType { file, directory, link }

class FileNode {
  const FileNode({
    required this.path,
    required this.name,
    required this.type,
    this.children = const <FileNode>[],
    this.childrenLoaded = false,
    this.size,
    this.modifiedAt,
  });

  final String path;
  final String name;
  final FileNodeType type;
  final List<FileNode> children;
  final bool childrenLoaded;
  final int? size;
  final DateTime? modifiedAt;

  bool get isDirectory => type == FileNodeType.directory;

  bool get isFile => type == FileNodeType.file;

  bool get isLink => type == FileNodeType.link;

  FileNode copyWith({
    String? path,
    String? name,
    FileNodeType? type,
    List<FileNode>? children,
    bool? childrenLoaded,
    int? size,
    DateTime? modifiedAt,
  }) {
    return FileNode(
      path: path ?? this.path,
      name: name ?? this.name,
      type: type ?? this.type,
      children: children ?? this.children,
      childrenLoaded: childrenLoaded ?? this.childrenLoaded,
      size: size ?? this.size,
      modifiedAt: modifiedAt ?? this.modifiedAt,
    );
  }
}
