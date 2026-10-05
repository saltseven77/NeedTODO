import 'memory_storage.dart';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:needtodo/app.dart';

import 'package:needtodo/store.dart';

void main() {
  for (final size in [
    const Size(320, 568),
    const Size(844, 390),
    const Size(360, 780),
    const Size(390, 844),
    const Size(1024, 768),
    const Size(1366, 900),
  ]) {
    testWidgets('local list and calendar settings at $size', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = AppStore(MemoryStorage())..ready = true;
      await tester.pumpWidget(NeedTodoApp(store: store));
      expect(find.text('本机使用'), findsOneWidget);
      await tester.ensureVisible(find.text('本机使用'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('本机使用'));
      await tester.pumpAndSettle();
      expect(find.textContaining('无法跨设备同步'), findsOneWidget);
      await tester.tap(find.text('继续使用'));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 80)),
      );
      await tester.pumpAndSettle();
      expect(find.byTooltip('详细添加'), findsOneWidget);
      await tester.enterText(find.byType(TextField).first, '新日程');
      await tester.tap(find.byTooltip('添加'));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 80)),
      );
      await tester.pumpAndSettle();
      expect(find.text('新日程'), findsOneWidget);
      await tester.tap(find.byTooltip('月历'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('展开日程清单'), findsOneWidget);
      expect(find.byTooltip('添加当天日程'), findsNothing);
      await tester.tap(find.byTooltip('展开日程清单'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('收起日程清单'), findsOneWidget);
      await tester.tap(find.byTooltip('收起日程清单'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('添加当天日程'), findsNothing);
      await tester.tap(find.byTooltip('设置'));
      await tester.pumpAndSettle();
      expect(find.text('设置'), findsOneWidget);
      final original = store.document.list.paletteId;
      await tester.ensureVisible(find.text('青苔'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('青苔'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('保存'),
        450,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(find.text('保存'));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 80)),
      );
      await tester.pumpAndSettle();
      expect(store.document.calendar.paletteId, 'sage');
      expect(store.document.list.paletteId, original);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
  testWidgets('date picker and editor stay usable above the keyboard', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = AppStore(MemoryStorage())
      ..ready = true
      ..local = true;
    await tester.pumpWidget(NeedTodoApp(store: store));
    await tester.tap(find.byTooltip('详细添加'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, '日程内容'), '中文输入');
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    tester.view.resetViewInsets();
    await tester.pumpWidget(const SizedBox());
  });
}
