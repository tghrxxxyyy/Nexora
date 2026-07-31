import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../models/markdown_theme.dart';
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
                  Row(
                    children: [
                      Icon(
                        Icons.palette_outlined,
                        size: 17,
                        color: AppColors.textMuted,
                      ),
                      const SizedBox(width: 9),
                      Text(
                        'Markdown 阅读主题',
                        style: TextStyle(
                          color: AppColors.text,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text('仅影响 Markdown 预览，Nexora 为默认主题', style: _captionStyle),
                  const SizedBox(height: 10),
                  _ThemeSelectionField(
                    theme: controller.markdownTheme,
                    onTap: () => showDialog<void>(
                      context: context,
                      builder: (context) =>
                          _ThemePickerDialog(controller: controller),
                    ),
                  ),
                  const SizedBox(height: 8),
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

class _ThemeSelectionField extends StatelessWidget {
  const _ThemeSelectionField({required this.theme, required this.onTap});

  final MarkdownTheme theme;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = theme.accent;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          height: 52,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: theme.previewSurface,
            borderRadius: BorderRadius.circular(6),
            boxShadow: [
              BoxShadow(
                color: accent.withValues(alpha: 0.12),
                blurRadius: 16,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Row(
            children: [
              _ThemeSwatch(theme: theme, compact: true),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      theme.label,
                      style: TextStyle(
                        color: theme.isDark ? Colors.white : AppColors.text,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      theme.description,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: theme.isDark
                            ? Colors.white70
                            : AppColors.textMuted,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.expand_more_rounded, color: accent, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

class _ThemePickerDialog extends StatelessWidget {
  const _ThemePickerDialog({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: SizedBox(
        width: 660,
        height: 620,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 20, 14, 14),
          child: ListenableBuilder(
            listenable: controller,
            builder: (context, child) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.auto_awesome_rounded,
                      color: AppColors.signal,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '选择 Markdown 阅读主题',
                      style: TextStyle(
                        color: AppColors.text,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const Spacer(),
                    AppIconButton(
                      icon: Icons.close_rounded,
                      tooltip: '关闭主题选择',
                      size: 28,
                      iconSize: 15,
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text('主题仅作用于 Markdown 预览与原地编辑', style: _captionStyle),
                const SizedBox(height: 16),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.only(right: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _ThemeGroup(
                          title: '标准',
                          themes: const [
                            MarkdownTheme.nexora,
                            MarkdownTheme.github,
                            MarkdownTheme.newsprint,
                          ],
                          controller: controller,
                        ),
                        _ThemeGroup(
                          title: 'Phycat Color',
                          themes: const [
                            MarkdownTheme.cherry,
                            MarkdownTheme.caramel,
                            MarkdownTheme.forest,
                            MarkdownTheme.mint,
                            MarkdownTheme.sky,
                            MarkdownTheme.prussian,
                            MarkdownTheme.sakura,
                            MarkdownTheme.mauve,
                          ],
                          controller: controller,
                        ),
                        _ThemeGroup(
                          title: 'Phycat Neon',
                          themes: const [
                            MarkdownTheme.vampire,
                            MarkdownTheme.radiation,
                            MarkdownTheme.abyss,
                          ],
                          controller: controller,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ThemeGroup extends StatelessWidget {
  const _ThemeGroup({
    required this.title,
    required this.themes,
    required this.controller,
  });

  final String title;
  final List<MarkdownTheme> themes;
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: AppColors.textMuted,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: themes
                .map(
                  (theme) => _ThemeGalleryCard(
                    theme: theme,
                    selected: controller.markdownTheme == theme,
                    onTap: () {
                      controller.setMarkdownTheme(theme);
                      Navigator.pop(context);
                    },
                  ),
                )
                .toList(growable: false),
          ),
        ],
      ),
    );
  }
}

class _ThemeGalleryCard extends StatelessWidget {
  const _ThemeGalleryCard({
    required this.theme,
    required this.selected,
    required this.onTap,
  });

  final MarkdownTheme theme;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = theme.accent;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(7),
        child: AnimatedContainer(
          duration: AppMotion.standard,
          curve: AppMotion.emphasized,
          width: 190,
          height: 102,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: theme.previewSurface,
            borderRadius: BorderRadius.circular(7),
            boxShadow: [
              BoxShadow(
                color: accent.withValues(alpha: selected ? 0.28 : 0.10),
                blurRadius: selected ? 20 : 12,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _ThemeSwatch(theme: theme)),
              const SizedBox(height: 7),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      theme.label,
                      style: TextStyle(
                        color: theme.isDark ? Colors.white : AppColors.text,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (selected)
                    Icon(Icons.check_circle_rounded, color: accent, size: 15),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ThemeSwatch extends StatelessWidget {
  const _ThemeSwatch({required this.theme, this.compact = false});

  final MarkdownTheme theme;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final accent = theme.accent;
    return Container(
      width: compact ? 36 : double.infinity,
      decoration: BoxDecoration(
        color: theme.previewSurface,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Padding(
        padding: EdgeInsets.all(compact ? 5 : 7),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: compact ? 24 : 52,
              height: compact ? 3 : 4,
              decoration: BoxDecoration(
                color: accent,
                borderRadius: BorderRadius.circular(99),
                boxShadow: theme.isDark
                    ? [BoxShadow(color: accent, blurRadius: 7)]
                    : null,
              ),
            ),
            SizedBox(height: compact ? 4 : 6),
            Container(
              width: compact ? 19 : 76,
              height: compact ? 2 : 3,
              color: theme.isDark ? Colors.white54 : AppColors.textMuted,
            ),
            if (!compact) ...[
              const SizedBox(height: 5),
              Container(
                width: 58,
                height: 3,
                decoration: BoxDecoration(
                  color: theme.accentSoft,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
