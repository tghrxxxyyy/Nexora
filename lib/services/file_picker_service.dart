import 'package:file_selector/file_selector.dart';
import 'package:path/path.dart' as p;

import '../models/workspace_item.dart';

class FilePickerService {
  const FilePickerService();

  Future<List<WorkspaceItem>> pickFiles({
    List<XTypeGroup> acceptedTypeGroups = const <XTypeGroup>[],
    String? initialDirectory,
  }) async {
    final files = await openFiles(
      acceptedTypeGroups: acceptedTypeGroups,
      initialDirectory: initialDirectory,
    );
    return _uniqueWorkspaces(
      files.map(
        (file) => WorkspaceItem(
          path: _normalize(file.path),
          name: p.basename(file.path),
          type: WorkspaceItemType.file,
        ),
      ),
    );
  }

  Future<List<WorkspaceItem>> pickDirectories({
    String? initialDirectory,
  }) async {
    final paths = await getDirectoryPaths(initialDirectory: initialDirectory);
    return _uniqueWorkspaces(
      paths
          .whereType<String>()
          .where((path) => path.trim().isNotEmpty)
          .map(
            (path) => WorkspaceItem(
              path: _normalize(path),
              name: p.basename(path),
              type: WorkspaceItemType.directory,
            ),
          ),
    );
  }

  List<WorkspaceItem> _uniqueWorkspaces(Iterable<WorkspaceItem> workspaces) {
    final uniqueByPath = <String, WorkspaceItem>{};
    for (final workspace in workspaces) {
      uniqueByPath.putIfAbsent(workspace.path, () => workspace);
    }
    return List<WorkspaceItem>.unmodifiable(uniqueByPath.values);
  }

  String _normalize(String path) => p.normalize(p.absolute(path));
}
