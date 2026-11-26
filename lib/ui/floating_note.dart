import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../model.dart';
import '../platform_services.dart';
import 'components.dart';

class FloatingNote extends StatefulWidget {
  final DesktopController desktop;
  final Appearance appearance;
  final List<Todo> tasks;
  final VoidCallback open, menu;
  const FloatingNote({
    super.key,
    required this.desktop,
    required this.appearance,
    required this.tasks,
    required this.open,
    required this.menu,
  });
  @override
  State<FloatingNote> createState() => _FloatingNoteState();
}

class _FloatingNoteState extends State<FloatingNote> {
  Timer? hover, cursorWatch, outsideClose;
  bool checkingCursor = false;
  void show(bool visible) {
    hover?.cancel();
    final d = widget.desktop;
    if (visible && d.noteVisible) return;
    hover = Timer(Duration(milliseconds: visible ? 350 : 250), () async {
      if (!mounted || d.busy) return;
      try {
        final inside = await d.pointerOverBallNote();
        if (!mounted) return;
        if (visible && inside == false) return;
        if (!visible && inside == true) return;
        await d.showBallNote(visible);
      } catch (e) {
        d.onError?.call(e);
      }
    });
  }

  void watchCursor() {
    final d = widget.desktop;
    if (!d.noteVisible) {
      cursorWatch?.cancel();
      cursorWatch = null;
      outsideClose?.cancel();
      outsideClose = null;
      return;
    }
    cursorWatch ??= Timer.periodic(const Duration(milliseconds: 150), (
      _,
    ) async {
      if (checkingCursor || !mounted || d.busy) return;
      checkingCursor = true;
      try {
        final inside = await d.pointerOverBallNote();
        if (!mounted || !d.noteVisible) return;
        if (inside == false) {
          outsideClose ??= Timer(const Duration(milliseconds: 250), () async {
            outsideClose = null;
            try {
              if (mounted &&
                  !d.busy &&
                  d.noteVisible &&
                  await d.pointerOverBallNote() == false) {
                await d.showBallNote(false);
              }
            } catch (e) {
              d.onError?.call(e);
            }
          });
        } else {
          outsideClose?.cancel();
          outsideClose = null;
        }
      } catch (e) {
        d.onError?.call(e);
      } finally {
        checkingCursor = false;
      }
    });
  }

  @override
  void dispose() {
    hover?.cancel();
    cursorWatch?.cancel();
    outsideClose?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.desktop, p = widget.appearance.palette;
    final tasks = [...widget.tasks]..sort(compareTaskTime);
    watchCursor();
    return MouseRegion(
      onEnter: (_) => show(true),
      onExit: (_) => show(false),
      child: Material(
        color: Colors.transparent,
        child: Stack(
          children: [
            Positioned(
              left: d.noteBallOffset.dx,
              top: d.noteBallOffset.dy,
              width: 68,
              height: 68,
              child: GestureDetector(
                onPanStart: (_) {
                  hover?.cancel();
                  d.guard(() async {
                    await d.showBallNote(false);
                    await windowManager.startDragging();
                  });
                },
                onTap: widget.open,
                onSecondaryTap: widget.menu,
                onLongPress: widget.menu,
                child: Center(
                  child: Identity(
                    data: widget.appearance.floatingImage,
                    size: 60,
                  ),
                ),
              ),
            ),
            if (d.noteVisible && !d.externalNote)
              Positioned(
                left: d.notePanelRect.left,
                top: d.notePanelRect.top,
                width: d.notePanelRect.width,
                height: d.notePanelRect.height,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  decoration: BoxDecoration(
                    color: const Color(0xfffdfdfd),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xffe5e5e7)),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x14000000),
                        blurRadius: 10,
                        offset: Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        '今日计划',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: const Color(0xff292c32),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Expanded(
                        child: tasks.isEmpty
                            ? const Center(
                                child: Text(
                                  '今天暂无计划',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Color(0xff8b8e94),
                                  ),
                                ),
                              )
                            : ListView.builder(
                                itemCount: tasks.length,
                                itemBuilder: (context, i) {
                                  final t = tasks[i];
                                  return Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 8,
                                    ),
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Padding(
                                          padding: const EdgeInsets.only(
                                            top: 2,
                                          ),
                                          child: Icon(
                                            t.done
                                                ? CupertinoIcons
                                                      .check_mark_circled
                                                : CupertinoIcons.circle,
                                            size: 13,
                                            color: t.done
                                                ? const Color(0xffa0a3a8)
                                                : p.accent,
                                          ),
                                        ),
                                        const SizedBox(width: 9),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                t.title,
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  height: 1.4,
                                                  color: t.done
                                                      ? const Color(0xff9a9da2)
                                                      : const Color(0xff292c32),
                                                  decoration: t.done
                                                      ? TextDecoration
                                                            .lineThrough
                                                      : null,
                                                ),
                                              ),
                                              if (taskTimeLabel(t).isNotEmpty)
                                                Text(
                                                  taskTimeLabel(t),
                                                  style: const TextStyle(
                                                    fontSize: 10,
                                                    height: 1.7,
                                                    color: Color(0xff92959b),
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class TodoNotePanel extends StatelessWidget {
  final List<Todo> tasks;
  final Color accent;
  const TodoNotePanel({super.key, required this.tasks, required this.accent});
  @override
  Widget build(BuildContext context) {
    final p = Appearance().palette..accent = accent;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      decoration: BoxDecoration(
        color: const Color(0xfffdfdfd),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xffe5e5e7)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 10,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '今日计划',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: const Color(0xff292c32),
            ),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: tasks.isEmpty
                ? const Center(
                    child: Text(
                      '今天暂无计划',
                      style: TextStyle(fontSize: 12, color: Color(0xff8b8e94)),
                    ),
                  )
                : ListView.builder(
                    itemCount: tasks.length,
                    itemBuilder: (context, i) {
                      final t = tasks[i];
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Icon(
                                t.done
                                    ? CupertinoIcons.check_mark_circled
                                    : CupertinoIcons.circle,
                                size: 13,
                                color: t.done
                                    ? const Color(0xffa0a3a8)
                                    : p.accent,
                              ),
                            ),
                            const SizedBox(width: 9),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    t.title,
                                    style: TextStyle(
                                      fontSize: 12,
                                      height: 1.4,
                                      color: t.done
                                          ? const Color(0xff9a9da2)
                                          : const Color(0xff292c32),
                                      decoration: t.done
                                          ? TextDecoration.lineThrough
                                          : null,
                                    ),
                                  ),
                                  if (taskTimeLabel(t).isNotEmpty)
                                    Text(
                                      taskTimeLabel(t),
                                      style: const TextStyle(
                                        fontSize: 10,
                                        height: 1.7,
                                        color: Color(0xff92959b),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
