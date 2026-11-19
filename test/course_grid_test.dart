import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:needtodo/course.dart';
import 'package:needtodo/model.dart';
import 'package:needtodo/store.dart';
import 'package:needtodo/ui/timetable.dart';

import 'memory_storage.dart';

void main() {
  test('course colors follow the selected settings set rather than legacy overrides', () async {
    final store = AppStore(MemoryStorage())..local = true;
    final course = Course(
      name: '旧课程',
      termStart: DateTime(2026, 11, 16),
      color: 0xffff0000,
      textColor: 0xff000000,
    );
    store.document.courses = [course];
    await store.prepareCourseColors();
    final id = store.courseLevel(course);
    final custom = store.timetableAppearance;
    custom.levelSet.levels.firstWhere((l) => l.id == id).color = Colors.blue;
    await store.saveAppearance('timetable', custom);
    expect(
      store.timetableAppearance.taskColor(store.courseLevel(course)).toARGB32(),
      Colors.blue.toARGB32(),
    );
    final gray = store.timetableAppearance..levelSetId = 'gray';
    await store.saveAppearance('timetable', gray);
    expect(
      store.timetableAppearance.taskColor(id).toARGB32(),
      isNot(Colors.blue.toARGB32()),
    );
    await store.shutdown();
  });
  testWidgets(
    'course editor selects a settings color without inline palette design',
    (tester) async {
      final store = AppStore(MemoryStorage())..local = true;
      await store.prepareCourseColors();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: CourseEditor(store: store, date: DateTime(2026, 11, 19)),
            ),
          ),
        ),
      );
      expect(find.text('课程颜色'), findsOneWidget);
      expect(find.text('课程底色'), findsNothing);
      expect(find.text('普通'), findsNothing);
      for (final field
          in tester.widgetList<TextField>(find.byType(TextField)).take(3)) {
        expect(field.decoration!.counterText, '');
      }
      await tester.pumpWidget(const SizedBox());
      await store.shutdown();
    },
  );
  test(
    'lesson spans compress breaks and retain per-course colors on reload',
    () {
      final grid = CourseGrid();
      final c = Course(
        name: '数学',
        termStart: DateTime(2026, 11, 16),
        startPeriod: 3,
        endPeriod: 4,
        color: 0xffedc4d7,
        textColor: 0xff49394a,
      );
      final saved = Document(courses: [c]).clone().courses.single;
      expect(grid.span(saved), (2, 3));
      expect(saved.color, 0xffedc4d7);
      expect(saved.textColor, 0xff49394a);
      final settings = CourseGrid.fromJson({
        ...grid.toJson(),
        'rowHeight': 80,
        'fontSize': 14,
        'radius': 3,
      });
      expect(settings.rowHeight, 80);
      expect(settings.fontSize, 14);
      expect(settings.radius, 3);
    },
  );
  testWidgets('phone shows all seven weekdays and merged lesson blocks', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final now = DateTime.now(), store = AppStore(MemoryStorage())..local = true;
    final monday = DateTime(now.year, now.month, now.day - now.weekday + 1);
    store.document.courses = [
      Course(
        id: 'm',
        name: '数学',
        termStart: monday,
        weekday: 1,
        startPeriod: 1,
        endPeriod: 2,
        color: 0xffedc4d7,
      ),
      Course(
        id: 'w',
        name: '物理',
        termStart: monday,
        weekday: 3,
        startPeriod: 3,
        endPeriod: 4,
      ),
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: Timetable(store: store)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('日'), findsOneWidget);
    expect(find.text('数学'), findsOneWidget);
    expect(find.text('物理'), findsOneWidget);
    final a = tester.getRect(find.byKey(const ValueKey('course-block-m'))),
        b = tester.getRect(find.byKey(const ValueKey('course-block-w')));
    expect(b.left, greaterThan(a.right));
    expect(b.top, greaterThan(a.bottom));
    expect(a.height, store.courseGrid.rowHeight * 2 - 4);
    await tester.tap(find.byTooltip('课表排版'));
    await tester.pumpAndSettle();
    expect(find.text('节次时间'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await store.shutdown();
  });
}
