import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../state/app_controller.dart';
import 'ui_primitives.dart';

class SettingsDialog extends StatelessWidget {
  const SettingsDialog({required this.controller, super.key});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: SizedBox(
        width: 390,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 14, 14),
          child: ListenableBuilder(
            listenable: controller,
            builder: (context, child) {
              final percent = (controller.fontScale * 100).round();
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.tune_rounded,
                        size: 18,
                        color: AppColors.signal,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '设置',
                        style: TextStyle(
                          color: AppColors.text,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const Spacer(),
                      AppIconButton(
                        icon: Icons.close_rounded,
                        tooltip: '关闭设置',
                        size: 28,
                        iconSize: 15,
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  const SizedBox(height: 22),
                  Row(
                    children: [
                      Icon(
                        Icons.format_size_rounded,
                        size: 17,
                        color: AppColors.textMuted,
                      ),
                      const SizedBox(width: 9),
                      Text(
                        '字体大小',
                        style: TextStyle(
                          color: AppColors.text,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '$percent%',
                        style: TextStyle(
                          color: AppColors.signal,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(width: 2),
                      AppIconButton(
                        icon: Icons.restart_alt_rounded,
                        tooltip: '恢复默认大小',
                        size: 26,
                        iconSize: 15,
                        onPressed: controller.fontScale == 1
                            ? null
                            : () => controller.setFontScale(1),
                      ),
                    ],
                  ),
                  Slider(
                    value: controller.fontScale,
                    min: 0.85,
                    max: 1.45,
                    divisions: 12,
                    onChanged: controller.setFontScale,
                  ),
                  Padding(
                    padding: const EdgeInsets.only(left: 2, right: 4),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('85%', style: _captionStyle),
                        Text('默认', style: _captionStyle),
                        Text('145%', style: _captionStyle),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

final _captionStyle = TextStyle(color: AppColors.textDim, fontSize: 10);
