import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:needtodo/model.dart';
import 'package:needtodo/platform_services.dart';
import 'package:needtodo/ui/floating_note.dart';

import 'memory_storage.dart';

class SeparateDesktop extends DesktopController {
  SeparateDesktop() : super(MemoryStorage(), calendar: false) {
    collapsed = true;
  }
  @override
  Future<Rect> hoverWorkArea(Rect anchor) async =>
      const Rect.fromLTWH(0, 0, 1440, 900);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'separate note never moves or resizes the balloon while showing or hiding',
    () async {
      const ball = Rect.fromLTWH(1000, 720, 134, 68);
      final messages = <String>[], panels = <Rect?>[];
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        const MethodChannel('window_manager'),
        (c) async {
          messages.add(c.method);
          if (c.method == 'getBounds') {
            return {
              'x': ball.left,
              'y': ball.top,
              'width': ball.width,
              'height': ball.height,
            };
          }
          return null;
        },
      );
      final d = SeparateDesktop()
        ..ball = ball
        ..onHoverNote = (bounds) async {
          panels.add(bounds);
        };
      await d.showBallNote(true);
      expect(d.noteVisible, true);
      expect(d.noteBallOffset, Offset.zero);
      expect(panels.single!.bottom, lessThanOrEqualTo(ball.top));
      await d.showBallNote(false);
      expect(d.noteVisible, false);
      expect(panels.last, null);
      expect(
        messages.where(
          (m) => m == 'setBounds' || m == 'setSize' || m == 'setPosition',
        ),
        isEmpty,
      );
      expect(d.ball, ball);
      d.dispose();
      messenger.setMockMethodCallHandler(
        const MethodChannel('window_manager'),
        null,
      );
    },
  );
  testWidgets(
    'balloon does not paint popup text when an independent popup is connected',
    (tester) async {
      final d = SeparateDesktop()
        ..onHoverNote = (_) async {}
        ..noteVisible = true;
      await tester.pumpWidget(
        MaterialApp(
          home: FloatingNote(
            desktop: d,
            appearance: Appearance(),
            tasks: [Todo(title: '不应绘制在球窗口内', date: '2026-11-26')],
            open: () {},
            menu: () {},
          ),
        ),
      );
      expect(find.text('今日计划'), findsNothing);
      expect(find.text('不应绘制在球窗口内'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      d.dispose();
    },
  );
}
