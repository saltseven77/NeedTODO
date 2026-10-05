import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:needtodo/model.dart';
import 'package:needtodo/store.dart';

import 'memory_storage.dart';

class InterruptedClient extends http.BaseClient {
  int attempts = 0;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    attempts++;
    if (attempts == 1) {
      return http.StreamedResponse(
        Stream<List<int>>.error(
          http.ClientException(
            'Connection closed while receiving data',
            request.url,
          ),
        ),
        200,
      );
    }
    return http.StreamedResponse(
      Stream.value(
        utf8.encode(
          jsonEncode({
            'revision': 3,
            'document': Document(
              tasks: [Todo(title: 'Downloaded task', date: '2026-10-05')],
            ).toJson(),
          }),
        ),
      ),
      200,
    );
  }
}

class ReadableCloud extends AppStore {
  final Document cloud;
  int uploads = 0;
  bool failUpload = false;
  ReadableCloud(super.storage, this.cloud);
  @override
  Future<Map<String, dynamic>> request(
    String method,
    String path, [
    Map<String, dynamic>? body,
  ]) async {
    if (method == 'GET') return {'revision': 8, 'document': cloud.toJson()};
    uploads++;
    if (failUpload) {
      throw http.ClientException('Connection closed while receiving data');
    }
    return {'revision': 9, 'document': body!['document']};
  }
}

void main() {
  test(
    'a truncated sync response is retried including body stream errors',
    () async {
      final client = InterruptedClient();
      final store = AppStore(MemoryStorage(), httpClient: client);
      final result = await store.request('GET', '/v2/sync');
      expect(client.attempts, 2);
      expect(
        (result['document']['tasks'] as List).single['title'],
        'Downloaded task',
      );
      await store.shutdown();
    },
  );
  test(
    'read-only sync downloads cloud content without a redundant upload',
    () async {
      final store =
          ReadableCloud(
              MemoryStorage(),
              Document(
                tasks: [Todo(title: 'Cloud content', date: '2026-10-05')],
              ),
            )
            ..account = {
              'id': 'fixture',
              'username': 'fixture',
              'githubLogin': 'bound',
            };
      await store.sync();
      expect(store.document.tasks.single.title, 'Cloud content');
      expect(store.uploads, 0);
      expect(store.revision, 8);
      await store.shutdown();
    },
  );
  test('downloaded data remains visible and persisted if uploading local changes fails', () async {
    final storage = MemoryStorage();
    final store =
        ReadableCloud(
            storage,
            Document(
              tasks: [Todo(title: 'Cloud content', date: '2026-10-05')],
            ),
          )
          ..account = {
            'id': 'fixture',
            'username': 'fixture',
            'githubLogin': 'bound',
          }
          ..failUpload = true;
    await store.saveTask(Todo(title: 'Local draft', date: '2026-10-05'));
    await expectLater(store.sync(), throwsA(isA<http.ClientException>()));
    expect(store.document.tasks.map((t) => t.title).toSet(), {
      'Cloud content',
      'Local draft',
    });
    expect(
      (storage.values.values.single['document']['tasks'] as List).length,
      2,
    );
    expect(store.syncing, false);
    await store.shutdown();
  });
}
