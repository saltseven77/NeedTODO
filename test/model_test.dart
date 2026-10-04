import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:needtodo/model.dart';
import 'package:needtodo/storage.dart';
import 'package:needtodo/store.dart';

void main() {
  test('appearance profiles, alpha, levels and radius survive reload independently', () {
    final d = Document();
    d.calendar.name = '我的月历';
    d.calendar.radius = 36;
    d.calendar.palette.accent = d.calendar.palette.accent.withValues(alpha: .4);
    d.calendar.levelSet.levels.first.name = '稍后';
    final copy = Document.fromJson(d.toJson());
    expect(copy.list.name, '泥土豆');
    expect(copy.list.radius, 22);
    expect(copy.calendar.radius, 36);
    expect(copy.calendar.palette.accent.a, closeTo(.4, .01));
    expect(copy.calendar.levelSet.levels.first.name, '稍后');
    expect(copy.list.levelSet.levels.first.name, '普通');
  });
  test('sync preserves concurrent tasks and deletion tombstones', () {
    final old = Todo(
      id: 'a',
      title: 'old',
      date: '2026-09-28',
      updated: DateTime.utc(2026),
    );
    final gone = old.copy(deleted: true),
        other = Todo(id: 'b', title: 'phone', date: '2026-09-28');
    final merged = mergeDocuments(
      Document(tasks: [gone]),
      Document(tasks: [old, other]),
    );
    expect(merged.tasks.length, 2);
    expect(merged.tasks.firstWhere((e) => e.id == 'a').deleted, true);
  });
  test('deleted tasks discard private contents but still suppress stale device copies', () {
    final old = Todo(
      id: 'deleted-task',
      title: 'private content',
      date: '2026-10-04',
      category: 'private category',
      updated: DateTime.utc(2026, 10, 1),
    );
    final deleted = old.copy(deleted: true);
    final compact = deleted.toJson();
    expect(compact.keys.toSet(), {'id', 'deleted', 'updated'});
    final restored = Todo.fromJson(compact);
    expect(restored.title, isEmpty);
    final merged = mergeDocuments(
      Document(tasks: [old]),
      Document(tasks: [restored]),
    );
    expect(merged.tasks.single.deleted, true);
    expect(merged.tasks.single.id, old.id);
  });
  test(
    'serialized file commits recover the previous complete snapshot',
    () async {
      final dir = await Directory.systemTemp.createTemp('needtodo-test-');
      addTearDown(() => dir.delete(recursive: true));
      final storage = JsonStorage(dir);
      await Future.wait(
        List.generate(20, (i) => storage.write('test', {'value': i})),
      );
      expect((await storage.read('test'))!['value'], 19);
      await File('${dir.path}/test.json').writeAsString('broken');
      expect((await storage.read('test'))!['value'], 18);
    },
  );
  test('local workspace retains ownership and data across reentry', () async {
    final dir = await Directory.systemTemp.createTemp('needtodo-local-');
    addTearDown(() => dir.delete(recursive: true));
    final store = AppStore(JsonStorage(dir));
    await store.load();
    await store.enterLocal();
    await store.saveTask(Todo(title: '本机日程', date: '2026-09-28'));
    await store.enterLocal();
    expect(store.document.tasks.single.title, '本机日程');
    expect(store.account, isNull);
    await store.shutdown();
  });
  test('week boundaries and leap days use local calendar dates', () {
    expect(periodKey('week', DateTime(2024, 1, 1)), '2024-01-01');
    expect(periodKey('week', DateTime(2023, 1, 1)), '2022-12-26');
    expect(dayKey(DateTime(2024, 2, 29)), '2024-02-29');
  });
}
