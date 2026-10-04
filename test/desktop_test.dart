import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:needtodo/platform_services.dart';

import 'memory_storage.dart';

class TestDesktop extends DesktopController {
  TestDesktop(super.storage) : super(calendar: true);
  @override
  Future<Rect> clamp(Rect r) async => r;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('calendar-only startup hides the first frame without hiding later manual shows', () async {
    final calls = <String>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(const MethodChannel('window_manager'), (
      call,
    ) async {
      calls.add(call.method);
      return call.method.startsWith('is') ? false : null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(
        const MethodChannel('window_manager'),
        null,
      ),
    );
    final controller = TestDesktop(MemoryStorage());
    await controller.initialize(showWindow: false);
    expect(calls, isNot(contains('show')));
    expect(calls, contains('setOpacity'));
    calls.clear();
    controller.onWindowEvent('show');
    await Future<void>.delayed(Duration.zero);
    expect(calls.first, 'hide');
    expect(calls, contains('setSkipTaskbar'));
    calls.clear();
    controller.onWindowEvent('show');
    await Future<void>.delayed(Duration.zero);
    expect(calls, isEmpty);
    await controller.close();
  });
  test(
    'initialize waits for saved geometry before exposing the window',
    () async {
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final restored = Completer<void>(), blocked = Completer<void>();
      messenger.setMockMethodCallHandler(
        const MethodChannel('window_manager'),
        (call) async {
          if (call.method == 'setBounds' &&
              (call.arguments as Map)['x'] == 100.0) {
            blocked.complete();
            await restored.future;
          }
          return call.method.startsWith('is') ? false : null;
        },
      );
      addTearDown(
        () => messenger.setMockMethodCallHandler(
          const MethodChannel('window_manager'),
          null,
        ),
      );
      final storage = MemoryStorage();
      await storage.write('window-calendar', {
        'expanded': {'x': 100, 'y': 100, 'w': 800, 'h': 600},
      });
      final c = TestDesktop(storage);
      bool done = false;
      final initializing = c.initialize().then((_) => done = true);
      await blocked.future;
      await Future<void>.delayed(Duration.zero);
      expect(done, false);
      restored.complete();
      await initializing;
      expect(done, true);
      await c.close();
    },
  );
  test(
    'embedding is deferred until settings closes and detached before editing',
    () async {
      final calls = <String>[];
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(native, (call) async {
        calls.add('embed:${call.arguments}');
        return null;
      });
      messenger.setMockMethodCallHandler(
        const MethodChannel('window_manager'),
        (call) async {
          calls.add(call.method);
          return call.method.startsWith('is') ? false : null;
        },
      );
      addTearDown(() {
        messenger.setMockMethodCallHandler(native, null);
        messenger.setMockMethodCallHandler(
          const MethodChannel('window_manager'),
          null,
        );
      });
      final controller = DesktopController(MemoryStorage(), calendar: true);
      await controller.editing(true);
      calls.clear();
      await controller.setLocked(true);
      expect(controller.embedded, true);
      expect(calls, contains('setResizable'));
      expect(calls, isNot(contains('embed:true')));
      await controller.editing(false);
      expect(calls.last, 'embed:true');
      calls.clear();
      await controller.editing(true);
      expect(calls.first, 'embed:false');
      expect(calls, contains('focus'));
      await controller.setLocked(false);
      await controller.editing(false);
      expect(controller.embedded, false);
      expect(controller.locked, false);
    },
  );
  test(
    'failed desktop attach returns to an editable top-level window',
    () async {
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(native, (call) async {
        if (call.arguments == true) throw PlatformException(code: 'desktop');
        return null;
      });
      messenger.setMockMethodCallHandler(
        const MethodChannel('window_manager'),
        (call) async => call.method.startsWith('is') ? false : null,
      );
      addTearDown(() {
        messenger.setMockMethodCallHandler(native, null);
        messenger.setMockMethodCallHandler(
          const MethodChannel('window_manager'),
          null,
        );
      });
      final c = DesktopController(MemoryStorage(), calendar: true);
      await c.editing(true);
      await c.setEmbedded(true);
      await expectLater(c.editing(false), throwsA(isA<PlatformException>()));
      expect(c.embedded, false);
      expect(c.locked, false);
      expect(c.busy, false);
    },
  );
}
