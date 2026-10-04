import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:needtodo/app.dart';
import 'package:needtodo/model.dart';
import 'package:needtodo/store.dart';
import 'package:needtodo/ui/components.dart';
import 'package:needtodo/ui/categories.dart';
import 'package:needtodo/ui/schedule.dart';
import 'package:needtodo/ui/reminder_popup.dart';

import 'memory_storage.dart';

void main() {
  test('categories persist and perfect check-ins exclude blank, future and long-term plans', () {
    final tasks = [
      Todo(title: '已完成一', date: '2026-10-01', category: '学习', done: true),
      Todo(title: '已完成二', date: '2026-10-01', category: '工作', done: true),
      Todo(title: '删除任务', date: '2026-10-01', deleted: true),
      Todo(title: '未完成', date: '2026-10-02', category: '工作'),
      Todo(title: '已完成三', date: '2026-10-03', done: true),
      Todo(title: '月计划', date: '2026-10-03', scope: 'month'),
      Todo(title: '未来任务', date: '2026-10-04', done: true),
    ];
    final copy = Document(tasks: tasks).clone();
    expect(copy.tasks.first.copy(done: false).category, '学习');
    expect(taskCategories(copy.tasks), ['学习', '工作']);
    final stats = monthCheckins(
      copy.tasks,
      DateTime(2026, 10),
      DateTime(2026, 10, 3),
    );
    expect(stats.perfect, 2);
    expect(stats.planned, 3);
    expect(minuteAfterStart(1438), 1439);
    expect(minuteAfterStart(1439), 1440);
    expect(minuteLabel(minuteAfterStart(1439)), '24:00');
  });

  testWidgets(
    'month view reports completion by category including uncategorized tasks',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: appTheme(),
          home: Scaffold(
            body: MonthOverview(
              tasks: [
                Todo(
                  title: '阅读',
                  date: '2026-10-01',
                  category: '学习',
                  done: true,
                ),
                Todo(title: '写作', date: '2026-10-01', category: '学习'),
                Todo(title: '散步', date: '2026-10-02', done: true),
              ],
              appearance: Appearance(),
              month: DateTime(2026, 10),
              today: DateTime(2026, 10, 3),
              edit: (_) {},
              toggle: (_) {},
            ),
          ),
        ),
      );
      expect(find.text('学习'), findsOneWidget);
      expect(find.text('未分类'), findsOneWidget);
      expect(find.text('1 / 2'), findsOneWidget);
      expect(find.text('1 / 1'), findsOneWidget);
      expect(find.text('完美打卡 1 天'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'detailed add carries the quick draft, saves its category and defaults end to next minute',
    (tester) async {
      tester.view.physicalSize = const Size(700, 850);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = AppStore(MemoryStorage())
        ..ready = true
        ..local = true;
      store.document.tasks = [
        Todo(title: '已有任务', date: dayKey(DateTime.now()), category: '学习'),
      ];
      await tester.pumpWidget(NeedTodoApp(store: store));
      await tester.enterText(find.widgetWithText(TextField, '添加日程'), '计划草稿');
      await tester.tap(find.byTooltip('详细添加'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(
              find
                  .descendant(
                    of: find.byType(TaskEditor),
                    matching: find.byType(TextField),
                  )
                  .first,
            )
            .controller!
            .text,
        '计划草稿',
      );
      expect(find.text('上午'), findsNothing);
      expect(find.text('下午'), findsNothing);
      expect(find.text('晚上'), findsNothing);
      await tester.tap(find.text('具体时间'));
      await tester.pumpAndSettle();
      expect(find.text('09:00'), findsOneWidget);
      expect(find.text('09:01'), findsOneWidget);
      await tester.tap(find.byTooltip('任务类别').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('学习').last);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('保存'));
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(store.document.tasks.last.title, '计划草稿');
      expect(store.document.tasks.last.category, '学习');
      expect(store.document.tasks.last.endMinute, 541);
      expect(
        tester
            .widget<TextField>(find.widgetWithText(TextField, '添加日程'))
            .controller!
            .text,
        isEmpty,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    '24-hour view locates current time even with untimed tasks above it',
    (tester) async {
      tester.view.physicalSize = const Size(400, 400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: appTheme(),
          home: Scaffold(
            body: DayTimeline(
              selectedDate: DateTime(2026, 10, 1),
              currentTime: DateTime(2026, 10, 1, 15, 25),
              tasks: [Todo(title: '未安排任务', date: '2026-10-01')],
              appearance: Appearance(),
              edit: (_) {},
              toggle: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester.getTopLeft(find.text('15:00')).dy,
        inInclusiveRange(0, 150),
      );
      expect(tester.getTopLeft(find.text('00:00')).dy, lessThan(0));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'compact reminder fits two-line task text and closes immediately',
    (tester) async {
      var closed = false;
      await tester.pumpWidget(
        MaterialApp(
          theme: appTheme(),
          home: Scaffold(
            body: SizedBox(
              width: 360,
              height: reminderHeight(1),
              child: ReminderToast(
                titles: ['这是一条长度超过一行的任务提醒，需要在小弹窗中保持清晰可读'],
                style: ReminderStyle(message: '这是一个更长的提醒语，用来检查紧凑弹窗是否会溢出'),
                onClose: () => closed = true,
              ),
            ),
          ),
        ),
      );
      expect(reminderHeight(1), 96);
      await tester.tap(find.byTooltip('关闭提醒'));
      expect(closed, true);
      expect(tester.takeException(), isNull);
    },
  );
}
