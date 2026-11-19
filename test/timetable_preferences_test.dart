import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:needtodo/store.dart';
import 'package:needtodo/platform_services.dart';
import 'package:needtodo/ui/preferences.dart';

import 'memory_storage.dart';

void main() {
  test(
    'timetable appearance saves independently and survives reopening',
    () async {
      final storage = MemoryStorage();
      final store = AppStore(storage);
      await store.enterLocal();
      final original = store.document.list.name;
      final custom = store.timetableAppearance..name = '我的课程';
      custom.palette.background = const Color(0xfff0e5db);
      await store.dispatch({
        'type': 'preferences',
        'profiles': {'timetable': custom.toJson()},
      });
      expect(store.document.list.name, original);
      expect(store.timetableAppearance.name, '我的课程');
      await store.shutdown();
      final reopened = AppStore(storage);
      await reopened.load();
      expect(reopened.timetableAppearance.name, '我的课程');
      expect(
        reopened.timetableAppearance.palette.background,
        const Color(0xfff0e5db),
      );
      expect(reopened.document.list.name, original);
      await reopened.shutdown();
    },
  );
  testWidgets('course settings display on narrow Android screens', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = AppStore(MemoryStorage())..local = true;
    final services = PlatformServices(android: true);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SettingsView(
              store: store,
              layout: 'timetable',
              services: services,
              preview: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('课程表'), findsWidgets);
    expect(find.text('课程颜色套组'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    services.dispose();
    await store.shutdown();
  });
  testWidgets('an open editor cannot collapse into the floating ball', (
    tester,
  ) async {
    final calls = <String>[];
    const channel = MethodChannel('window_manager');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final desktop = DesktopController(MemoryStorage(), calendar: false);
    await desktop.editing(true);
    await desktop.collapse();
    expect(desktop.collapsed, false);
    expect(calls, isEmpty);
    desktop.onWindowMinimize();
    await tester.pump();
    expect(desktop.collapsed, false);
    expect(calls, isEmpty);
    await desktop.editing(false);
    desktop.dispose();
  });
}
