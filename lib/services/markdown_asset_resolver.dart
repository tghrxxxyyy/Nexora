import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

class MarkdownAssetResolver {
  const MarkdownAssetResolver._();

  static String? resolveLocalPath({
    required String source,
    required String documentPath,
    required String workspaceRoot,
  }) {
    if (source.isEmpty) return null;
    // Uri.decodeFull throws ArgumentError on stray `%` (e.g. paths containing
    // `50%off.png` or HTML attributes like width="80%" leaking into the src).
    // Fall back to the raw source so the rest of the pipeline still runs.
    String decodedSource;
    try {
      decodedSource = Uri.decodeFull(source);
    } catch (_) {
      decodedSource = source;
    }
    final uri = Uri.tryParse(decodedSource);
    if (uri?.scheme == 'file') return uri!.toFilePath();
    if (uri?.hasScheme ?? false) return null;
    if (p.isAbsolute(decodedSource) && File(decodedSource).existsSync()) {
      return p.normalize(decodedSource);
    }
    final path = decodedSource.startsWith('/')
        ? p.join(workspaceRoot, decodedSource.substring(1))
        : p.join(p.dirname(documentPath), decodedSource);
    return p.normalize(path);
  }

  static String? dataUriForPath(String path) {
    final file = File(path);
    if (!file.existsSync()) return null;
    final extension = p.extension(path).toLowerCase();
    final mimeType = switch (extension) {
      '.avif' => 'image/avif',
      '.gif' => 'image/gif',
      '.jpeg' || '.jpg' => 'image/jpeg',
      '.png' => 'image/png',
      '.svg' => 'image/svg+xml',
      '.webp' => 'image/webp',
      _ => 'application/octet-stream',
    };
    return 'data:$mimeType;base64,${base64Encode(file.readAsBytesSync())}';
  }
}
