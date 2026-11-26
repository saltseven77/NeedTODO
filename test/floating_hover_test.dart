import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:needtodo/model.dart';
import 'package:needtodo/platform_services.dart';
import 'package:needtodo/ui/floating_note.dart';

import 'memory_storage.dart';

class CursorDesktop extends DesktopController {
  bool inside = true;
  int opened = 0, closed = 0, expandedCount = 0;
  CursorDesktop() : super(MemoryStorage(), calendar: false) {
    collapsed = true;
  }
  @override
  Future<bool?> pointerOverBallNote() async => inside;
  @override
  Future<void> showBallNote(bool visible) async {
    if (visible == noteVisible) return;
    noteVisible = visible;
    if (visible) {
      opened++;
    } else {
      closed++;
    }
    notifyListeners();
  }

  @override
  Future<void> expand() async {
    expandedCount++;
    collapsed = false;
  }
}

void main() {
  testWidgets(
    'resize-generated mouse exits do not repeatedly close and reopen the hover note',
    (tester) async {
      final desktop = CursorDesktop();
      await tester.pumpWidget(
        MaterialApp(
          home: ListenableBuilder(
            listenable: desktop,
            builder: (context, _) => FloatingNote(
              desktop: desktop,
              appearance: Appearance(),
              tasks: [],
              open: () {},
              menu: () {},
            ),
          ),
        ),
      );
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: const Offset(900, 900));
      await mouse.moveTo(const Offset(30, 30));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      expect(desktop.opened, 1);
      expect(desktop.noteVisible, true);
      // The native viewport can report an exit while the physical pointer is still over the ball/note.
      await mouse.moveTo(const Offset(900, 900));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();
      await mouse.moveTo(const Offset(30, 30));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      expect(desktop.opened, 1);
      expect(desktop.closed, 0);
      desktop.onWindowFocus();
      await tester.pump();
      expect(desktop.expandedCount, 0);
      desktop.inside = false;
      await mouse.moveTo(const Offset(900, 900));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();
      expect(desktop.closed, 1);
      expect(desktop.noteVisible, false);
      await mouse.removePointer();
      await tester.pumpWidget(const SizedBox());
      desktop.dispose();
    },
  );
  test('focus caused by reading a note is ignored but taskbar focus outside it expands the list', () async {
    final desktop = CursorDesktop()..noteVisible = true;
    await desktop.wakeFromFocus();
    expect(desktop.expandedCount, 0);
    desktop.noteVisible = false;
    desktop.inside = false;
    desktop.onWindowFocus();
    await Future<void>.delayed(Duration.zero);
    expect(desktop.expandedCount, 0);
    desktop.noteVisible = true;
    desktop.inside = false;
    await desktop.wakeFromFocus();
    expect(desktop.expandedCount, 1);
    desktop.dispose();
  });
}
