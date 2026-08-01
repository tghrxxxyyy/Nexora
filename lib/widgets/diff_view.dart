import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../models/git_diff.dart';
import '../state/app_controller.dart';
import 'ui_primitives.dart';

/// Renders a side-by-side diff for the file currently selected in the Git
/// panel. Replaces the document area while [AppController.gitActiveDiff] is
/// non-null. The two columns scroll together because they share a single
/// vertical [ListView] and each row paints both halves.
class DiffView extends StatelessWidget {
  const DiffView({required this.controller, super.key});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final target = controller.gitActiveDiff;
    final change = controller.lookupActiveGitFileChange();
    return Column(
      children: [
        _DiffHeader(
          target: target!,
          onClose: controller.closeGitDiff,
        ),
        SignalDivider(),
        Expanded(
          child: change == null
              ? const _EmptyState(
                  message: '差异内容已过期，请刷新 Git 面板后重试',
                  icon: Icons.history_rounded,
                )
              : change.binary
                  ? const _EmptyState(
                      message: '二进制文件无法显示差异',
                      icon: Icons.block_rounded,
                    )
                  : change.hunks.isEmpty
                      ? const _EmptyState(
                          message: '此文件没有文本差异',
                          icon: Icons.check_rounded,
                        )
                      : _DiffBody(change: change),
        ),
      ],
    );
  }
}

class _DiffHeader extends StatelessWidget {
  const _DiffHeader({required this.target, required this.onClose});

  final GitDiffTarget target;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      color: AppColors.backgroundRaised,
      child: Row(
        children: [
          _StatusBadge(status: target.status),
          const SizedBox(width: 9),
          Flexible(
            child: Text(
              target.path,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: AppColors.text,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (target.oldPath != null) ...[
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                '← ${target.oldPath}',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: AppColors.textDim,
                  fontSize: 11,
                ),
              ),
            ),
          ],
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: AppColors.signal.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(3),
            ),
            child: Text(
              target.shortSha,
              style: TextStyle(
                color: AppColors.signal,
                fontSize: 9.5,
                fontWeight: FontWeight.w700,
                fontFamily: 'MapleMonoCN',
                letterSpacing: 0.3,
              ),
            ),
          ),
          const Spacer(),
          AppIconButton(
            icon: Icons.close_rounded,
            tooltip: '关闭差异视图',
            size: 28,
            iconSize: 16,
            onPressed: onClose,
          ),
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});

  final GitFileStatus status;

  @override
  Widget build(BuildContext context) {
    final (label, color, icon) = switch (status) {
      GitFileStatus.added => ('新增', AppColors.acid, Icons.add_rounded),
      GitFileStatus.modified => ('修改', AppColors.amber, Icons.edit_rounded),
      GitFileStatus.deleted => ('删除', AppColors.coral, Icons.remove_rounded),
      GitFileStatus.renamed => ('重命名', AppColors.signal, Icons.drive_file_rename_outline_rounded),
      GitFileStatus.copied => ('复制', AppColors.signalDim, Icons.copy_all_rounded),
      GitFileStatus.typeChange => ('类型', AppColors.signalDim, Icons.swap_horiz_rounded),
      GitFileStatus.unmerged => ('冲突', AppColors.coral, Icons.warning_amber_rounded),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: color.withValues(alpha: 0.42), width: 0.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10, color: color),
          const SizedBox(width: 3),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 9.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}

class _DiffBody extends StatelessWidget {
  const _DiffBody({required this.change});

  final GitFileChange change;

  @override
  Widget build(BuildContext context) {
    final rows = <_RowSpec>[];
    for (final hunk in change.hunks) {
      rows.add(_RowSpec.header(hunk.header));
      for (final aligned in _align(hunk)) {
        rows.add(_RowSpec.line(aligned));
      }
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: rows.length,
      itemBuilder: (context, index) {
        final row = rows[index];
        if (row.header != null) {
          return _HunkHeaderRow(text: row.header!);
        }
        return _DiffRow(line: row.line!);
      },
    );
  }

