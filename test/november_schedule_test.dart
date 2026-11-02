import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:needtodo/app.dart';
import 'package:needtodo/model.dart';
import 'package:needtodo/platform_services.dart';
import 'package:needtodo/store.dart';
import 'package:needtodo/ui/floating_note.dart';

import 'memory_storage.dart';

class NoteDesktop extends DesktopController {
  NoteDesktop() : super(MemoryStorage(), calendar: false) {
    collapsed = true;
  }
  @override
  Future<void> showBallNote(bool visible) async {
    noteVisible = visible;
    notifyListeners();
  }
}

void main() {
  test('hover note stays on the same display and preserves the ball at screen edges', () {
    const area = Rect.fromLTWH(-1920, 0, 1920, 1040);
    const anchor = Rect.fromLTWH(-68, 972, 68, 68);
    final note = floatingNoteBounds(anchor, area);
    expect(note, const Rect.fromLTWH(-380, 710, 380, 330));
    expect(anchor.topLeft - note.topLeft, const Offset(312, 262));
    expect(area.contains(note.topLeft), true);
  });
  testWidgets('reminder wheels respond to mouse dragging and scrolling', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(700, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = AppStore(MemoryStorage());
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: TaskEditor(
              task: Todo(
                title: '提醒',
                date: '2030-11-02',
                reminder: DateTime(2030, 11, 2, 10),
              ),
              date: DateTime(2030, 11, 2),
              scope: 'day',
              appearance: Appearance(),
              store: store,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final initial = tester
        .widget<CupertinoDatePicker>(find.byType(CupertinoDatePicker))
        .initialDateTime;
    final wheel = find.byType(CupertinoPicker).at(1);
    await tester.drag(
      wheel,
      const Offset(0, -64),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();
    final dragged = tester
        .widget<CupertinoDatePicker>(find.byType(CupertinoDatePicker))
        .initialDateTime;
    expect(dragged, isNot(initial));
    await tester.sendEventToBinding(
      PointerScrollEvent(
        position: tester.getCenter(wheel),
        scrollDelta: const Offset(0, 64),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<CupertinoDatePicker>(find.byType(CupertinoDatePicker))
          .initialDateTime,
      isNot(dragged),
    );
    await tester.pumpWidget(const SizedBox());
    await store.shutdown();
  });

  testWidgets(
    'week and month return to their own periods without a weekly progress bar',
    (tester) async {
      final store = AppStore(MemoryStorage())
        ..ready = true
        ..local = true;
      await tester.pumpWidget(NeedTodoApp(store: store));
      await tester.pumpAndSettle();
      await tester.tap(find.text('周计划'));
      await tester.tap(find.byTooltip('上一周期'));
      await tester.pumpAndSettle();
      expect(find.text('回到本周'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      await tester.tap(find.text('回到本周'));
      await tester.pumpAndSettle();
      expect(find.text('回到本周'), findsNothing);
      await tester.tap(find.text('月计划'));
      await tester.tap(find.byTooltip('上一周期'));
      await tester.pumpAndSettle();
      expect(find.text('回到本月'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await store.shutdown();
    },
  );

  testWidgets(
    'ball hover opens a scrollable note with completed plans struck out',
    (tester) async {
      tester.view.physicalSize = const Size(380, 330);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final desktop = NoteDesktop();
      await tester.pumpWidget(
        MaterialApp(
          home: ListenableBuilder(
            listenable: desktop,
            builder: (context, _) => FloatingNote(
              desktop: desktop,
              appearance: Appearance(),
              tasks: [
                Todo(title: '完成的计划', date: '2030-11-02', done: true),
                Todo(title: '待办计划', date: '2030-11-02'),
              ],
              open: () {},
              menu: () {},
            ),
          ),
        ),
      );
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: const Offset(400, 400));
      await mouse.moveTo(const Offset(30, 30));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      expect(find.text('今日计划'), findsOneWidget);
      expect(
        tester.widget<Text>(find.text('完成的计划')).style!.decoration,
        TextDecoration.lineThrough,
      );
      await mouse.moveTo(const Offset(180, 80));
      await tester.pump(const Duration(milliseconds: 400));
      expect(desktop.noteVisible, true);
      await mouse.moveTo(const Offset(400, 400));
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pump();
      expect(find.text('今日计划'), findsNothing);
      await mouse.removePointer();
      await tester.pumpWidget(const SizedBox());
      desktop.dispose();
    },
  );
}
