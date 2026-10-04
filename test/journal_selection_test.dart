import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:needtodo/model.dart';
import 'package:needtodo/storage.dart';
import 'package:needtodo/store.dart';
import 'package:needtodo/ui/components.dart';
import 'package:needtodo/ui/journal.dart';

import 'memory_storage.dart';

class PausedStorage extends MemoryStorage {
  bool paused = false;
  final gate = Completer<void>();
  @override
  Future<void> write(String key, Map<String, dynamic> value) async {
    if (paused) await gate.future;
    await super.write(key, value);
  }
}

Future<AppStore> setup(WidgetTester tester, {MemoryStorage? storage}) async {
  tester.view.physicalSize = const Size(1120, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final store = AppStore(storage ?? MemoryStorage())
    ..ready = true
    ..local = true;
  final week = JournalWeek('2026-09-28');
  week.day('2026-10-01')
    ..height = 210
    ..stickers = [
      JournalSticker(
        id: 'lower',
        kind: 'note',
        text: '便签 A',
        x: 20,
        y: 20,
        width: 160,
        height: 110,
        layer: 1,
        style: NoteStyle(paper: const Color(0xffffefb3)),
      ),
      JournalSticker(
        id: 'upper',
        kind: 'note',
        text: '便签 B',
        x: 60,
        y: 30,
        width: 160,
        height: 100,
        layer: 2,
        style: NoteStyle(paper: const Color(0xffdceaf3)),
      ),
    ];
  week.day('2026-10-02').height = 200;
  store.document.journals[week.key] = week;
  await tester.pumpWidget(
    MaterialApp(
      theme: appTheme(),
      home: Scaffold(
        body: JournalWorkspace(
          store: store,
          accent: blue,
          initialDate: DateTime(2026, 10, 1),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return store;
}

Future<void> choose(WidgetTester tester, String label) async {
  await tester.tap(find.byTooltip('选择对象'));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

void main() {
  test('snapshot copies mutable containers without copying image strings', () {
    final week = JournalWeek('2026-09-28')
      ..board.add(
        JournalSticker(
          kind: 'list',
          text: '一',
          checked: [0],
          image: 'large image',
        ),
      );
    final document = Document(journals: {week.key: week});
    final copy = document.clone();
    copy.journals[week.key]!.board.first.checked.clear();
    copy.journals[week.key]!.board.first.style.fontSize = 24;
    expect(week.board.first.checked, [0]);
    expect(week.board.first.style.fontSize, 13);
    expect(
      identical(
        copy.journals[week.key]!.board.first.image,
        week.board.first.image,
      ),
      true,
    );
  });

  testWidgets('dropdown selection drags the covered note by its body', (
    tester,
  ) async {
    final store = await setup(tester);
    await choose(tester, '10月1日 · 便签 · 便签 A');
    final canvas = find.byKey(const ValueKey('journal-canvas-2026-10-01'));
    final scale = tester.getSize(canvas).width / 360;
    final origin = tester.getTopLeft(canvas);
    final drag = await tester.startGesture(
      origin + Offset(90 * scale, 60 * scale),
    );
    await drag.moveBy(Offset(18 * scale, 12 * scale));
    await drag.moveBy(Offset(32 * scale, 8 * scale));
    await drag.up();
    await tester.pump(const Duration(milliseconds: 80));
    await store.flushDrafts();
    final items = store.document.journals['2026-09-28']!
        .day('2026-10-01')
        .stickers;
    expect(items.first.x, closeTo(70, 2));
    expect(items.last.x, 60);
    expect(find.byKey(const ValueKey('selection-lower')), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await store.shutdown();
  });

  testWidgets(
    'object moves to the right page with a deletion marker in the original day',
    (tester) async {
      final store = await setup(tester);
      await choose(tester, '10月1日 · 便签 · 便签 A');
      final source = find.byKey(const ValueKey('journal-canvas-2026-10-01'));
      final destination = find.byKey(const ValueKey('journal-canvas-board'));
      final scale = tester.getSize(source).width / 360;
      final start = tester.getTopLeft(source) + Offset(90 * scale, 60 * scale);
      final end =
          tester.getTopLeft(destination) + Offset(180 * scale, 120 * scale);
      final drag = await tester.startGesture(start);
      await drag.moveBy(const Offset(20, 0));
      await drag.moveTo(end);
      await drag.up();
      await tester.pumpAndSettle();
      await store.flushDrafts();
      final week = store.document.journals['2026-09-28']!;
      expect(week.day('2026-10-01').stickers.first.deleted, true);
      expect(week.board.single.id, 'lower');
      expect(week.board.single.text, '便签 A');
      expect(week.board.single.deleted, false);
      expect(find.byKey(const ValueKey('selection-lower')), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await store.shutdown();
    },
  );

  testWidgets('delete disappears before a slow write finishes', (tester) async {
    final storage = PausedStorage();
    final store = await setup(tester, storage: storage);
    await choose(tester, '10月1日 · 便签 · 便签 A');
    storage.paused = true;
    await tester.tap(find.byTooltip('删除贴纸'));
    await tester.pump();
    expect(find.byKey(const ValueKey('sticker-lower')), findsNothing);
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.byKey(const ValueKey('sticker-lower')), findsNothing);
    storage.gate.complete();
    await store.flushDrafts();
    await tester.pumpWidget(const SizedBox());
    await store.shutdown();
  });

  test(
    'background file encoding retains an independent atomic snapshot',
    () async {
      final directory = await Directory.systemTemp.createTemp('needtodo-json-');
      try {
        final storage = JsonStorage(directory);
        final data = <String, dynamic>{
          'list': [1, 2],
          'document': {'name': 'saved'},
        };
        final write = storage.write('test', data);
        (data['list'] as List).clear();
        data['document']['name'] = 'changed';
        await write;
        expect((await storage.read('test'))!['list'], [1, 2]);
        expect((await storage.read('test'))!['document']['name'], 'saved');
      } finally {
        if (!directory.absolute.path.startsWith(
          Directory.systemTemp.absolute.path,
        )) {
          throw StateError('Unexpected test directory');
        }
        await directory.delete(recursive: true);
      }
    },
  );
}
