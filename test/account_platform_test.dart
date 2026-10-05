import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:needtodo/app.dart';
import 'package:needtodo/model.dart';
import 'package:needtodo/platform_services.dart';
import 'package:needtodo/store.dart';
import 'package:needtodo/ui/account_recovery.dart';

import 'memory_storage.dart';
import 'calendar_reminder_test.dart' show RecordingNotifications;

class AccountStore extends AppStore {
  final requests = <String>[];
  AccountStore(super.storage);
  @override
  Future<Map<String, dynamic>> request(
    String method,
    String path, [
    Map<String, dynamic>? body,
  ]) async {
    requests.add('$method $path');
    if (method == 'GET') return {'revision': 0, 'document': null};
    return {'revision': 1, 'document': body?['document']};
  }
}

class RecoveryStore extends AppStore {
  String status = 'complete';
  RecoveryStore() : super(MemoryStorage());
  @override
  Future<Map<String, dynamic>> startRecovery() async => {
    'ticket': 'fixture-only',
  };
  @override
  Future<Map<String, dynamic>> recoveryStatus(String ticket) async => {
    'status': status,
    if (status == 'consumed') 'username': 'recovered_user',
  };
}

class AndroidPermissions extends AndroidFlutterLocalNotificationsPlugin {
  bool exact = false;
  @override
  Future<bool?> canScheduleExactNotifications() async => exact;
}

class AndroidNotifications extends RecordingNotifications {
  final permissions = AndroidPermissions();
  final modes = <AndroidScheduleMode>[];
  DidReceiveNotificationResponseCallback? tapped;
  @override
  Future<bool?> initialize({
    required InitializationSettings settings,
    DidReceiveNotificationResponseCallback? onDidReceiveNotificationResponse,
    DidReceiveBackgroundNotificationResponseCallback?
    onDidReceiveBackgroundNotificationResponse,
  }) async {
    tapped = onDidReceiveNotificationResponse;
    return true;
  }

  @override
  Future<NotificationAppLaunchDetails?>
  getNotificationAppLaunchDetails() async => const NotificationAppLaunchDetails(
    true,
    notificationResponse: NotificationResponse(
      notificationResponseType: NotificationResponseType.selectedNotification,
      payload: 'cold-start-task',
    ),
  );
  @override
  T? resolvePlatformSpecificImplementation<
    T extends FlutterLocalNotificationsPlatform
  >() => permissions as T;
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
    modes.add(androidScheduleMode);
    await super.zonedSchedule(
      id: id,
      scheduledDate: scheduledDate,
      notificationDetails: notificationDetails,
      androidScheduleMode: androidScheduleMode,
      title: title,
      body: body,
      payload: payload,
      matchDateTimeComponents: matchDateTimeComponents,
    );
  }
}

