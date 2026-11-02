import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:needtodo/model.dart';
import 'package:needtodo/ui/schedule.dart';

void main() {
  testWidgets(
    'timeline preserves each configured task color, opacity and text color',
    (tester) async {
      final appearance = Appearance();
      appearance.levelSet.levels[0].color = const Color(0x667843a2);
      appearance.levelSet.levels[0].textColor = const Color(0xff452060);
      appearance.levelSet.levels[1].color = const Color(0xff8a3a51);
      appearance.levelSet.levels[1].textColor = Colors.white;
      final tasks = [
        Todo(
          id: 'a',
          title: '自定义半透明',
          date: '2026-11-02',
          startMinute: 540,
          endMinute: 600,
        ),
        Todo(
          id: 'b',
          title: '自定义深色',
          date: '2026-11-02',
          level: 'important',
          startMinute: 600,
          endMinute: 660,
          done: true,
        ),
      ];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DayTimeline(
              tasks: tasks,
              appearance: appearance,
              currentTime: DateTime(2026, 11, 2, 9),
              edit: (_) {},
              toggle: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      for (final t in tasks) {
        final card = tester.widget<Container>(
          find.byKey(ValueKey('timeline-event-${t.id}')),
        );
        expect(
          (card.decoration as BoxDecoration).color,
          appearance.taskColor(t.level),
        );
        expect(
          tester.widget<Text>(find.text(t.title)).style!.color,
          appearance.taskTextColor(t.level),
        );
      }
      expect(
        tester.widget<Text>(find.text('自定义深色')).style!.decoration,
        TextDecoration.lineThrough,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
