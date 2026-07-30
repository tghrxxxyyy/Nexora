enum FileChangeType { added, modified, removed }

class FileChangeEvent {
  const FileChangeEvent({
    required this.watchedPath,
    required this.path,
    required this.type,
    required this.occurredAt,
  });

  final String watchedPath;
  final String path;
  final FileChangeType type;
  final DateTime occurredAt;
}
