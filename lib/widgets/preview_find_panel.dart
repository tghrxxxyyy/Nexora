import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../state/preview_find_controller.dart';
import 'ui_primitives.dart';

class PreviewFindPanel extends StatelessWidget {
  const PreviewFindPanel({required this.controller, super.key});

  final PreviewFindController controller;

  @override
  Widget build(BuildContext context) {
    final resultText = controller.matchCount == 0
        ? '0 / 0'
        : '${controller.activeIndex + 1} / ${controller.matchCount}';

    return Container(
      width: 394,
      margin: const EdgeInsets.only(top: 12, right: 16),
      padding: const EdgeInsets.all(7),
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
        borderRadius: BorderRadius.circular(7),
        boxShadow: [
          BoxShadow(
            color: AppColors.background.withValues(alpha: 0.48),
            blurRadius: 28,
            offset: const Offset(0, 10),
          ),
          BoxShadow(
            color: AppColors.signal.withValues(alpha: 0.075),
            blurRadius: 18,
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 31,
              child: TextField(
                controller: controller.queryController,
                focusNode: controller.focusNode,
                onSubmitted: (_) => controller.nextMatch(),
                style: TextStyle(color: AppColors.text, fontSize: 12),
                decoration: const InputDecoration(
                  hintText: '在预览中查找',
                  prefixIcon: Icon(Icons.search_rounded, size: 16),
                  contentPadding: EdgeInsets.symmetric(horizontal: 9),
                ),
              ),
            ),
          ),
          const SizedBox(width: 5),
          _FindOption(
            label: 'Aa',
            tooltip: '区分大小写',
            selected: controller.caseSensitive,
            onPressed: controller.toggleCaseSensitive,
          ),
          SizedBox(
            width: 48,
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
            tooltip: '上一个匹配项',
            size: 28,
            iconSize: 16,
            onPressed: controller.matchCount == 0
                ? null
                : controller.previousMatch,
          ),
          AppIconButton(
            icon: Icons.keyboard_arrow_down_rounded,
            tooltip: '下一个匹配项',
            size: 28,
            iconSize: 16,
            onPressed: controller.matchCount == 0 ? null : controller.nextMatch,
          ),
          AppIconButton(
            icon: Icons.close_rounded,
            tooltip: '关闭查找',
            size: 28,
            iconSize: 15,
            onPressed: controller.close,
          ),
        ],
      ),
    );
  }
}

class _FindOption extends StatelessWidget {
  const _FindOption({
    required this.label,
    required this.tooltip,
    required this.selected,
    required this.onPressed,
  });

  final String label;
  final String tooltip;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(4),
        child: AnimatedContainer(
          width: 28,
          height: 28,
          duration: AppMotion.quick,
          curve: AppMotion.curve,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected
                ? AppColors.signal.withValues(alpha: 0.14)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
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
