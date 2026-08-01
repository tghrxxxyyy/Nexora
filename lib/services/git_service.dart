import 'dart:io';

import '../models/git_commit.dart';
import '../models/git_diff.dart';
import 'git_diff_parser.dart';

/// Wraps the system `git` CLI for read-only inspection of the active
/// workspace's repository. Every command is invoked with `-C <root>` so the
/// caller can pass either the repository root or any subdirectory; we resolve
/// the actual top-level via `rev-parse --show-toplevel` first.
class GitService {
  const GitService();

  /// Returns the repository top-level path containing [workspacePath], or
  /// `null` if the path is not inside a git working tree (or git is missing).
  Future<String?> findRepositoryRoot(String workspacePath) async {
    final result = await _run(workspacePath, ['rev-parse', '--show-toplevel']);
    if (result.exitCode != 0) return null;
    final out = (result.stdout as String).trim();
    if (out.isEmpty || out.startsWith('fatal:')) return null;
    return out;
  }

  /// Snapshots the current branch, dirty flags, and upstream ahead/behind
  /// counters. Returns `null` if [repoRoot] is not a valid repository.
  Future<GitRepoStatus?> getStatus(String repoRoot) async {
    final branchRes = await _run(repoRoot, ['symbolic-ref', '--quiet', '--short', 'HEAD']);
    final detached = branchRes.exitCode != 0;
    String branch;
    if (detached) {
      final head = await _run(repoRoot, ['rev-parse', '--short', 'HEAD']);
      branch = head.exitCode == 0
          ? (head.stdout as String).trim()
          : 'HEAD';
    } else {
      branch = (branchRes.stdout as String).trim();
    }

    final statusRes = await _run(
      repoRoot,
      ['status', '--porcelain', '--untracked-files=normal'],
    );
    final statusLines = (statusRes.stdout as String)
        .split('\n')
        .where((l) => l.trim().isNotEmpty);
    var stagedDirty = false;
    var workingTreeDirty = false;
    for (final line in statusLines) {
      if (line.length < 2) continue;
      final x = line[0];
      final y = line[1];
      if (x != ' ' && x != '?') stagedDirty = true;
      if (y != ' ' && y != '?') workingTreeDirty = true;
    }

    var ahead = 0;
    var behind = 0;
    String? upstream;
    final abRes = await _run(
      repoRoot,
      ['rev-list', '--left-right', '--count', 'HEAD...@{upstream}'],
    );
    if (abRes.exitCode == 0) {
      final parts = (abRes.stdout as String).trim().split(RegExp(r'\s+'));
      if (parts.length == 2) {
        ahead = int.tryParse(parts[0]) ?? 0;
        behind = int.tryParse(parts[1]) ?? 0;
      }
      final upRes = await _run(
        repoRoot,
        ['rev-parse', '--abbrev-ref', '--symbolic-full-name', '@{upstream}'],
      );
      if (upRes.exitCode == 0) {
        upstream = (upRes.stdout as String).trim();
        if (upstream.isEmpty) upstream = null;
      }
    }

    return GitRepoStatus(
      rootPath: repoRoot,
      branch: branch,
      detached: detached,
      workingTreeDirty: workingTreeDirty,
      stagedDirty: stagedDirty,
      ahead: ahead,
      behind: behind,
      upstream: upstream,
    );
  }

  /// Fetches the most recent [limit] commits on the current branch
  /// (first-parent), newest first.
  Future<List<GitCommit>> getRecentCommits(
    String repoRoot, {
    int limit = 100,
  }) async {
    const fieldSep = '\x1f';
    const recordSep = '\x1e';
    final format = [
      '%H', '%h', '%an', '%ae', '%at', '%s', '%b',
    ].join(fieldSep);
    final res = await _run(repoRoot, [
      'log',
      '-n', '$limit',
      '--first-parent',
      '--no-decorate',
      '--no-color',
      '--pretty=format:$format$recordSep',
    ]);
    if (res.exitCode != 0) return const [];

    final output = res.stdout as String;
    final commits = <GitCommit>[];
    for (final raw in output.split(recordSep)) {
      final record = raw.trim();
      if (record.isEmpty) continue;
      final parts = record.split(fieldSep);
      if (parts.length < 6) continue;
      final sha = parts[0];
      final shortSha = parts[1];
      final author = parts[2];
      final email = parts[3];
      final timestamp = int.tryParse(parts[4]) ?? 0;
      final subject = parts[5];
      final body = parts.length > 6 ? parts[6].trim() : '';
      commits.add(GitCommit(
        sha: sha,
        shortSha: shortSha,
        author: author,
        email: email,
        authorDate: DateTime.fromMillisecondsSinceEpoch(
          timestamp * 1000,
          isUtc: true,
        ),
        subject: subject,
        body: body,
      ));
    }
    return List<GitCommit>.unmodifiable(commits);
  }

  /// Returns the combined diff (text) for the given commit — i.e. what
  /// `git show <sha>` would print, minus the metadata header.
  Future<String> getCommitDiff(String repoRoot, String sha) async {
    final res = await _run(repoRoot, [
      'show',
      '--no-color',
      '--first-parent',
      '--format=',
      sha,
    ]);
    if (res.exitCode != 0) return '';
    return res.stdout as String;
  }

  /// Returns the diff between `HEAD` and the working tree (both staged and
  /// unstaged changes for tracked files). Untracked files are not included.
  Future<String> getWorkingTreeDiff(String repoRoot) async {
    final res = await _run(repoRoot, ['diff', 'HEAD', '--no-color']);
    if (res.exitCode == 0) return res.stdout as String;
    final fallback = await _run(repoRoot, ['diff', '--no-color']);
    return fallback.stdout as String;
  }

  /// Returns structured file-level changes for either the working tree
  /// (when [sha] is `null`) or a specific commit. Each [GitFileChange]
  /// carries its parsed hunks ready for split-view rendering.
  Future<List<GitFileChange>> getFileChanges(
    String repoRoot, {
    String? sha,
  }) async {
    final raw = sha == null
        ? await getWorkingTreeDiff(repoRoot)
        : await getCommitDiff(repoRoot, sha);
    return const GitDiffParser().parse(raw);
  }

  Future<ProcessResult> _run(String cwd, List<String> args) {
    return Process.run('git', ['-C', cwd, ...args]);
  }
}
