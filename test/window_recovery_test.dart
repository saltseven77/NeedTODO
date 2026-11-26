import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:needtodo/platform_services.dart';

import 'memory_storage.dart';

class RestoreDesktop extends DesktopController {
  RestoreDesktop() : super(MemoryStorage(), calendar: false);
  @override
  Future<Rect> clamp(Rect r) async => r;
}

class WakeDesktop extends DesktopController {
  int expansions = 0;
  WakeDesktop() : super(MemoryStorage(), calendar: false);
  @override
  Future<void> expand() async {
    expansions++;
    collapsed = false;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'reopening a hidden maximized window restores native state before bounds',
    () async {
      final calls = <String>[];
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        const MethodChannel('window_manager'),
        (c) async {
          calls.add(c.method);
          return c.method.startsWith('is') ? false : null;
        },
      );
      messenger.setMockMethodCallHandler(native, (c) async => null);
      final controller = RestoreDesktop()
        ..expanded = const Rect.fromLTWH(40, 50, 430, 700)
        ..maximized = true;
      await controller.expand();
      expect(calls.indexOf('unmaximize'), lessThan(calls.indexOf('setBounds')));
      expect(controller.maximized, false);
      controller.dispose();
      messenger.setMockMethodCallHandler(native, null);
      messenger.setMockMethodCallHandler(
        const MethodChannel('window_manager'),
        null,
      );
    },
  );

  test(
    'taskbar focus and minimized floating ball expand the main interface',
    () async {
      final controller = WakeDesktop()..collapsed = true;
      await controller.wakeFromFocus();
      await Future<void>.delayed(Duration.zero);
      expect(controller.expansions, 1);
      expect(controller.collapsed, false);
      controller.collapsed = true;
      controller.onWindowMinimize();
      await Future<void>.delayed(Duration.zero);
      expect(controller.expansions, 2);
      expect(controller.collapsed, false);
      controller.dispose();
    },
  );
  test(
    'locking an embedded calendar does not detach and remount its surface',
    () async {
      final calls = <bool>[];
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(native, (c) async {
        if (c.method == 'embed') calls.add(c.arguments as bool);
        return null;
      });
      messenger.setMockMethodCallHandler(
        const MethodChannel('window_manager'),
        (c) async => null,
      );
      final controller = DesktopController(MemoryStorage(), calendar: true)
        ..embedded = true
        ..locked = true;
      await controller.setEmbedded(true);
      expect(calls, [true]);
      controller.dispose();
      messenger.setMockMethodCallHandler(native, null);
      messenger.setMockMethodCallHandler(
        const MethodChannel('window_manager'),
        null,
      );
    },
  );

  test('restore reapplies saved normal bounds and refreshes Flutter instead of persisting full screen', () async {
    const bounds = Rect.fromLTWH(40, 50, 430, 700);
    final calls = <MethodCall>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(const MethodChannel('window_manager'), (
      call,
    ) async {
      calls.add(call);
      if (call.method == 'getBounds') {
        return {'x': 40.0, 'y': 50.0, 'width': 430.0, 'height': 700.0};
      }
      return false;
    });
    messenger.setMockMethodCallHandler(native, (call) async {
      calls.add(call);
      return null;
    });
    final storage = MemoryStorage(),
        controller = DesktopController(MemoryStorage(), calendar: false)
          ..expanded = bounds;
    await controller.toggleMaximize();
    await controller.toggleMaximize();
    final set = calls.singleWhere((c) => c.method == 'setBounds');
    expect(set.arguments['width'], 430);
    expect(set.arguments['height'], 700);
    expect(controller.expanded, bounds);
    expect(controller.maximized, false);
    expect(controller.busy, false);
    expect(calls.where((c) => c.method == 'refreshLayout').length, 2);
    controller.dispose();
    await storage.flush();
    messenger.setMockMethodCallHandler(native, null);
    messenger.setMockMethodCallHandler(
      const MethodChannel('window_manager'),
      null,
    );
  });
  test('failed desktop attachment falls back to a visible resizable calendar without a second attach', () async {
    final nativeCalls = <bool>[];
    final windows = <String>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(const MethodChannel('window_manager'), (
      call,
    ) async {
      windows.add(call.method);
      return call.method.startsWith('is') ? false : null;
    });
    messenger.setMockMethodCallHandler(native, (call) async {
      if (call.method == 'embed') {
        nativeCalls.add(call.arguments as bool);
        if (call.arguments == true) throw PlatformException(code: 'desktop');
      }
      return null;
    });
    final storage = MemoryStorage();
    final controller = DesktopController(storage, calendar: true)
      ..embedded = true
      ..locked = true;
    await expectLater(
      controller.setEmbedded(true),
      throwsA(isA<PlatformException>()),
    );
    expect(controller.embedded, false);
    expect(controller.locked, false);
    expect(windows, contains('show'));
    expect(nativeCalls.where((v) => v).length, 1);
    expect(storage.values['window-calendar']!['embedded'], false);
    controller.dispose();
    messenger.setMockMethodCallHandler(native, null);
    messenger.setMockMethodCallHandler(
      const MethodChannel('window_manager'),
      null,
    );
  });
}
