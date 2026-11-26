import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:needtodo/platform_services.dart';

import 'memory_storage.dart';

class GeometryDesktop extends DesktopController {
  GeometryDesktop(super.storage) : super(calendar: false);
  @override
  Future<Rect> clamp(Rect bounds) async => bounds;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('taskbar restoration retains normal size and ball position even when minimized bounds are invalid', () async {
    const normal = Rect.fromLTWH(560, 130, 520, 680),
        ball = Rect.fromLTWH(1100, 760, 68, 68);
    Rect bounds = normal;
    bool minimized = false;
    final storage = MemoryStorage(),
        controller = GeometryDesktop(MemoryStorage());
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(const MethodChannel('window_manager'), (
      c,
    ) async {
      switch (c.method) {
        case 'isMinimized':
          return minimized;
        case 'isFullScreen':
        case 'isMaximized':
          return false;
        case 'getBounds':
          return {
            'x': bounds.left,
            'y': bounds.top,
            'width': bounds.width,
            'height': bounds.height,
          };
        case 'setBounds':
          bounds = Rect.fromLTWH(
            c.arguments['x'],
            c.arguments['y'],
            c.arguments['width'],
            c.arguments['height'],
          );
          return null;
        case 'restore':
          minimized = false;
          bounds = const Rect.fromLTWH(0, 0, 68, 68);
          return null;
        default:
          return null;
      }
    });
    messenger.setMockMethodCallHandler(native, (c) async => null);
    controller.ball = ball;
    await controller.collapse();
    expect(bounds, ball);
    expect(controller.expanded, normal);
    minimized = true;
    bounds = const Rect.fromLTWH(-32000, -32000, 68, 68);
    await controller.expand();
    expect(bounds, normal);
    expect(controller.ball, ball);
    await controller.collapse();
    expect(bounds, ball);
    expect(controller.expanded, normal);
    controller.dispose();
    await storage.flush();
    messenger.setMockMethodCallHandler(native, null);
    messenger.setMockMethodCallHandler(
      const MethodChannel('window_manager'),
      null,
    );
  });
  test('late normal-window geometry reads cannot overwrite a collapsed window snapshot', () async {
    const normal = Rect.fromLTWH(600, 140, 450, 650),
        anchor = Rect.fromLTWH(1100, 700, 68, 68);
    final late = Completer<Map<String, double>>();
    var reads = 0;
    Rect current = normal;
    final storage = MemoryStorage(),
        controller = GeometryDesktop(MemoryStorage())
          ..expanded = normal
          ..ball = anchor;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(const MethodChannel('window_manager'), (
      c,
    ) async {
      if (c.method.startsWith('is')) return false;
      if (c.method == 'getBounds') {
        if (++reads == 1) return late.future;
        return {
          'x': current.left,
          'y': current.top,
          'width': current.width,
          'height': current.height,
        };
      }
      if (c.method == 'setBounds') {
        current = Rect.fromLTWH(
          c.arguments['x'],
          c.arguments['y'],
          c.arguments['width'],
          c.arguments['height'],
        );
      }
      return null;
    });
    messenger.setMockMethodCallHandler(native, (c) async => null);
    final save = controller.saveNow();
    await Future<void>.delayed(Duration.zero);
    await controller.collapse();
    late.complete({'x': 0, 'y': 0, 'width': 68, 'height': 68});
    await save;
    expect(controller.expanded, normal);
    expect(controller.ball, anchor);
    await controller.expand();
    expect(current, normal);
    controller.dispose();
    await storage.flush();
    messenger.setMockMethodCallHandler(native, null);
    messenger.setMockMethodCallHandler(
      const MethodChannel('window_manager'),
      null,
    );
  });
  test('hover panels stay clear of the ball above and at the top edge', () {
    const area = Rect.fromLTWH(0, 0, 1440, 900);
    for (final anchor in [
      const Rect.fromLTWH(900, 700, 68, 68),
      const Rect.fromLTWH(0, 0, 68, 68),
    ]) {
      final layout = floatingNoteLayout(anchor, area),
          panel = layout.note.shift(layout.bounds.topLeft);
      expect(panel.overlaps(anchor), false);
      expect(layout.ballOffset + layout.bounds.topLeft, anchor.topLeft);
      if (anchor.top > 400) {
        expect(panel.bottom, lessThan(anchor.top));
      } else {
        expect(panel.top, greaterThan(anchor.bottom));
      }
    }
  });
}
