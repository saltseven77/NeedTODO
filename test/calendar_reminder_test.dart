import 'package:flutter/material.dart';

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:needtodo/app.dart';
import 'package:needtodo/model.dart';
import 'package:needtodo/platform_services.dart';
import 'package:needtodo/store.dart';

import 'memory_storage.dart';

class RecordingNotifications extends Fake
    implements FlutterLocalNotificationsPlugin {
  final pending = <int, PendingNotificationRequest>{};
  final bodies = <String?>[];
  NotificationDetails? details;
  bool failScheduling = false;
  @override
  Future<List<PendingNotificationRequest>>
  pendingNotificationRequests() async => pending.values.toList();
  @override
  Future<void> cancel({required int id, String? tag}) async {
    pending.remove(id);
  }

  @override
  Future<void> zonedSchedule({
    required int id,
    required tz.TZDateTime scheduledDate,
    required NotificationDetails notificationDetails,
    required AndroidScheduleMode androidScheduleMode,
    String? title,
    String? body,
    String? payload,
    DateTimeComponents? matchDateTimeComponents,
  }) async {
    if (failScheduling) throw StateError('模拟系统通知不可用');
    expect(
      pending.containsKey(id),
      false,
      reason: 'Replacing a reminder must cancel its old schedule',
    );
    pending[id] = PendingNotificationRequest(id, title, body, payload);
    bodies.add(body);
    details = notificationDetails;
  }
}

void main() {
  test(
    'running app delivers due reminder once even if native scheduling fails',
    () async {
      if (!Platform.isWindows) return;
      final fake = RecordingNotifications()..failScheduling = true;
      final services = PlatformServices(notifications: fake)
        ..initialized = true;
      addTearDown(services.dispose);
      var received = 0;
      services.onReminder = (tasks, style) async {
        received += tasks.length;
      };
      final document = Document(
        tasks: [
          Todo(
            title: '提醒验证',
            date: dayKey(DateTime.now()),
            reminder: DateTime.now().add(const Duration(milliseconds: 700)),
          ),
        ],
      );
      await expectLater(services.publish(document), throwsStateError);
      await Future<void>.delayed(const Duration(milliseconds: 1000));
      expect(received, 1);
      fake.failScheduling = false;
      await services.publish(document);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(received, 1);
    },
  );
  testWidgets(
    'weekday headings align with date columns at both window widths',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      for (final width in [390.0, 1024.0]) {
        tester.view.physicalSize = Size(width, 740);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: CalendarWorkspace(
                appearance: Appearance(),
                selected: DateTime(2026, 9),
                tasks: const [],
                wide: width > 760,
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
        await tester.pumpAndSettle();
        final headings = ['一', '二', '三', '四', '五', '六', '日'];
        final dates = ['31', '1', '2', '3', '4', '5', '6'];
        for (var i = 0; i < 7; i++) {
          expect(
            tester.getCenter(find.text(headings[i])).dx,
            closeTo(tester.getCenter(find.text(dates[i]).first).dx, .5),
          );
        }
      }
    },
  );

  testWidgets(
    'locked desktop calendar allows direct check-in without opening agenda',
    (tester) async {
      tester.view.physicalSize = const Size(1050, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = AppStore(MemoryStorage())
        ..ready = true
        ..local = true;
      store.document.tasks = [Todo(title: '读书', date: dayKey(DateTime.now()))];
      final desktop = DesktopController(MemoryStorage(), calendar: true)
        ..locked = true;
      await tester.pumpWidget(NeedTodoApp(store: store, desktop: desktop));
      expect(find.byTooltip('解锁桌面'), findsOneWidget);
      expect(find.byTooltip('清单'), findsNothing);
      await tester.tap(find.byTooltip('打卡：读书'));
      await tester.pumpAndSettle();
      expect(store.document.tasks.single.done, true);
      expect(find.byTooltip('添加当天日程'), findsNothing);
      await tester.tap(find.byTooltip('取消打卡：读书'));
      await tester.pumpAndSettle();
      expect(store.document.tasks.single.done, false);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await store.shutdown();
    },
  );

  test(
    'reminder custom copy survives storage and schedules without duplicates',
    () async {
      final notifications = RecordingNotifications();
      final services = PlatformServices(notifications: notifications)
        ..initialized = true;
      var task = Todo(
        title: '读书',
        date: '2026-09-29',
        reminder: DateTime.now().add(const Duration(hours: 2)),
      );
      final doc = Document(
        tasks: [task],
        reminders: ReminderStyle(message: '留一点时间给自己'),
      );
      final restored = doc.clone();
      expect(restored.reminders.message, '留一点时间给自己');
      await services.publish(restored);
      expect(notifications.bodies.single, '留一点时间给自己\n读书');
      expect(
        notifications.details!.windows!.images.single.placement,
        WindowsImagePlacement.appLogoOverride,
      );
      await services.publish(restored);
      expect(notifications.bodies.length, 1);
      restored.calendar.avatar = 'calendar-only';
      restored.list.background = 'list-only';
      await services.publish(restored);
      expect(notifications.bodies.length, 1);
      task = task.copy(title: '读两页书');
      restored.tasks = [task];
      await services.publish(restored);
      expect(notifications.bodies.length, 2);
      restored.tasks = [task.copy(done: true)];
      await services.publish(restored);
      expect(notifications.pending, isEmpty);
    },
  );
}
