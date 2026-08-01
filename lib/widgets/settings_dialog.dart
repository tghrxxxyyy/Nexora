import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../app_theme.dart';
import '../services/file_icon_resolver.dart';
import '../state/app_controller.dart';
import '../state/icon_theme_registry.dart';
import 'ui_primitives.dart';

class SettingsDialog extends StatelessWidget {
  const SettingsDialog({required this.controller, super.key});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: SizedBox(
        width: 560,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 14, 14),
          child: ListenableBuilder(
            listenable: controller,
            builder: (context, _) {
              final percent = (controller.fontScale * 100).round();
              return SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildHeader(context),
                    const SizedBox(height: 22),
                    _buildThemeSection(context),
                    const SizedBox(height: 22),
                    _buildIconThemeSection(context),
                    const SizedBox(height: 22),
                    _buildFontSection(percent),
                    const SizedBox(height: 20),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Row(
      children: [
        Icon(Icons.tune_rounded, size: 18, color: AppColors.signal),
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
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }

  Widget _buildThemeSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.palette_outlined, size: 17, color: AppColors.textMuted),
            const SizedBox(width: 9),
            Text(
              '主题',
              style: TextStyle(
                color: AppColors.text,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final theme in controller.availableThemes)
              _ThemeCard(
                theme: theme,
                selected: theme.id == controller.currentThemeId,
                onTap: () => controller.setTheme(theme.id),
                onDelete: theme.builtIn
                    ? null
                    : () => controller.deleteTheme(theme.id),
              ),
          ],
        ),
        const SizedBox(height: 12),
        TechButton(
          label: '导入主题…',
          icon: Icons.file_download_outlined,
          onPressed: controller.pickThemeFile,
          compact: true,
        ),
      ],
    );
  }

  Widget _buildIconThemeSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.perm_media_outlined,
              size: 17,
              color: AppColors.textMuted,
            ),
            const SizedBox(width: 9),
            Text(
              '图标主题',
              style: TextStyle(
                color: AppColors.text,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final theme in controller.availableIconThemes)
              _IconThemeCard(
                theme: theme,
                selected: theme.id == controller.currentIconThemeId,
                onTap: () => controller.setIconTheme(theme.id),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildFontSection(int percent) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
      ],
    );
  }
}

class _ThemeCard extends StatefulWidget {
  const _ThemeCard({
    required this.theme,
    required this.selected,
    required this.onTap,
    this.onDelete,
  });

  final AppThemeDefinition theme;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onDelete;

  @override
  State<_ThemeCard> createState() => _ThemeCardState();
}

class _ThemeCardState extends State<_ThemeCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final palette = theme.palette;
    final selected = widget.selected;
    final borderColor = selected
        ? palette.signal
        : _hovered
        ? AppColors.lineStrong
        : AppColors.line;
    final background = selected
        ? AppColors.signal.withValues(alpha: 0.06)
        : _hovered
        ? AppColors.surfaceHover.withValues(alpha: 0.4)
        : AppColors.surface.withValues(alpha: 0.4);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: AppMotion.quick,
          curve: AppMotion.curve,
          width: 132,
          padding: const EdgeInsets.fromLTRB(8, 8, 6, 8),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: borderColor, width: selected ? 1.5 : 1),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      theme.name,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppColors.text,
                        fontSize: 11,
                        fontWeight: selected
                            ? FontWeight.w700
                            : FontWeight.w600,
                      ),
                    ),
                  ),
                  if (widget.onDelete != null)
                    _DeleteChip(onTap: widget.onDelete!),
                ],
              ),
              const SizedBox(height: 7),
              _ThemePreview(palette: palette),
            ],
          ),
        ),
      ),
    );
  }
}

