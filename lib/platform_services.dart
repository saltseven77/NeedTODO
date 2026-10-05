import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'package:window_manager/window_manager.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:path_provider/path_provider.dart';

import 'model.dart';
import 'storage.dart';

const native = MethodChannel('com.needtodo/platform');
const reminderTestId = 2147483000;

class PlatformServices {
  final FlutterLocalNotificationsPlugin notifications;
  PlatformServices({
    FlutterLocalNotificationsPlugin? notifications,
    Directory? dataDirectory,
    bool? android,
  }) : notifications = notifications ?? FlutterLocalNotificationsPlugin(),
       isAndroid = android ?? Platform.isAndroid,
       _deliveryStorage = dataDirectory == null
           ? null
           : JsonStorage(dataDirectory),
       _mediaDirectory = dataDirectory == null
           ? null
           : Directory('${dataDirectory.path}/reminders');
  final Map<int, List<Object?>> _scheduled = {};
  final bool isAndroid;
  String? _pendingOpenTask;
  void Function(String)? _onOpenTask;
  set onOpenTask(void Function(String)? handler) {
    _onOpenTask = handler;
    if (handler != null && _pendingOpenTask != null) {
      final id = _pendingOpenTask!;
      _pendingOpenTask = null;
      handler(id);
    }
  }

  void _openTask(String? id) {
    if (id == null || id.isEmpty) return;
    if (_onOpenTask != null) {
      _onOpenTask!(id);
    } else {
      _pendingOpenTask = id;
    }
  }

  final Map<String, String> _mediaSources = {};
  Directory? _mediaDirectory;
  final JsonStorage? _deliveryStorage;
  final _delivered = <String>{};
  final _ids = <String, int>{};
  final DateTime _startedAt = DateTime.now();
  Timer? _dueTimer, _testTimer;
  bool _foreground = true;
  void setForeground(bool foreground) {
    if (!Platform.isWindows && foreground && !_foreground) {
      // The OS already handled reminders delivered while the mobile app slept.
      for (final task in _waiting()) {
        if (task.reminder!.isBefore(
          DateTime.now().subtract(const Duration(seconds: 5)),
        )) {
          _delivered.add(_deliveryKey(task));
        }
      }
    }
    _foreground = foreground;
    _arm();
  }

  Document? _latest;
  Future<void> Function(List<Todo>, ReminderStyle)? _onReminder;
  void Function(Object)? onError;
  set onReminder(Future<void> Function(List<Todo>, ReminderStyle)? callback) {
    _onReminder = callback;
    _arm();
  }

  String _deliveryKey(Todo task) =>
      '${task.id}/${task.reminder!.toUtc().toIso8601String()}';
  List<Todo> _waiting() =>
      _latest?.tasks
          .where(
            (t) =>
                !t.done &&
                !t.deleted &&
                t.reminder != null &&
                !t.reminder!.isBefore(
                  _startedAt.subtract(const Duration(minutes: 2)),
                ) &&
                !_delivered.contains(_deliveryKey(t)),
          )
          .toList() ??
      [];
  void _arm() {
    _dueTimer?.cancel();
    if (_onReminder == null || (!Platform.isWindows && !_foreground)) return;
    final waiting = _waiting()
      ..sort((a, b) => a.reminder!.compareTo(b.reminder!));
    if (waiting.isEmpty) return;
    final delay = waiting.first.reminder!.difference(DateTime.now());
    _dueTimer = Timer(delay.isNegative ? Duration.zero : delay, () {
      unawaited(_deliverDue());
    });
  }

  Future<void> _deliverDue() async {
    if (_onReminder == null || _latest == null) return;
    final due = _waiting()
        .where((t) => !t.reminder!.isAfter(DateTime.now()))
        .toList();
    if (due.isEmpty) {
      _arm();
      return;
    }
    for (final task in due) {
      _delivered.add(_deliveryKey(task));
    }
    final handler = _onReminder!, style = _latest!.reminders.clone();
    try {
      // A short native fallback delay lets the running app show one personalized
      // reminder and cancel its system duplicate. Closed apps keep the OS schedule.
      for (final task in due) {
        final id = _ids[task.id];
        if (initialized && id != null) {
          try {
            await notifications.cancel(id: id);
          } catch (e) {
            onError?.call(e);
          }
        }
      }
      if (_delivered.length > 500) {
        _delivered.removeAll(_delivered.take(_delivered.length - 500).toList());
      }
      await _deliveryStorage?.write('reminder-deliveries', {
        'keys': _delivered.toList(),
      });
      _arm();
      await handler(due, style);
    } catch (e) {
      for (final task in due) {
        _delivered.remove(_deliveryKey(task));
      }
      onError?.call(e);
      _dueTimer?.cancel();
      _dueTimer = Timer(
        const Duration(seconds: 15),
        () => unawaited(_deliverDue()),
      );
    }
  }

