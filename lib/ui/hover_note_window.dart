import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:window_manager/window_manager.dart';

import '../model.dart';
import 'components.dart';
import 'floating_note.dart';

Future<void> runHoverNoteWindow(Uri peer, String token) async {
  await windowManager.ensureInitialized();
  await windowManager.waitUntilReadyToShow(
    const WindowOptions(
      size: Size(304, 320),
      minimumSize: Size(240, 100),
      backgroundColor: Colors.transparent,
      skipTaskbar: true,
      titleBarStyle: TitleBarStyle.hidden,
    ),
  );
  await windowManager.setOpacity(0);
  await windowManager.setAsFrameless();
  await windowManager.setHasShadow(false);
  await windowManager.setResizable(false);
  await windowManager.setAlwaysOnTop(true);
  runApp(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: appTheme(),
      home: HoverNoteWindow(peer: peer, token: token),
    ),
  );
}

class HoverNoteWindow extends StatefulWidget {
  final Uri peer;
  final String token;
  const HoverNoteWindow({super.key, required this.peer, required this.token});
  @override
  State<HoverNoteWindow> createState() => _HoverNoteWindowState();
}

class _HoverNoteWindowState extends State<HoverNoteWindow> {
  final client = http.Client();
  Timer? timer;
  bool fetching = false, visible = false;
  int revision = -1, generation = -1, failures = 0;
  String day = '';
  List<Todo> tasks = [];
  Color accent = const Color(0xff537da5);
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(poll());
      timer = Timer.periodic(
        const Duration(milliseconds: 150),
        (_) => unawaited(poll()),
      );
    });
  }

  Future<void> poll() async {
    if (fetching || !mounted) return;
    fetching = true;
    try {
      final response = await client
          .get(widget.peer, headers: {'authorization': widget.token})
          .timeout(const Duration(seconds: 2));
      if (response.statusCode != 200) {
        throw const FormatException('Parent unavailable');
      }
      final state = object(jsonDecode(response.body));
      failures = 0;
      final show = state['visible'] == true;
      if (!show) {
        await windowManager.hide();
        visible = false;
        revision = state['revision'];
        return;
      }
      final changed =
          state['revision'] != revision ||
          state['generation'] != generation ||
          state['day'] != day;
      if (changed) {
        tasks =
            (state['tasks'] as List? ?? [])
                .map((t) => Todo.fromJson(object(t)))
                .toList()
              ..sort(compareTaskTime);
        accent = readColor(state['accent'], accent);
        if (mounted) setState(() {});
      }
      if (!visible || state['revision'] != revision) {
        final b = object(state['bounds']);
        await windowManager.setBounds(
          Rect.fromLTWH(
            (b['x'] as num).toDouble(),
            (b['y'] as num).toDouble(),
            (b['w'] as num).toDouble(),
            (b['h'] as num).toDouble(),
          ),
        );
        // Wait until the panel is laid out before presenting its separate surface.
        await WidgetsBinding.instance.endOfFrame;
        if (!mounted) return;
        await windowManager.setOpacity(1);
        await windowManager.show(inactive: true);
        visible = true;
      }
      revision = state['revision'];
      generation = state['generation'];
      day = state['day'] ?? '';
    } catch (_) {
      if (++failures >= 3) {
        timer?.cancel();
        await windowManager.destroy();
      }
    } finally {
      fetching = false;
    }
  }

  @override
  void dispose() {
    timer?.cancel();
    client.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: Padding(
      padding: const EdgeInsets.all(8),
      child: TodoNotePanel(tasks: tasks, accent: accent),
    ),
  );
}
