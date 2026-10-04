import 'dart:async';
import 'dart:io';

import 'package:app_links/app_links.dart';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:window_manager/window_manager.dart';

import 'model.dart';
import 'store.dart';
import 'platform_services.dart';
import 'ui/components.dart';
import 'ui/preferences.dart';
import 'ui/schedule.dart';
import 'holiday_calendar.dart';
import 'ui/reminder_popup.dart';
import 'ui/categories.dart';
import 'ui/journal.dart';

class NeedTodoApp extends StatelessWidget {
  final AppStore store;
  final DesktopController? desktop;
  final PlatformServices? services;
  const NeedTodoApp({
    super.key,
    required this.store,
    this.desktop,
    this.services,
  });
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: '泥土豆',
    debugShowCheckedModeBanner: false,
    theme: appTheme(),
    locale: const Locale('zh', 'CN'),
    supportedLocales: const [Locale('zh', 'CN'), Locale('en')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    home: ListenableBuilder(
      listenable: store,
      builder: (context, _) => !store.ready
          ? const Scaffold(body: Center(child: CupertinoActivityIndicator()))
          : store.entered
          ? Workspace(store: store, desktop: desktop, services: services)
          : LoginPage(store: store, desktop: desktop),
    ),
  );
}

class LoginPage extends StatefulWidget {
  final AppStore store;
  final DesktopController? desktop;
  const LoginPage({super.key, required this.store, this.desktop});
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final username = TextEditingController(), password = TextEditingController();
  bool register = false, busy = false;
  String? error;
  @override
  void dispose() {
    username.dispose();
    password.dispose();
    super.dispose();
  }