  Future<void> testReminder([ReminderStyle? preview]) async {
    if (_onReminder == null) throw StateError('请先打开清单');
    final style =
        preview?.clone() ?? _latest?.reminders.clone() ?? ReminderStyle();
    if (isAndroid && initialized) {
      await permission();
      final exact =
          await notifications
              .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin
              >()
              ?.canScheduleExactNotifications() ==
          true;
      await notifications.cancel(id: reminderTestId);
      await notifications.zonedSchedule(
        id: reminderTestId,
        title: '日程提醒',
        body: '这是一条测试提醒',
        scheduledDate: tz.TZDateTime.from(
          DateTime.now().add(const Duration(seconds: 3)).toUtc(),
          tz.UTC,
        ),
        notificationDetails: await _details(style),
        androidScheduleMode: exact
            ? AndroidScheduleMode.exactAllowWhileIdle
            : AndroidScheduleMode.inexactAllowWhileIdle,
      );
    }
    _testTimer?.cancel();
    _testTimer = Timer(const Duration(seconds: 3), () async {
      try {
        if (isAndroid && !_foreground) return;
        if (isAndroid && initialized) {
          await notifications.cancel(id: reminderTestId);
        }
        await _onReminder?.call([
          Todo(
            title: '这是一条测试提醒',
            date: dayKey(DateTime.now()),
            reminder: DateTime.now(),
          ),
        ], style);
      } catch (e) {
        onError?.call(e);
      }
    });
  }

  void dispose() {
    _dueTimer?.cancel();
    _testTimer?.cancel();
    _onReminder = null;
    _onOpenTask = null;
  }

