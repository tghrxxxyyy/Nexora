import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/document_model.dart';
import '../models/file_node.dart';
import 'text_file_codec.dart';

class FileSystemService {
  const FileSystemService();

  static const int defaultMaximumTextFileBytes = 16 * 1024 * 1024;

  Future<List<FileNode>> listDirectory(
    String directoryPath, {
    bool includeHidden = true,
    Set<String> ignoredDirectoryNames = const <String>{},
  }) async {
    final nodes = <FileNode>[];
    final directory = Directory(_normalize(directoryPath));

    await for (final entity in directory.list(followLinks: false)) {
      final name = p.basename(entity.path);
      if (!includeHidden && name.startsWith('.')) {
        continue;
      }

      final type = await FileSystemEntity.type(entity.path, followLinks: false);
      if (type == FileSystemEntityType.directory &&
          _isIgnoredDirectory(name, ignoredDirectoryNames)) {
        continue;
      }
      nodes.add(await _nodeForEntity(entity.path, type));
    }

    nodes.sort(_compareNodes);
    return List<FileNode>.unmodifiable(nodes);
  }

  Future<FileNode> readTree(
    String rootPath, {
    bool includeHidden = true,
    Set<String> ignoredDirectoryNames = commonIgnoredDirectoryNames,
    int maximumDepth = 32,
  }) async {
    if (maximumDepth < 0) {
      throw ArgumentError.value(maximumDepth, 'maximumDepth');
    }
    final normalizedPath = _normalize(rootPath);
    final type = await FileSystemEntity.type(
      normalizedPath,
      followLinks: false,
    );
    if (type == FileSystemEntityType.notFound) {
      throw FileSystemException('Path does not exist', normalizedPath);
    }
    return _readNodeRecursively(
      normalizedPath,
      type,
      depth: 0,
      maximumDepth: maximumDepth,
      includeHidden: includeHidden,
      ignoredDirectoryNames: ignoredDirectoryNames,
    );
  }

  Future<DocumentModel> readDocument(
    String filePath, {
    int maximumBytes = defaultMaximumTextFileBytes,
  }) async {
    final normalizedPath = _normalize(filePath);
    final file = File(normalizedPath);
    final stat = await file.stat();
    if (stat.type != FileSystemEntityType.file) {
      throw FileSystemException('Path is not a file', normalizedPath);
    }
    if (DocumentModel.isImagePath(normalizedPath)) {
      return DocumentModel(
        path: normalizedPath,
        name: p.basename(normalizedPath),
        content: '',
        savedContent: '',
        size: stat.size,
        modifiedAt: stat.modified,
      );
    }

    if (stat.size > maximumBytes) {
      throw FileTooLargeException(normalizedPath, stat.size, maximumBytes);
    }

    final decoded = TextFileCodec.tryDecode(await file.readAsBytes());
    if (decoded == null) {
      throw BinaryFileException(normalizedPath);
    }
    return DocumentModel(
      path: normalizedPath,
      name: p.basename(normalizedPath),
      content: decoded.content,
      savedContent: decoded.content,
      size: stat.size,
      modifiedAt: stat.modified,
      hasUtf8Bom: decoded.hasUtf8Bom,
    );
  }

  Future<DocumentModel> saveDocument(
    DocumentModel document, {
    bool overwriteExternalChanges = false,
  }) async {
    final file = File(_normalize(document.path));
    if (!overwriteExternalChanges && document.modifiedAt != null) {
      final currentStat = await file.stat();
      final modificationChanged = !currentStat.modified.isAtSameMomentAs(
        document.modifiedAt!,
      );
      if (currentStat.size != document.size || modificationChanged) {
        throw ExternalFileChangeException(document.path);
      }
    }

    final bytes = TextFileCodec.encode(
      document.content,
      includeUtf8Bom: document.hasUtf8Bom,
    );
    await file.writeAsBytes(bytes, flush: true);
    final savedStat = await file.stat();
    return document.markSaved(
      modifiedAt: savedStat.modified,
      size: savedStat.size,
    );
  }

  Future<FileNode> _readNodeRecursively(
    String entityPath,
    FileSystemEntityType type, {
    required int depth,
    required int maximumDepth,
    required bool includeHidden,
    required Set<String> ignoredDirectoryNames,
  }) async {
    final node = await _nodeForEntity(entityPath, type);
    if (!node.isDirectory || depth >= maximumDepth) {
      return node;
    }

    final children = await listDirectory(
      entityPath,
      includeHidden: includeHidden,
      ignoredDirectoryNames: ignoredDirectoryNames,
    );
    final loadedChildren = <FileNode>[];
    for (final child in children) {
      loadedChildren.add(
        await _readNodeRecursively(
          child.path,
          child.type == FileNodeType.directory
              ? FileSystemEntityType.directory
              : child.type == FileNodeType.link
              ? FileSystemEntityType.link
              : FileSystemEntityType.file,
          depth: depth + 1,
          maximumDepth: maximumDepth,
          includeHidden: includeHidden,
          ignoredDirectoryNames: ignoredDirectoryNames,
        ),
      );
    }
    return node.copyWith(
      children: List<FileNode>.unmodifiable(loadedChildren),
      childrenLoaded: true,
    );
  }

  Future<FileNode> _nodeForEntity(
    String entityPath,
    FileSystemEntityType type,
  ) async {
    final normalizedPath = _normalize(entityPath);
    if (type == FileSystemEntityType.link) {
      return FileNode(
        path: normalizedPath,
        name: p.basename(normalizedPath),
        type: FileNodeType.link,
      );
    }

    final stat = await FileStat.stat(normalizedPath);
    return FileNode(
      path: normalizedPath,
      name: p.basename(normalizedPath),
      type: type == FileSystemEntityType.directory
          ? FileNodeType.directory
          : FileNodeType.file,
      size: type == FileSystemEntityType.file ? stat.size : null,
      modifiedAt: stat.modified,
    );
  }

  bool _isIgnoredDirectory(String name, Set<String> ignoredNames) {
    final lowerName = name.toLowerCase();
    return ignoredNames.any((ignored) => ignored.toLowerCase() == lowerName);
  }

  int _compareNodes(FileNode left, FileNode right) {
    if (left.isDirectory != right.isDirectory) {
      return left.isDirectory ? -1 : 1;
    }
    return left.name.toLowerCase().compareTo(right.name.toLowerCase());
  }

  String _normalize(String path) => p.normalize(p.absolute(path));
}

class BinaryFileException implements Exception {
  const BinaryFileException(this.path);

  final String path;

  @override
  String toString() => 'BinaryFileException: $path is not a UTF-8 text file';
}

class FileTooLargeException implements Exception {
  const FileTooLargeException(this.path, this.actualBytes, this.maximumBytes);

  final String path;
  final int actualBytes;
  final int maximumBytes;

  @override
  String toString() {
    return 'FileTooLargeException: $path has $actualBytes bytes, limit is '
        '$maximumBytes bytes';
  }
}

class ExternalFileChangeException implements Exception {
  const ExternalFileChangeException(this.path);

  final String path;

  @override
  String toString() => 'ExternalFileChangeException: $path changed on disk';
}
