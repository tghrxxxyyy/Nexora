import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../app_theme.dart';
import '../models/git_commit.dart';
import '../models/git_diff.dart';
import '../services/file_icon_resolver.dart';
import '../state/app_controller.dart';
import 'ui_primitives.dart';

class GitPanel extends StatefulWidget {
  const GitPanel({required this.controller, super.key});

  final AppController controller;

  @override
  State<GitPanel> createState() => _GitPanelState();
}

class _GitPanelState extends State<GitPanel> {
  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final workspace = controller.activeWorkspace;
    final status = controller.gitStatus;

    return PanelSurface(
      child: Column(
        children: [
          PanelLabel(
            label: 'Git',
            trailing: AppIconButton(
              icon: Icons.refresh_rounded,
              tooltip: '刷新',
              size: 27,
              iconSize: 14,
              onPressed: controller.gitLoading
                  ? null
                  : controller.refreshGitState,
            ),
          ),
          if (workspace == null)
            const Expanded(child: _EmptyState(message: '未打开工作区'))
          else if (controller.gitLoading && status == null)
            Expanded(
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.4,
                    color: AppColors.signal,
                  ),
                ),
              ),
            )
          else if (status == null)
            const Expanded(
              child: _EmptyState(message: '当前工作区不是 Git 仓库'),
            )
          else ...[
            _BranchHeader(status: status),
            SignalDivider(),
            Expanded(
              flex: 5,
              child: _CommitList(controller: controller),
            ),
            SignalDivider(),
            Expanded(
              flex: 7,
              child: _FileList(controller: controller),
            ),
          ],
        ],
      ),
    );
  }
}

class _BranchHeader extends StatelessWidget {
  const _BranchHeader({required this.status});

  final GitRepoStatus status;

  @override
  Widget build(BuildContext context) {
    final detached = status.detached;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 10, 8),
      child: Row(
        children: [
          Icon(
            detached ? Icons.call_split_rounded : Icons.account_tree_rounded,
            size: 14,
            color: AppColors.signal,
          ),
          const SizedBox(width: 7),
          Flexible(
            child: Text(
              status.branch,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: AppColors.text,
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (status.upstream != null) ...[
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                '↗ ${status.upstream}',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: AppColors.textDim,
                  fontSize: 10,
                ),
              ),
            ),
          ],
          const SizedBox(width: 6),
          if (status.ahead > 0)
            _Badge(label: '↑${status.ahead}', color: AppColors.signal),
          if (status.behind > 0) ...[
            const SizedBox(width: 3),
            _Badge(label: '↓${status.behind}', color: AppColors.signalDim),
          ],
          if (status.dirty) ...[
            const SizedBox(width: 6),
            _Badge(label: '修改', color: AppColors.amber),
          ],
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: color.withValues(alpha: 0.36), width: 0.5),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 9,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.1,
        ),
      ),
    );
  }
}

class _CommitList extends StatelessWidget {
  const _CommitList({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final commits = controller.gitCommits;
    final selectedSha = controller.gitSelectedSha;
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: commits.length + 1,
      itemExtent: 44,
      itemBuilder: (context, index) {
        if (index == 0) {
          return _WorkingTreeRow(
            selected: selectedSha == null,
            dirty: controller.gitStatus?.dirty ?? false,
            onTap: () => controller.selectGitDiffTarget(null),
          );
        }
        final commit = commits[index - 1];
        return _CommitRow(
          commit: commit,
          selected: selectedSha == commit.sha,
          onTap: () => controller.selectGitDiffTarget(commit.sha),
        );
      },
    );
  }
}

class _WorkingTreeRow extends StatefulWidget {
  const _WorkingTreeRow({
    required this.selected,
    required this.dirty,
    required this.onTap,
  });

  final bool selected;
  final bool dirty;
  final VoidCallback onTap;

  @override
  State<_WorkingTreeRow> createState() => _WorkingTreeRowState();
}

class _WorkingTreeRowState extends State<_WorkingTreeRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final selected = widget.selected;
    final background = selected
        ? AppColors.signal.withValues(alpha: 0.085)
        : _hovered
        ? AppColors.signal.withValues(alpha: 0.035)
        : Colors.transparent;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          color: background,
          child: Row(
            children: [
              Icon(
                Icons.edit_note_rounded,
                size: 16,
                color: selected ? AppColors.signal : AppColors.textMuted,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '工作区修改',
                      style: TextStyle(
                        color: selected
                            ? AppColors.text
                            : AppColors.textMuted,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      widget.dirty ? '尚未提交' : '无未提交修改',
                      style: TextStyle(
                        color:
                            widget.dirty ? AppColors.amber : AppColors.textDim,
                        fontSize: 9.5,
                      ),
                    ),
                  ],
                ),
              ),
              if (widget.dirty)
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: AppColors.amber,
                    shape: BoxShape.circle,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CommitRow extends StatefulWidget {
  const _CommitRow({
    required this.commit,
    required this.selected,
    required this.onTap,
  });

  final GitCommit commit;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_CommitRow> createState() => _CommitRowState();
}