void main() {
  testWidgets(
    'recovery waits for browser password reset before returning to login',
    (tester) async {
      final store = RecoveryStore();
      String? returned;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  returned = await Navigator.push<String>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => AccountRecoveryPage(store: store),
                    ),
                  );
                },
                child: const Text('Open recovery'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open recovery'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('通过 GitHub 验证'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      expect(find.textContaining('请在浏览器中设置新密码'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      expect(returned, isNull);
      store.status = 'consumed';
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      expect(returned, 'recovered_user');
      await tester.pumpWidget(const SizedBox());
      await store.shutdown();
    },
  );
  test(
    'notification taps survive cold launch and are delivered only once',
    () async {
      final fake = AndroidNotifications(), opened = <String>[];
      final services = PlatformServices(notifications: fake, android: true);
      await services.initialize();
      services.onOpenTask = opened.add;
      expect(opened, ['cold-start-task']);
      services.onOpenTask = null;
      services.onOpenTask = opened.add;
      expect(opened.length, 1);
      fake.tapped!(
        const NotificationResponse(
          notificationResponseType:
              NotificationResponseType.selectedNotification,
          payload: 'warm-task',
        ),
      );
      expect(opened.last, 'warm-task');
      services.dispose();
    },
  );
  test(
    'unbound accounts keep edits locally and send no cloud requests',
    () async {
      final storage = MemoryStorage(), store = AccountStore(MemoryStorage());
      final local = AccountStore(
        storage,
      )..account = {'id': 'same-user', 'username': 'test', 'githubLogin': null};
      await local.saveTask(Todo(title: 'Only local', date: '2026-10-05'));
      await local.sync();
      expect(local.requests, isEmpty);
      expect(
        storage.values.values.single['document']['tasks'].single['title'],
        'Only local',
      );
      local.account!['githubLogin'] = 'linked';
      await local.sync();
      expect(local.requests, ['GET /v2/sync', 'PUT /v2/sync']);
      expect(local.document.tasks.single.title, 'Only local');
      await local.shutdown();
      await store.shutdown();
    },
  );

  testWidgets(
    'closing to tray keeps app alive; explicit exit waits for saving and runs once',
    (tester) async {
      final calls = <String>[];
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        const MethodChannel('window_manager'),
        (call) async {
          calls.add(call.method);
          if (call.method == 'getBounds') {
            return {'x': 40.0, 'y': 40.0, 'width': 430.0, 'height': 700.0};
          }
          return call.method.startsWith('is') ? false : null;
        },
      );
      messenger.setMockMethodCallHandler(native, (call) async {
        calls.add(call.method);
        return null;
      });
      addTearDown(() {
        messenger.setMockMethodCallHandler(
          const MethodChannel('window_manager'),
          null,
        );
        messenger.setMockMethodCallHandler(native, null);
      });
      final desktop = DesktopController(MemoryStorage(), calendar: false)
        ..trayReady = true;
      final saved = Completer<void>();
      var closing = 0;
      desktop.onClose = () async {
        closing++;
        await saved.future;
      };
      desktop.onWindowClose();
      await tester.pumpAndSettle();
      expect(calls, contains('hide'));
      expect(calls, isNot(contains('destroy')));
      expect(closing, 0);
      final quitting = desktop.quit();
      await tester.pump();
      expect(closing, 1);
      expect(calls, isNot(contains('trayEnable')));
      await desktop.quit();
      saved.complete();
      await quitting;
      expect(calls.indexOf('trayEnable'), lessThan(calls.indexOf('destroy')));
      expect(calls.where((c) => c == 'destroy').length, 1);
      await desktop.close();
    },
  );

  testWidgets(
    'Android reminders use a high priority channel, reschedule when exact access changes, and omit journals from widgets',
    (tester) async {
      final fake = AndroidNotifications();
      final snapshots = <Map<String, dynamic>>[];
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(native, (call) async {
        if (call.method == 'widgetUpdate') {
          snapshots.add(jsonDecode(call.arguments as String));
        }
        return null;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(native, null));
      final services = PlatformServices(notifications: fake, android: true)
        ..initialized = true;
      addTearDown(services.dispose);
      final doc = Document(
        tasks: [
          Todo(
            title: 'Android notification',
            date: '2026-10-05',
            reminder: DateTime.now().add(const Duration(hours: 1)),
          ),
        ],
        journals: {'2026-10-05': JournalWeek('2026-10-05')},
      );
      await services.publish(doc);
      expect(fake.modes, [AndroidScheduleMode.inexactAllowWhileIdle]);
      expect(fake.details!.android!.importance, Importance.max);
      expect(fake.details!.android!.priority, Priority.high);
      expect(snapshots.single.keys.toSet(), {'calendar', 'tasks'});
      expect(snapshots.single['tasks'].single['title'], 'Android notification');
      fake.permissions.exact = true;
      await services.publish(doc);
      expect(fake.modes.last, AndroidScheduleMode.exactAllowWhileIdle);
      expect(fake.pending.length, 1);
    },
  );

  testWidgets(
    'first launch shows login; cancelling local choice stays on login',
    (tester) async {
      final store = AppStore(MemoryStorage())..ready = true;
      await tester.pumpWidget(NeedTodoApp(store: store));
      expect(find.text('登录'), findsNWidgets(2));
      await tester.tap(find.text('本机使用'));
      await tester.pumpAndSettle();
      expect(find.textContaining('数据仅保存在当前设备'), findsOneWidget);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(store.entered, false);
      expect(find.text('注册账号'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await store.shutdown();
    },
  );
}
