import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

dynamic _snapshotJson(dynamic value) {
  if (value is Map) {
    return value.map(
      (key, value) => MapEntry(key.toString(), _snapshotJson(value)),
    );
  }
  if (value is List) return value.map(_snapshotJson).toList();
  return value;
}

String _encodeSnapshot(Map<String, dynamic> value) => jsonEncode(value);

/// A single writer serializes commits. The previous complete snapshot survives a
/// crash between renaming the current file and promoting the temporary file.
class JsonStorage {
  final Directory directory;
  Future<void> _queue = Future.value();
  JsonStorage(this.directory);
  Future<Map<String, dynamic>?> read(String key) async {
    for (final suffix in ['', '.bak']) {
      try {
        final v = jsonDecode(
          await File('${directory.path}/$key.json$suffix').readAsString(),
        );
        if (v is Map<String, dynamic>) return v;
      } on FileSystemException {
        continue;
      } on FormatException {
        continue;
      }
    }
    return null;
  }

  Future<void> write(String key, Map<String, dynamic> data) {
    final snapshot = Map<String, dynamic>.from(_snapshotJson(data));
    final op = _queue.then((_) async {
      final bytes = await compute(_encodeSnapshot, snapshot);
      await directory.create(recursive: true);
      final file = File('${directory.path}/$key.json'),
          temp = File('${directory.path}/$key.json.tmp'),
          backup = File('${directory.path}/$key.json.bak');
      await temp.writeAsString(bytes, flush: true);
      if (await file.exists()) {
        if (await backup.exists()) await backup.delete();
        await file.rename(backup.path);
      }
      await temp.rename(file.path);
    });
    _queue = op.catchError((Object _) {});
    return op;
  }

  Future<void> flush() => _queue;
}