  Future<void> run(Future<void> Function() fn) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await fn();
    } catch (e) {
      if (mounted) {
        setState(() => error = e.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Column(
        children: [
          if (widget.desktop != null)
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onPanStart: (_) => windowManager.startDragging(),
                    child: const SizedBox(height: 40),
                  ),
                ),
                AnimatedBuilder(
                  animation: widget.desktop!,
                  builder: (context, _) => ActionIcon(
                    widget.desktop!.maximized
                        ? CupertinoIcons.fullscreen_exit
                        : CupertinoIcons.fullscreen,
                    widget.desktop!.maximized ? '还原窗口' : '最大化窗口',
                    () => widget.desktop!.guard(widget.desktop!.toggleMaximize),
                  ),
                ),
                ActionIcon(
                  CupertinoIcons.xmark,
                  '关闭',
                  () => widget.desktop!.onWindowClose(),
                ),
              ],
            ),
          Expanded(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(28),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 350),
                  child: AutofillGroup(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Row(
                          children: [
                            Identity(size: 34),
                            SizedBox(width: 10),
                            Text(
                              '泥土豆',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 36),
                        Text(
                          register ? '注册' : '登录',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 24),
                        TextField(
                          controller: username,
                          autofillHints: const [AutofillHints.username],
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            hintText: '账号',
                            labelText: '账号',
                          ),
                          maxLength: 32,
                          buildCounter: (
                            _, {
                            required currentLength,
                            required isFocused,
                            required maxLength,
                          }) => null,
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: password,
                          autofillHints: [
                            register
                                ? AutofillHints.newPassword
                                : AutofillHints.password,
                          ],
                          obscureText: true,
                          maxLength: 128,
                          buildCounter: (
                            _, {
                            required currentLength,
                            required isFocused,
                            required maxLength,
                          }) => null,
                          decoration: const InputDecoration(
                            hintText: '密码',
                            labelText: '密码',
                          ),
                          onSubmitted: (_) => run(
                            () => widget.store.authenticate(
                              username.text,
                              password.text,
                              register,
                            ),
                          ),
                        ),
                        if (error != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: Text(
                              error!,
                              style: const TextStyle(
                                color: Colors.redAccent,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        const SizedBox(height: 20),
                        FilledButton(
                          onPressed: busy
                              ? null
                              : () => run(
                                  () => widget.store.authenticate(
                                    username.text,
                                    password.text,
                                    register,
                                  ),
                                ),
                          child: Text(
                            busy
                                ? '请稍候'
                                : register
                                ? '注册'
                                : '登录',
                          ),
                        ),
                        TextButton(
                          onPressed: busy
                              ? null
                              : () => setState(() {
                                  register = !register;
                                  error = null;
                                }),
                          child: Text(register ? '已有账号，登录' : '注册账号'),
                        ),
                        const SizedBox(height: 16),
                        TextButton(
                          onPressed: busy
                              ? null
                              : () => run(widget.store.enterLocal),
                          child: const Text(
                            '本机使用',
                            style: TextStyle(color: muted),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class Workspace extends StatefulWidget {
  final AppStore store;
  final DesktopController? desktop;
  final PlatformServices? services;
  const Workspace({
    super.key,
    required this.store,
    this.desktop,
    this.services,
  });
  @override
  State<Workspace> createState() => _WorkspaceState();
}

class _WorkspaceState extends State<Workspace> with WidgetsBindingObserver {
  bool calendar = false;
  bool journal = false;
  bool showAgenda = false;
  bool? timelineOverride;
  bool get timeline => timelineOverride ?? store.document.reminders.timeline;
  String scope = 'day';
  DateTime selected = dayOnly(DateTime.now());
  Appearance? preview;
  final quick = TextEditingController();
  bool adding = false;
  int lastSignal = 0;
  late final holidayCalendar = HolidayCalendar(store.storage);
  Timer? todayTimer;
  Future<void> _reminderDialogs = Future.value();
  DateTime today = dayOnly(DateTime.now());
  StreamSubscription<Uri>? links;
  String get layout => calendar ? 'calendar' : 'list';
  Appearance get appearance =>
      preview ??
      (calendar ? widget.store.document.calendar : widget.store.document.list);
  AppStore get store => widget.store;
  @override
  void initState() {
    super.initState();
    calendar = widget.desktop?.calendar ?? false;
    widget.desktop?.addListener(refresh);
    if (widget.desktop?.embedded == true) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) run(() => widget.desktop!.setEmbedded(true));
      });
    }
    holidayCalendar.addListener(refresh);
    unawaited(holidayCalendar.loadAround(selected.year));
    store.addListener(changed);
    widget.services?.onReminder = showReminders;
    WidgetsBinding.instance.addObserver(this);
    todayTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      final now = dayOnly(DateTime.now());
      if (mounted && now != today) setState(() => today = now);
    });
    if (Platform.isAndroid || Platform.isIOS) {
      void openDate(String? value) {
        final date = DateTime.tryParse(value ?? '');
        if (date != null && mounted) {
          setState(() {
            selected = date;
            calendar = true;
          });
        }
      }

      native.setMethodCallHandler((call) async {
        if (call.method == 'openDate') openDate(call.arguments as String?);
      });
      native
          .invokeMethod<String>('widgetLaunch')
          .then(openDate)
          .catchError((Object _) {});
      final appLinks = AppLinks();
      appLinks
          .getInitialLink()
          .then((uri) {
            if (uri?.host == 'calendar') openDate(uri?.queryParameters['date']);
          })
          .catchError((Object _) {});
      links = appLinks.uriLinkStream.listen((uri) {
        if (uri.host == 'calendar') openDate(uri.queryParameters['date']);
      }, onError: (Object _) {});
    }
  }

  void refresh() {
    if (mounted) setState(() {});
  }

  Future<void> showReminders(List<Todo> tasks, ReminderStyle style) {
    final next = _reminderDialogs.then((_) async {
      if (!mounted) return;
      if (Platform.isWindows) {
        await showDesktopReminder(store.storage.directory, tasks, style);
      } else {
        await showTopReminder(context, tasks, style);
      }
    });
    _reminderDialogs = next.catchError((Object _) {});
    return next;
  }

  void changed() {
    if (widget.desktop?.calendar == true &&
        store.remoteOpenSignal != lastSignal) {
      lastSignal = store.remoteOpenSignal;
      run(widget.desktop!.expand);
    }
    refresh();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    widget.services?.setForeground(state == AppLifecycleState.resumed);
    if (state == AppLifecycleState.resumed) {
      run(store.sync);
    }
  }

  @override
  void dispose() {
    widget.services?.onReminder = null;
    holidayCalendar.removeListener(refresh);
    holidayCalendar.dispose();
    todayTimer?.cancel();
    links?.cancel();
    if (Platform.isAndroid || Platform.isIOS) native.setMethodCallHandler(null);
    quick.dispose();
    widget.desktop?.removeListener(refresh);
    store.removeListener(changed);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> run(Future<void> Function() fn) async {
    try {
      await fn();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
        );
      }
    }
  }

  Future<void> openSettings() async {
    await run(() async {
      await widget.desktop?.editing(true);
      if (!mounted) return;
      try {
        await showPanel(
          context,
          '设置',
          SettingsView(
            store: store,
            layout: layout,
            desktop: widget.desktop,
            preview: (v) {
              if (mounted) setState(() => preview = v);
            },
          ),
          width: 390,
          fixedHeight: true,
        );
      } finally {
        if (mounted) setState(() => preview = null);
        await widget.desktop?.editing(false);
      }
    });
  }

  Future<void> edit([Todo? task, DateTime? date]) async {
    final fromQuick = task == null && date == null && !calendar;
    final draftText = fromQuick ? quick.text : '';
    await run(() async {
      await widget.desktop?.editing(true);
      if (!mounted) return;
      try {
        final saved = await showPanel<bool>(
          context,
          task == null ? '添加日程' : '编辑日程',
          TaskEditor(
            task: task,
            initialTitle: draftText,
            date: date ?? selected,
            scope: calendar ? 'day' : scope,
            appearance: appearance,
            store: store,
            services: widget.services,
          ),
        );
        if (saved == true && fromQuick && mounted && quick.text == draftText) {
          quick.clear();
        }
      } finally {
        await widget.desktop?.editing(false);
      }
    });
  }

  Future<void> pickDate() async {
    await run(() async {
      await widget.desktop?.editing(true);
      if (!mounted) return;
      try {
        final d = await chooseDate(context, selected);
        if (d != null && mounted) {
          setState(() => selected = d);
          unawaited(holidayCalendar.loadAround(d.year));
        }
      } finally {
        await widget.desktop?.editing(false);
      }
    });
  }

  void shift(int direction) {
    setState(() {
      selected = calendar || scope == 'month'
          ? DateTime(selected.year, selected.month + direction, 1)
          : DateTime(
              selected.year,
              selected.month,
              selected.day + direction * (scope == 'week' ? 7 : 1),
            );
    });
    unawaited(holidayCalendar.loadAround(selected.year));
  }

  void toggleCalendar() {
    if (widget.desktop != null) {
      if (calendar) {
        run(() => windowManager.hide());
      } else {
        run(store.openCalendar);
      }
    } else {
      setState(() {
        calendar = !calendar;
        preview = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final a = journal && !calendar
        ? (appearance.clone()
            ..background = ''
            ..effect = 'default'
            ..opacity = 1)
        : widget.desktop?.maximized == true
        ? appearance.clone()
        : appearance;
    if (widget.desktop?.maximized == true) a.radius = 0;
    if (journal && !calendar) {
      a.palette.background = panel;
      a.palette.text = ink;
    }
    final p = a.palette, d = widget.desktop;
    if (d?.collapsed == true) {
      return Material(
        color: Colors.transparent,
        child: GestureDetector(
          onPanStart: (_) => windowManager.startDragging(),
          onTap: () => run(d!.expand),
          child: Center(
            child: Identity(data: store.document.list.floatingImage, size: 60),
          ),
        ),
      );
    }
    if (d?.docked != null) {
      return Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => run(d!.expand),
          child: Container(
            decoration: BoxDecoration(
              color: blue,
              borderRadius: BorderRadius.circular(10),
            ),
            alignment: Alignment.center,
            child: const Icon(
              CupertinoIcons.calendar,
              size: 18,
              color: Colors.white,
            ),
          ),
        ),
      );
    }
    Widget body = Scaffold(
      backgroundColor: d == null ? panel : Colors.transparent,
      body: SafeArea(
        child: Surface(
          appearance: a,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 8, 8, 4),
                child: Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onPanStart: d == null || d.locked
                            ? null
                            : (_) => windowManager.startDragging(),
                        child: Row(
                          children: [
                            Identity(data: a.avatar, size: 28),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                a.name,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: p.text,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (calendar && d != null)
                      ActionIcon(
                        d.locked
                            ? CupertinoIcons.lock_fill
                            : CupertinoIcons.lock_open,
                        d.locked ? '解锁桌面' : '锁定桌面',
                        d.busy ? null : () => run(() => d.setLocked(!d.locked)),
                        color: d.locked ? p.accent : p.text,
                      )
                    else
                      ActionIcon(
                        calendar
                            ? CupertinoIcons.list_bullet
                            : CupertinoIcons.calendar,
                        calendar
                            ? '清单'
                            : d == null
                            ? '月历'
                            : '打开桌面月历',
                        toggleCalendar,
                        color: p.text,
                      ),
                    if (!calendar)
                      ActionIcon(
                        journal
                            ? CupertinoIcons.list_bullet
                            : CupertinoIcons.book,
                        journal ? '返回清单' : '日记',
                        () => setState(() => journal = !journal),
                        color: journal ? p.accent : p.text,
                      ),
                    ActionIcon(
                      CupertinoIcons.slider_horizontal_3,
                      '设置',
                      openSettings,
                      color: p.text,
                    ),
                    if (d != null && !d.locked)
                      ActionIcon(
                        d.maximized
                            ? CupertinoIcons.fullscreen_exit
                            : CupertinoIcons.fullscreen,
                        d.maximized ? '还原窗口' : '最大化窗口',
                        d.locked || d.busy ? null : () => run(d.toggleMaximize),
                        color: p.text,
                      ),
                    if (d != null)
                      ActionIcon(
                        CupertinoIcons.minus,
                        '收起',
                        () => run(calendar ? d.hideCalendar : d.collapse),
                        color: p.text,
                      ),
                  ],
                ),
              ),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, c) {
                    final wide = c.maxWidth >= 760 && c.maxHeight >= 430;
                    return calendar
                        ? CalendarWorkspace(
                            appearance: a,
                            calendarDays: holidayCalendar.days,
                            selected: selected,
                            tasks: store.document.tasks,
                            wide: wide,
                            showAgenda: showAgenda,
                            toggleAgenda: () =>
                                setState(() => showAgenda = !showAgenda),
                            select: (date) => setState(() {
                              selected = date;
                              showAgenda = true;
                            }),
                            edit: edit,
                            toggle: (t) => run(() => store.toggleTask(t)),
                            previous: () => shift(-1),
                            next: () => shift(1),
                            pickDate: pickDate,
                          )
                        : journal
                        ? JournalWorkspace(
                            store: store,
                            accent: p.accent,
                            desktop: d,
                          )
                        : Center(
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 720),
                              child: Column(
                                children: [
                                  if (c.maxHeight >= 330)
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 20,
                                        vertical: 12,
                                      ),
                                      child: SizedBox(
                                        width: double.infinity,
                                        child:
                                            CupertinoSlidingSegmentedControl<
                                              String
                                            >(
                                              groupValue: scope,
                                              backgroundColor: p.line
                                                  .withValues(alpha: .08),
                                              thumbColor: p.background
                                                  .withValues(alpha: 1),
                                              children: {
                                                for (final e in const {
                                                  'day': '日计划',
                                                  'week': '周计划',
                                                  'month': '月计划',
                                                }.entries)
                                                  e.key: Padding(
                                                    padding:
                                                        const EdgeInsets.symmetric(
                                                          vertical: 6,
                                                        ),
                                                    child: Text(
                                                      e.value,
                                                      style: TextStyle(
                                                        color: p.text,
                                                        fontSize: 13,
                                                      ),
                                                    ),
                                                  ),
                                              },
                                              onValueChanged: (v) {
                                                if (v != null) {
                                                  setState(() => scope = v);
                                                }
                                              },
                                            ),
                                      ),
                                    ),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                    ),
                                    child: Row(
                                      children: [
                                        TextButton(
                                          onPressed: pickDate,
                                          child: Text(
                                            scope == 'day' &&
                                                    dayKey(selected) ==
                                                        dayKey(today)
                                                ? '今天 · ${periodLabel(scope, selected)}'
                                                : periodLabel(scope, selected),
                                            style: TextStyle(
                                              color: p.text,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ),
                                        const Spacer(),
                                        if (dayKey(selected) != dayKey(today))
                                          TextButton(
                                            style: TextButton.styleFrom(
                                              minimumSize: const Size(0, 32),
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 4,
                                                  ),
                                            ),
                                            onPressed: () => setState(
                                              () => selected = today,
                                            ),
                                            child: Text(
                                              '回到今天',
                                              style: TextStyle(
                                                fontSize: 11,
                                                color: p.accent,
                                              ),
                                            ),
                                          ),
                                        ActionIcon(
                                          CupertinoIcons.chevron_left,
                                          '上一周期',
                                          () => shift(-1),
                                          color: p.text,
                                        ),
                                        ActionIcon(
                                          CupertinoIcons.chevron_right,
                                          '下一周期',
                                          () => shift(1),
                                          color: p.text,
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (scope == 'day' && c.maxHeight >= 370)
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 16,
                                        vertical: 8,
                                      ),
                                      child: Row(
                                        children: List.generate(7, (i) {
                                          final date = selected
                                                  .subtract(
                                                    Duration(
                                                      days:
                                                          selected.weekday - 1,
                                                    ),
                                                  )
                                                  .add(Duration(days: i)),
                                              active =
                                                  dayKey(date) ==
                                                  dayKey(selected),
                                              isToday =
                                                  dayKey(date) == dayKey(today);
                                          return Expanded(
                                            child: TextButton(
                                              style: TextButton.styleFrom(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      vertical: 10,
                                                    ),
                                                backgroundColor: active
                                                    ? p.accent
                                                    : null,
                                                shape: RoundedRectangleBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(12),
                                                  side: isToday && !active
                                                      ? BorderSide(
                                                          color: p.accent,
                                                        )
                                                      : BorderSide.none,
                                                ),
                                              ),
                                              onPressed: () => setState(
                                                () => selected = date,
                                              ),
                                              child: Column(
                                                children: [
                                                  Text(
                                                    isToday
                                                        ? '今天'
                                                        : [
                                                            '一',
                                                            '二',
                                                            '三',
                                                            '四',
                                                            '五',
                                                            '六',
                                                            '日',
                                                          ][i],
                                                    style: TextStyle(
                                                      fontSize: 10,
                                                      color: active
                                                          ? p.background
                                                          : p.text.withValues(
                                                              alpha: .5,
                                                            ),
                                                    ),
                                                  ),
                                                  const SizedBox(height: 5),
                                                  Text(
                                                    '${date.day}',
                                                    style: TextStyle(
                                                      fontSize: 15,
                                                      fontWeight: isToday
                                                          ? FontWeight.w600
                                                          : FontWeight.w400,
                                                      color: active
                                                          ? p.background
                                                          : p.text,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          );
                                        }),
                                      ),
                                    ),
                                  if (scope == 'week')
                                    TaskProgress(
                                      tasks: tasksForPeriod(
                                        store.document.tasks,
                                        scope,
                                        selected,
                                      ),
                                      color: p.accent,
                                    ),
                                  if (scope == 'day')
                                    Align(
                                      alignment: Alignment.centerRight,
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 16,
                                        ),
                                        child:
                                            CupertinoSlidingSegmentedControl<
                                              bool
                                            >(
                                              groupValue: timeline,
                                              children: const {
                                                false: Text(
                                                  '任务',
                                                  style: TextStyle(
                                                    fontSize: 11,
                                                  ),
                                                ),
                                                true: Text(
                                                  '24小时',
                                                  style: TextStyle(
                                                    fontSize: 11,
                                                  ),
                                                ),
                                              },
                                              onValueChanged: (v) {
                                                if (v != null) {
                                                  setState(
                                                    () => timelineOverride = v,
                                                  );
                                                }
                                              },
                                            ),
                                      ),
                                    ),
                                  Expanded(
                                    child: scope == 'month'
                                        ? MonthOverview(
                                            key: ValueKey(
                                              'month-${selected.year}-${selected.month}',
                                            ),
                                            tasks: store.document.tasks,
                                            appearance: a,
                                            month: selected,
                                            today: today,
                                            edit: (t) => edit(t),
                                            toggle: (t) =>
                                                run(() => store.toggleTask(t)),
                                          )
                                        : scope == 'day' && timeline
                                        ? DayTimeline(
                                            selectedDate: selected,
                                            tasks: tasksForPeriod(
                                              store.document.tasks,
                                              scope,
                                              selected,
                                            ),
                                            appearance: a,
                                            edit: (t) => edit(t),
                                            toggle: (t) =>
                                                run(() => store.toggleTask(t)),
                                          )
                                        : TaskList(
                                            showDates: scope != 'day',
                                            tasks: tasksForPeriod(
                                              store.document.tasks,
                                              scope,
                                              selected,
                                            ),
                                            appearance: a,
                                            edit: (t) => edit(t),
                                            toggle: (t) =>
                                                run(() => store.toggleTask(t)),
                                          ),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                      16,
                                      8,
                                      16,
                                      18,
                                    ),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: TextField(
                                            controller: quick,
                                            style: TextStyle(color: p.text),
                                            decoration: InputDecoration(
                                              hintText: '添加日程',
                                              hintStyle: TextStyle(
                                                color: p.text.withValues(
                                                  alpha: .45,
                                                ),
                                              ),
                                              fillColor: p.text.withValues(
                                                alpha: .05,
                                              ),
                                              suffixIcon: ActionIcon(
                                                CupertinoIcons
                                                    .calendar_badge_plus,
                                                '详细添加',
                                                () => edit(),
                                              ),
                                            ),
                                            onSubmitted: (_) => quickAdd(),
                                          ),
                                        ),
                                        ActionIcon(
                                          CupertinoIcons.add_circled_solid,
                                          '添加',
                                          adding ? null : quickAdd,
                                          color: p.accent,
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                  },
                ),
              ),
              if (store.error != null)
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          store.error!,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.redAccent,
                          ),
                        ),
                      ),
                      ActionIcon(
                        CupertinoIcons.xmark,
                        '关闭提示',
                        () => setState(() => store.error = null),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    if (d != null && !d.locked) {
      body = DragToResizeArea(resizeEdgeSize: 6, child: body);
    }
    return body;
  }

  Future<void> quickAdd() async {
    if (adding || quick.text.trim().isEmpty) return;
    setState(() => adding = true);
    await run(() async {
      await store.saveTask(
        Todo(
          title: quick.text.trim(),
          date: dayKey(selected),
          scope: scope,
          level: appearance.levelSet.levels.first.id,
        ),
      );
      quick.clear();
    });
    if (mounted) setState(() => adding = false);
  }
}

