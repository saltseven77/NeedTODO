import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../course.dart';
import '../model.dart';
import '../store.dart';
import 'components.dart';

class Timetable extends StatefulWidget {
  final AppStore store;
  const Timetable({super.key, required this.store});
  @override
  State<Timetable> createState() => _TimetableState();
}

class _TimetableState extends State<Timetable> {
  DateTime selected = dayOnly(DateTime.now());
  AppStore get store => widget.store;
  Future<void> edit([Course? course]) => showPanel<void>(
    context,
    course == null ? '添加课程' : '编辑课程',
    CourseEditor(store: store, initial: course, date: selected),
    width: 460,
  );
  @override
  Widget build(BuildContext context) {
    final p = store.document.list.palette;
    final monday = selected.subtract(Duration(days: selected.weekday - 1));
    final courses = store.document.courses.where((c) => !c.deleted).toList();
    final dates = List.generate(7, (i) => monday.add(Duration(days: i)));
    final current =
        periodKey('week', selected) == periodKey('week', DateTime.now());
    List<Course> on(DateTime date) =>
        courses.where((c) => c.occursOn(date)).toList()
          ..sort((a, b) => a.start.compareTo(b.start));
    Widget card(Course c, {bool compact = false}) => Material(
      color: store.document.list.taskColor(c.level),
      borderRadius: BorderRadius.circular(7),
      child: InkWell(
        borderRadius: BorderRadius.circular(7),
        onTap: () => edit(c),
        child: Padding(
          padding: EdgeInsets.all(compact ? 8 : 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                c.name,
                maxLines: compact ? 2 : 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: compact ? 12 : 14,
                  fontWeight: FontWeight.w500,
                  color: store.document.list.taskTextColor(c.level),
                ),
              ),
              const SizedBox(height: 5),
              Text(
                '${minuteLabel(c.start)}–${minuteLabel(c.end)}',
                style: TextStyle(
                  fontSize: 11,
                  color: store.document.list.taskTextColor(c.level),
                ),
              ),
              if (c.room.isNotEmpty)
                Text(
                  c.room,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    color: store.document.list.taskTextColor(c.level),
                  ),
                ),
              if (!compact && c.teacher.isNotEmpty)
                Text(
                  c.teacher,
                  style: TextStyle(
                    fontSize: 11,
                    color: p.text.withValues(alpha: .6),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    return LayoutBuilder(
      builder: (context, box) {
        final wide = box.maxWidth >= 760;
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${monday.month}月${monday.day}日 — ${dates.last.month}月${dates.last.day}日',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: p.text,
                      ),
                    ),
                  ),
                  if (!current)
                    TextButton(
                      onPressed: () =>
                          setState(() => selected = dayOnly(DateTime.now())),
                      child: const Text('本周'),
                    ),
                  ActionIcon(
                    CupertinoIcons.chevron_left,
                    '上一周',
                    () => setState(
                      () =>
                          selected = selected.subtract(const Duration(days: 7)),
                    ),
                    compact: true,
                    color: p.text,
                  ),
                  ActionIcon(
                    CupertinoIcons.chevron_right,
                    '下一周',
                    () => setState(
                      () => selected = selected.add(const Duration(days: 7)),
                    ),
                    compact: true,
                    color: p.text,
                  ),
                  ActionIcon(
                    CupertinoIcons.add,
                    '添加课程',
                    () => edit(),
                    compact: true,
                    color: p.accent,
                  ),
                ],
              ),
            ),
            Padding(
              padding: EdgeInsets.only(left: wide ? 42 : 12, right: 12),
              child: Row(
                children: [
                  for (final date in dates)
                    Expanded(
                      child: TextButton(
                        onPressed: () => setState(() => selected = date),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          backgroundColor: dayKey(date) == dayKey(selected)
                              ? p.accent.withValues(alpha: .12)
                              : null,
                        ),
                        child: Column(
                          children: [
                            Text(
                              ['一', '二', '三', '四', '五', '六', '日'][date.weekday -
                                  1],
                              style: TextStyle(
                                fontSize: 11,
                                color: p.text.withValues(alpha: .6),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${date.day}',
                              style: TextStyle(
                                fontSize: 14,
                                color: dayKey(date) == dayKey(DateTime.now())
                                    ? p.accent
                                    : p.text,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: courses.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '还没有课程',
                            style: TextStyle(
                              color: p.text.withValues(alpha: .5),
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextButton(
                            onPressed: () => edit(),
                            child: const Text('添加第一门课程'),
                          ),
                        ],
                      ),
                    )
                  : wide
                  ? _week(dates, on, card)
                  : ListView(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 8,
                      ),
                      children: [
                        if (on(selected).isEmpty)
                          Padding(
                            padding: const EdgeInsets.all(32),
                            child: Center(
                              child: Text(
                                '当天没有课程',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: p.text.withValues(alpha: .5),
                                ),
                              ),
                            ),
                          ),
                        for (final c in on(selected))
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: card(c),
                          ),
                      ],
                    ),
            ),
          ],
        );
      },
    );
  }

  Widget _week(
    List<DateTime> dates,
    List<Course> Function(DateTime) on,
    Widget Function(Course, {bool compact}) card,
  ) {
    final entries = [for (final d in dates) ...on(d)];
    final first = entries.fold<int>(8, (h, c) => math.min(h, c.start ~/ 60));
    final last = entries.fold<int>(
      20,
      (h, c) => math.max(h, (c.end / 60).ceil()),
    );
    final p = store.document.list.palette;
    return SingleChildScrollView(
      padding: const EdgeInsets.only(right: 12, bottom: 16),
      child: SizedBox(
        height: (last - first) * 72.0 + 32,
        child: LayoutBuilder(
          builder: (context, box) => Stack(
            children: [
              for (var h = first; h <= last; h++)
                Positioned(
                  top: (h - first) * 72.0,
                  left: 4,
                  right: 0,
                  child: Row(
                    children: [
                      SizedBox(
                        width: 38,
                        child: Text(
                          '${h.toString().padLeft(2, '0')}:00',
                          style: TextStyle(
                            fontSize: 10,
                            color: p.text.withValues(alpha: .4),
                          ),
                        ),
                      ),
                      Expanded(
                        child: Divider(height: 1, color: p.line, thickness: .5),
                      ),
                    ],
                  ),
                ),
              for (var day = 0; day < 7; day++)
                ..._positionCourses(
                  on(dates[day]),
                  day,
                  first,
                  box.maxWidth,
                  card,
                ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _positionCourses(
    List<Course> courses,
    int day,
    int first,
    double width,
    Widget Function(Course, {bool compact}) card,
  ) {
    // Conflicting courses remain separately selectable rather than covering each other.
    final lanes = <int>[];
    final ends = <int>[];
    for (final c in courses) {
      var lane = ends.indexWhere((end) => end <= c.start);
      if (lane < 0) {
        lane = ends.length;
        ends.add(c.end);
      } else {
        ends[lane] = c.end;
      }
      lanes.add(lane);
    }
    final columns = math.max(1, ends.length);
    final dayWidth = (width - 42) / 7;
    return [
      for (var i = 0; i < courses.length; i++)
        Positioned(
          top: (courses[i].start / 60 - first) * 72 + 2,
          left: 42 + day * dayWidth + lanes[i] * dayWidth / columns,
          width: dayWidth / columns - 4,
          height: math.max(
            46,
            (courses[i].end - courses[i].start) / 60 * 72 - 4,
          ),
          child: ClipRect(
            child: SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: math.max(
                    46,
                    (courses[i].end - courses[i].start) / 60 * 72 - 4,
                  ),
                ),
                child: card(courses[i], compact: true),
              ),
            ),
          ),
        ),
    ];
  }
}

class CourseEditor extends StatefulWidget {
  final AppStore store;
  final Course? initial;
  final DateTime date;
  const CourseEditor({
    super.key,
    required this.store,
    this.initial,
    required this.date,
  });
  @override
  State<CourseEditor> createState() => _CourseEditorState();
}

class _CourseEditorState extends State<CourseEditor> {
  late final name = TextEditingController(text: widget.initial?.name),
      room = TextEditingController(text: widget.initial?.room),
      teacher = TextEditingController(text: widget.initial?.teacher);
  late final first = TextEditingController(
        text: '${widget.initial?.firstWeek ?? 1}',
      ),
      last = TextEditingController(text: '${widget.initial?.lastWeek ?? 20}');
  late int weekday = widget.initial?.weekday ?? widget.date.weekday,
      start = widget.initial?.start ?? 540,
      end = widget.initial?.end ?? 630,
      parity = widget.initial?.parity ?? 0;
  late String level =
      widget.initial?.level ??
      widget.store.document.list.levelSet.levels.first.id;
  late DateTime term =
      widget.initial?.termStart ??
      widget.store.document.courses
          .where((c) => !c.deleted)
          .firstOrNull
          ?.termStart ??
      widget.date.subtract(Duration(days: widget.date.weekday - 1));
  String? error;
  bool busy = false;
  @override
  void dispose() {
    for (final c in [name, room, teacher, first, last]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> time(bool from) async {
    final minute = from ? start : end;
    final value = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: (minute ~/ 60) % 24, minute: minute % 60),
      initialEntryMode: TimePickerEntryMode.input,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (value != null && mounted) {
      setState(() {
        final m = value.hour * 60 + value.minute;
        if (from) {
          start = m;
          if (end <= start) {
            end = math.min(1440, start + 90);
          }
        } else {
          end = m == 0 ? 1440 : m;
        }
      });
    }
  }

  Future<void> save([bool deleted = false]) async {
    if (busy) return;
    final a = int.tryParse(first.text), b = int.tryParse(last.text);
    if (!deleted &&
        (name.text.trim().isEmpty ||
            end <= start ||
            a == null ||
            b == null ||
            a < 1 ||
            b > 52 ||
            a > b)) {
      setState(() => error = '请填写课程名称，并检查上课时间与周次（1–52）');
      return;
    }
    setState(() => busy = true);
    try {
      final c = Course(
        id: widget.initial?.id,
        name: name.text.trim(),
        room: room.text.trim(),
        teacher: teacher.text.trim(),
        termStart: term,
        weekday: weekday,
        start: start,
        end: end,
        firstWeek: a ?? 1,
        lastWeek: b ?? 20,
        parity: parity,
        level: level,
        deleted: deleted,
      );
      await widget.store.dispatch({'type': 'course', 'value': c.toJson()});
      if (mounted) Navigator.pop(context);
    } catch (_) {
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
        controller: name,
        maxLength: 160,
        decoration: const InputDecoration(labelText: '课程名称'),
      ),
      Row(
        children: [
          Expanded(
            child: TextField(
              controller: room,
              maxLength: 160,
              decoration: const InputDecoration(labelText: '教室'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: teacher,
              maxLength: 160,
              decoration: const InputDecoration(labelText: '教师'),
            ),
          ),
        ],
      ),
      const SizedBox(height: 12),
      Wrap(
        spacing: 4,
        children: [
          for (var i = 1; i <= 7; i++)
            ChoiceChip(
              label: Text('周${['一', '二', '三', '四', '五', '六', '日'][i - 1]}'),
              selected: weekday == i,
              onSelected: (_) => setState(() => weekday = i),
            ),
        ],
      ),
      Row(
        children: [
          const Text('开始', style: TextStyle(fontSize: 12)),
          TextButton(
            onPressed: () => time(true),
            child: Text(minuteLabel(start)),
          ),
          const Spacer(),
          const Text('结束', style: TextStyle(fontSize: 12)),
          TextButton(
            onPressed: () => time(false),
            child: Text(minuteLabel(end)),
          ),
        ],
      ),
      Row(
        children: [
          const Text('学期第一周', style: TextStyle(fontSize: 12)),
          const Spacer(),
          TextButton(
            onPressed: () async {
              final d = await chooseDate(context, term);
              if (d != null && mounted) {
                setState(
                  () => term = d.subtract(Duration(days: d.weekday - 1)),
                );
              }
            },
            child: Text('${term.year}/${term.month}/${term.day}'),
          ),
        ],
      ),
      Row(
        children: [
          Expanded(
            child: TextField(
              controller: first,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: '开始周次'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: last,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: '结束周次'),
            ),
          ),
        ],
      ),
      const SizedBox(height: 14),
      CupertinoSlidingSegmentedControl<int>(
        groupValue: parity,
        children: const {0: Text('每周'), 1: Text('单周'), 2: Text('双周')},
        onValueChanged: (v) {
          if (v != null) setState(() => parity = v);
        },
      ),
      const SizedBox(height: 12),
      Wrap(
        spacing: 6,
        children: [
          for (final l in widget.store.document.list.levelSet.levels)
            ChoiceChip(
              label: Text(l.name),
              avatar: CircleAvatar(
                radius: 5,
                backgroundColor: l.color.withValues(alpha: 1),
              ),
              selected: level == l.id,
              onSelected: (_) => setState(() => level = l.id),
            ),
        ],
      ),
      if (error != null)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(
            error!,
            style: const TextStyle(color: Colors.red, fontSize: 12),
          ),
        ),
      const SizedBox(height: 18),
      Row(
        children: [
          if (widget.initial != null)
            TextButton(
              onPressed: busy ? null : () => save(true),
              child: const Text('删除课程'),
            ),
          const Spacer(),
          FilledButton(
            onPressed: busy ? null : () => save(),
            child: Text(busy ? '保存中…' : '保存'),
          ),
        ],
      ),
    ],
  );
}
