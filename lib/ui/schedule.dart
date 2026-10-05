import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../model.dart';
import 'components.dart';

class TaskProgress extends StatelessWidget {
  final List<Todo> tasks;
  final Color color;
  final bool showCounts;
  const TaskProgress({
    super.key,
    required this.tasks,
    required this.color,
    this.showCounts = true,
  });
  @override
  Widget build(BuildContext context) {
    final done = tasks.where((t) => t.done).length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 8),
      child: Row(
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: tasks.isEmpty ? 0 : done / tasks.length,
                minHeight: 3,
                color: color,
                backgroundColor: color.withValues(alpha: .12),
              ),
            ),
          ),
          if (showCounts) const SizedBox(width: 12),
          if (showCounts)
            Text(
              '$done / ${tasks.length}',
              style: TextStyle(fontSize: 11, color: color),
            ),
        ],
      ),
    );
  }
}

class DayTimeline extends StatefulWidget {
  final List<Todo> tasks;
  final Appearance appearance;
  final DateTime? selectedDate, currentTime;
  final ValueChanged<Todo> edit, toggle;
  const DayTimeline({
    super.key,
    required this.tasks,
    required this.appearance,
    this.selectedDate,
    this.currentTime,
    required this.edit,
    required this.toggle,
  });
  @override
  State<DayTimeline> createState() => _DayTimelineState();
}

class _DayTimelineState extends State<DayTimeline> {
  final scroll = ScrollController();
  final hourAnchor = GlobalKey();
  List<Todo> get tasks => widget.tasks;
  Appearance get appearance => widget.appearance;
  ValueChanged<Todo> get edit => widget.edit;
  ValueChanged<Todo> get toggle => widget.toggle;
  int get targetHour => (widget.currentTime ?? DateTime.now()).hour;

  void locateTime() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final context = hourAnchor.currentContext;
      if (mounted && context != null) {
        unawaited(Scrollable.ensureVisible(context, alignment: .15));
      }
    });
  }

  @override
  void initState() {
    super.initState();
    locateTime();
  }

  @override
  void didUpdateWidget(DayTimeline old) {
    super.didUpdateWidget(old);
    if (old.selectedDate != widget.selectedDate ||
        old.currentTime != widget.currentTime) {
      locateTime();
    }
  }

  @override
  void dispose() {
    scroll.dispose();
    super.dispose();
  }

  Widget card(Todo t) => Row(
    children: [
      SizedBox(
        width: 30,
        child: IconButton(
          padding: EdgeInsets.zero,
          tooltip: t.done ? '取消完成' : '完成',
          onPressed: () => toggle(t),
          icon: Icon(
            t.done
                ? CupertinoIcons.check_mark_circled_solid
                : CupertinoIcons.circle,
            size: 16,
            color: appearance.palette.accent,
          ),
        ),
      ),
      Expanded(
        child: InkWell(
          onTap: () => edit(t),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Text(
              '${taskTimeLabel(t)} ${t.title}'.trim(),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                color: appearance.taskTextColor(t.level),
                decoration: t.done ? TextDecoration.lineThrough : null,
              ),
            ),
          ),
        ),
      ),
    ],
  );
  @override
  Widget build(BuildContext context) {
    final events =
        tasks.where((t) => t.startMinute != null).map(_Event.new).toList()
          ..sort((a, b) => compareTaskTime(a.task, b.task));
    // Distribute overlapping appointments into columns within each overlap group.
    final group = <_Event>[];
    final ends = <double>[];
    double groupEnd = -1;
    void finishGroup() {
      for (final e in group) {
        e.columns = ends.length;
      }
      group.clear();
      ends.clear();
    }

    for (final e in events) {
      if (e.start >= groupEnd) {
        finishGroup();
        groupEnd = -1;
      }
      var lane = ends.indexWhere((end) => end <= e.start);
      if (lane < 0) {
        lane = ends.length;
        ends.add(e.layoutEnd);
      } else {
        ends[lane] = e.layoutEnd;
      }
      e.lane = lane;
      group.add(e);
      groupEnd = math.max(groupEnd, e.layoutEnd);
    }
    finishGroup();
    return SingleChildScrollView(
      controller: scroll,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (tasks.any((task) => task.startMinute == null)) ...[
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 6),
              child: Text(
                '未安排时间',
                style: TextStyle(fontSize: 11, color: muted),
              ),
            ),
            for (final task in tasks.where((task) => task.startMinute == null))
              Container(
                margin: const EdgeInsets.only(bottom: 4),
                decoration: BoxDecoration(
                  border: Border(
                    left: BorderSide(
                      width: 3,
                      color: appearance
                          .taskColor(task.level)
                          .withValues(alpha: 1),
                    ),
                  ),
                ),
                child: card(task),
              ),
          ],
          const SizedBox(height: 8),
          LayoutBuilder(
            builder: (context, c) => SizedBox(
              height: events.fold<double>(
                24 * 52 + 32,
                (height, e) => math.max(height, e.layoutEnd / 60 * 52 + 12),
              ),
              child: Stack(
                children: [
                  for (var h = 0; h <= 24; h++)
                    Positioned(
                      top: h * 52,
                      left: 0,
                      right: 0,
                      child: Row(
                        key: h == targetHour ? hourAnchor : null,
                        children: [
                          SizedBox(
                            width: 42,
                            child: Text(
                              '${h.toString().padLeft(2, '0')}:00',
                              style: TextStyle(
                                fontSize: 10,
                                color: h == targetHour
                                    ? appearance.palette.accent
                                    : muted,
                              ),
                            ),
                          ),
                          Expanded(
                            child: Divider(
                              height: 1,
                              thickness: .5,
                              color: appearance.palette.line,
                            ),
                          ),
                        ],
                      ),
                    ),
                  for (final e in events)
                    Positioned(
                      top: e.start / 60 * 52 + 6,
                      left: 46 + (c.maxWidth - 46) * e.lane / e.columns,
                      width: (c.maxWidth - 46) / e.columns - 3,
                      height: (e.layoutEnd - e.start) / 60 * 52,
                      child: Tooltip(
                        message: '${taskTimeLabel(e.task)} ${e.task.title}',
                        child: Stack(
                          children: [
                            Positioned(
                              left: 0,
                              top: 0,
                              height: math.max(
                                2.0,
                                (e.end - e.start) / 60 * 52,
                              ),
                              width: 4,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: appearance
                                      .taskColor(e.task.level)
                                      .withValues(alpha: e.task.done ? .4 : 1),
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                            ),
                            Positioned(
                              top: 0,
                              left: 10,
                              right: 1,
                              child: InkWell(
                                onTap: () => edit(e.task),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 2,
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        e.task.title,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w500,
                                          color: appearance.palette.text,
                                          decoration: e.task.done
                                              ? TextDecoration.lineThrough
                                              : null,
                                        ),
                                      ),
                                      Text(
                                        taskTimeLabel(e.task),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: appearance.palette.text
                                              .withValues(alpha: .6),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Event {
  final Todo task;
  int lane = 0, columns = 1;
  _Event(this.task);
  double get start => task.startMinute!.toDouble();
  double get end =>
      math.max(start + 1, (task.endMinute ?? task.startMinute! + 1).toDouble());
  double get layoutEnd => math.max(start + 40, end);
}
