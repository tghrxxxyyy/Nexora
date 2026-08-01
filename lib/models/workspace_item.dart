import 'split_layout.dart';

enum WorkspaceItemType { file, directory }

class WorkspaceItem {
  const WorkspaceItem({
    required this.path,
    required this.name,
    required this.type,
    this.selectedFilePath,
    this.split,
  });

  final String path;
  final String name;
  final WorkspaceItemType type;
  final String? selectedFilePath;

  /// Optional split tree. When `null`, the workspace shows a single pane for
  /// [selectedFilePath]. When set, the tree is rendered recursively and
  /// [selectedFilePath] tracks the most recently focused pane's path for
  /// tab-bar / dirty-state purposes.
  final SplitNode? split;

  String get id => '${type.name}:$path';

  bool get isDirectory => type == WorkspaceItemType.directory;

  bool get isFile => type == WorkspaceItemType.file;

  WorkspaceItem copyWith({
    String? path,
    String? name,
    WorkspaceItemType? type,
    String? selectedFilePath,
    bool clearSelectedFilePath = false,
    SplitNode? split,
    bool clearSplit = false,
  }) {
    return WorkspaceItem(
      path: path ?? this.path,
      name: name ?? this.name,
      type: type ?? this.type,
      selectedFilePath: clearSelectedFilePath
          ? null
          : selectedFilePath ?? this.selectedFilePath,
      split: clearSplit ? null : split ?? this.split,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is WorkspaceItem && other.type == type && other.path == path;
  }

  @override
  int get hashCode => Object.hash(type, path);
}