  bool initialized = false;
  Future<void> initialize() async {
    final saved = await _deliveryStorage?.read('reminder-deliveries');
    _delivered.addAll((saved?['keys'] as List? ?? []).whereType<String>());
    tzdata.initializeTimeZones();
    final ready = await notifications.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('ic_notification'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestSoundPermission: false,
          requestBadgePermission: false,
        ),
        windows: WindowsInitializationSettings(
          appName: '泥土豆',
          appUserModelId: 'com.needtodo.app',
          guid: 'aaef01d2-1323-4c97-95cc-bb521c531ff0',
        ),
      ),
      onDidReceiveNotificationResponse: (response) =>
          _openTask(response.payload),
    );
    if (ready != true) throw StateError('系统通知初始化失败');
    initialized = true;
    if (isAndroid || Platform.isIOS) {
      final launch = await notifications.getNotificationAppLaunchDetails();
      if (launch?.didNotificationLaunchApp == true) {
        _openTask(launch?.notificationResponse?.payload);
      }
    }
  }

  Future<void> permission() async {
    if (isAndroid) {
      final android = notifications
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      await android?.requestNotificationsPermission();
      if (await android?.canScheduleExactNotifications() != true) {
        await android?.requestExactAlarmsPermission();
      }
    }
    if (Platform.isIOS) {
      await notifications
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >()
          ?.requestPermissions(alert: true, sound: true, badge: true);
    }
  }

  Future<void> _queue = Future.value();

  Future<File?> _media(String key, String data) async {
    if (!data.startsWith('data:image/')) return null;
    _mediaDirectory ??= Directory(
      '${Platform.environment['NEEDTODO_DATA_DIR'] ?? (await getApplicationSupportDirectory()).path}/reminders',
    );
    final extension = data.startsWith('data:image/jpeg') ? 'jpg' : 'png';
    final file = File('${_mediaDirectory!.path}/$key.$extension');
    if (_mediaSources[key] != data || !await file.exists()) {
      await _mediaDirectory!.create(recursive: true);
      await file.writeAsBytes(base64Decode(data.split(',').last), flush: true);
      _mediaSources[key] = data;
    }
    return file;
  }

  Future<NotificationDetails> _details(ReminderStyle appearance) async {
    final avatar = await _media('reminder-avatar', appearance.avatar);
    final background = await _media(
      'reminder-background',
      appearance.background,
    );
    return NotificationDetails(
      windows: WindowsNotificationDetails(
        images: [
          WindowsImage(
            avatar?.uri ??
                Uri.file(
                  '${File(Platform.resolvedExecutable).parent.path}/data/flutter_assets/assets/potato.png',
                ),
            altText: '提醒头像',
            placement: WindowsImagePlacement.appLogoOverride,
            crop: WindowsImageCrop.circle,
          ),
          if (background != null)
            WindowsImage(
              background.uri,
              altText: '提醒背景',
              placement: WindowsImagePlacement.hero,
            ),
        ],
      ),
      android: AndroidNotificationDetails(
        'needtodo_schedule_alerts_v2',
        '日程提醒',
        channelDescription: '即将开始的日程，声音与顶部横幅提醒',
        importance: Importance.max,
        priority: Priority.high,
        category: AndroidNotificationCategory.reminder,
        playSound: true,
        enableVibration: true,
        visibility: NotificationVisibility.private,
        largeIcon: avatar == null ? null : FilePathAndroidBitmap(avatar.path),
        styleInformation: background == null
            ? null
            : BigPictureStyleInformation(
                FilePathAndroidBitmap(background.path),
              ),
      ),
      iOS: DarwinNotificationDetails(
        attachments: [
          if (background != null) DarwinNotificationAttachment(background.path),
        ],
      ),
    );
  }

  Future<void> publish(Document d) {
    final snapshot = d.clone();
    _latest = snapshot;
    _arm();
    final op = _queue.then((_) async {
      if (isAndroid || Platform.isIOS) {
        await native.invokeMethod(
          'widgetUpdate',
          jsonEncode({
            'calendar': snapshot.calendar.toJson(),
            'tasks': snapshot.tasks
                .where((t) => !t.deleted && !t.done && t.scope == 'day')
                .map(
                  (t) => {
                    'id': t.id,
                    'title': t.title,
                    'date': t.date,
                    'scope': t.scope,
                  },
                )
                .toList(),
          }),
        );
      }
      if (!initialized) throw StateError('系统通知未初始化');
      final future =
          snapshot.tasks
              .where(
                (t) =>
                    !t.deleted &&
                    !t.done &&
                    t.reminder != null &&
                    t.reminder!.isAfter(DateTime.now()),
              )
              .toList()
            ..sort((a, b) => a.reminder!.compareTo(b.reminder!));
      // IDs are deterministic across process restarts, and collision-resolved.
      final ids = <int>{reminderTestId};
      final schedules = <int, Todo>{};
      for (final t in future.take(60)) {
        var id = t.id.codeUnits.fold(
          17,
          (int n, int c) => (n * 31 + c) & 0x7fffffff,
        );
        while (ids.contains(id)) {
          id = (id + 1) & 0x7fffffff;
        }
        ids.add(id);
        schedules[id] = t;
        _ids[t.id] = id;
      }
      final pending = await notifications.pendingNotificationRequests();
      final pendingIds = pending.map((p) => p.id).toSet();
      for (final p in pending) {
        if (!ids.contains(p.id) ||
            (p.id == reminderTestId && _testTimer?.isActive != true)) {
          await notifications.cancel(id: p.id);
        }
      }
      _scheduled.removeWhere((id, _) => !ids.contains(id));
      NotificationDetails? details;
      final exact =
          isAndroid &&
          await notifications
                  .resolvePlatformSpecificImplementation<
                    AndroidFlutterLocalNotificationsPlugin
                  >()
                  ?.canScheduleExactNotifications() ==
              true;
      final mode = exact
          ? AndroidScheduleMode.exactAllowWhileIdle
          : AndroidScheduleMode.inexactAllowWhileIdle;
      for (final entry in schedules.entries) {
        final t = entry.value;
        final appearance = snapshot.reminders;
        final signature = <Object?>[
          t.title,
          t.reminder!.toUtc().toIso8601String(),
          appearance.message,
          appearance.avatar,
          appearance.background,
          mode,
        ];
        if (listEquals(_scheduled[entry.key], signature) &&
            pendingIds.contains(entry.key)) {
          continue;
        }
        details ??= await _details(appearance);
        // Media preparation can take time; never send a date that has just elapsed.
        final delivery = isAndroid
            ? t.reminder!
            : t.reminder!.add(const Duration(seconds: 5));
        if (!delivery.isAfter(DateTime.now())) continue;
        // Windows AddToSchedule appends even when the tag is unchanged.
        for (final previous in pending.where((p) => p.id == entry.key)) {
          await notifications.cancel(id: previous.id);
        }
        await notifications.zonedSchedule(
          id: entry.key,
          title: '日程提醒',
          body: appearance.message.trim().isEmpty
              ? t.title
              : '${appearance.message.trim()}\n${t.title}',
          scheduledDate: tz.TZDateTime.from(delivery.toUtc(), tz.UTC),
          notificationDetails: details,
          androidScheduleMode: mode,
          payload: t.id,
        );
        _scheduled[entry.key] = signature;
      }
      final confirmed = (await notifications.pendingNotificationRequests())
          .map((n) => n.id)
          .toSet();
      if (schedules.entries.any(
        (entry) =>
            entry.value.reminder!.isAfter(
              DateTime.now().add(const Duration(seconds: 10)),
            ) &&
            !confirmed.contains(entry.key),
      )) {
        throw StateError('系统没有保存提醒排程');
      }
    });
    _queue = op.catchError((Object _) {});
    return op;
  }
}

