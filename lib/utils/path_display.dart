/// Truncates a long absolute path with an ellipsis in the middle so it fits
/// inside tooltips without overflowing the screen edge.
///
/// `/Users/zhangyongbin/Desktop/Learn/AI/Nexora/lib/widgets/file_sidebar.dart`
/// becomes `/Users/.../file_sidebar.dart` when shorter than [maxLength].
String truncatePathForDisplay(String path, {int maxLength = 60}) {
  if (path.length <= maxLength) return path;
  final separator = path.contains('\\') ? '\\' : '/';
  final lastSep = path.lastIndexOf(separator);
  if (lastSep < 0) return path;
  final fileName = path.substring(lastSep + 1);
  // Keep the leading root segment (e.g. `/Users`) so the user still knows
  // roughly where the file lives.
  final firstSep = path.indexOf(separator, 1);
  final head = firstSep > 0 ? path.substring(0, firstSep) : path.substring(0, 1);
  final budget = maxLength - fileName.length - head.length - 5; // ".../" + sep
  if (budget <= 0) {
    // Path is mostly filename — just keep filename.
    return fileName;
  }
  return '$head$separator...$separator$fileName';
}
