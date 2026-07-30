import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/search_models.dart';
import 'text_file_codec.dart';

class GlobalSearchService {
  const GlobalSearchService({
    this.ignoredDirectoryNames = commonIgnoredDirectoryNames,
  });

  final Set<String> ignoredDirectoryNames;

  Future<SearchReport> search(
    Iterable<String> roots,
    String query, {
    SearchOptions options = const SearchOptions(),
  }) async {
    _validate(query, options);
    final expression = _buildExpression(query, options);
    final state = _SearchState();

    await _visitFiles(roots, options, state.errors, (filePath) async {
      final candidate = await _readCandidate(filePath, options, state);
      if (candidate == null) {
        return true;
      }

      var lineStartOffset = 0;
      final lines = candidate.content.split('\n');
      for (var lineIndex = 0; lineIndex < lines.length; lineIndex++) {
        final rawLine = lines[lineIndex];
        final line = rawLine.endsWith('\r')
            ? rawLine.substring(0, rawLine.length - 1)
            : rawLine;
        for (final match in expression.allMatches(line)) {
          state.results.add(
            SearchResult(
              filePath: filePath,
              lineNumber: lineIndex + 1,
              columnNumber: match.start + 1,
              lineText: line,
              matchedText: match.group(0) ?? '',
              startOffset: lineStartOffset + match.start,
              endOffset: lineStartOffset + match.end,
            ),
          );
          if (state.results.length >= options.maxResults) {
            state.truncated = true;
            return false;
          }
        }
        lineStartOffset += rawLine.length + 1;
      }
      return true;
    });

    return SearchReport(
      results: List<SearchResult>.unmodifiable(state.results),
      scannedFileCount: state.scannedFileCount,
      skippedBinaryFileCount: state.skippedBinaryFileCount,
      skippedLargeFileCount: state.skippedLargeFileCount,
      errors: List<String>.unmodifiable(state.errors),
      truncated: state.truncated,
    );
  }

  Future<ReplaceReport> replaceAll(
    Iterable<String> roots,
    String query,
    String replacement, {
    SearchOptions options = const SearchOptions(),
  }) async {
    _validate(query, options);
    final expression = _buildExpression(query, options);
    final state = _ReplaceState();

    await _visitFiles(roots, options, state.errors, (filePath) async {
      final candidate = await _readCandidate(filePath, options, state);
      if (candidate == null) {
        return true;
      }

      final matches = expression.allMatches(candidate.content).toList();
      if (matches.isEmpty) {
        return true;
      }
      if (matches.any((match) => match.start == match.end)) {
        state.errors.add(
          '$filePath: replacement expressions must not match empty text',
        );
        return true;
      }

      final updatedContent = candidate.content.replaceAllMapped(
        expression,
        (match) => options.useRegularExpression
            ? _expandReplacement(replacement, match)
            : replacement,
      );
      if (updatedContent == candidate.content) {
        return true;
      }

      try {
        final currentStat = await File(filePath).stat();
        final changedOnDisk =
            currentStat.size != candidate.stat.size ||
            !currentStat.modified.isAtSameMomentAs(candidate.stat.modified);
        if (changedOnDisk) {
          state.errors.add('$filePath: changed while replacement was running');
          return true;
        }
        await File(filePath).writeAsBytes(
          TextFileCodec.encode(
            updatedContent,
            includeUtf8Bom: candidate.hasUtf8Bom,
          ),
          flush: true,
        );
        state.changedFileCount++;
        state.replacementCount += matches.length;
      } on FileSystemException catch (error) {
        state.errors.add('$filePath: ${error.message}');
      }
      return true;
    });

    return ReplaceReport(
      changedFileCount: state.changedFileCount,
      replacementCount: state.replacementCount,
      scannedFileCount: state.scannedFileCount,
      skippedBinaryFileCount: state.skippedBinaryFileCount,
      skippedLargeFileCount: state.skippedLargeFileCount,
      errors: List<String>.unmodifiable(state.errors),
    );
  }

  Future<void> _visitFiles(
    Iterable<String> roots,
    SearchOptions options,
    List<String> errors,
    Future<bool> Function(String path) visitor,
  ) async {
    final visited = <String>{};
    final excludedPaths = options.excludedPaths.map(_normalize).toSet();
    for (final root in roots) {
      final shouldContinue = await _visitPath(
        _normalize(root),
        options,
        excludedPaths,
        visited,
        errors,
        visitor,
      );
      if (!shouldContinue) {
        return;
      }
    }
  }

