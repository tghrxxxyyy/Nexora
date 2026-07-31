import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class AppSessionStore {
  const AppSessionStore();

  Future<Map<String, dynamic>?> read() async {
    try {
      final file = await _file();
      if (await file.exists()) return _decode(await file.readAsString());
      for (final legacyFile in await _legacyFiles()) {
        if (!await legacyFile.exists()) continue;
        final value = _decode(await legacyFile.readAsString());
        if (value == null) continue;
        await write(value);
        return value;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<void> write(Map<String, dynamic> value) async {
    final file = await _file();
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(value), flush: true);
  }

  Future<File> _file() async {
    final directory = await getApplicationSupportDirectory();
    return File(p.join(directory.path, 'nexora-session.json'));
  }

  Future<List<File>> _legacyFiles() async {
    final directory = await getApplicationSupportDirectory();
    final home = Platform.environment['HOME'];
    return [
      File(p.join(directory.path, 'fileverse-session.json')),
      File(
        p.join(
          directory.parent.path,
          'com.xuyu.fileverse',
          'fileverse-session.json',
        ),
      ),
      File(p.join(directory.path, 'x-file-session.json')),
      File(
        p.join(directory.parent.path, 'com.xuyu.xfile', 'x-file-session.json'),
      ),
      if (home != null)
        File(
          p.join(
            home,
            'Library',
            'Containers',
            'com.xuyu.fileverse',
            'Data',
            'Library',
            'Application Support',
            'com.xuyu.fileverse',
            'fileverse-session.json',
          ),
        ),
      if (home != null)
        File(
          p.join(
            home,
            'Library',
            'Containers',
            'com.xuyu.xfile',
            'Data',
            'Library',
            'Application Support',
            'com.xuyu.xfile',
            'x-file-session.json',
          ),
        ),
    ];
  }

  Map<String, dynamic>? _decode(String source) {
    final decoded = jsonDecode(source);
    return decoded is Map<String, dynamic> ? decoded : null;
  }
}
