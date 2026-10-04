import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:needtodo/model.dart';
import 'package:needtodo/store.dart';

import 'memory_storage.dart';

void main() {
  test('unchanged polling does not repaint and late polling cannot undo a check-in', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final task = Todo(title: '读书', date: '2026-09-29');
    final document = Document(tasks: [task]);
    var generation = 0, calls = 0;
    final staleStarted = Completer<void>(), releaseStale = Completer<void>();
    final staleSent = Completer<void>();
    server.listen((request) async {
      if (request.method == 'POST') {
        await request.drain<void>();
        document.tasks = [task.copy(done: true)];
        generation++;
      }
      final body = jsonEncode({
        'document': document.toJson(),
        'generation': generation,
        'local': true,
        'signal': 0,
      });
      if (request.method == 'GET' && ++calls == 3) {
        staleStarted.complete();
        await releaseStale.future;
        request.response.write(body);
        await request.response.close();
        staleSent.complete();
      } else {
        request.response.write(body);
        await request.response.close();
      }
    });
    final store = AppStore(
      MemoryStorage(),
      peer: Uri.parse('http://127.0.0.1:${server.port}'),
    );
    addTearDown(() async {
      if (!releaseStale.isCompleted) releaseStale.complete();
      await store.shutdown();
      await server.close(force: true);
    });
    await store.load();
    var rebuilds = 0;
    store.addListener(() => rebuilds++);
    await staleStarted.future.timeout(const Duration(seconds: 5));
    expect(rebuilds, 0);
    await store.toggleTask(task);
    expect(store.document.tasks.single.done, true);
    expect(rebuilds, 1);
    releaseStale.complete();
    await staleSent.future;
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(store.document.tasks.single.done, true);
    expect(rebuilds, 1);
  });
}
