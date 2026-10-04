import 'dart:convert';
import 'dart:io';

import 'package:needtodo/storage.dart';

class MemoryStorage extends JsonStorage {
  final Map<String, Map<String, dynamic>> values = {};
  MemoryStorage() : super(Directory.systemTemp);
  @override
  Future<void> flush() async {}
  @override
  Future<Map<String, dynamic>?> read(String key) async =>
      values[key] == null ? null : jsonDecode(jsonEncode(values[key]));
  @override
  Future<void> write(String key, Map<String, dynamic> data) async {
    values[key] = jsonDecode(jsonEncode(data));
  }
}
