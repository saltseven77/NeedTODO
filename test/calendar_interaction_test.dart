import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:needtodo/platform_services.dart';

import 'memory_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const windows = MethodChannel('window_manager');
  final calls = <MethodCall>[];
  setUp(() {
    calls.clear();
    messenger.setMockMethodCallHandler(native, (c) async {
      calls.add(c);
      return null;
    });
    messenger.setMockMethodCallHandler(windows, (c) async {
      calls.add(c);
      return null;
    });
  });
  tearDown(() {
    messenger.setMockMethodCallHandler(native, null);
    messenger.setMockMethodCallHandler(windows, null);
  });

  test(
    'listeners see an enabled lock button after every completed transition',
    () async {
      final c = DesktopController(MemoryStorage(), calendar: true);
      final observed = <bool>[];
      c.addListener(() => observed.add(c.busy));
      await c.setLocked(true);
      expect(c.locked, true);
      expect(observed.last, false);
      await c.setLocked(false);
      expect(c.locked, false);
      expect(observed, [true, false, true, false]);
      expect(calls.where((c) => c.method == 'embed').map((c) => c.arguments), [
        true,
        false,
      ]);
      expect(calls.where((c) => c.method == 'setAlwaysOnTop'), isEmpty);
      c.dispose();
    },
  );

  test('opening and closing task editors leaves the calendar surface and bounds intact', () async {
    final c = DesktopController(MemoryStorage(), calendar: true)
      ..embedded = true
      ..locked = true;
    for (var i = 0; i < 3; i++) {
      await c.editing(true);
      await c.editing(false);
    }
    expect(calls.map((c) => c.method), List.filled(6, 'desktopEditing'));
    expect(c.embedded, true);
    expect(c.locked, true);
    expect(c.busy, false);
    c.dispose();
  });

  test(
    'unlock failure also enables the button so a second attempt can succeed',
    () async {
      var fail = true;
      messenger.setMockMethodCallHandler(native, (call) async {
        if (call.method == 'embed' && call.arguments == false && fail) {
          throw PlatformException(code: 'desktop');
        }
        return null;
      });
      final c = DesktopController(MemoryStorage(), calendar: true)
        ..embedded = true
        ..locked = true;
      final observed = <bool>[];
      c.addListener(() => observed.add(c.busy));
      await expectLater(c.setLocked(false), throwsA(isA<PlatformException>()));
      expect(observed.last, false);
      expect(c.locked, true);
      fail = false;
      await c.setLocked(false);
      expect(c.locked, false);
      expect(observed.last, false);
      c.dispose();
    },
  );

  test(
    'a rapid second request cannot start another native parent transition',
    () async {
      final pending = Completer<void>();
      messenger.setMockMethodCallHandler(native, (call) async {
        calls.add(call);
        if (call.method == 'embed') await pending.future;
        return null;
      });
      final c = DesktopController(MemoryStorage(), calendar: true);
      final first = c.setLocked(true);
      await Future<void>.delayed(Duration.zero);
      await c.setLocked(true);
      expect(c.busy, true);
      expect(calls.where((c) => c.method == 'embed').length, 1);
      pending.complete();
      await first;
      expect(c.busy, false);
      c.dispose();
    },
  );
}
