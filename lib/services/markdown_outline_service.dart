import '../models/markdown_heading.dart';

class MarkdownOutlineService {
  const MarkdownOutlineService();

  List<MarkdownHeading> extract(String source) {
    final lines = source.split('\n');
    final offsets = <int>[];
    var offset = 0;
    for (final line in lines) {
      offsets.add(offset);
      offset += line.length + 1;
    }

    // Skip a leading YAML front matter block (`---\n...\n---\n`) line-by-line
    // instead of stripping the source. Its inner `key: value\n---\n` looks
    // exactly like a setext h2 to the scanner and would inject a phantom
    // heading that desyncs every later anchor from the DOM by one. Stripping
    // the source would shift line numbers; skipping in-place keeps the
    // reported `lineNumber` aligned with the original file (so the outline
    // panel and editor jumps point at the right row).
    var startIndex = 0;
    if (lines.isNotEmpty && RegExp(r'^---[ \t]*$').hasMatch(lines[0])) {
      for (var i = 1; i < lines.length; i++) {
        if (RegExp(r'^---[ \t]*$').hasMatch(lines[i])) {
          startIndex = i + 1;
          break;
        }
      }
    }

    final headings = <MarkdownHeading>[];
    final anchorCounts = <String, int>{};
    _Fence? fence;
    _SetextCandidate? setextCandidate;

    for (var index = startIndex; index < lines.length; index++) {
      final line = _withoutCarriageReturn(lines[index]);
      final marker = _fenceMarker(line);
      if (fence != null) {
        setextCandidate = null;
        if (marker != null &&
            marker.character == fence.character &&
            marker.length >= fence.length &&
            marker.trailingText.trim().isEmpty) {
          fence = null;
        }
        continue;
      }
      if (marker != null) {
        fence = marker;
        setextCandidate = null;
        continue;
      }

      final atxMatch = RegExp(
        r'^\s{0,3}(#{1,6})(?:[ \t]+|$)(.*)$',
      ).firstMatch(line);
      if (atxMatch != null) {
        final rawText = atxMatch.group(2) ?? '';
        final text = _plainHeadingText(
          rawText.replaceFirst(RegExp(r'[ \t]+#+[ \t]*$'), ''),
        );
        if (text.isNotEmpty) {
          headings.add(
            _heading(
              level: atxMatch.group(1)!.length,
              text: text,
              lineIndex: index,
              sourceOffset: offsets[index],
              anchorCounts: anchorCounts,
            ),
          );
        }
        setextCandidate = null;
        continue;
      }

      if (RegExp(r'^\s{0,3}(=+|-+)\s*$').hasMatch(line)) {
        if (setextCandidate != null) {
          headings.add(
            _heading(
              level: line.trimLeft().startsWith('=') ? 1 : 2,
              text: setextCandidate.text,
              lineIndex: setextCandidate.lineIndex,
              sourceOffset: setextCandidate.sourceOffset,
              anchorCounts: anchorCounts,
            ),
          );
        }
        setextCandidate = null;
        continue;
      }

      if (line.trim().isEmpty ||
          line.startsWith('    ') ||
          line.startsWith('\t')) {
        setextCandidate = null;
        continue;
      }
      final text = _plainHeadingText(line.trim());
      if (text.isEmpty) {
        setextCandidate = null;
        continue;
      }
      setextCandidate = _SetextCandidate(
        text: text,
        lineIndex: index,
        sourceOffset: offsets[index],
      );
    }

    return List<MarkdownHeading>.unmodifiable(headings);
  }

  MarkdownHeading _heading({
    required int level,
    required String text,
    required int lineIndex,
    required int sourceOffset,
    required Map<String, int> anchorCounts,
  }) {
    final baseAnchor = _anchorBase(text);
    final duplicateIndex = anchorCounts.update(
      baseAnchor,
      (count) => count + 1,
      ifAbsent: () => 0,
    );
    final anchor = duplicateIndex == 0
        ? baseAnchor
        : '$baseAnchor-$duplicateIndex';
    return MarkdownHeading(
      level: level,
      text: text,
      anchor: anchor,
      lineNumber: lineIndex + 1,
      sourceOffset: sourceOffset,
    );
  }

  _Fence? _fenceMarker(String line) {
    final match = RegExp(r'^\s{0,3}(`{3,}|~{3,})(.*)$').firstMatch(line);
    if (match == null) {
      return null;
    }
    final marker = match.group(1)!;
    return _Fence(marker[0], marker.length, match.group(2) ?? '');
  }

  String _plainHeadingText(String text) {
    return text
        .replaceAllMapped(
          RegExp(r'!?\[([^\]]+)\]\([^)]*\)'),
          (match) => match.group(1) ?? '',
        )
        .replaceAll(RegExp(r'[*_~`]'), '')
        .replaceAll(RegExp(r'<[^>]+>'), '')
        .replaceAllMapped(RegExp(r'\\(.)'), (match) => match.group(1) ?? '')
        .trim();
  }

  String _anchorBase(String text) {
    final output = StringBuffer();
    var pendingHyphen = false;
    for (final rune in text.toLowerCase().runes) {
      final isAsciiLetter = rune >= 97 && rune <= 122;
      final isDigit = rune >= 48 && rune <= 57;
      final isNonAsciiContent =
          rune > 127 &&
          !(rune >= 0x3000 && rune <= 0x303f) &&
          !(rune >= 0xff00 && rune <= 0xff65);
      if (isAsciiLetter || isDigit || isNonAsciiContent || rune == 95) {
        if (pendingHyphen && output.isNotEmpty) {
          output.write('-');
        }
        output.writeCharCode(rune);
        pendingHyphen = false;
      } else if (rune == 45 || rune == 32 || rune == 9) {
        pendingHyphen = output.isNotEmpty;
      }
    }
    return output.isEmpty ? 'section' : output.toString();
  }

  String _withoutCarriageReturn(String line) {
    return line.endsWith('\r') ? line.substring(0, line.length - 1) : line;
  }
}

class _Fence {
  const _Fence(this.character, this.length, this.trailingText);

  final String character;
  final int length;
  final String trailingText;
}

class _SetextCandidate {
  const _SetextCandidate({
    required this.text,
    required this.lineIndex,
    required this.sourceOffset,
  });

  final String text;
  final int lineIndex;
  final int sourceOffset;
}
