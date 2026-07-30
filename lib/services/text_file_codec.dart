import 'dart:convert';
import 'dart:typed_data';

const Set<String> commonIgnoredDirectoryNames = <String>{
  '.dart_tool',
  '.git',
  '.gradle',
  '.hg',
  '.idea',
  '.next',
  '.nuxt',
  '.svn',
  'build',
  'coverage',
  'deriveddata',
  'dist',
  'node_modules',
  'out',
  'pods',
  'target',
};

class DecodedText {
  const DecodedText({required this.content, required this.hasUtf8Bom});

  final String content;
  final bool hasUtf8Bom;
}

class TextFileCodec {
  const TextFileCodec._();

  static DecodedText? tryDecode(Uint8List bytes) {
    if (_hasBinaryControlBytes(bytes)) {
      return null;
    }

    final hasUtf8Bom =
        bytes.length >= 3 &&
        bytes[0] == 0xef &&
        bytes[1] == 0xbb &&
        bytes[2] == 0xbf;
    final contentBytes = hasUtf8Bom ? bytes.sublist(3) : bytes;

    try {
      return DecodedText(
        content: utf8.decode(contentBytes, allowMalformed: false),
        hasUtf8Bom: hasUtf8Bom,
      );
    } on FormatException {
      return null;
    }
  }

  static Uint8List encode(String content, {bool includeUtf8Bom = false}) {
    final encoded = utf8.encode(content);
    if (!includeUtf8Bom) {
      return Uint8List.fromList(encoded);
    }
    return Uint8List.fromList(<int>[0xef, 0xbb, 0xbf, ...encoded]);
  }

  static bool _hasBinaryControlBytes(Uint8List bytes) {
    if (bytes.isEmpty) {
      return false;
    }

    var controlByteCount = 0;
    final sampleLength = bytes.length < 8192 ? bytes.length : 8192;
    for (var index = 0; index < sampleLength; index++) {
      final byte = bytes[index];
      if (byte == 0) {
        return true;
      }
      if (byte < 32 && byte != 9 && byte != 10 && byte != 12 && byte != 13) {
        controlByteCount++;
      }
    }
    return controlByteCount / sampleLength > 0.05;
  }
}