class DesktopController extends ChangeNotifier with WindowListener {
  final JsonStorage storage;
  final bool calendar;
  Rect? expanded, ball;
  bool collapsed = false,
      locked = false,
      embedded = false,
      busy = false,
      maximized = false;
  bool _editing = false;
  bool _hideFirstFrame = false;
  String? docked;
  Timer? _saveTimer, _edgeTimer;
  Future<void> Function()? onClose;
  Future<void> Function()? onOpenCalendar;
  bool trayReady = false, _quitting = false;
  void Function(Object)? onError;
  DesktopController(this.storage, {required this.calendar});
  String get key => calendar ? 'window-calendar' : 'window-list';
  Rect? _rect(dynamic v) {
    final j = object(v);
    if (j.isEmpty) return null;
    return Rect.fromLTWH(
      number(j['x'], 40, -40000, 40000),
      number(j['y'], 40, -40000, 40000),
      number(j['w'], 420, 32, 16000),
      number(j['h'], 700, 32, 16000),
    );
  }

  Map<String, double>? _json(Rect? r) =>
      r == null ? null : {'x': r.left, 'y': r.top, 'w': r.width, 'h': r.height};
  Future<Rect> clamp(Rect r) async {
    final displays = await screenRetriever.getAllDisplays();
    final display =
        displays
            .where(
              (d) => Rect.fromLTWH(
                d.visiblePosition?.dx ?? 0,
                d.visiblePosition?.dy ?? 0,
                d.visibleSize?.width ?? d.size.width,
                d.visibleSize?.height ?? d.size.height,
              ).contains(r.center),
            )
            .firstOrNull ??
        await screenRetriever.getPrimaryDisplay();
    final origin = display.visiblePosition ?? Offset.zero,
        size = display.visibleSize ?? display.size;
    final w = r.width.clamp(32, size.width).toDouble(),
        h = r.height.clamp(32, size.height).toDouble();
    return Rect.fromLTWH(
      r.left.clamp(origin.dx, origin.dx + size.width - w).toDouble(),
      r.top.clamp(origin.dy, origin.dy + size.height - h).toDouble(),
      w,
      h,
    );
  }

