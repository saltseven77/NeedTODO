import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ffi' hide Size;
import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:window_manager/window_manager.dart';

import '../model.dart';
import 'components.dart';

const reminderLifetime = Duration(seconds: 20);
double reminderHeight(int count) => 96 + (count - 1).clamp(0, 2) * 34.0;
const _reminderReady = 'NEEDTODO_REMINDER_READY';

void preventReminderActivation(int handle) {
  final user32 = DynamicLibrary.open('user32.dll');
  final getStyle = user32
      .lookupFunction<IntPtr Function(IntPtr, Int32), int Function(int, int)>(
        'GetWindowLongPtrW',
      );
  final setStyle = user32
      .lookupFunction<
        IntPtr Function(IntPtr, Int32, IntPtr),
        int Function(int, int, int)
      >('SetWindowLongPtrW');
  // A corner reminder must not take keyboard focus from the user's current app.
  const extendedStyle = -20, noActivate = 0x08000000;
  setStyle(handle, extendedStyle, getStyle(handle, extendedStyle) | noActivate);
}

/// Uses the existing secondary-process entry in the Windows native host, so a
/// reminder can own its window without changing the main window's visibility.
Future<void> showDesktopReminder(
  Directory data,
  List<Todo> tasks,
  ReminderStyle style,
) async {
  final folder = Directory('${data.path}/reminder-popups');
  await folder.create(recursive: true);
  final file = File('${folder.path}/reminder-${newId()}.json');
  await file.writeAsString(
    jsonEncode({
      'titles': tasks.map((t) => t.title).toList(),
      'style': style.toJson(),
    }),
    flush: true,
  );
  try {
    final process = await Process.start(Platform.resolvedExecutable, [
      '--calendar',
      '--reminder',
      file.absolute.path,
    ], workingDirectory: File(Platform.resolvedExecutable).parent.path);
    await process.stdin.close();
    final ready = process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .fold<bool>(
          false,
          (shown, line) => shown || line.trim() == _reminderReady,
        );
    final diagnostic = process.stderr
        .transform(utf8.decoder)
        .fold<String>(
          '',
          (text, part) => text.length >= 4096
              ? text
              : (text + part).substring(
                  0,
                  math.min(4096, text.length + part.length),
                ),
        );
    final code = await process.exitCode,
        shown = await ready,
        error = await diagnostic;
    if (code != 0 && !shown) {
      throw StateError('提醒窗口未能打开（退出码 $code）${error.isEmpty ? '' : '：$error'}');
    }
    if (code != 0) {
      try {
        await File('${data.path}/errors.log').writeAsString(
          '${DateTime.now().toIso8601String()} Reminder exited after displaying: $code\n$error\n',
          mode: FileMode.append,
        );
      } catch (_) {}
    }
  } finally {
    if (await file.exists()) await file.delete();
  }
}

Future<void> runDesktopReminder(Directory data, String payload) async {
  final allowed = Directory('${data.path}/reminder-popups');
  final file = File(payload);
  if (!RegExp(r'^reminder-[a-z0-9]+\.json$')
      .hasMatch(file.uri.pathSegments.last)) {
    throw const FormatException('无效提醒文件名');
  }
  if ((await file.parent.resolveSymbolicLinks()).toLowerCase() !=
      (await allowed.resolveSymbolicLinks()).toLowerCase()) {
    throw const FormatException('无效提醒文件');
  }
  if (await file.length() > 4000000) throw const FormatException('提醒图片过大');
  final json = object(jsonDecode(await file.readAsString()));
  final titles = (json['titles'] as List? ?? [])
      .whereType<String>()
      .take(60)
      .toList();
  final style = ReminderStyle.fromJson(object(json['style']));
  await file.delete();
  await windowManager.ensureInitialized();
  final display = await screenRetriever.getPrimaryDisplay();
  final origin = display.visiblePosition ?? Offset.zero,
      area = display.visibleSize ?? display.size;
  final width = math.min(360.0, area.width - 32),
      height = math.min(reminderHeight(titles.length), area.height - 32);
  await windowManager.waitUntilReadyToShow(
    WindowOptions(
      size: Size(width, height),
      backgroundColor: Colors.transparent,
      skipTaskbar: true,
      alwaysOnTop: true,
      title: '日程提醒',
      titleBarStyle: TitleBarStyle.hidden,
    ),
  );
  await windowManager.setAsFrameless();
  preventReminderActivation(await windowManager.getId());
  await windowManager.setResizable(false);
  await windowManager.setHasShadow(false);
  await windowManager.setSkipTaskbar(true);
  await windowManager.setAlwaysOnTop(true);
  await windowManager.setBounds(
    Rect.fromLTWH(
      origin.dx + area.width - width - 16,
      origin.dy + area.height - height - 16,
      width,
      height,
    ),
  );
  runApp(_DesktopReminder(titles: titles, style: style));
}

