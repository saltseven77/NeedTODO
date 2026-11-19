import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:needtodo/app.dart';
import 'package:needtodo/course.dart';
import 'package:needtodo/model.dart';
import 'package:needtodo/store.dart';
import 'package:needtodo/ui/timetable.dart';

import 'memory_storage.dart';

void main() {
  test(
    'courses respect term boundaries, weekdays and odd or even teaching weeks',
    () {
      final c = Course(
        name: '数学',
        termStart: DateTime(2026, 11, 16),
        firstWeek: 2,
        lastWeek: 4,
        parity: 2,
      );
      expect(c.occursOn(DateTime(2026, 11, 9)), false);
      expect(c.occursOn(DateTime(2026, 11, 16)), false);
      expect(c.occursOn(DateTime(2026, 11, 23)), true);
      expect(c.occursOn(DateTime(2026, 11, 24)), false);
      expect(c.occursOn(DateTime(2026, 11, 30)), false);
      expect(c.occursOn(DateTime(2026, 12, 7)), true);
      expect(c.occursOn(DateTime(2026, 12, 21)), false);
    },
  );
  test(
    'course edits and deletions survive offline merging and persistence',
    () async {
      final storage = MemoryStorage();
      final store = AppStore(storage)..local = true;
      final c = Course(
        id: 'c',
        name: '数学',
        termStart: DateTime(2026, 11, 16),
        updated: DateTime.utc(2026, 11, 19),
      );
      await store.dispatch({'type': 'course', 'value': c.toJson()});
      expect(
        Document.fromJson(storage.values['local']!['document'])
            .courses
            .single
            .name,
        '数学',
      );
      final tombstone = Course.fromJson({
        'id': 'c',
        'deleted': true,
        'updated': '2026-11-20T00:00:00Z',
      });
      final merged = mergeDocuments(
        store.document,
        Document(courses: [tombstone]),
      );
      expect(merged.clone().courses.single.deleted, true);
      await store.shutdown();
    },
  );
  for (final width in [320.0, 1100.0]) {
    testWidgets('course timetable and editing adapt at width $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = AppStore(MemoryStorage())
        ..ready = true
        ..local = true;
      await tester.pumpWidget(NeedTodoApp(store: store));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('课程表'));
      await tester.pumpAndSettle();
      expect(find.byType(Timetable), findsOneWidget);
      await tester.tap(find.text('添加第一门课程'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, '课程名称'), '计算机网络');
      await tester.ensureVisible(find.text('保存'));
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(store.document.courses.single.name, '计算机网络');
      expect(find.text('计算机网络'), findsOneWidget);
      await tester.tap(find.text('计算机网络'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('删除课程'));
      await tester.tap(find.text('删除课程'));
      await tester.pumpAndSettle();
      expect(store.document.courses.single.deleted, true);
      expect(find.text('添加第一门课程'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await store.shutdown();
    });
  }
}
