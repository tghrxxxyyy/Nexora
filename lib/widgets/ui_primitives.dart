import 'package:flutter/material.dart';

import '../app_theme.dart';

class AppIconButton extends StatefulWidget {
  const AppIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.selected = false,
    this.size = 32,
    this.iconSize = 17,
    this.accent,
    super.key,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool selected;
  final double size;
  final double iconSize;
  final Color? accent;

  @override
  State<AppIconButton> createState() => _AppIconButtonState();
}

class _AppIconButtonState extends State<AppIconButton> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final activeColor = widget.accent ?? AppColors.signal;
    final enabled = widget.onPressed != null;
    final background = widget.selected
        ? activeColor.withValues(alpha: 0.1)
        : _hovered
        ? activeColor.withValues(alpha: 0.03)
        : Colors.transparent;

    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() {
          _hovered = false;
          _pressed = false;
        }),
        child: GestureDetector(
          onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
          onTapCancel: enabled ? () => setState(() => _pressed = false) : null,
          onTapUp: enabled
              ? (_) {
                  setState(() => _pressed = false);
                  widget.onPressed?.call();
                }
              : null,
          child: AnimatedScale(
            scale: _pressed ? 0.94 : 1,
            duration: AppMotion.quick,
            curve: AppMotion.curve,
            child: AnimatedContainer(
              width: widget.size,
              height: widget.size,
              duration: AppMotion.quick,
              curve: AppMotion.curve,
              decoration: BoxDecoration(
                color: background,
                borderRadius: BorderRadius.circular(4),
              ),
              alignment: Alignment.center,
              child: Icon(
                widget.icon,
                size: widget.iconSize,
                color: !enabled
                    ? AppColors.textDim
                    : widget.selected
                    ? activeColor
                    : AppColors.textMuted,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class TechButton extends StatefulWidget {
  const TechButton({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.primary = false,
    this.compact = false,
    super.key,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool primary;
  final bool compact;

  @override
  State<TechButton> createState() => _TechButtonState();
}

class _TechButtonState extends State<TechButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    final baseColor = widget.primary
        ? AppColors.signal.withValues(alpha: _hovered ? 0.2 : 0.12)
        : _hovered
        ? AppColors.signal.withValues(alpha: 0.055)
        : AppColors.surface;

    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: AppMotion.quick,
        curve: AppMotion.curve,
        decoration: BoxDecoration(
          color: enabled ? baseColor : AppColors.surface,
          borderRadius: BorderRadius.circular(4),
        ),
        child: InkWell(
          onTap: widget.onPressed,
          borderRadius: BorderRadius.circular(4),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: widget.compact ? 10 : 15,
              vertical: widget.compact ? 7 : 10,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  widget.icon,
                  size: widget.compact ? 15 : 17,
                  color: enabled
                      ? widget.primary
                            ? AppColors.signal
                            : AppColors.textMuted
                      : AppColors.textDim,
                ),
                const SizedBox(width: 8),
                Text(
                  widget.label,
                  style: TextStyle(
                    color: enabled ? AppColors.text : AppColors.textDim,
                    fontSize: widget.compact ? 11 : 12,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0,
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

class PanelLabel extends StatelessWidget {
  const PanelLabel({required this.label, this.trailing, super.key});

  final String label;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 38,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: [
            Container(
              width: 2,
              height: 12,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    AppColors.signal.withValues(alpha: 0.18),
                    AppColors.signal,
                    AppColors.acid.withValues(alpha: 0.58),
                  ],
                ),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label.toUpperCase(),
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0,
                ),
              ),
            ),
            ?trailing,
          ],
        ),
      ),
    );
  }
}

class SignalDivider extends StatelessWidget {
  const SignalDivider({this.vertical = false, super.key});

  final bool vertical;

  @override
  Widget build(BuildContext context) {
    final surfaceMist = Color.alphaBlend(
      AppColors.surface.withValues(alpha: 0.24),
      AppColors.backgroundRaised,
    );
    final signalMist = Color.alphaBlend(
      AppColors.signal.withValues(alpha: 0.035),
      surfaceMist,
    );
    return SizedBox(
      width: vertical ? 12 : double.infinity,
      height: vertical ? double.infinity : 8,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: vertical ? Alignment.centerLeft : Alignment.topCenter,
            end: vertical ? Alignment.centerRight : Alignment.bottomCenter,
            stops: const [0, 0.28, 0.5, 0.72, 1],
            colors: [
              AppColors.backgroundRaised,
              surfaceMist,
              signalMist,
              surfaceMist,
              AppColors.backgroundRaised,
            ],
          ),
        ),
      ),
    );
  }
}

class PanelSurface extends StatelessWidget {
  const PanelSurface({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final top = Color.alphaBlend(
      AppColors.surfaceRaised.withValues(alpha: 0.36),
      AppColors.background,
    );
    final middle = Color.alphaBlend(
      AppColors.surface.withValues(alpha: 0.26),
      AppColors.background,
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [top, middle, AppColors.background],
        ),
      ),
      child: child,
    );
  }
}
