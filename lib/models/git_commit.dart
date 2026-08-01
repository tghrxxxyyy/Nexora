class GitCommit {
  const GitCommit({
    required this.sha,
    required this.shortSha,
    required this.author,
    required this.email,
    required this.authorDate,
    required this.subject,
    this.body = '',
  });

  final String sha;
  final String shortSha;
  final String author;
  final String email;
  final DateTime authorDate;
  final String subject;
  final String body;
}

class GitRepoStatus {
  const GitRepoStatus({
    required this.rootPath,
    required this.branch,
    required this.detached,
    required this.workingTreeDirty,
    required this.stagedDirty,
    required this.ahead,
    required this.behind,
    this.upstream,
  });

  final String rootPath;
  final String branch;
  final bool detached;
  final bool workingTreeDirty;
  final bool stagedDirty;
  final int ahead;
  final int behind;
  final String? upstream;

  bool get dirty => workingTreeDirty || stagedDirty;
}