  Future<void> initialize({bool showWindow = true}) async {
    await windowManager.ensureInitialized();
    _hideFirstFrame = !showWindow;
    if (_hideFirstFrame) await windowManager.setOpacity(0);
    final saved = await storage.read(key) ?? {};
    expanded = _rect(saved['expanded']);
    ball = _rect(saved['ball']);
    locked = saved['locked'] == true;
    embedded = calendar && (locked || saved['embedded'] == true);
    if (embedded) locked = true;
    await windowManager.waitUntilReadyToShow(
      WindowOptions(
        size: calendar ? const Size(1050, 740) : const Size(430, 700),
        minimumSize: const Size(340, 440),
        backgroundColor: Colors.transparent,
        skipTaskbar: !showWindow,
        title: '泥土豆',
        titleBarStyle: TitleBarStyle.hidden,
      ),
    );
    await windowManager.setAsFrameless();
    await windowManager.setHasShadow(false);
    await windowManager.setBounds(
      await clamp(
        expanded ?? Rect.fromLTWH(60, 60, calendar ? 1050 : 430, 700),
      ),
    );
    await windowManager.setPreventClose(true);
    await windowManager.setResizable(!locked);
    windowManager.addListener(this);
    if (showWindow) await windowManager.show();
  }

  @override
  void onWindowEvent(String eventName) {
    if (eventName != 'show' || !_hideFirstFrame) return;
    _hideFirstFrame = false;
    // The native runner shows its first frame. Keep the calendar-only host
    // transparent until that one automatic show has been hidden.
    guard(() async {
      await windowManager.hide();
      await windowManager.setOpacity(1);
      await windowManager.setSkipTaskbar(false);
    });
  }

  Future<void> persist() async {
    await storage.write(key, {
      'expanded': _json(expanded),
      'ball': _json(ball),
      'locked': locked,
      'embedded': embedded,
    });
  }

  @override
  void onWindowMove() => _changed();
  @override
  void onWindowResize() => _changed();
  @override
  void onWindowMaximize() {
    maximized = true;
    notifyListeners();
  }

  @override
  void onWindowUnmaximize() {
    maximized = false;
    notifyListeners();
  }

  Future<void> toggleMaximize() async {
    if (busy || collapsed || locked) return;
    if (maximized) {
      await windowManager.unmaximize();
      maximized = false;
    } else {
      await saveNow();
      await windowManager.maximize();
      maximized = true;
    }
    notifyListeners();
  }

  @override
  void onWindowClose() {
    guard(() async {
      if (calendar) {
        await hideCalendar();
      } else {
        if (trayReady) {
          await hideToTray();
        } else {
          await quit();
        }
      }
    });
  }

  @override
  void onWindowMinimize() {
    guard(() async {
      await windowManager.restore();
      if (calendar) {
        await hideCalendar();
      } else {
        await collapse();
      }
    });
  }

  void guard(Future<void> Function() operation) {
    operation().catchError((Object e) {
      onError?.call(e);
    });
  }

