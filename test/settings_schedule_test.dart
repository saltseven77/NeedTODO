import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:needtodo/model.dart';
import 'package:needtodo/store.dart';
import 'package:needtodo/ui/components.dart';
import 'package:needtodo/ui/preferences.dart';
import 'package:needtodo/ui/schedule.dart';

import 'memory_storage.dart';

void main() {
  testWidgets('color plane is visible and dragging previews before saving', (
    tester,
  ) async {
    Color selected = Colors.blue;
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme(),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 320,
              child: ColorEditor(
                initial: selected,
                onPreview: (color) => selected = color,
              ),
            ),
          ),
        ),
      ),
    );
    final plane = find.byKey(const ValueKey('color-plane'));
    expect(tester.getSize(plane), const Size(320, 160));
    await tester.tapAt(tester.getTopLeft(plane) + const Offset(280, 40));
    await tester.pump();
    expect(selected, isNot(Colors.blue));
    final before = selected;
    await tester.drag(plane, const Offset(-100, 40));
    await tester.pump();
    expect(selected, isNot(before));
    expect(
      tester
          .widget<ColorSample>(find.byKey(const ValueKey('live-color')))
          .color,
      selected,
    );
  });

  testWidgets('settings separates appearance and reminder tabs', (
    tester,
  ) async {
    final store = AppStore(MemoryStorage())..local = true;
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme(),
        home: Scaffold(
          body: SingleChildScrollView(
            child: SizedBox(
              width: 390,
              child: SettingsView(
                store: store,
                layout: 'list',
                preview: (_) {},
              ),
            ),
          ),
        ),
      ),
    );
    expect(find.text('提醒语'), findsNothing);
    expect(find.text('打开桌面月历'), findsNothing);
    await tester.tap(find.text('日程'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('更换提醒头像'), findsOneWidget);
    expect(find.text('外观'), findsNothing);
    await tester.enterText(find.byType(TextFormField), '专注当下');
    await tester.tap(find.text('月历'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('青苔'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('保存'));
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(store.document.list.paletteId, 'paper');
    expect(store.document.calendar.paletteId, 'sage');
    expect(store.document.reminders.message, '专注当下');
    expect(tester.takeException(), isNull);
  });

  test(
    'time ranges, independent appearance merge and holidays survive reload',
    () {
      final older = DateTime.utc(2026, 9, 1), newer = DateTime.utc(2026, 9, 2);
      final local = Document(
        list: Appearance(name: '清单独立', updated: newer),
        calendar: Appearance(updated: older),
        reminders: ReminderStyle(
          message: '独立提醒',
          avatar: 'reminder-avatar',
          updated: newer,
        ),
        tasks: [
          Todo(
            title: '会议',
            date: '2026-09-29',
            startMinute: 540,
            endMinute: 600,
          ),
          Todo(title: '散步', date: '2026-09-30', timePeriod: '晚上'),
        ],
        holidays: [Holiday(name: '休假', start: '2026-09-29', end: '2026-10-03')],
      );
      local.list.levelSet.levels.first.textColor = Colors.red;
      final remote = Document(
        list: Appearance(updated: older),
        calendar: Appearance(name: '月历独立', updated: newer),
      );
      final merged = mergeDocuments(local, remote).clone();
      expect(merged.list.name, '清单独立');
      expect(merged.calendar.name, '月历独立');
      expect(merged.reminders.avatar, 'reminder-avatar');
      expect(
        merged.list.taskTextColor('normal').toARGB32(),
        Colors.red.toARGB32(),
      );
      expect(
        merged.calendar.taskTextColor('normal').toARGB32(),
        isNot(Colors.red.toARGB32()),
      );
      expect(taskTimeLabel(merged.tasks.first), '09:00–10:00');
      expect(
        tasksForPeriod(merged.tasks, 'week', DateTime(2026, 9, 29)).length,
        2,
      );
      expect(merged.holidays.single.contains(DateTime(2026, 10, 1)), true);
    },
  );

  testWidgets('timeline accommodates overlapping and broad time periods', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme(),
        home: Scaffold(
          body: DayTimeline(
            tasks: [
              Todo(
                title: '会议',
                date: '2026-09-29',
                startMinute: 0,
                endMinute: 60,
              ),
              Todo(
                title: '讨论',
                date: '2026-09-29',
                startMinute: 30,
                endMinute: 90,
              ),
              Todo(title: '读书', date: '2026-09-29', timePeriod: '晚上'),
            ],
            appearance: Appearance(),
            edit: (_) {},
            toggle: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('00:00'), findsOneWidget);
    expect(find.text('未安排时间'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
