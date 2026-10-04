import 'dart:io';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:needtodo/model.dart';
import 'package:needtodo/store.dart';
import 'package:needtodo/ui/components.dart';
import 'package:needtodo/ui/journal.dart';

import 'memory_storage.dart';

void main() {
  test('sticker style preserves independent fill, outline and text, including legacy bold', () {
    final legacy = NoteStyle.fromJson({'ink': 0xff445566, 'bold': true});
    expect(legacy.fontWeight, 600);
    expect(legacy.edge, legacy.ink);
    final custom = NoteStyle(
      paper: const Color(0x60d4e2dc),
      ink: const Color(0xff573641),
      border: const Color(0xff77918a),
      borderWidth: 3.5,
      fontSize: 45.5,
      fontWeight: 300,
    ).clone();
    expect(custom.paper, const Color(0x60d4e2dc));
    expect(custom.ink, const Color(0xff573641));
    expect(custom.border, const Color(0xff77918a));
    expect(custom.borderWidth, 3.5);
    expect(custom.fontSize, 45.5);
    expect(custom.fontWeight, 300);
  });
  testWidgets(
    'shape properties and typography remain independent after reopening',
    (tester) async {
      tester.view.physicalSize = const Size(1100, 950);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final storage = MemoryStorage();
      final store = AppStore(storage)
        ..ready = true
        ..local = true;
      await tester.pumpWidget(
        MaterialApp(
          theme: appTheme(),
          home: Scaffold(
            body: JournalWorkspace(
              store: store,
              accent: Colors.blue,
              initialDate: DateTime(2026, 10, 1),
            ),
          ),
        ),
      );
      await tester.tap(find.byTooltip('添加贴纸或文本'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('圆形'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('大小与文字'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('sticker-property-宽度')),
        '220',
      );
      await tester.enterText(
        find.byKey(const ValueKey('sticker-property-高度')),
        '150',
      );
      await tester.enterText(
        find.byKey(const ValueKey('sticker-property-边框粗细')),
        '3',
      );
      await tester.enterText(
        find.byKey(const ValueKey('sticker-property-text')),
        '周末的小事',
      );
      await tester.tap(find.text('完成'));
      await tester.pumpAndSettle();
      for (final field in {
        '字体颜色': 'A04050',
        '边框颜色': '507080',
        '区域底色': 'E3EBDD',
      }.entries) {
        await tester.tap(find.byTooltip(field.key));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField).last, field.value);
        await tester.tap(find.text('完成'));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.byTooltip('字号'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('24'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('字体粗细'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('粗体'));
      await tester.pumpAndSettle();
      await store.flushDrafts();
      await tester.pump();
      final sticker = store.document.journals['2026-09-28']!
          .day('2026-10-01')
          .stickers
          .single;
      expect(sticker.width, 220);
      expect(sticker.height, 150);
      expect(sticker.text, '周末的小事');
      expect(sticker.style.borderWidth, 3);
      expect(sticker.style.border, const Color(0xff507080));
      expect(sticker.style.ink, const Color(0xffa04050));
      expect(sticker.style.paper.toARGB32() & 0xffffff, 0xe3ebdd);
      expect(sticker.style.paper.a, greaterThan(0));
      expect(sticker.style.fontSize, 24);
      expect(sticker.style.fontWeight, 700);
      final label = tester.widget<TextField>(
        find.descendant(
          of: find.byKey(ValueKey('sticker-label-${sticker.id}')),
          matching: find.byType(TextField),
        ),
      );
      expect(label.style!.color, sticker.style.ink);
      expect(label.style!.fontWeight, FontWeight.w700);
      final painter = tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .map((w) => w.painter)
          .whereType<JournalShape>()
          .single;
      expect(painter.ink, sticker.style.border);
      expect(painter.paper, sticker.style.paper);
      final reloaded = AppStore(storage);
      await reloaded.enterLocal();
      expect(
        reloaded.document.journals['2026-09-28']!
            .day('2026-10-01')
            .stickers
            .single
            .style
            .toJson(),
        sticker.style.toJson(),
      );
      await tester.pumpWidget(const SizedBox());
      await store.shutdown();
      await reloaded.shutdown();
      expect(tester.takeException(), isNull);
    },
  );
  test(
    'week merge retains edits to separate days and stickers and date resets',
    () {
      final a = JournalWeek('2026-09-28'), b = JournalWeek('2026-09-28');
      a.day('2026-09-28')
        ..text = '电脑上的记录'
        ..updated = DateTime.utc(2026, 10, 4);
      b.day('2026-09-29')
        ..text = '手机上的记录'
        ..updated = DateTime.utc(2026, 10, 4);
      a.board.add(
        JournalSticker(
          id: 'a',
          kind: 'rect',
          updated: DateTime.utc(2026, 10, 4),
        ),
      );
      b.board.add(
        JournalSticker(
          id: 'b',
          kind: 'text',
          text: '自由页',
          updated: DateTime.utc(2026, 10, 4),
        ),
      );
      final gone = JournalSticker(
        id: 'old',
        deleted: true,
        updated: DateTime.utc(2026, 10, 4),
      );
      a.board.add(gone);
      b.board.add(
        JournalSticker(
          id: 'old',
          kind: 'image',
          image: 'private',
          updated: DateTime.utc(2026, 10, 1),
        ),
      );
      final merged = mergeDocuments(
        Document(
          journals: {a.key: a},
          dateHeaders: {
            '2026-10-04': DateHeaderStyle(updated: DateTime.utc(2026, 10, 4)),
          },
        ),
        Document(
          journals: {b.key: b},
          dateHeaders: {
            '2026-10-04': DateHeaderStyle(
              color: Colors.red,
              updated: DateTime.utc(2026, 10, 1),
            ),
          },
        ),
      ).clone();
      expect(merged.journals[a.key]!.day('2026-09-28').text, '电脑上的记录');
      expect(merged.journals[a.key]!.day('2026-09-29').text, '手机上的记录');
      expect(merged.journals[a.key]!.board.where((e) => !e.deleted).length, 2);
      expect(
        merged.journals[a.key]!.board.firstWhere((e) => e.id == 'old').image,
        isEmpty,
      );
      expect(merged.dateHeaders['2026-10-04']!.color, isNull);
    },
  );
  test('date header follows accent opacity and per-day overrides', () {
    final appearance = Appearance();
    appearance.palette.accent = const Color(0x804d83a3);
    final today = DateTime(2026, 10, 4);
    expect(
      calendarDateHeaderColor(DateTime(2026, 10, 3), today, appearance).a,
      closeTo(appearance.palette.accent.a * .5, .005),
    );
    expect(
      calendarDateHeaderColor(today, today, appearance).a,
      closeTo(appearance.palette.accent.a * .7, .005),
    );
    expect(
      calendarDateHeaderColor(DateTime(2026, 10, 5), today, appearance),
      Colors.transparent,
    );
    expect(
      calendarDateHeaderColor(
        today,
        today,
        appearance,
        DateHeaderStyle(color: Colors.pink),
      ),
      Colors.pink,
    );
  });
  testWidgets(
    'journal saves writing and movable resizable stickers across reload',
    (tester) async {
      tester.view.physicalSize = const Size(1100, 850);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final storage = MemoryStorage(),
          store = AppStore(storage)
            ..ready = true
            ..local = true;
      await tester.pumpWidget(
        MaterialApp(
          theme: appTheme(),
          home: Scaffold(
            body: JournalWorkspace(
              store: store,
              accent: Colors.blue,
              initialDate: DateTime(2026, 10, 1),
            ),
          ),
        ),
      );
      final field = find.descendant(
        of: find.byKey(const ValueKey('journal-text-2026-10-01')),
        matching: find.byType(TextField),
      );
      await tester.enterText(field, '今天，留一点时间给自己。');
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump();
      expect(
        store.document.journals['2026-09-28']!.day('2026-10-01').text,
        '今天，留一点时间给自己。',
      );
      await tester.tap(find.byTooltip('添加贴纸或文本'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('方框'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump();
      final before = store.document.journals['2026-09-28']!
          .day('2026-10-01')
          .stickers
          .single;
      final id = before.id, x = before.x, width = before.width;
      await tester.drag(find.byKey(ValueKey('move-$id')), const Offset(26, 8));
      await tester.pump();
      await tester.drag(
        find.byKey(ValueKey('resize-$id')),
        const Offset(25, 16),
      );
      await store.flushDrafts();
      await tester.pump();
      final after = store.document.journals['2026-09-28']!
          .day('2026-10-01')
          .stickers
          .single;
      expect(after.x, greaterThan(x));
      expect(after.width, greaterThan(width));
      final reload = AppStore(storage);
      await reload.enterLocal();
      expect(
        reload.document.journals['2026-09-28']!.day('2026-10-01').text,
        '今天，留一点时间给自己。',
      );
      expect(
        reload.document.journals['2026-09-28']!
            .day('2026-10-01')
            .stickers
            .single
            .width,
        after.width,
      );
      await tester.enterText(field, '退出前最后一笔。');
      await store.shutdown();
      final closed = Document.fromJson(storage.values['local']!['document']);
      expect(closed.journals['2026-09-28']!.day('2026-10-01').text, '退出前最后一笔。');
      await tester.pumpWidget(const SizedBox());
      await reload.shutdown();
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('narrow journal switches to a patterned free page', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 780);
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
            accent: Colors.blue,
            initialDate: DateTime(2026, 10, 1),
          ),
        ),
      ),
    );
    await tester.tap(find.text('自由页').first);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('纸张背景'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('方格'));
    await tester.pumpAndSettle();
    await store.flushDrafts();
    await tester.pump();
    expect(store.document.journals['2026-09-28']!.style.pattern, 'grid');
    expect(find.byKey(const ValueKey('journal-canvas-board')), findsOneWidget);
    expect(tester.takeException(), isNull);
    expect(find.text('已保存'), findsNothing);
    expect(find.byTooltip('上传图片贴纸'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await store.shutdown();
  });
  testWidgets('journal visual preview', (tester) async {
    if (Platform.environment['NEEDTODO_PREVIEW'] == '1' && Platform.isWindows) {
      await tester.runAsync(() async {
        for (final entry in {
          'Segoe UI': 'C:/Windows/Fonts/msyh.ttc',
          'Microsoft YaHei UI': 'C:/Windows/Fonts/msyh.ttc',
          'packages/cupertino_icons/CupertinoIcons': '.cache/pub/hosted/pub.dev/cupertino_icons-1.0.9/assets/CupertinoIcons.ttf',
        }.entries) {
          final file = File(entry.value);
          if (!await file.exists()) continue;
          final loader = FontLoader(entry.key)
            ..addFont(
              Future.value(ByteData.sublistView(await file.readAsBytes())),
            );
          await loader.load();
        }
      });
    }
    tester.view.physicalSize = const Size(1120, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final week = JournalWeek('2026-09-28');
    for (var i = 0; i < 7; i++) {
      week.day(dayKey(DateTime(2026, 9, 28 + i)))
        ..text = [
          '把想做的小事写下来。',
          '午后散步，给自己留一点空白。',
          '读完一章书，整理桌面。',
          '今天的天气很好。',
          '晚饭后慢慢走回家。',
          '给这周留下一点记录。',
          '休息，也是一件重要的小事。',
        ][i]
        ..height = 64;
    }
    week.day('2026-09-30').style.paper = const Color(0x18a3b6ab);
    week.style.pattern = 'grid';
    week.board.addAll([
      JournalSticker(
        id: 'heading',
        text: '这一周的小事',
        x: 24,
        y: 26,
        width: 310,
        height: 60,
        style: NoteStyle(fontSize: 22),
      ),
      JournalSticker(
        id: 'note',
        text: '做一点喜欢的事，\n也留一点时间给自己。',
        x: 24,
        y: 110,
        width: 290,
        height: 95,
        style: NoteStyle(ink: const Color(0xff4d83a3), fontSize: 15),
      ),
      JournalSticker(
        id: 'dots',
        kind: 'dots',
        x: 270,
        y: 235,
        width: 110,
        height: 90,
        style: NoteStyle(ink: const Color(0xff9daea5)),
      ),
      JournalSticker(
        id: 'box',
        kind: 'rect',
        x: 24,
        y: 275,
        width: 200,
        height: 125,
        style: NoteStyle(
          ink: const Color(0xff9daea5),
          paper: const Color(0x159daea5),
        ),
      ),
    ]);
    week.board.add(
      JournalSticker(
        id: 'uploaded-image',
        kind: 'image',
        image:
            'data:image/png;base64,${base64Encode(File('assets/potato.png').readAsBytesSync())}',
        x: 250,
        y: 380,
        width: 120,
        height: 120,
      ),
    );
    final store = AppStore(MemoryStorage())
      ..ready = true
      ..local = true;
    store.document.journals[week.key] = week;
    final boundary = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme(),
        home: Scaffold(
          body: RepaintBoundary(
            key: boundary,
            child: ColoredBox(
              color: panel,
              child: JournalWorkspace(
                store: store,
                accent: const Color(0xff4d83a3),
                initialDate: DateTime(2026, 10, 1),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    if (Platform.environment['NEEDTODO_PREVIEW'] == '1') {
      await tester.runAsync(() async {
        final image = tester.widget<Image>(find.byType(Image).last);
        await precacheImage(image.image, boundary.currentContext!);
      });
      await tester.pump();
      await tester.runAsync(() async {
        final image =
            await (boundary.currentContext!.findRenderObject()
                    as RenderRepaintBoundary)
                .toImage(pixelRatio: 1.5);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        final file = File('.cache/previews/journal-wide.png');
        await file.parent.create(recursive: true);
        await file.writeAsBytes(data!.buffer.asUint8List());
        image.dispose();
      });
    }
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await store.shutdown();
  });
}
