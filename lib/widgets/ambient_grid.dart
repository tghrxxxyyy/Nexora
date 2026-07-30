import 'package:flutter/material.dart';

import '../app_theme.dart';

class AmbientGrid extends StatelessWidget {
  const AmbientGrid({required this.themeMode, super.key});

  final AppThemeMode themeMode;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: RepaintBoundary(
        child: CustomPaint(
          painter: _GridPainter(
            gridColor: AppColors.line,
            signalColor: AppColors.signal,
          ),
          size: Size.infinite,
        ),
      ),
    );
  }
}

class _GridPainter extends CustomPainter {
  const _GridPainter({required this.gridColor, required this.signalColor});

  final Color gridColor;
  final Color signalColor;

  @override
  void paint(Canvas canvas, Size size) {
    const spacing = 44.0;
    final gridPaint = Paint()
      ..color = gridColor.withValues(alpha: 0.035)
      ..strokeWidth = 0.6;
    final crossPaint = Paint()
      ..color = signalColor.withValues(alpha: 0.04)
      ..strokeWidth = 1;

    for (double x = 0; x <= size.width; x += spacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
    for (double y = 0; y <= size.height; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    const crossStride = spacing * 4;
    crossPaint.color = signalColor.withValues(alpha: 0.028);
    for (double x = crossStride; x < size.width; x += crossStride) {
      for (double y = crossStride; y < size.height; y += crossStride) {
        canvas.drawLine(Offset(x - 3, y), Offset(x + 3, y), crossPaint);
        canvas.drawLine(Offset(x, y - 3), Offset(x, y + 3), crossPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _GridPainter oldDelegate) =>
      gridColor != oldDelegate.gridColor ||
      signalColor != oldDelegate.signalColor;
}