class TaskList extends StatelessWidget {
  final bool showDates;
  final List<Todo> tasks;
  final Appearance appearance;
  final ValueChanged<Todo> edit, toggle;
  const TaskList({
    super.key,
    this.showDates = false,
    required this.tasks,
    required this.appearance,
    required this.edit,
    required this.toggle,
  });
  @override
  Widget build(BuildContext context) {
    final p = appearance.palette,
        ordered = [...tasks]
          ..sort((a, b) {
            final order = compareTaskTime(a, b, byDate: showDates);
            return order == 0
                ? tasks.indexOf(a).compareTo(tasks.indexOf(b))
                : order;
          });
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
          child: Row(
            children: [
              Text(
                showDates ? '日程' : '待办',
                style: TextStyle(
                  fontSize: 12,
                  color: p.text.withValues(alpha: .65),
                ),
              ),
              const Spacer(),
              if (!showDates)
                Text(
                  '${tasks.where((t) => t.done).length} / ${tasks.length}',
                  style: TextStyle(
                    fontSize: 12,
                    color: p.text.withValues(alpha: .65),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: tasks.isEmpty
              ? Center(
                  child: Text(
                    '暂无日程',
                    style: TextStyle(
                      color: p.text.withValues(alpha: .4),
                      fontSize: 13,
                    ),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 4,
                  ),
                  itemCount: ordered.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 7),
                  itemBuilder: (context, i) {
                    final t = ordered[i];
                    return Column(
                      key: ValueKey(t.id),
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (showDates &&
                            (i == 0 || ordered[i - 1].date != t.date))
                          Padding(
                            padding: EdgeInsets.fromLTRB(
                              4,
                              i == 0 ? 2 : 12,
                              4,
                              8,
                            ),
                            child: Text(
                              dateLabel(DateTime.parse(t.date)),
                              style: TextStyle(
                                fontSize: 12,
                                color: p.text,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        Container(
                          decoration: BoxDecoration(
                            color: appearance.taskColor(t.level),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: [
                              IconButton(
                                tooltip: t.done ? '取消完成' : '完成',
                                onPressed: () => toggle(t),
                                icon: Icon(
                                  t.done
                                      ? CupertinoIcons.check_mark_circled_solid
                                      : CupertinoIcons.circle,
                                  size: 21,
                                  color: p.accent,
                                ),
                              ),
                              Expanded(
                                child: InkWell(
                                  onTap: () => edit(t),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 13,
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          t.title,
                                          style: TextStyle(
                                            color: appearance
                                                .taskTextColor(t.level)
                                                .withValues(
                                                  alpha:
                                                      appearance
                                                          .taskTextColor(
                                                            t.level,
                                                          )
                                                          .a *
                                                      (t.done ? .45 : 1),
                                                ),
                                            decoration: t.done
                                                ? TextDecoration.lineThrough
                                                : null,
                                            fontSize: 13,
                                            fontWeight: FontWeight.w400,
                                            height: 1.45,
                                          ),
                                        ),
                                        if (t.category.isNotEmpty)
                                          Text(
                                            t.category,
                                            style: TextStyle(
                                              fontSize: 10,
                                              color: p.text.withValues(
                                                alpha: .6,
                                              ),
                                            ),
                                          ),
                                        if (taskTimeLabel(t).isNotEmpty)
                                          Text(
                                            taskTimeLabel(t),
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: appearance
                                                  .taskTextColor(t.level)
                                                  .withValues(
                                                    alpha:
                                                        appearance
                                                            .taskTextColor(
                                                              t.level,
                                                            )
                                                            .a *
                                                        .65,
                                                  ),
                                            ),
                                          ),
                                        if (t.reminder != null && !t.done)
                                          Padding(
                                            padding: const EdgeInsets.only(
                                              top: 3,
                                            ),
                                            child: Text(
                                              '${t.reminder!.toLocal().month}/${t.reminder!.toLocal().day} ${t.reminder!.toLocal().hour.toString().padLeft(2, '0')}:${t.reminder!.toLocal().minute.toString().padLeft(2, '0')}',
                                              style: TextStyle(
                                                fontSize: 11,
                                                color: p.text.withValues(
                                                  alpha: .5,
                                                ),
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                            ],
                          ),
                        ),
                      ],
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class CalendarTask extends StatelessWidget {
  final Todo task;
  final Appearance appearance;
  final ValueChanged<Todo> toggle, edit;
  const CalendarTask({
    super.key,
    required this.task,
    required this.appearance,
    required this.toggle,
    required this.edit,
  });

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.fromLTRB(3, 3, 3, 0),
    decoration: BoxDecoration(
      color: appearance.taskColor(task.level),
      borderRadius: BorderRadius.circular(5),
    ),
    child: Row(
      children: [
        SizedBox(
          width: 28,
          height: 28,
          child: IconButton(
            padding: EdgeInsets.zero,
            tooltip: task.done ? '取消打卡：${task.title}' : '打卡：${task.title}',
            onPressed: () => toggle(task),
            icon: Icon(
              task.done
                  ? CupertinoIcons.check_mark_circled_solid
                  : CupertinoIcons.circle,
              size: 15,
              color: appearance.palette.accent,
            ),
          ),
        ),
        Expanded(
          child: InkWell(
            onTap: () => edit(task),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text(
                task.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  color: appearance
                      .taskTextColor(task.level)
                      .withValues(
                        alpha:
                            appearance.taskTextColor(task.level).a *
                            (task.done ? .45 : 1),
                      ),
                  decoration: task.done ? TextDecoration.lineThrough : null,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 4),
      ],
    ),
  );
}

class CalendarWorkspace extends StatelessWidget {
  final Map<String, DateHeaderStyle> dateHeaders;
  final ValueChanged<DateTime>? editHeader;
  final Map<String, CalendarDay> calendarDays;
  final bool showAgenda;
  final VoidCallback toggleAgenda;
  final Appearance appearance;
  final DateTime selected;
  final List<Todo> tasks;
  final bool wide;
  final ValueChanged<DateTime> select;
  final Future<void> Function([Todo?, DateTime?]) edit;
  final ValueChanged<Todo> toggle;
  final VoidCallback previous, next, pickDate;
  const CalendarWorkspace({
    super.key,
    required this.appearance,
    required this.selected,
    required this.tasks,
    required this.wide,
    required this.select,
    required this.edit,
    required this.toggle,
    required this.previous,
    required this.next,
    required this.pickDate,
    required this.showAgenda,
    required this.toggleAgenda,
    this.calendarDays = const {},
    this.dateHeaders = const {},
    this.editHeader,
  });
  @override
  Widget build(BuildContext context) {
    final p = appearance.palette,
        month = DateTime(selected.year, selected.month),
        start = month.subtract(Duration(days: month.weekday - 1));
    const calendarInset = 12.0;
    const calendarHeight = 410.0;
    final dayTasks = tasks
        .where(
          (t) => !t.deleted && t.scope == 'day' && t.date == dayKey(selected),
        )
        .toList();
    Widget calendar = Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: TextButton(
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    alignment: Alignment.centerLeft,
                  ),
                  onPressed: pickDate,
                  child: Text(
                    '${selected.year}年 ${selected.month}月',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: p.text,
                      fontSize: 18,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
              ActionIcon(
                CupertinoIcons.chevron_left,
                '上个月',
                previous,
                color: p.text,
              ),
              ActionIcon(
                CupertinoIcons.chevron_right,
                '下个月',
                next,
                color: p.text,
              ),
              ActionIcon(
                CupertinoIcons.sidebar_right,
                showAgenda ? '收起日程清单' : '展开日程清单',
                toggleAgenda,
                color: p.text,
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: calendarInset),
          child: Row(
            children: ['一', '二', '三', '四', '五', '六', '日']
                .map(
                  (s) => Expanded(
                    child: Center(
                      child: Text(
                        s,
                        style: TextStyle(
                          fontSize: 11,
                          color: p.text.withValues(alpha: .5),
                        ),
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: LayoutBuilder(
            builder: (context, c) => GridView.builder(
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: calendarInset),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 7,
                childAspectRatio:
                    (c.maxWidth - calendarInset * 2) / 7 / (c.maxHeight / 6),
                crossAxisSpacing: 0,
                mainAxisSpacing: 0,
              ),
              itemCount: 42,
              itemBuilder: (context, i) {
                final date = start.add(Duration(days: i)),
                    key = dayKey(date),
                    active = key == dayKey(selected),
                    today = key == dayKey(DateTime.now()),
                    items =
                        tasks
                            .where(
                              (t) =>
                                  !t.deleted &&
                                  t.scope == 'day' &&
                                  t.date == key,
                            )
                            .toList()
                          ..sort(compareTaskTime);
                final holiday = calendarDays[key];
                final previousHoliday =
                    calendarDays[dayKey(
                      date.subtract(const Duration(days: 1)),
                    )];
                return InkWell(
                  onTap: () => select(date),
                  onLongPress: () => edit(null, date),
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    decoration: BoxDecoration(
                      color: active ? p.accent.withValues(alpha: .10) : null,
                      border: Border(
                        right: wide && i % 7 != 6
                            ? BorderSide(color: p.line, width: .5)
                            : BorderSide.none,
                        bottom: wide && i < 35
                            ? BorderSide(color: p.line, width: .5)
                            : BorderSide.none,
                      ),
                    ),
                    child: Column(
                      children: [
                        Container(
                          key: ValueKey('date-header-$key'),
                          width: 24,
                          height: 24,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: today ? p.accent : Colors.transparent,
                            shape: BoxShape.circle,
                          ),
                          child: Text(
                            '${date.day}',
                            style: TextStyle(
                              color: today
                                  ? (ThemeData.estimateBrightnessForColor(
                                              p.accent,
                                            ) ==
                                            Brightness.dark
                                        ? Colors.white
                                        : p.text)
                                  : date.month == month.month
                                  ? p.text
                                  : p.text.withValues(alpha: .4),
                              fontSize: 13,
                              fontWeight: today
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                            ),
                          ),
                        ),
                        SizedBox(
                          height: 16,
                          child: holiday == null
                              ? null
                              : Tooltip(
                                  message:
                                      '${holiday.name} · ${holiday.off ? '休息' : '调休上班'}',
                                  child: Text(
                                    holiday.off
                                        ? (previousHoliday?.name !=
                                                      holiday.name ||
                                                  date.day == 1
                                              ? holiday.name
                                              : '休')
                                        : '班',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 9,
                                      color: holiday.off
                                          ? const Color(0xffb65d5d)
                                          : p.text.withValues(alpha: .6),
                                    ),
                                  ),
                                ),
                        ),
                        if (items.isNotEmpty)
                          Expanded(
                            child: LayoutBuilder(
                              builder: (context, cell) => cell.maxWidth >= 72
                                  ? ListView.builder(
                                      padding: EdgeInsets.zero,
                                      itemCount: items.length,
                                      itemBuilder: (context, index) =>
                                          CalendarTask(
                                            task: items[index],
                                            appearance: appearance,
                                            toggle: toggle,
                                            edit: (t) => edit(t),
                                          ),
                                    )
                                  : Center(
                                      child: Text(
                                        '${items.where((t) => t.done).length}/${items.length}',
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: p.accent,
                                        ),
                                      ),
                                    ),
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
    final agenda = Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 12, 0),
          child: Row(
            children: [
              Text(
                '${selected.month}月${selected.day}日',
                style: TextStyle(color: p.text, fontWeight: FontWeight.w500),
              ),
              const Spacer(),
              ActionIcon(
                CupertinoIcons.add,
                '添加当天日程',
                () => edit(null, selected),
                color: p.accent,
              ),
            ],
          ),
        ),
        Expanded(
          child: TaskList(
            tasks: dayTasks,
            appearance: appearance,
            edit: (t) => edit(t),
            toggle: toggle,
          ),
        ),
      ],
    );
    if (!showAgenda) {
      return LayoutBuilder(
        builder: (context, c) => c.maxHeight < calendarHeight
            ? SingleChildScrollView(
                child: SizedBox(height: calendarHeight, child: calendar),
              )
            : calendar,
      );
    }
    return wide
        ? Row(
            children: [
              Expanded(flex: 7, child: calendar),
              SizedBox(width: 300, child: agenda),
            ],
          )
        : LayoutBuilder(
            builder: (context, c) => c.maxHeight < calendarHeight + 250
                ? ListView(
                    children: [
                      SizedBox(height: calendarHeight, child: calendar),
                      SizedBox(height: 300, child: agenda),
                    ],
                  )
                : Column(
                    children: [
                      SizedBox(
                        height: (c.maxHeight * .54).clamp(
                          calendarHeight,
                          calendarHeight + 40,
                        ),
                        child: calendar,
                      ),
                      Expanded(child: agenda),
                    ],
                  ),
          );
  }
}

class TaskEditor extends StatefulWidget {
  final Todo? task;
  final String initialTitle;
  final DateTime date;
  final String scope;
  final Appearance appearance;
  final AppStore store;
  final PlatformServices? services;
  const TaskEditor({
    super.key,
    this.task,
    this.initialTitle = '',
    required this.date,
    required this.scope,
    required this.appearance,
    required this.store,
    this.services,
  });
  @override
  State<TaskEditor> createState() => _TaskEditorState();
}

class _TaskEditorState extends State<TaskEditor> {
  late final title = TextEditingController(
    text: widget.task?.title ?? widget.initialTitle,
  );
  late String scope = widget.task?.scope ?? widget.scope,
      level = widget.task?.level ?? widget.appearance.levelSet.levels.first.id;
  late String category = widget.task?.category ?? '';
  late DateTime date = widget.task == null
      ? widget.date
      : DateTime.parse(widget.task!.date);
  late DateTime? reminder = widget.task?.reminder?.toLocal();
  late String timing = widget.task?.startMinute != null ? 'exact' : '';
  late int startMinute = widget.task?.startMinute ?? 9 * 60,
      endMinute = widget.task?.endMinute ?? minuteAfterStart(startMinute);
  Future<void> pickTime(bool start) async {
    final initial = start ? startMinute : endMinute;
    final value = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: (initial ~/ 60) % 24, minute: initial % 60),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (value != null && mounted) {
      setState(() {
        final minute = value.hour * 60 + value.minute;
        if (start) {
          startMinute = minute;
          endMinute = minuteAfterStart(minute);
        } else {
          endMinute = minute == 0 ? 1440 : minute;
        }
      });
    }
  }

  bool busy = false;
  String? error;
  @override
  void dispose() {
    title.dispose();
    super.dispose();
  }

  Future<void> save({bool delete = false}) async {
    if (busy) return;
    if (!delete && title.text.trim().isEmpty) {
      setState(() => error = '请输入日程');
      return;
    }
    if (!delete && timing == 'exact' && endMinute <= startMinute) {
      setState(() => error = '结束时间应晚于开始时间');
      return;
    }
    if (!delete &&
        reminder != null &&
        reminder!.isBefore(DateTime.now()) &&
        reminder != widget.task?.reminder) {
      setState(() => error = '请选择未来时间');
      return;
    }
    setState(() => busy = true);
    try {
      if (!delete && reminder != null) await widget.services?.permission();
      final task =
          widget.task ?? Todo(title: title.text.trim(), date: dayKey(date));
      await widget.store.saveTask(
        task.copy(
          title: title.text.trim(),
          date: dayKey(date),
          scope: scope,
          level: level,
          category: category,
          reminder: reminder,
          startMinute: timing == 'exact' ? startMinute : null,
          endMinute: timing == 'exact' ? endMinute : null,
          clearTime: timing != 'exact',
          timePeriod: '',
          clearReminder: reminder == null,
          deleted: delete,
        ),
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => error = '保存失败，请重试');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      TextField(
        controller: title,
        autofocus: true,
        maxLength: 160,
        minLines: 1,
        maxLines: 3,
        decoration: const InputDecoration(hintText: '日程内容', labelText: '日程内容'),
      ),
      const SizedBox(height: 12),
      CupertinoSlidingSegmentedControl<String>(
        groupValue: scope,
        children: const {
          'day': Text('日计划'),
          'week': Text('周计划'),
          'month': Text('月计划'),
        },
        onValueChanged: (s) {
          if (s != null) setState(() => scope = s);
        },
      ),
      const SizedBox(height: 16),
      Row(
        children: [
          const Text('日期'),
          const Spacer(),
          TextButton(
            onPressed: () async {
              final d = await chooseDate(context, date);
              if (d != null) setState(() => date = d);
            },
            child: Text('${date.year}/${date.month}/${date.day}'),
          ),
        ],
      ),
      const SizedBox(height: 8),
      Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final e in const {'': '不设时间', 'exact': '具体时间'}.entries)
            ChoiceChip(
              label: Text(e.value),
              selected: timing == e.key,
              onSelected: (_) => setState(() => timing = e.key),
            ),
        ],
      ),
      if (timing == 'exact')
        Row(
          children: [
            const Text('开始', style: TextStyle(fontSize: 12)),
            TextButton(
              onPressed: () => pickTime(true),
              child: Text(minuteLabel(startMinute)),
            ),
            const Spacer(),
            const Text('结束', style: TextStyle(fontSize: 12)),
            TextButton(
              onPressed: () => pickTime(false),
              child: Text(minuteLabel(endMinute)),
            ),
          ],
        ),
      CategoryPicker(
        categories: taskCategories(widget.store.document.tasks),
        value: category,
        onChanged: (v) => setState(() => category = v),
      ),
      const SizedBox(height: 4),
      SwitchListTile.adaptive(
        contentPadding: EdgeInsets.zero,
        title: const Text('日程提醒', style: TextStyle(fontSize: 13)),
        value: reminder != null,
        onChanged: (v) => setState(
          () => reminder = v
              ? (date.isAfter(DateTime.now())
                    ? DateTime(date.year, date.month, date.day, 9)
                    : DateTime.now().add(const Duration(hours: 1)))
              : null,
        ),
      ),
      if (reminder != null)
        SizedBox(
          height: 150,
          child: CupertinoDatePicker(
            mode: CupertinoDatePickerMode.dateAndTime,
            initialDateTime: reminder,
            use24hFormat: true,
            onDateTimeChanged: (d) => setState(() => reminder = d),
          ),
        ),
      const SizedBox(height: 12),
      Wrap(
        spacing: 8,
        runSpacing: 6,
        children: widget.appearance.levelSet.levels
            .map(
              (l) => ChoiceChip(
                label: Text(l.name),
                avatar: CircleAvatar(
                  radius: 6,
                  backgroundColor: l.color.withValues(alpha: 1),
                ),
                selected: level == l.id,
                onSelected: (_) => setState(() => level = l.id),
              ),
            )
            .toList(),
      ),
      if (error != null)
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Text(
            error!,
            style: const TextStyle(color: Colors.redAccent, fontSize: 12),
          ),
        ),
      const SizedBox(height: 20),
      Row(
        children: [
          if (widget.task != null)
            TextButton(
              onPressed: busy ? null : () => save(delete: true),
              child: const Text(
                '删除',
                style: TextStyle(color: Colors.redAccent),
              ),
            ),
          const Spacer(),
          TextButton(
            onPressed: busy ? null : () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(onPressed: busy ? null : save, child: const Text('保存')),
        ],
      ),
    ],
  );
}
