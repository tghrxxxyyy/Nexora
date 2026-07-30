import 'package:flutter/material.dart';
import 'package:re_editor/re_editor.dart';

import '../app_theme.dart';

class EditorContextMenuController implements SelectionToolbarController {
  const EditorContextMenuController();

  @override
  void hide(BuildContext context) {}

  @override
  void show({
    required BuildContext context,
    required CodeLineEditingController controller,
    required TextSelectionToolbarAnchors anchors,
    Rect? renderRect,
    required LayerLink layerLink,
    required ValueNotifier<bool> visibility,
  }) {
    showMenu<void>(
      context: context,
      color: AppColors.surfaceRaised,
      position: RelativeRect.fromSize(
        anchors.primaryAnchor & const Size(170, double.infinity),
        MediaQuery.sizeOf(context),
      ),
      items: [
        _item('剪切', Icons.content_cut_rounded, controller.cut),
        _item('复制', Icons.content_copy_rounded, controller.copy),
        _item('粘贴', Icons.content_paste_rounded, controller.paste),
        _item('全选', Icons.select_all_rounded, controller.selectAll),
      ],
    );
  }

  PopupMenuItem<void> _item(String label, IconData icon, VoidCallback action) {
    return PopupMenuItem<void>(
      height: 36,
      onTap: action,
      child: Row(
        children: [
          Icon(icon, size: 15, color: AppColors.textMuted),
          const SizedBox(width: 10),
          Text(label),
        ],
      ),
    );
  }
}
