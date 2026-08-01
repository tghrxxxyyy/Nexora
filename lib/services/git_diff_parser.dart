import '../models/git_diff.dart';

/// Parses unified `git diff` output into structured [GitFileChange]s. Each
/// file block becomes a [GitFileChange] with its [GitDiffHunk]s fully tokenized
/// into typed [GitDiffLine]s, ready for a side-by-side renderer.
class GitDiffParser {
  const GitDiffParser();

  List<GitFileChange> parse(String diff) {
    final files = <GitFileChange>[];
    if (diff.isEmpty) return files;
    final lines = diff.split('\n');

    var i = 0;
    while (i < lines.length) {
      if (!_isDiffHeader(lines[i])) {
        i++;
        continue;
      }
      // Always consume the header line so the outer loop makes progress —
      // otherwise a diff consisting of a single empty file would loop
      // forever re-reading the same header.
      final block = <String>[lines[i]];
      i++;
      while (i < lines.length && !_isDiffHeader(lines[i])) {
        block.add(lines[i]);
        i++;
      }
      final file = _parseFileBlock(block);
      if (file != null) files.add(file);
    }
    return List<GitFileChange>.unmodifiable(files);
  }

  bool _isDiffHeader(String line) => line.startsWith('diff --git ');

  GitFileChange? _parseFileBlock(List<String> lines) {
    var status = GitFileStatus.modified;
    String? oldPath;
    String? newPath;
    var binary = false;

    for (final line in lines) {
      if (line.startsWith('new file mode')) {
        status = GitFileStatus.added;
      } else if (line.startsWith('deleted file mode')) {
        status = GitFileStatus.deleted;
      } else if (line.startsWith('rename from')) {
        status = GitFileStatus.renamed;
        oldPath = line.substring('rename from '.length);
      } else if (line.startsWith('rename to')) {
        status = GitFileStatus.renamed;
        newPath = line.substring('rename to '.length);
      } else if (line.startsWith('copy from')) {
        status = GitFileStatus.copied;
        oldPath = line.substring('copy from '.length);
      } else if (line.startsWith('copy to')) {
        status = GitFileStatus.copied;
        newPath = line.substring('copy to '.length);
      } else if (line.startsWith('old mode') || line.startsWith('new mode')) {
        status = GitFileStatus.typeChange;
      } else if (line.startsWith('--- ')) {
        final rest = line.substring(4);
        if (rest != '/dev/null') {
          oldPath = _stripPrefix(rest);
        }
      } else if (line.startsWith('+++ ')) {
        final rest = line.substring(4);
        if (rest != '/dev/null') {
          newPath = _stripPrefix(rest);
        }
      } else if (line.startsWith('Binary files') ||
          line.startsWith('GIT binary patch')) {
        binary = true;
      }
    }

    // For `diff --git a/x b/x` lines the paths are unreliable when spaces are
    // involved, so we prefer the ---/+++ lines and fall back to the header.
    if (newPath == null && oldPath == null) {
      final header = lines.firstWhere(
        (l) => l.startsWith('diff --git '),
        orElse: () => '',
      );
      final match = RegExp(r'^diff --git a/(.+) b/(.+)$').firstMatch(header);
      if (match != null) {
        oldPath ??= match.group(1);
        newPath ??= match.group(2);
      }
    }

    final path = newPath ?? oldPath;
    if (path == null || path.isEmpty) return null;

    final hunks = binary ? const <GitDiffHunk>[] : _parseHunks(lines);

    return GitFileChange(
      path: path,
      status: status,
      hunks: hunks,
      oldPath: status == GitFileStatus.renamed ||
              status == GitFileStatus.copied
          ? oldPath
          : null,
      binary: binary,
    );
  }

  /// Strips the conventional `a/` / `b/` prefix git adds to diff paths. Falls
  /// back to the raw string when the prefix is absent (e.g. when the user
  /// configured `diff.noprefix`).
  String _stripPrefix(String path) {
    if (path.startsWith('a/') || path.startsWith('b/')) return path.substring(2);
    return path;
  }

  List<GitDiffHunk> _parseHunks(List<String> lines) {
    final hunks = <GitDiffHunk>[];
    GitDiffHunk? current;
    final buffer = <GitDiffLine>[];
    var oldLine = 0;
    var newLine = 0;

    void flush() {
      if (current == null) return;
      hunks.add(GitDiffHunk(
        oldStart: current!.oldStart,
        oldCount: current!.oldCount,
        newStart: current!.newStart,
        newCount: current!.newCount,
        header: current!.header,
        lines: List<GitDiffLine>.unmodifiable(buffer),
      ));
      current = null;
      buffer.clear();
    }

    for (final line in lines) {
      final m = RegExp(
        r'^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@',
      ).firstMatch(line);
      if (m != null) {
        flush();
        final oldStart = int.parse(m.group(1)!);
        final oldCount = m.group(2) != null ? int.parse(m.group(2)!) : 1;
        final newStart = int.parse(m.group(3)!);
        final newCount = m.group(4) != null ? int.parse(m.group(4)!) : 1;
        current = GitDiffHunk(
          oldStart: oldStart,
          oldCount: oldCount,
          newStart: newStart,
          newCount: newCount,
          header: line,
          lines: const [],
        );
        oldLine = oldStart;
        newLine = newStart;
        continue;
      }
      if (current == null) continue;
      if (line.isEmpty) continue;
      final prefix = line[0];
      if (prefix == '+') {
        buffer.add(GitDiffLine(
          type: GitDiffLineType.addition,
          content: line.substring(1),
          newNumber: newLine,
        ));
        newLine++;
      } else if (prefix == '-') {
        buffer.add(GitDiffLine(
          type: GitDiffLineType.deletion,
          content: line.substring(1),
          oldNumber: oldLine,
        ));
        oldLine++;
      } else if (prefix == '\\') {
        // "\ No newline at end of file" — metadata, skip.
        continue;
      } else {
        // Context line — strip the leading space git emits.
        buffer.add(GitDiffLine(
          type: GitDiffLineType.context,
          content: line.substring(1),
          oldNumber: oldLine,
          newNumber: newLine,
        ));
        oldLine++;
        newLine++;
      }
    }
    flush();
    return hunks;
  }
}
