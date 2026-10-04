import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:needtodo/app.dart';
import 'package:needtodo/model.dart';
import 'package:needtodo/platform_services.dart';
import 'package:needtodo/store.dart';

import 'memory_storage.dart';

void main() {
  testWidgets('maximize restores its icon and preserves normal bounds', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1100, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final calls = <String>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(const MethodChannel('window_manager'), (
      call,
    ) async {
      calls.add(call.method);
      if (call.method == 'getBounds') {
        return {'x': 40.0, 'y': 50.0, 'width': 800.0, 'height': 600.0};
      }
      return call.method.startsWith('is') ? false : null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(
        const MethodChannel('window_manager'),
        null,
      ),
    );
    final storage = MemoryStorage(),
        desktop = DesktopController(MemoryStorage(), calendar: false);
    final store = AppStore(storage)
      ..ready = true
      ..local = true;
    await tester.pumpWidget(NeedTodoApp(store: store, desktop: desktop));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('最大化窗口'));
    await tester.pumpAndSettle();
    expect(calls, contains('maximize'));
    expect(find.byTooltip('还原窗口'), findsOneWidget);
    expect(desktop.expanded, const Rect.fromLTWH(40, 50, 800, 600));
    await desktop.saveNow();
    expect(desktop.expanded, const Rect.fromLTWH(40, 50, 800, 600));
    await tester.tap(find.byTooltip('还原窗口'));
    await tester.pumpAndSettle();
    expect(calls, contains('unmaximize'));
    expect(find.byTooltip('最大化窗口'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await store.shutdown();
    await desktop.close();
  });

  testWidgets('calendar has no date bars and only circles today', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1120, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final today = DateTime.now(), appearance = Appearance();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CalendarWorkspace(
            appearance: appearance,
            selected: today,
            tasks: const [],
            wide: true,
            select: (_) {},
            edit: ([task, date]) async {},
            toggle: (_) {},
            previous: () {},
            next: () {},
            pickDate: () {},
            showAgenda: false,
            toggleAgenda: () {},
            dateHeaders: {dayKey(today): DateHeaderStyle(color: Colors.red)},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final containers = tester
        .widgetList<Container>(
          find.byWidgetPredicate(
            (w) =>
                w is Container &&
                w.key is ValueKey<String> &&
                (w.key as ValueKey<String>).value.startsWith('date-header-'),
          ),
        )
        .toList();
    expect(containers.length, 42);
    expect(
      containers
          .where(
            (c) => (c.decoration as BoxDecoration).color != Colors.transparent,
          )
          .length,
      1,
    );
    final marker = tester.widget<Container>(
      find.byKey(ValueKey('date-header-${dayKey(today)}')),
    );
    expect(marker.constraints!.maxWidth, 24);
    expect((marker.decoration as BoxDecoration).shape, BoxShape.circle);
    expect(
      (marker.decoration as BoxDecoration).color,
      appearance.palette.accent,
    );
    expect(
      find.byTooltip('修改 ${today.month}月${today.day}日 日期颜色'),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });
}
