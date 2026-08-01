enum GitFileStatus { added, modified, deleted, renamed, copied, typeChange, unmerged }

enum GitDiffLineType { context, addition, deletion }

class GitDiffLine {
  const GitDiffLine({
    required this.type,
    required this.content,
    this.oldNumber,
    this.newNumber,
  });

  final GitDiffLineType type;
  final String content;
  final int? oldNumber;
  final int? newNumber;
}

class GitDiffHunk {
  const GitDiffHunk({
    required this.oldStart,
    required this.oldCount,
    required this.newStart,
    required this.newCount,
    required this.header,
    required this.lines,
  });

  final int oldStart;
  final int oldCount;
  final int newStart;
  final int newCount;
  final String header;
  final List<GitDiffLine> lines;
}

/// Parsed representation of a single file's diff. The [hunks] list is empty
/// for binary files (recognized via the `Binary files differ` marker).
class GitFileChange {
  const GitFileChange({
    required this.path,
    required this.status,
    required this.hunks,
    this.oldPath,
    this.binary = false,
  });

  final String path;
  final GitFileStatus status;
  final List<GitDiffHunk> hunks;
  final String? oldPath;
  final bool binary;

  String get displayName {
    final i = path.lastIndexOf('/');
    return i < 0 ? path : path.substring(i + 1);
  }

  String get directory {
    final i = path.lastIndexOf('/');
    return i < 0 ? '' : path.substring(0, i);
  }
}

/// Lightweight identifier for the diff currently shown in the editor area.
/// The full parsed content lives in [AppController.gitFileChanges] — this
/// class only carries enough to find it again after a re-render.
class GitDiffTarget {
  const GitDiffTarget({
    required this.sha,
    required this.path,
    required this.displayName,
    required this.status,
    this.oldPath,
  });

  /// `null` means the working tree (uncommitted changes), otherwise a
  /// full commit sha from [GitCommit.sha].
  final String? sha;
  final String path;
  final String displayName;
  final GitFileStatus status;
  final String? oldPath;

  String get shortSha => sha == null
      ? 'WORKING'
      : (sha!.length > 7 ? sha!.substring(0, 7) : sha!);
}