  /// Pairs consecutive `-` runs with the `+` runs that follow them so that
  /// the left and right columns stay row-aligned. Pure insertions or
  /// deletions fill the missing side with `null`, which renders as a dimmed
  /// placeholder cell.
  List<_AlignedLine> _align(GitDiffHunk hunk) {
    final out = <_AlignedLine>[];
    final lines = hunk.lines;
    var i = 0;
    while (i < lines.length) {
      final line = lines[i];
      if (line.type == GitDiffLineType.context) {
        out.add(_AlignedLine(left: line, right: line));
        i++;
        continue;
      }
      final dels = <GitDiffLine>[];
      while (i < lines.length && lines[i].type == GitDiffLineType.deletion) {
        dels.add(lines[i]);
        i++;
      }
      final adds = <GitDiffLine>[];
      while (i < lines.length && lines[i].type == GitDiffLineType.addition) {
        adds.add(lines[i]);
        i++;
      }
      if (dels.isEmpty && adds.isEmpty) {
        // Unrecognized prefix; skip defensively.
        i++;
        continue;
      }
      final pairCount = dels.length > adds.length ? dels.length : adds.length;
      for (var j = 0; j < pairCount; j++) {
        out.add(_AlignedLine(
          left: j < dels.length ? dels[j] : null,
          right: j < adds.length ? adds[j] : null,
        ));
      }
    }
    return out;
  }
}

class _RowSpec {
  _RowSpec.header(this.header) : line = null;
  _RowSpec.line(this.line) : header = null;

  final String? header;
  final _AlignedLine? line;
}

class _AlignedLine {
  const _AlignedLine({required this.left, required this.right});

  final GitDiffLine? left;
  final GitDiffLine? right;
}

class _HunkHeaderRow extends StatelessWidget {
  const _HunkHeaderRow({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      color: AppColors.signal.withValues(alpha: 0.08),
      child: Text(
        text,
        style: TextStyle(
          color: AppColors.signal,
          fontSize: 10.5,
          fontFamily: 'MapleMonoCN',
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _DiffRow extends StatelessWidget {
  const _DiffRow({required this.line});

  final _AlignedLine line;

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: _cell(line.left, side: _Side.left)),
          Container(width: 1, color: AppColors.lineStrong),
          Expanded(child: _cell(line.right, side: _Side.right)),
        ],
      ),
    );
  }

  Widget _cell(GitDiffLine? line, {_Side side = _Side.right}) {
    if (line == null) {
      return Container(
        color: AppColors.surface.withValues(alpha: 0.45),
        child: Row(
          children: [
            SizedBox(width: _Gutter.width),
            Container(width: 1, color: AppColors.line),
            const Expanded(child: SizedBox()),
          ],
        ),
      );
    }
    final isDeletion = line.type == GitDiffLineType.deletion;
    final isAddition = line.type == GitDiffLineType.addition;
    final bg = isDeletion
        ? AppColors.coral.withValues(alpha: 0.11)
        : isAddition
        ? AppColors.acid.withValues(alpha: 0.11)
        : Colors.transparent;
    final fg = isDeletion
        ? AppColors.coral
        : isAddition
        ? AppColors.acid
        : AppColors.text;
    final number = side == _Side.left ? line.oldNumber : line.newNumber;
    return Container(
      color: bg,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Gutter(number: number),
          Container(width: 1, color: AppColors.line),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(6, 1, 6, 1),
              child: SelectableText(
                line.content.isEmpty ? ' ' : line.content,
                style: TextStyle(
                  color: fg,
                  fontSize: 11.5,
                  fontFamily: 'MapleMonoCN',
                  height: 1.4,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

enum _Side { left, right }

class _Gutter extends StatelessWidget {
  const _Gutter({required this.number});

  final int? number;

  static const double width = 46;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: number == null
          ? const SizedBox.expand()
          : Padding(
              padding: const EdgeInsets.only(right: 5, top: 1),
              child: Text(
                '$number',
                textAlign: TextAlign.right,
                style: TextStyle(
                  color: AppColors.textDim,
                  fontSize: 10,
                  fontFamily: 'MapleMonoCN',
                  height: 1.4,
                ),
              ),
            ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.message, required this.icon});

  final String message;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: AppColors.textDim, size: 26),
          const SizedBox(height: 8),
          Text(
            message,
            style: TextStyle(color: AppColors.textDim, fontSize: 11.5),
          ),
        ],
      ),
    );
  }
}