/// A miniature mock-up of the editor surface rendered entirely with the
/// theme's own palette, so users can see what each theme actually looks
/// like instead of abstract color dots.
class _ThemePreview extends StatelessWidget {
  const _ThemePreview({required this.palette});

  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(3),
      child: Container(
        height: 46,
        decoration: BoxDecoration(
          color: palette.background,
          border: Border.all(color: palette.line.withValues(alpha: 0.7)),
        ),
        child: Row(
          children: [
            Container(
              width: 18,
              color: palette.surface,
              padding: const EdgeInsets.symmetric(
                vertical: 4,
                horizontal: 3,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _bar(palette.signal, width: 9, height: 2),
                  _bar(palette.textDim, width: 11, height: 1.5),
                  _bar(palette.textDim, width: 8, height: 1.5),
                  _bar(palette.textDim, width: 10, height: 1.5),
                ],
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    height: 6,
                    color: palette.backgroundRaised,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 2,
                    ),
                    child: Row(
                      children: [
                        _bar(palette.signal, width: 12, height: 2),
                        const SizedBox(width: 4),
                        _bar(palette.textDim, width: 8, height: 1.5),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(5, 4, 5, 4),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _bar(palette.text, width: 24, height: 2),
                          const SizedBox(height: 3),
                          _bar(palette.textMuted, width: 38, height: 1.5),
                          const SizedBox(height: 2),
                          _bar(palette.textMuted, width: 32, height: 1.5),
                          const Spacer(),
                          Container(
                            height: 1.5,
                            width: 14,
                            decoration: BoxDecoration(
                              color: palette.signal.withValues(alpha: 0.55),
                              borderRadius: BorderRadius.circular(0.5),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _bar(Color color, {required double width, required double height}) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(0.5),
      ),
    );
  }
}

class _IconThemeCard extends StatefulWidget {
  const _IconThemeCard({
    required this.theme,
    required this.selected,
    required this.onTap,
  });

  final FileIconTheme theme;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_IconThemeCard> createState() => _IconThemeCardState();
}

class _IconThemeCardState extends State<_IconThemeCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final selected = widget.selected;
    final borderColor = selected
        ? AppColors.signal
        : _hovered
        ? AppColors.lineStrong
        : AppColors.line;
    final background = selected
        ? AppColors.signal.withValues(alpha: 0.06)
        : _hovered
        ? AppColors.surfaceHover.withValues(alpha: 0.4)
        : AppColors.surface.withValues(alpha: 0.4);

    const samples = ['folder', 'markdown', 'dart', 'json'];
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: AppMotion.quick,
          curve: AppMotion.curve,
          width: 168,
          padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: borderColor,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                theme.name,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: AppColors.text,
                  fontSize: 11,
                  fontWeight:
                      selected ? FontWeight.w700 : FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  for (final name in samples) ...[
                    _IconSample(name: name, resolver: theme.resolver),
                    const SizedBox(width: 6),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _IconSample extends StatelessWidget {
  const _IconSample({required this.name, required this.resolver});

  final String name;
  final FileIconResolver resolver;

  @override
  Widget build(BuildContext context) {
    const fakePath = '/tmp/sample/';
    final isFolder = name == 'folder';
    final visual = resolver.resolve(
      FileIconContext(path: '$fakePath$name', isDirectory: isFolder),
    );
    final double iconSize = isFolder ? 18 : 16;
    if (visual.svgAssetKey != null) {
      return SvgPicture.asset(
        visual.svgAssetKey!,
        width: iconSize,
        height: iconSize,
        colorFilter: visual.tintSvg && visual.color != null
            ? ColorFilter.mode(visual.color!, BlendMode.srcIn)
            : null,
      );
    }
    return Icon(
      visual.icon ?? Icons.insert_drive_file_outlined,
      size: iconSize,
      color: visual.color ?? AppColors.textDim,
    );
  }
}

class _DeleteChip extends StatefulWidget {
  const _DeleteChip({required this.onTap});

  final VoidCallback onTap;

  @override
  State<_DeleteChip> createState() => _DeleteChipState();
}

class _DeleteChipState extends State<_DeleteChip> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: '删除主题',
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: widget.onTap,
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: const EdgeInsets.all(2),
            child: Icon(
              Icons.close_rounded,
              size: 12,
              color: _hovered ? AppColors.coral : AppColors.textDim,
            ),
          ),
        ),
      ),
    );
  }
}

final _captionStyle = TextStyle(color: AppColors.textDim, fontSize: 10);
