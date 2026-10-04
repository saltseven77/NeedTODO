import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:needtodo/app.dart';
import 'package:needtodo/model.dart';
import 'package:needtodo/ui/components.dart';
import 'package:needtodo/ui/reminder_popup.dart';

void main() {
  testWidgets(
    'task list orders appointments by time and keeps untimed insertion order',
    (tester) async {
      final date = dayKey(DateTime.now()),
          old = DateTime.utc(2026, 1, 1),
          newer = DateTime.utc(2026, 1, 2);
      final tasks = [
        Todo(title: '下午约定', date: date, startMinute: 840, created: old),
        Todo(title: '未定时间一', date: date, created: old),
        Todo(title: '上午约定', date: date, startMinute: 540, created: newer),
        Todo(title: '未定时间二', date: date, created: newer),
      ];
      await tester.pumpWidget(
        MaterialApp(
          theme: appTheme(),
          home: Scaffold(
            body: TaskList(
              tasks: tasks,
              appearance: Appearance(),
              edit: (_) {},
              toggle: (_) {},
            ),
          ),
        ),
      );
      final labels = ['上午约定', '下午约定', '未定时间一', '未定时间二'];
      for (var i = 1; i < labels.length; i++) {
        expect(
          tester.getTopLeft(find.text(labels[i])).dy,
          greaterThan(tester.getTopLeft(find.text(labels[i - 1])).dy),
        );
      }
    },
  );

  testWidgets('mobile reminder appears at the top without replacing the page', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme(),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => unawaited(
                  showTopReminder(context, [
                    Todo(title: '提醒内容', date: '2026-09-29'),
                  ], ReminderStyle(message: '准备开始')),
                ),
                child: const Text('清单内容'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('清单内容'));
    await tester.pumpAndSettle();
    expect(find.text('清单内容'), findsOneWidget);
    expect(find.text('提醒内容'), findsOneWidget);
    expect(tester.getTopLeft(find.byType(ReminderToast)).dy, 12);
    await tester.tap(find.byTooltip('关闭提醒'));
    await tester.pumpAndSettle();
    expect(find.byType(ReminderToast), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('today number stays opaque over a translucent user palette', (
    tester,
  ) async {
    final now = DateTime.now(), a = Appearance();
    a.palette.accent = const Color(0x4099cdee);
    a.palette.background = Colors.transparent;
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme(),
        home: Scaffold(
          body: CalendarWorkspace(
            appearance: a,
            selected: now,
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
          ),
        ),
      ),
    );
    final day = find.byWidgetPredicate(
      (w) =>
          w is Text &&
          w.data == '${now.day}' &&
          w.style?.fontWeight == FontWeight.w600,
    );
    expect(day, findsOneWidget);
    final color = tester.widget<Text>(day).style!.color!;
    expect(color.a, 1);
    expect(color.computeLuminance(), lessThan(.1));
    expect(tester.takeException(), isNull);
  });
}
