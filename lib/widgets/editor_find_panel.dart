import 'package:flutter/material.dart';
import 'package:re_editor/re_editor.dart';

import '../app_theme.dart';
import 'ui_primitives.dart';

class EditorFindPanel extends StatelessWidget implements PreferredSizeWidget {
  const EditorFindPanel({
    required this.controller,
    required this.readOnly,
    super.key,
  });

  final CodeFindController controller;
  final bool readOnly;

  @override
  Size get preferredSize {
    final value = controller.value;
    if (value == null) return Size.zero;
    return Size.fromHeight(value.replaceMode ? 84 : 46);
  }

  @override
  Widget build(BuildContext context) {
    final value = controller.value;
    if (value == null) return const SizedBox.shrink();
    final result = value.result;
    final resultText = result == null
        ? '0 / 0'
        : '${result.index + 1} / ${result.matches.length}';

    return Align(
      alignment: Alignment.topRight,
      child: Container(
        width: 430,
        margin: const EdgeInsets.only(top: 7, right: 12),
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              AppColors.surfaceRaised.withValues(alpha: 0.98),
              AppColors.surface.withValues(alpha: 0.97),
              AppColors.backgroundRaised.withValues(alpha: 0.98),
            ],
          ),
          borderRadius: BorderRadius.circular(5),
          boxShadow: [
            BoxShadow(
              color: AppColors.background.withValues(alpha: 0.48),
              blurRadius: 20,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 30,
                    child: TextField(
                      controller: controller.findInputController,
                      focusNode: controller.findInputFocusNode,
                      textAlignVertical: TextAlignVertical.center,
                      style: const TextStyle(fontSize: 12),
                      decoration: const InputDecoration(
                        hintText: '查找',
                        contentPadding: EdgeInsets.symmetric(horizontal: 9),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 5),
                _ToggleText(
                  label: 'Aa',
                  tooltip: '区分大小写',
                  selected: value.option.caseSensitive,
                  onTap: controller.toggleCaseSensitive,
                ),
                _ToggleText(
                  label: '.*',
                  tooltip: '正则表达式',
                  selected: value.option.regex,
                  onTap: controller.toggleRegex,
                ),
                SizedBox(
                  width: 51,
                  child: Text(
                    resultText,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppColors.textDim,
                      fontSize: 10,
                      fontFamily: 'MapleMonoCN',
                    ),
                  ),
                ),
                AppIconButton(
                  icon: Icons.keyboard_arrow_up_rounded,
                  tooltip: '上一个',
                  size: 28,
                  iconSize: 16,
                  onPressed: result == null ? null : controller.previousMatch,
                ),
                AppIconButton(
                  icon: Icons.keyboard_arrow_down_rounded,
                  tooltip: '下一个',
                  size: 28,
                  iconSize: 16,
                  onPressed: result == null ? null : controller.nextMatch,
                ),
                AppIconButton(
                  icon: Icons.close_rounded,
                  tooltip: '关闭',
                  size: 28,
                  iconSize: 15,
                  onPressed: controller.close,
                ),
              ],
            ),
            if (value.replaceMode) ...[
              const SizedBox(height: 5),
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 30,
                      child: TextField(
                        controller: controller.replaceInputController,
                        focusNode: controller.replaceInputFocusNode,
                        textAlignVertical: TextAlignVertical.center,
                        style: const TextStyle(fontSize: 12),
                        decoration: const InputDecoration(
                          hintText: '替换为',
                          contentPadding: EdgeInsets.symmetric(horizontal: 9),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 5),
                  AppIconButton(
                    icon: Icons.find_replace_rounded,
                    tooltip: '替换当前项',
                    size: 28,
                    iconSize: 16,
                    onPressed: readOnly || result == null
                        ? null
                        : controller.replaceMatch,
                  ),
                  AppIconButton(
                    icon: Icons.done_all_rounded,
                    tooltip: '全部替换',
                    size: 28,
                    iconSize: 16,
                    onPressed: readOnly || result == null
                        ? null
                        : controller.replaceAllMatches,
                  ),
                  const SizedBox(width: 79),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ToggleText extends StatelessWidget {
  const _ToggleText({
    required this.label,
    required this.tooltip,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String tooltip;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(3),
        child: AnimatedContainer(
          width: 28,
          height: 28,
          duration: AppMotion.quick,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected
                ? AppColors.signal.withValues(alpha: 0.12)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(3),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? AppColors.signal : AppColors.textDim,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              fontFamily: 'MapleMonoCN',
            ),
          ),
        ),
      ),
    );
  }
}
