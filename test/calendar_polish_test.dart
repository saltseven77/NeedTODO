import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:needtodo/app.dart';
import 'package:needtodo/model.dart';
import 'package:needtodo/store.dart';
import 'package:needtodo/holiday_calendar.dart';

import 'memory_storage.dart';

void main() {
  test('holiday feed distinguishes holiday and adjusted working day', () {
    final days = HolidayCalendar.parse({
      'year': 2026,
      'days': [
        {'name': '国庆节', 'date': '2026-10-01', 'isOffDay': true},
        {'name': '国庆节', 'date': '2026-10-10', 'isOffDay': false},
        {'name': 'invalid', 'date': 'not-a-date', 'isOffDay': true},
      ],
    }, 2026);
    expect(days.length, 2);
    expect(days['2026-10-01']!.off, true);
    expect(days['2026-10-10']!.off, false);
  });
  testWidgets(
    'settings height stays fixed and today remains marked after date selection',
    (tester) async {
      tester.view.physicalSize = const Size(800, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = AppStore(MemoryStorage())
        ..ready = true
        ..local = true;
      await tester.pumpWidget(NeedTodoApp(store: store));
      await tester.pumpAndSettle();
      expect(find.text('今天'), findsOneWidget);
      await tester.tap(find.byTooltip('上一周期'));
      await tester.pumpAndSettle();
      expect(find.text('回到今天'), findsOneWidget);
      await tester.tap(find.text('回到今天'));
      await tester.pumpAndSettle();
      expect(find.text('今天'), findsOneWidget);
      await tester.tap(find.byTooltip('设置'));
      await tester.pumpAndSettle();
      final size = tester.getSize(find.byType(Dialog));
      await tester.tap(find.text('账号'));
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byType(Dialog)), size);
      await tester.tap(find.text('日程'));
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byType(Dialog)), size);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('week list groups tasks by date', (tester) async {
    final store = AppStore(MemoryStorage())
      ..ready = true
      ..local = true;
    store.document.tasks = [Todo(title: '日期测试', date: dayKey(DateTime.now()))];
    await tester.pumpWidget(NeedTodoApp(store: store));
    await tester.pumpAndSettle();
    await tester.tap(find.text('周计划'));
    await tester.pumpAndSettle();
    expect(find.text(dateLabel(DateTime.now())), findsOneWidget);
    expect(find.text('标记假期'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
}