class _CommitRowState extends State<_CommitRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final commit = widget.commit;
    final selected = widget.selected;
    final background = selected
        ? AppColors.signal.withValues(alpha: 0.085)
        : _hovered
        ? AppColors.signal.withValues(alpha: 0.035)
        : Colors.transparent;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          color: background,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Row(
                children: [
                  Text(
                    commit.shortSha,
                    style: TextStyle(
                      color: AppColors.signal,
                      fontSize: 9.5,
                      fontWeight: FontWeight.w700,
                      fontFamily: 'MapleMonoCN',
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      commit.author,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 9.5,
                      ),
                    ),
                  ),
                  Text(
                    _relativeTime(commit.authorDate),
                    style: TextStyle(
                      color: AppColors.textDim,
                      fontSize: 9,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 1),
              Text(
                commit.subject,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: AppColors.text,
                  fontSize: 11,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FileList extends StatelessWidget {
  const _FileList({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final files = controller.gitFileChanges;
    final activePath = controller.gitActiveDiff?.path;
    final selectedSha = controller.gitSelectedSha;
    final headerLabel = selectedSha == null
        ? '工作区修改 · ${files.length} 个文件'
        : '${files.length} 个文件已变更';
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 10, 4),
          child: Row(
            children: [
              Icon(
                Icons.difference_outlined,
                size: 13,
                color: AppColors.textMuted,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  headerLabel,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.2,
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: files.isEmpty
              ? const _EmptyState(
                  message: '无文件变更',
                  icon: Icons.check_rounded,
                )
              : ListView.builder(
                  padding: const EdgeInsets.only(top: 2, bottom: 6),
                  itemCount: files.length,
                  itemExtent: 30,
                  itemBuilder: (context, index) {
                    final change = files[index];
                    return _FileRow(
                      change: change,
                      selected: activePath == change.path,
                      onTap: () => controller.selectGitFile(change.path),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _FileRow extends StatefulWidget {
  const _FileRow({
    required this.change,
    required this.selected,
    required this.onTap,
  });

  final GitFileChange change;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_FileRow> createState() => _FileRowState();
}

class _FileRowState extends State<_FileRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final change = widget.change;
    final selected = widget.selected;
    final background = selected
        ? AppColors.signal.withValues(alpha: 0.09)
        : _hovered
        ? AppColors.surfaceHover.withValues(alpha: 0.55)
        : Colors.transparent;
    final (statusLabel, statusColor) = _statusVisual(change.status);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 0, 8, 0),
          color: background,
          child: Row(
            children: [
              SizedBox(
                width: 14,
                height: 14,
                child: _FileIcon(path: change.path),
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      change.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: selected
                            ? AppColors.text
                            : AppColors.text,
                        fontSize: 11,
                        fontWeight: selected
                            ? FontWeight.w600
                            : FontWeight.w400,
                      ),
                    ),
                    if (change.directory.isNotEmpty)
                      Text(
                        change.directory,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: AppColors.textDim,
                          fontSize: 9,
                          height: 1.1,
                        ),
                      ),
                  ],
                ),
              ),
              Container(
                width: 14,
                height: 14,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Text(
                  statusLabel,
                  style: TextStyle(
                    color: statusColor,
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    fontFamily: 'MapleMonoCN',
                    height: 1.1,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

(String, Color) _statusVisual(GitFileStatus status) {
  return switch (status) {
    GitFileStatus.added => ('A', AppColors.acid),
    GitFileStatus.modified => ('M', AppColors.amber),
    GitFileStatus.deleted => ('D', AppColors.coral),
    GitFileStatus.renamed => ('R', AppColors.signal),
    GitFileStatus.copied => ('C', AppColors.signalDim),
    GitFileStatus.typeChange => ('T', AppColors.signalDim),
    GitFileStatus.unmerged => ('U', AppColors.coral),
  };
}

class _FileIcon extends StatelessWidget {
  const _FileIcon({required this.path});

  final String path;

  @override
  Widget build(BuildContext context) {
    final visual = resolveFileVisual(
      FileIconContext(path: path, isDirectory: false),
    );
    if (visual.svgAssetKey != null) {
      return SvgPicture.asset(
        visual.svgAssetKey!,
        width: 13,
        height: 13,
        colorFilter: visual.tintSvg && visual.color != null
            ? ColorFilter.mode(visual.color!, BlendMode.srcIn)
            : null,
      );
    }
    return Icon(
      visual.icon ?? Icons.insert_drive_file_outlined,
      size: 12,
      color: visual.color ?? AppColors.textDim,
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.message, this.icon});

  final String message;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon ?? Icons.layers_clear_outlined,
            color: AppColors.textDim,
            size: 22,
          ),
          const SizedBox(height: 8),
          Text(
            message,
            style: TextStyle(color: AppColors.textDim, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

String _relativeTime(DateTime utcTime) {
  final now = DateTime.now().toUtc();
  final delta = now.difference(utcTime);
  if (delta.inSeconds < 60) return '刚刚';
  if (delta.inMinutes < 60) return '${delta.inMinutes}分钟前';
  if (delta.inHours < 24) return '${delta.inHours}小时前';
  if (delta.inDays < 7) return '${delta.inDays}天前';
  if (delta.inDays < 30) return '${(delta.inDays / 7).floor()}周前';
  final local = utcTime.toLocal();
  return '${local.year}-${local.month.toString().padLeft(2, '0')}-'
      '${local.day.toString().padLeft(2, '0')}';
}
