import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:needtodo/app.dart';
import 'package:needtodo/course.dart';
import 'package:needtodo/model.dart';
import 'package:needtodo/store.dart';
import 'package:needtodo/ui/schedule.dart';

import 'memory_storage.dart';

void main() {
  test('course schedule follows teaching weeks, edits and deletion without duplicates', () async {
    final storage = MemoryStorage(),
        store = AppStore(MemoryStorage())..local = true;
    final c = Course(
      id: 'c',
      name: '数学',
      termStart: DateTime(2026, 11, 16),
      weekday: 1,
      parity: 1,
      startPeriod: 1,
      endPeriod: 2,
      lastWeek: 4,
    );
    await store.dispatch({'type': 'course', 'value': c.toJson()});
    expect(store.schedule('day', DateTime(2026, 11, 16)).single.title, '数学');
    expect(store.schedule('day', DateTime(2026, 11, 23)), isEmpty);
    expect(store.schedule('month', DateTime(2026, 11)).length, 2);
    expect(store.document.tasks, isEmpty);
    final occurrence = store.schedule('day', DateTime(2026, 11, 16)).single;
    expect(occurrence.startMinute, 480);
    expect(occurrence.endMinute, 575);
    await store.toggleTask(occurrence);
    expect(store.schedule('day', DateTime(2026, 11, 16)).single.done, true);
    expect(store.schedule('day', DateTime(2026, 11, 30)).single.done, false);
    expect(store.document.tasks.length, 1);
    final renamed = Course.fromJson({
      ...c.toJson(),
      'name': '数学（改名）',
      'updated': '2026-11-20T00:00:00Z',
    });
    await store.dispatch({'type': 'course', 'value': renamed.toJson()});
    expect(
      store.schedule('day', DateTime(2026, 11, 16)).single.title,
      '数学（改名）',
    );
    expect(store.schedule('day', DateTime(2026, 11, 16)).single.done, true);
    await store.dispatch({
      'type': 'course',
      'value': {'id': 'c', 'deleted': true, 'updated': '2026-11-21T00:00:00Z'},
    });
    expect(store.schedule('month', DateTime(2026, 11)), isEmpty);
    await store.shutdown();
    await storage.flush();
  });
  test(
    'course completion survives document serialization and reload',
    () async {
      final storage = MemoryStorage(),
          store = AppStore(MemoryStorage())..local = true;
      final c = Course(
        name: '英语',
        termStart: DateTime(2026, 11, 16),
        weekday: 1,
      );
      store.document.courses = [c];
      await store.toggleTask(
        store.schedule('day', DateTime(2026, 11, 16)).single,
      );
      final doc = store.document.clone();
      expect(
        courseSchedule(
          doc,
          DateTime(2026, 11, 16),
          DateTime(2026, 11, 17),
        ).single.done,
        true,
      );
      await store.shutdown();
      await storage.flush();
    },
  );
  testWidgets(
    'today course appears automatically in daily timeline and opens course editor',
    (tester) async {
      final now = DateTime.now(),
          store = AppStore(MemoryStorage())
            ..local = true
            ..ready = true;
      store.document.courses = [
        Course(name: '自动课程', termStart: now, weekday: now.weekday),
      ];
      await tester.pumpWidget(NeedTodoApp(store: store));
      await tester.pumpAndSettle();
      expect(find.text('自动课程'), findsOneWidget);
      await tester.tap(find.text('24小时'));
      await tester.pumpAndSettle();
      expect(find.byType(DayTimeline), findsOneWidget);
      expect(find.text('自动课程'), findsOneWidget);
      await tester.ensureVisible(find.text('自动课程'));
      await tester.tap(find.text('自动课程'));
      await tester.pumpAndSettle();
      expect(find.text('编辑课程'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await store.shutdown();
    },
  );
  test(
    'built-in lavender changes to apricot without replacing custom purple',
    () async {
      final store = AppStore(MemoryStorage())..local = true;
      await store.prepareCourseColors();
      final a = store.timetableAppearance;
      a.levelSet.levels[6].color = const Color(0xffe0d8f4);
      a.levelSet.levels[1].color = const Color(0xffc9c0ef);
      await store.saveAppearance('timetable', a);
      expect(
        store.timetableAppearance.levelSet.levels[6].color.toARGB32(),
        0xffe4c49e,
      );
      expect(
        store.timetableAppearance.levelSet.levels[1].color.toARGB32(),
        0xffc9c0ef,
      );
      await store.shutdown();
    },
  );
}