  void _changed() {
    if (busy) return;
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 300), () {
      guard(saveNow);
    });
  }

  Future<void> saveNow() async {
    if (busy || maximized) return;
    final r = await windowManager.getBounds();
    if (collapsed) {
      ball = r;
    } else if (docked == null) {
      expanded = r;
    }
    await persist();
    if (calendar && !locked && docked == null) {
      final ds = await screenRetriever.getAllDisplays();
      final cursor = await screenRetriever.getCursorScreenPoint();
      final d = ds
          .where(
            (d) => Rect.fromLTWH(
              d.visiblePosition?.dx ?? 0,
              d.visiblePosition?.dy ?? 0,
              d.size.width,
              d.size.height,
            ).contains(cursor),
          )
          .firstOrNull;
      if (d != null) {
        final x = d.visiblePosition?.dx ?? 0;
        final width = d.visibleSize?.width ?? d.size.width;
        if (r.right < x + 28) {
          await dock('left');
        } else if (r.left > x + width - 28) {
          await dock('right');
        }
      }
    }
  }

  Future<void> collapse() async {
    if (busy || collapsed) return;
    if (maximized) {
      await windowManager.unmaximize();
      maximized = false;
    }
    busy = true;
    try {
      expanded = await windowManager.getBounds();
      await persist();
      await native.invokeMethod('embed', false);
      collapsed = true;
      await windowManager.setMinimumSize(const Size(68, 68));
      await windowManager.setResizable(false);
      await windowManager.setBounds(
        await clamp(
          ball ??
              Rect.fromLTWH(expanded?.left ?? 60, expanded?.top ?? 60, 68, 68),
        ),
      );
      await windowManager.setAlwaysOnTop(true);
      notifyListeners();
    } finally {
      busy = false;
    }
  }

  Future<void> expand() async {
    if (busy) return;
    busy = true;
    _edgeTimer?.cancel();
    try {
      if (_hideFirstFrame) {
        _hideFirstFrame = false;
        await windowManager.setOpacity(1);
        await windowManager.setSkipTaskbar(false);
      }
      if (embedded) await native.invokeMethod('embed', false);
      if (collapsed) ball = await windowManager.getBounds();
      collapsed = false;
      docked = null;
      await windowManager.setMinimumSize(const Size(340, 440));
      await windowManager.setBounds(
        await clamp(expanded ?? const Rect.fromLTWH(60, 60, 430, 700)),
      );
      await windowManager.setResizable(!locked);
      await windowManager.setAlwaysOnTop(false);
      await windowManager.show();
      await windowManager.focus();
      await persist();
      notifyListeners();
      if (embedded) await native.invokeMethod('embed', true);
    } finally {
      busy = false;
    }
  }

  Future<void> setLocked(bool value) async {
    if (busy) return;
    if (calendar) {
      if (locked == value && embedded == value) return;
      await setEmbedded(value);
      return;
    }
    if (locked == value) return;
    if (embedded && !value) {
      await setEmbedded(false);
      return;
    }
    final previous = locked;
    busy = true;
    try {
      await windowManager.setResizable(!value);
      locked = value;
      await persist();
    } catch (_) {
      locked = previous;
      await windowManager.setResizable(!previous);
      rethrow;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> setEmbedded(bool value) async {
    if (busy) return;
    busy = true;
    _saveTimer?.cancel();
    final previous = embedded, previousLock = locked;
    try {
      // Reconfigure only while top-level. Reparenting an open editor steals IME focus.
      await native.invokeMethod('embed', false);
      await windowManager.setResizable(!value);
      await windowManager.setAlwaysOnTop(false);
      if (!_editing && value) await native.invokeMethod('embed', true);
      embedded = value;
      locked = value;
      await persist();
      notifyListeners();
    } catch (_) {
      embedded = previous;
      locked = previousLock;
      await windowManager.setResizable(!previousLock);
      if (!_editing && previous) await native.invokeMethod('embed', true);
      rethrow;
    } finally {
      busy = false;
    }
  }

  Future<void> editing(bool value) async {
    if (_editing == value) return;
    _editing = value;
    // Top-level dialogs already have focus. Showing/focusing the native window
    // for every dialog creates unnecessary activation and redraw transitions.
    if (!embedded) return;
    busy = true;
    _saveTimer?.cancel();
    try {
      if (value) {
        if (embedded) await native.invokeMethod('embed', false);
        await windowManager.show();
        await windowManager.focus();
      } else if (embedded) {
        try {
          await native.invokeMethod('embed', true);
        } catch (_) {
          embedded = false;
          locked = false;
          await windowManager.setResizable(true);
          await persist();
          notifyListeners();
          rethrow;
        }
      }
    } finally {
      busy = false;
    }
  }

  Future<void> hideCalendar() async {
    await saveNow();
    await windowManager.hide();
  }

  Future<void> dock(String side) async {
    if (busy || locked) return;
    busy = true;
    try {
      await native.invokeMethod('embed', false);
      docked = side;
      final displays = await screenRetriever.getAllDisplays();
      final cursor = await screenRetriever.getCursorScreenPoint();
      final d =
          displays
              .where(
                (d) => Rect.fromLTWH(
                  d.visiblePosition?.dx ?? 0,
                  d.visiblePosition?.dy ?? 0,
                  d.visibleSize?.width ?? d.size.width,
                  d.visibleSize?.height ?? d.size.height,
                ).contains(cursor),
              )
              .firstOrNull ??
          await screenRetriever.getPrimaryDisplay();
      final o = d.visiblePosition ?? Offset.zero, s = d.visibleSize ?? d.size;
      await windowManager.setMinimumSize(const Size(24, 88));
      await windowManager.setResizable(false);
      await windowManager.setBounds(
        Rect.fromLTWH(
          side == 'left' ? o.dx : o.dx + s.width - 24,
          (expanded?.top ?? 80).clamp(o.dy, o.dy + s.height - 88).toDouble(),
          24,
          88,
        ),
      );
      await windowManager.setAlwaysOnTop(true);
      notifyListeners();
      _edgeTimer = Timer.periodic(const Duration(milliseconds: 180), (_) {
        guard(() async {
          final p = await screenRetriever.getCursorScreenPoint();
          final near =
              p.dy >= o.dy &&
              p.dy <= o.dy + s.height &&
              (side == 'left'
                  ? p.dx >= o.dx && p.dx <= o.dx + 36
                  : p.dx >= o.dx + s.width - 36 && p.dx <= o.dx + s.width);
          if (near) {
            await windowManager.show(inactive: true);
          } else {
            await windowManager.hide();
          }
        });
      });
    } finally {
      busy = false;
    }
  }

  Future<void> close() async {
    _edgeTimer?.cancel();
    _saveTimer?.cancel();
    windowManager.removeListener(this);
    await persist();
  }

  Future<void> initializeTray() async {
    if (calendar) return;
    native.setMethodCallHandler((call) async {
      if (call.method != 'trayAction') return;
      guard(() async {
        switch (call.arguments) {
          case 1:
            await expand();
          case 2:
            await onOpenCalendar?.call();
          case 3:
            await windowManager.show();
            if (!collapsed) await collapse();
          case 4:
            await quit();
        }
      });
    });
    await native.invokeMethod('trayEnable', true);
    trayReady = true;
  }

  Future<void> hideToTray() async {
    await saveNow();
    await windowManager.hide();
  }

  Future<void> quit() async {
    if (_quitting) return;
    _quitting = true;
    try {
      await saveNow();
      await onClose?.call();
      if (trayReady) {
        await native.invokeMethod('trayEnable', false);
        trayReady = false;
        native.setMethodCallHandler(null);
      }
      await windowManager.destroy();
    } catch (_) {
      _quitting = false;
      rethrow;
    }
  }
}

class StartupSelection {
  final bool list, calendar;
  const StartupSelection({this.list = false, this.calendar = false});
  bool get enabled => list || calendar;
  List<String> get arguments => [
    '--startup',
    if (list) '--startup-list',
    if (calendar) '--startup-calendar',
  ];

  static StartupSelection? launch(List<String> args) {
    if (!args.contains('--startup')) return null;
    return StartupSelection(
      list: args.contains('--startup-list'),
      calendar: args.contains('--startup-calendar'),
    );
  }

  String command(String executable) => '"$executable" ${arguments.join(' ')}';

  static StartupSelection fromCommand(String command, String executable) {
    final match = RegExp(r'^\s*"([^"]+)"(.*)$').firstMatch(command);
    final path = match?.group(1) ?? command.trim();
    if (path.toLowerCase() != executable.toLowerCase()) {
      return const StartupSelection();
    }
    final args = (match?.group(2) ?? '').trim().split(RegExp(r'\s+'));
    // Existing startup entries launched the list without arguments.
    return launch(args) ?? const StartupSelection(list: true);
  }
}

class WindowsStartup {
  static const key = r'HKCU\Software\Microsoft\Windows\CurrentVersion\Run';
  static Future<StartupSelection> selection() async {
    final result = await Process.run('reg.exe', [
      'query',
      key,
      '/v',
      'NeedTODO',
    ]);
    if (result.exitCode != 0) return const StartupSelection();
    final match = RegExp(r'REG_SZ\s+([^\r\n]+)')
        .firstMatch(result.stdout.toString());
    return StartupSelection.fromCommand(
      match?.group(1) ?? '',
      Platform.resolvedExecutable,
    );
  }

  static Future<void> setSelection(StartupSelection value) async {
    final result = await Process.run(
      'reg.exe',
      value.enabled
          ? [
              'add',
              key,
              '/v',
              'NeedTODO',
              '/t',
              'REG_SZ',
              '/d',
              value.command(Platform.resolvedExecutable),
              '/f',
            ]
          : ['delete', key, '/v', 'NeedTODO', '/f'],
    );
    if (result.exitCode != 0) throw Exception('开机启动设置失败，请重试');
  }
}
