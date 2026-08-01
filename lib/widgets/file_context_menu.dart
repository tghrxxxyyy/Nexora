import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../state/app_controller.dart';

/// Shows the standard file / directory context menu used by both the sidebar
/// tree and the editor tab bar. The four actions are the same set the user
/// sees when right-clicking a file in VSCode: paste-able copy of the file
/// itself, reveal in the native file manager, and copying the relative or
/// absolute path.
Future<void> showFileContextMenu({
  required BuildContext context,
  required Offset position,
  required AppController controller,
  required String path,
  bool isDirectory = false,
}) async {
  final selected = await showMenu<_FileContextAction>(
    context: context,
    position: RelativeRect.fromLTRB(
      position.dx,
      position.dy,
      position.dx,
      position.dy,
    ),
    items: [
      PopupMenuItem(
        value: _FileContextAction.copyFile,
        height: 32,
        child: _MenuItemRow(
          icon: Icons.content_copy_rounded,
          label: isDirectory ? '复制文件夹' : '复制文件',
        ),
      ),
      PopupMenuItem(
        value: _FileContextAction.reveal,
        height: 32,
        child: const _MenuItemRow(
          icon: Icons.folder_open_rounded,
          label: '在 Finder 中显示',
        ),
      ),
      const PopupMenuDivider(height: 4),
      const PopupMenuItem(
        value: _FileContextAction.copyRelative,
        height: 32,
        child: _MenuItemRow(
          icon: Icons.link_rounded,
          label: '复制相对路径',
        ),
      ),
      const PopupMenuItem(
        value: _FileContextAction.copyAbsolute,
        height: 32,
        child: _MenuItemRow(
          icon: Icons.description_outlined,
          label: '复制绝对路径',
        ),
      ),
    ],
  );
  if (selected == null) return;
  switch (selected) {
    case _FileContextAction.copyFile:
      await controller.copyFileToClipboard(path);
      break;
    case _FileContextAction.reveal:
      await controller.revealInFileManager(path);
      break;
    case _FileContextAction.copyRelative:
      await controller.copyRelativePath(path);
      break;
    case _FileContextAction.copyAbsolute:
      await controller.copyAbsolutePath(path);
      break;
  }
}

enum _FileContextAction { copyFile, reveal, copyRelative, copyAbsolute }

class _MenuItemRow extends StatelessWidget {
  const _MenuItemRow({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 14, color: AppColors.textMuted),
        const SizedBox(width: 9),
        Text(label, style: TextStyle(color: AppColors.text, fontSize: 11.5)),
      ],
    );
  }
}
