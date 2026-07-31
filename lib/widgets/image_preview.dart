import 'dart:io';

import 'package:flutter/material.dart';

import '../app_theme.dart';

class ImagePreview extends StatelessWidget {
  const ImagePreview({required this.path, super.key});

  final String path;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.backgroundRaised,
      child: InteractiveViewer(
        minScale: 0.5,
        maxScale: 6,
        boundaryMargin: const EdgeInsets.all(96),
        child: Center(
          child: Image.file(
            File(path),
            fit: BoxFit.contain,
            errorBuilder: (context, error, stackTrace) => Text(
              '无法预览此图片',
              style: TextStyle(color: AppColors.textMuted, fontSize: 12),
            ),
          ),
        ),
      ),
    );
  }
}
