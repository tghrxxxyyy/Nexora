import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:path/path.dart' as p;

import '../app_theme.dart';
import '../services/file_icon_resolver.dart';

/// Floating card shown under the cursor while a [PaneDragPayload] is being
/// dragged. Renders the resolved file icon + basename so the user gets a
/// VSCode-like ghost of what they're moving.
class PaneDragFeedback extends StatelessWidget {
  const PaneDragFeedback({required this.filePath, super.key});

  final String filePath;

  @override
  Widget build(BuildContext context) {
    final visual = resolveFileVisual(
      FileIconContext(path: filePath, isDirectory: false),
    );
    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: AppColors.signal.withValues(alpha: 0.6)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.35),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildIcon(visual),
            const SizedBox(width: 7),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 200),
              child: Text(
                p.basename(filePath),
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: AppColors.text,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIcon(FileVisual visual) {
    if (visual.svgAssetKey != null) {
      return SvgPicture.asset(
        visual.svgAssetKey!,
        width: 14,
        height: 14,
        colorFilter: visual.tintSvg && visual.color != null
            ? ColorFilter.mode(visual.color!, BlendMode.srcIn)
            : null,
      );
    }
    return Icon(visual.icon, size: 14, color: visual.color);
  }
}
