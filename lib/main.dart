import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'app.dart';
import 'model.dart';
import 'storage.dart';
import 'store.dart';
import 'platform_services.dart';
import 'ui/components.dart';
import 'ui/reminder_popup.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  final executableDirectory = File(Platform.resolvedExecutable).parent;
  final portable =
      Platform.isWindows &&
      await File('${executableDirectory.path}/portable.flag').exists();
  final isolatedDirectory =
      Platform.environment['NEEDTODO_DATA_DIR'] ??
      (portable ? '${executableDirectory.path}/user-data' : null);
  final directory = isolatedDirectory == null
      ? await getApplicationSupportDirectory()
      : Directory(isolatedDirectory);
  final storage = JsonStorage(directory);
  Future<void> log(Object e, StackTrace? stack) async {
    try {
      await directory.create(recursive: true);
      final file = File('${directory.path}/errors.log');
      if (await file.exists() && await file.length() > 1000000) {
        await file.writeAsString('');
      }
      await file.writeAsString(
        '${DateTime.now().toIso8601String()} ${e.runtimeType}: $e\n${stack ?? ''}\n',
        mode: FileMode.append,
      );
    } catch (_) {}
  }

  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    unawaited(log(details.exception, details.stack));
  };
  PlatformDispatcher.instance.onError = (e, stack) {
    unawaited(log(e, stack));
    return true;
  };
  if (Platform.isWindows &&
      args.length == 3 &&
      args[0] == '--calendar' &&
      args[1] == '--reminder') {
    try {
      await runDesktopReminder(directory, args[2]);
    } catch (e, stack) {
      await log(e, stack);
      exit(1);
    }
    return;
  }
  final secondary = args.length >= 3 && args[0] == '--calendar';
  final startup = Platform.isWindows && !secondary
      ? StartupSelection.launch(args)
      : null;
  final calendarOnly = startup?.calendar == true && startup?.list == false;
  final store = AppStore(
    storage,
    peer: secondary
        ? Uri.parse('http://127.0.0.1:${int.parse(args[1])}')
        : null,
    peerToken: secondary ? args[2] : '',
  );
  DesktopController? desktop;
  PlatformServices? services;
  try {
    if (Platform.isWindows) {
      desktop = DesktopController(storage, calendar: secondary);
      await desktop.initialize(showWindow: !calendarOnly);
      desktop.onError = store.setError;
      desktop.onClose = () async {
        await store.shutdown();
        closeDesktopReminders();
        services?.dispose();
        await desktop!.close();
      };
      if (!secondary) {
        desktop.onOpenCalendar = () async {
          if (store.entered) {
            await store.openCalendar();
          } else {
            await desktop!.expand();
          }
        };
        try {
          await desktop.initializeTray();
        } catch (e, stack) {
          unawaited(log(e, stack));
        }
      }
    }
    if (!secondary) {
      services = PlatformServices(dataDirectory: directory);
      try {
        await services.initialize();
      } catch (e, stack) {
        unawaited(log(e, stack));
        store.error = '提醒暂不可用，请检查系统通知权限';
      }
    }
    store.onDocumentChanged = () {
      services?.publish(store.entered ? store.document : Document()).catchError(
        (Object e) {
          unawaited(log(e, null));
          store.setError('系统通知更新失败；程序运行时仍会弹出提醒');
        },
      );
    };
    services?.onError = (e) {
      unawaited(log(e, null));
      store.setError('提醒显示失败，请检查后重试');
    };
    store.onReminderTest = services?.testReminder;
    // Read-only migration of the old desktop format into the new local workspace.
    if (isolatedDirectory == null &&
        !secondary &&
        Platform.isWindows &&
        await storage.read('local') == null) {
      final roaming = Platform.environment['APPDATA'];
      if (roaming != null) {
        final old = File('$roaming/liubai-todo/liubai.json');
        if (await old.exists()) {
          try {
            final doc = Document.fromJson(
              object(jsonDecode(await old.readAsString())),
            );
            await storage.write('local', {
              'document': doc.toJson(),
              'revision': 0,
            });
          } catch (e, stack) {
            unawaited(log(e, stack));
          }
        }
      }
    }
    await store.load();
    if (calendarOnly && !store.entered) await desktop?.expand();
    runApp(NeedTodoApp(store: store, desktop: desktop, services: services));
    if (startup?.calendar == true) {
      bool opened = false;
      void openStartupCalendar() {
        if (opened || !store.entered) return;
        opened = true;
        store.removeListener(openStartupCalendar);
        store
            .openCalendar()
            .then((_) async {
              if (calendarOnly) await desktop?.hideCalendar();
            })
            .catchError((Object e) async {
              await log(e, null);
              store.setError('桌面月历启动失败，请重试');
              await desktop?.expand();
            });
      }

      store.addListener(openStartupCalendar);
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => openStartupCalendar(),
      );
    }
  } catch (e, stack) {
    await log(e, stack);
    if (calendarOnly) {
      try {
        await desktop?.expand();
      } catch (_) {}
    }
    runApp(
      MaterialApp(
        theme: appTheme(),
        home: Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Identity(size: 48),
                  const SizedBox(height: 20),
                  const Text('暂时无法打开'),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: () async {
                      try {
                        await store.load();
                        runApp(
                          NeedTodoApp(
                            store: store,
                            desktop: desktop,
                            services: services,
                          ),
                        );
                      } catch (_) {}
                    },
                    child: const Text('重试'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
