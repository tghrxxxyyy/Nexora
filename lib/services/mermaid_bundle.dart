import 'package:flutter/services.dart' show rootBundle;

/// Loads the bundled `mermaid.min.js` asset as a string for inline embedding.
///
/// Earlier revisions copied the asset to `getApplicationSupportDirectory`
/// and referenced it via a `file://` URL. That worked on iOS but the macOS
/// WKWebView sandbox blocks file access to the app container, so the script
/// never loaded. Inlining the JS into the HTML string sidesteps the file
/// system entirely and works on both platforms.
class MermaidBundle {
  static const _assetKey = 'assets/vendor/mermaid.min.js';

  static String? _cachedScript;

  /// Returns the mermaid.min.js source as a string, ready to drop into an
  /// inline `<script>` tag.
  ///
  /// Returns null if the asset cannot be read. Callers should treat null as
  /// "mermaid unavailable" and skip the `<script>` tag, letting the Markdown
  /// load normally with raw ` ```mermaid ` source visible.
  static Future<String?> script() async {
    final cached = _cachedScript;
    if (cached != null) return cached;

    try {
      final source = await rootBundle.loadString(_assetKey);
      _cachedScript = source;
      return source;
    } catch (_) {
      return null;
    }
  }

  /// Drops the in-memory cache so the next [script] call re-reads the bundle.
  /// Useful for tests or after a bundle update.
  static void reset() => _cachedScript = null;
}