  Future<bool> _visitPath(
    String entityPath,
    SearchOptions options,
    Set<String> excludedPaths,
    Set<String> visited,
    List<String> errors,
    Future<bool> Function(String path) visitor,
  ) async {
    if (!visited.add(entityPath) || _isExcluded(entityPath, excludedPaths)) {
      return true;
    }

    final type = await FileSystemEntity.type(entityPath, followLinks: false);
    if (type == FileSystemEntityType.file) {
      if (_extensionAllowed(entityPath, options.includedExtensions)) {
        return visitor(entityPath);
      }
      return true;
    }
    if (type != FileSystemEntityType.directory) {
      return true;
    }

    try {
      await for (final entity in Directory(
        entityPath,
      ).list(followLinks: false)) {
        final childPath = _normalize(entity.path);
        final childType = await FileSystemEntity.type(
          childPath,
          followLinks: false,
        );
        if (childType == FileSystemEntityType.directory &&
            _isIgnoredDirectory(p.basename(childPath))) {
          continue;
        }
        final shouldContinue = await _visitPath(
          childPath,
          options,
          excludedPaths,
          visited,
          errors,
          visitor,
        );
        if (!shouldContinue) {
          return false;
        }
      }
    } on FileSystemException catch (error) {
      errors.add('$entityPath: ${error.message}');
    }
    return true;
  }

  Future<_TextCandidate?> _readCandidate(
    String filePath,
    SearchOptions options,
    _OperationState state,
  ) async {
    state.scannedFileCount++;
    try {
      final file = File(filePath);
      final statBeforeRead = await file.stat();
      if (statBeforeRead.size > options.maxFileBytes) {
        state.skippedLargeFileCount++;
        return null;
      }
      final bytes = await file.readAsBytes();
      final statAfterRead = await file.stat();
      if (statBeforeRead.size != statAfterRead.size ||
          !statBeforeRead.modified.isAtSameMomentAs(statAfterRead.modified)) {
        state.errors.add('$filePath: changed while it was being read');
        return null;
      }
      final decoded = TextFileCodec.tryDecode(bytes);
      if (decoded == null) {
        state.skippedBinaryFileCount++;
        return null;
      }
      return _TextCandidate(
        content: decoded.content,
        hasUtf8Bom: decoded.hasUtf8Bom,
        stat: statAfterRead,
      );
    } on FileSystemException catch (error) {
      state.errors.add('$filePath: ${error.message}');
      return null;
    }
  }

  RegExp _buildExpression(String query, SearchOptions options) {
    var source = options.useRegularExpression ? query : RegExp.escape(query);
    if (options.wholeWord) {
      source = r'(?<![A-Za-z0-9_])(?:' + source + r')(?![A-Za-z0-9_])';
    }
    try {
      return RegExp(
        source,
        caseSensitive: options.caseSensitive,
        unicode: true,
      );
    } on FormatException catch (error) {
      throw ArgumentError.value(query, 'query', error.message);
    }
  }

  String _expandReplacement(String replacement, Match match) {
    return replacement.replaceAllMapped(RegExp(r'\$(\$|\{\d+\}|\d+)'), (token) {
      final value = token.group(1)!;
      if (value == r'$') {
        return r'$';
      }
      final groupText = value.startsWith('{')
          ? value.substring(1, value.length - 1)
          : value;
      final groupIndex = int.parse(groupText);
      if (groupIndex > match.groupCount) {
        return '';
      }
      return match.group(groupIndex) ?? '';
    });
  }

  void _validate(String query, SearchOptions options) {
    if (query.isEmpty) {
      throw ArgumentError.value(query, 'query', 'must not be empty');
    }
    if (options.maxFileBytes <= 0) {
      throw ArgumentError.value(options.maxFileBytes, 'maxFileBytes');
    }
    if (options.maxResults <= 0) {
      throw ArgumentError.value(options.maxResults, 'maxResults');
    }
  }

  bool _isIgnoredDirectory(String name) {
    final lowerName = name.toLowerCase();
    return ignoredDirectoryNames.any(
      (ignoredName) => ignoredName.toLowerCase() == lowerName,
    );
  }

  bool _extensionAllowed(String path, Set<String> includedExtensions) {
    if (includedExtensions.isEmpty) {
      return true;
    }
    final extension = p.extension(path).toLowerCase().replaceFirst('.', '');
    return includedExtensions.any(
      (included) => included.toLowerCase().replaceFirst('.', '') == extension,
    );
  }

  bool _isExcluded(String path, Set<String> excludedPaths) {
    return excludedPaths.any(
      (excluded) => path == excluded || p.isWithin(excluded, path),
    );
  }

  String _normalize(String path) => p.normalize(p.absolute(path));
}

class _TextCandidate {
  const _TextCandidate({
    required this.content,
    required this.hasUtf8Bom,
    required this.stat,
  });

  final String content;
  final bool hasUtf8Bom;
  final FileStat stat;
}

abstract class _OperationState {
  int scannedFileCount = 0;
  int skippedBinaryFileCount = 0;
  int skippedLargeFileCount = 0;
  final List<String> errors = <String>[];
}

class _SearchState extends _OperationState {
  final List<SearchResult> results = <SearchResult>[];
  bool truncated = false;
}

class _ReplaceState extends _OperationState {
  int changedFileCount = 0;
  int replacementCount = 0;
}