class _DesktopReminder extends StatefulWidget {
  final List<String> titles;
  final ReminderStyle style;
  const _DesktopReminder({required this.titles, required this.style});
  @override
  State<_DesktopReminder> createState() => _DesktopReminderState();
}

class _DesktopReminderState extends State<_DesktopReminder> {
  Timer? timer;
  bool closing = false;
  void close() {
    if (closing) return;
    closing = true;
    timer?.cancel();
    if (mounted) setState(() {});
    unawaited(() async {
      try {
        await windowManager.hide().timeout(const Duration(milliseconds: 150));
      } catch (_) {}
      // Exit the popup process after hiding; destroying the engine inside a
      // method-channel reply can block shutdown and report a failed delivery.
      exit(0);
    }());
  }

  @override
  void initState() {
    super.initState();
    timer = Timer(reminderLifetime, close);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(
        windowManager
            .show(inactive: true)
            .then((_) => stdout.writeln(_reminderReady)),
      );
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: appTheme(),
    home: Material(
      color: Colors.transparent,
      child: closing
          ? const SizedBox.shrink()
          : ReminderToast(
              titles: widget.titles,
              style: widget.style,
              onClose: close,
            ),
    ),
  );
}

Future<void> showTopReminder(
  BuildContext context,
  List<Todo> tasks,
  ReminderStyle style,
) async {
  final done = Completer<void>();
  late OverlayEntry entry;
  Timer? timer;
  void close() {
    if (done.isCompleted) return;
    timer?.cancel();
    entry.remove();
    entry.dispose();
    done.complete();
  }

  entry = OverlayEntry(
    builder: (context) => Positioned(
      top: MediaQuery.paddingOf(context).top + 12,
      left: 16,
      right: 16,
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: SizedBox(
            height: reminderHeight(tasks.length),
            child: ReminderToast(
              titles: tasks.map((t) => t.title).toList(),
              style: style,
              onClose: close,
            ),
          ),
        ),
      ),
    ),
  );
  Overlay.of(context, rootOverlay: true).insert(entry);
  timer = Timer(reminderLifetime, close);
  await done.future;
}

class ReminderToast extends StatelessWidget {
  final List<String> titles;
  final ReminderStyle style;
  final VoidCallback onClose;
  const ReminderToast({
    super.key,
    required this.titles,
    required this.style,
    required this.onClose,
  });
  @override
  Widget build(BuildContext context) {
    final background = imageBytes(style.background);
    return Material(
      color: Colors.white,
      elevation: 0,
      shadowColor: const Color(0x22000000),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xffe1e4e8), width: .6),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (background != null)
            Image.memory(background, fit: BoxFit.cover, gaplessPlayback: true),
          if (background != null) const ColoredBox(color: Color(0xd9ffffff)),
          Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Identity(data: style.avatar, size: 28),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '日程提醒',
                            style: TextStyle(fontSize: 11, color: muted),
                          ),
                          if (style.message.isNotEmpty) ...[
                            const SizedBox(height: 3),
                            Text(
                              style.message,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: ink,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    SizedBox(
                      width: 24,
                      height: 24,
                      child: IconButton(
                        padding: EdgeInsets.zero,
                        tooltip: '关闭提醒',
                        onPressed: onClose,
                        icon: const Icon(
                          CupertinoIcons.xmark,
                          size: 14,
                          color: muted,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: ListView.separated(
                    padding: EdgeInsets.zero,
                    itemCount: titles.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 6),
                    itemBuilder: (context, index) => Text(
                      titles[index],
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        color: ink,
                        height: 1.4,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
