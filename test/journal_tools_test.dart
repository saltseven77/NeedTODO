import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:needtodo/model.dart';
import 'package:needtodo/store.dart';
import 'package:needtodo/ui/components.dart';
import 'package:needtodo/ui/journal.dart';

import 'memory_storage.dart';

Future<AppStore> showJournal(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1120, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final store = AppStore(MemoryStorage())
    ..ready = true
    ..local = true;
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

void main() {
  test('white paper, small rotated objects and drawing layers survive serialization', () {
    final week = JournalWeek('2026-09-28');
    expect(week.style.paper, Colors.white);
    week.board.add(
      JournalSticker(
        id: 'ink',
        kind: 'highlight',
        width: 6,
        height: 5,
        rotation: -45,
        layer: -2,
        points: const [Offset(0, .2), Offset(1, .8)],
        strokeWidth: 12,
      ),
    );
    week.board.add(
      JournalSticker(
        id: 'list',
        kind: 'list',
        listType: 'check',
        checked: [1],
        text: '一\n二',
        layer: 3,
      ),
    );
    final restored = week.clone();
    expect(restored.board.first.width, 6);
    expect(restored.board.first.rotation, -45);
    expect(restored.board.first.points, const [Offset(0, .2), Offset(1, .8)]);
    expect(restored.board.last.checked, [1]);
    expect(orderedJournalItems(restored.board).first.id, 'ink');
    final old = week.toJson();
    old['style']['paper'] = 0xfffaf9f5;
    expect(JournalWeek.fromJson(week.key, old).style.paper, Colors.white);
  });

  testWidgets('notes, layer ordering, tiny resizing and aligned pages', (
    tester,
  ) async {
    final store = await showJournal(tester);
    await tester.tap(find.byTooltip('便签纸'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('雾蓝'));
    await tester.pumpAndSettle();
    await store.flushDrafts();
    var items = store.document.journals['2026-09-28']!
        .day('2026-10-01')
        .stickers;
    final note = items.single;
    expect(note.kind, 'note');
    expect(note.style.paper, const Color(0xffdceaf3));
    final noteBox = tester.getRect(find.byKey(ValueKey('sticker-${note.id}')));
    final center = noteBox.center + const Offset(0, 6);
    final rotation = await tester.startGesture(
      tester.getCenter(find.byKey(ValueKey('rotate-${note.id}'))),
    );
    await rotation.moveBy(const Offset(6, 0));
    await rotation.moveTo(center + const Offset(90, 0));
    await rotation.up();
    await tester.pumpAndSettle();
    await store.flushDrafts();
    expect(
      store.document.journals['2026-09-28']!
          .day('2026-10-01')
          .stickers
          .first
          .rotation
          .abs(),
      greaterThan(10),
    );
    await tester.tap(find.byTooltip('添加贴纸或文本'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('方框'));
    await tester.pumpAndSettle();
    await store.flushDrafts();
    items = store.document.journals['2026-09-28']!.day('2026-10-01').stickers;
    final id = items.last.id;
    await tester.tap(find.byTooltip('图层顺序'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('置于底层'));
    await tester.pumpAndSettle();
    await tester.drag(
      find.byKey(ValueKey('resize-$id')),
      const Offset(-300, -300),
    );
    await store.flushDrafts();
    await tester.pump();
    items = store.document.journals['2026-09-28']!.day('2026-10-01').stickers;
    expect(orderedJournalItems(items).first.id, id);
    expect(items.last.width, 4);
    expect(items.last.height, 4);
    final field = find.descendant(
      of: find.byKey(const ValueKey('journal-text-2026-10-01')),
      matching: find.byType(TextField),
    );
    await tester.enterText(field, List.filled(12, '把这一天写下来。').join('\n'));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump();
    expect(
      tester.getSize(find.byKey(const ValueKey('journal-week-page'))).height,
      closeTo(
        tester.getSize(find.byKey(const ValueKey('journal-free-page'))).height,
        1,
      ),
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await store.shutdown();
  });

  testWidgets(
    'highlighter holds straight, rotates and shares layers with stickers',
    (tester) async {
      final store = await showJournal(tester);
      await tester.tap(find.byTooltip('荧光笔'));
      await tester.pumpAndSettle();
      final canvas = find.byKey(const ValueKey('journal-canvas-board'));
      final origin = tester.getTopLeft(canvas);
      final stroke = await tester.startGesture(origin + const Offset(40, 70));
      await stroke.moveTo(origin + const Offset(100, 115));
      await stroke.moveTo(origin + const Offset(170, 85));
      await tester.pump(const Duration(milliseconds: 550));
      await stroke.up();
      await tester.pumpAndSettle();
      await store.flushDrafts();
      final marker = store.document.journals['2026-09-28']!.board.single;
      expect(marker.kind, 'highlight');
      expect(marker.points.length, 2);
      expect(marker.layer, lessThan(0));
      await tester.tap(find.byTooltip('退出荧光笔'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('旋转').first);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).last, '35');
      await tester.tap(find.text('完成'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('图层顺序'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('置于顶层'));
      await tester.pumpAndSettle();
      await store.flushDrafts();
      final result = store.document.journals['2026-09-28']!.board.single;
      expect(result.rotation, 35);
      expect(result.layer, greaterThan(0));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await store.shutdown();
    },
  );

  testWidgets(
    'double clicking an existing sticker does not create a text box',
    (tester) async {
      final store = await showJournal(tester);
      await tester.tap(find.byKey(const ValueKey('journal-canvas-board')));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('便签纸'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('樱花粉'));
      await tester.pumpAndSettle();
      final week =
          store.pendingJournals['2026-09-28'] ??
          store.document.journals['2026-09-28'];
      final entry = week!.board.single;
      final field = find.descendant(
        of: find.byKey(ValueKey('sticker-${entry.id}')),
        matching: find.byType(TextField),
      );
      await tester.enterText(field, '一点开心');
      await tester.tap(field);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(field);
      await tester.pumpAndSettle();
      await store.flushDrafts();
      expect(store.document.journals['2026-09-28']!.board.length, 1);
      expect(store.document.journals['2026-09-28']!.board.single.text, '一点开心');
      await tester.tap(find.byTooltip('快速列表'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('勾选列表'));
      await tester.pumpAndSettle();
      final list =
          (store.pendingJournals['2026-09-28'] ??
                  store.document.journals['2026-09-28'])!
              .board
              .last;
      await tester.tap(
        find
            .descendant(
              of: find.byKey(ValueKey('sticker-${list.id}')),
              matching: find.byIcon(CupertinoIcons.square),
            )
            .first,
      );
      await store.flushDrafts();
      expect(store.document.journals['2026-09-28']!.board.last.checked, [0]);
      await tester.pumpWidget(const SizedBox());
      await store.shutdown();
    },
  );
  testWidgets('quick checkbox list inserts next item and keeps check state', (
    tester,
  ) async {
    final store = await showJournal(tester);
    await tester.tap(find.byTooltip('快速列表'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('勾选列表'));
    await tester.pumpAndSettle();
    final entry =
        (store.pendingJournals['2026-09-28'] ??
                store.document.journals['2026-09-28'])!
            .day('2026-10-01')
            .stickers
            .single;
    Finder line(int i) => find.descendant(
      of: find.byKey(ValueKey('list-${entry.id}-$i')),
      matching: find.byType(TextField),
    );
    await tester.enterText(line(0), '整理桌面');
    await tester.testTextInput.receiveAction(TextInputAction.next);
    await tester.pumpAndSettle();
    await tester.enterText(line(1), '读完一章书');
    await tester.tap(
      find
          .descendant(
            of: find.byKey(ValueKey('sticker-${entry.id}')),
            matching: find.byIcon(CupertinoIcons.square),
          )
          .first,
    );
    await store.flushDrafts();
    await tester.pump();
    final saved = store.document.journals['2026-09-28']!
        .day('2026-10-01')
        .stickers
        .single;
    expect(saved.text, '整理桌面\n读完一章书');
    expect(saved.checked, [0]);
    await tester.pumpWidget(const SizedBox());
    await store.shutdown();
  });
}
