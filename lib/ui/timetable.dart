import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../course.dart';
import '../model.dart';
import '../store.dart';
import '../platform_services.dart';
import 'components.dart';

const coursePastels = [
  0xffedc4d7,
  0xffc9c0ef,
  0xffa8d9eb,
  0xffa9dfd7,
  0xfff8dfa0,
  0xfff2c3a4,
];

class Timetable extends StatefulWidget {
  final AppStore store;
  final Appearance? appearance;
  final DesktopController? desktop;
  const Timetable({
    super.key,
    required this.store,
    this.appearance,
    this.desktop,
  });
  @override
  State<Timetable> createState() => _TimetableState();
}

class _TimetableState extends State<Timetable> {
  DateTime selected = dayOnly(DateTime.now());
  @override
  void initState() {
    super.initState();
    unawaited(
      widget.store.prepareCourseColors().catchError(
        (Object e) => widget.store.setError(e),
      ),
    );
  }

  AppStore get store => widget.store;
  Appearance get appearance => widget.appearance ?? store.timetableAppearance;
  Future<void> modal(String title, Widget child) async {
    await widget.desktop?.editing(true);
    if (!mounted) return;
    try {
      await showPanel<void>(context, title, child, width: 460);
    } finally {
      await widget.desktop?.editing(false);
    }
  }

  Future<void> edit([Course? course, int? period]) => modal(
    course == null ? '添加课程' : '编辑课程',
    CourseEditor(
      store: store,
      initial: course,
      date: selected,
      appearance: appearance,
      initialPeriod: period,
    ),
  );
  @override
  Widget build(BuildContext context) {
    final grid = store.courseGrid, p = appearance.palette;
    final monday = selected.subtract(Duration(days: selected.weekday - 1));
    final all = store.document.courses.where((c) => !c.deleted).toList();
    final anchor =
        all.firstOrNull?.termStart ??
        dayOnly(DateTime.now())
            .subtract(Duration(days: DateTime.now().weekday - 1));
    final termMonday = anchor.subtract(Duration(days: anchor.weekday - 1));
    final week = Course(name: '', termStart: anchor).weekOn(monday);
    final days = grid.weekends ? 7 : 5;
    return LayoutBuilder(
      builder: (context, box) {
        final small = box.maxWidth < 600;
        final gutter = small ? 36.0 : 48.0;
        final rowHeight = grid.rowHeight;
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 8, 6),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        PopupMenuButton<int>(
                          tooltip: '切换教学周',
                          onSelected: (w) => setState(
                            () => selected = termMonday.add(
                              Duration(days: (w - 1) * 7),
                            ),
                          ),
                          itemBuilder: (_) => [
                            for (var w = 1; w <= 52; w++)
                              PopupMenuItem(value: w, child: Text('第 $w 周')),
                          ],
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 5),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  week > 0 ? '第 $week 周' : '开学前',
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w500,
                                    color: p.text,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Icon(
                                  CupertinoIcons.chevron_down,
                                  size: 10,
                                  color: p.text.withValues(alpha: .5),
                                ),
                              ],
                            ),
                          ),
                        ),
                        Text(
                          '${grid.termName} · ${monday.month}月',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 10,
                            color: p.text.withValues(alpha: .5),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (periodKey('week', selected) !=
                      periodKey('week', DateTime.now()))
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
                    CupertinoIcons.slider_horizontal_3,
                    '课表排版',
                    () => modal('课表排版', CourseGridEditor(store: store)),
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
              padding: EdgeInsets.only(left: gutter, right: 6),
              child: Row(
                children: [
                  for (var d = 0; d < days; d++)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Column(
                          children: [
                            Text(
                              ['一', '二', '三', '四', '五', '六', '日'][d],
                              style: TextStyle(
                                fontSize: 11,
                                color: p.text.withValues(alpha: .5),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${monday.add(Duration(days: d)).day}',
                              style: TextStyle(
                                fontSize: 13,
                                color:
                                    dayKey(monday.add(Duration(days: d))) ==
                                        dayKey(DateTime.now())
                                    ? p.accent
                                    : p.text,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                child: SizedBox(
                  height: grid.slots.length * rowHeight,
                  child: LayoutBuilder(
                    builder: (context, c) {
                      final column = (c.maxWidth - gutter - 6) / days;
                      return Stack(
                        children: [
                          for (var i = 0; i < grid.slots.length; i++)
                            Positioned(
                              top: i * rowHeight,
                              left: 0,
                              width: gutter,
                              height: rowHeight,
                              child: Column(
                                children: [
                                  Text(
                                    '${i + 1}',
                                    style: TextStyle(
                                      fontSize: small ? 12 : 14,
                                      color: p.text.withValues(alpha: .7),
                                    ),
                                  ),
                                  Text(
                                    minuteLabel(grid.slots[i].start),
                                    style: TextStyle(
                                      fontSize: small ? 8 : 10,
                                      color: p.text.withValues(alpha: .4),
                                    ),
                                  ),
                                  Text(
                                    minuteLabel(grid.slots[i].end),
                                    style: TextStyle(
                                      fontSize: small ? 8 : 10,
                                      color: p.text.withValues(alpha: .4),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          for (var d = 0; d < days; d++)
                            for (var i = 0; i < grid.slots.length; i++)
                              Positioned(
                                top: i * rowHeight,
                                left: gutter + d * column,
                                width: column,
                                height: rowHeight,
                                child: GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onTap: () {
                                    setState(
                                      () => selected = monday.add(
                                        Duration(days: d),
                                      ),
                                    );
                                    edit(null, i + 1);
                                  },
                                  child: DecoratedBox(
                                    decoration: BoxDecoration(
                                      border: Border(
                                        bottom: BorderSide(
                                          color: p.line.withValues(alpha: .35),
                                          width: .5,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                          for (var d = 0; d < days; d++)
                            ...blocks(
                              all
                                  .where(
                                    (course) => course.occursOn(
                                      monday.add(Duration(days: d)),
                                    ),
                                  )
                                  .toList(),
                              d,
                              grid,
                              gutter,
                              column,
                              small,
                            ),
                          if (all.isEmpty)
                            Positioned(
                              left: gutter,
                              right: 8,
                              top: 20,
                              child: Center(
                                child: TextButton(
                                  onPressed: () => edit(),
                                  child: const Text('添加第一门课程'),
                                ),
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  List<Widget> blocks(
    List<Course> courses,
    int day,
    CourseGrid grid,
    double gutter,
    double column,
    bool small,
  ) {
    courses.sort((a, b) => grid.span(a).$1.compareTo(grid.span(b).$1));
    final lanes = <int>[], ends = <int>[];
    for (final c in courses) {
      final range = grid.span(c);
      var lane = ends.indexWhere((end) => end < range.$1);
      if (lane < 0) {
        lane = ends.length;
        ends.add(range.$2);
      } else {
        ends[lane] = range.$2;
      }
      lanes.add(lane);
    }
    final columns = math.max(1, ends.length);
    return [
      for (var i = 0; i < courses.length; i++)
        Positioned(
          key: ValueKey('course-block-${courses[i].id}'),
          top: grid.span(courses[i]).$1 * grid.rowHeight + 2,
          left: gutter + day * column + lanes[i] * column / columns + 2,
          width: math.max(1, column / columns - 4),
          height:
              (grid.span(courses[i]).$2 - grid.span(courses[i]).$1 + 1) *
                  grid.rowHeight -
              4,
          child: Material(
            color: appearance.taskColor(store.courseLevel(courses[i])),
            borderRadius: BorderRadius.circular(grid.radius),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => edit(courses[i]),
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: small ? 3 : 8,
                  vertical: 6,
                ),
                child: LayoutBuilder(
                  builder: (context, c) {
                    final ink = appearance.taskTextColor(
                      store.courseLevel(courses[i]),
                    );
                    return Center(
                      child: SingleChildScrollView(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              courses[i].name,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: grid.fontSize,
                                fontWeight: FontWeight.w500,
                                color: ink,
                                height: 1.3,
                              ),
                            ),
                            if (courses[i].room.isNotEmpty) ...[
                              const SizedBox(height: 5),
                              Text(
                                '@${courses[i].room}',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: math.max(9, grid.fontSize - 2),
                                  color: ink.withValues(alpha: ink.a * .75),
                                  height: 1.3,
                                ),
                              ),
                            ],
                            if (grid.showTeacher &&
                                courses[i].teacher.isNotEmpty)
                              Text(
                                courses[i].teacher,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 10,
                                  color: ink.withValues(alpha: ink.a * .6),
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
          ),
        ),
    ];
  }
}

class CourseGridEditor extends StatefulWidget {
  final AppStore store;
  const CourseGridEditor({super.key, required this.store});
  @override
  State<CourseGridEditor> createState() => _CourseGridEditorState();
}

class _CourseGridEditorState extends State<CourseGridEditor> {
  late final grid = CourseGrid.fromJson(widget.store.courseGrid.toJson());
  late final term = TextEditingController(text: grid.termName);
  String? error;
  @override
  void dispose() {
    term.dispose();
    super.dispose();
  }

  Future<void> time(int index, bool start) async {
    final old = grid.slots[index],
        m = start ? grid.slots[index].start : grid.slots[index].end;
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: (m ~/ 60) % 24, minute: m % 60),
      initialEntryMode: TimePickerEntryMode.input,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (t != null && mounted) {
      setState(() {
        final minute = t.hour * 60 + t.minute;
        grid.slots[index] = LessonSlot(
          start ? minute : old.start,
          start ? old.end : minute,
        );
      });
    }
  }

  Widget slider(
    String title,
    double value,
    double min,
    double max,
    ValueChanged<double> change,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('$title · ${value.round()}', style: const TextStyle(fontSize: 12)),
      Slider(
        value: value,
        min: min,
        max: max,
        onChanged: (v) => setState(() => change(v)),
      ),
    ],
  );
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      TextField(
        controller: term,
        maxLength: 60,
        decoration: const InputDecoration(labelText: '学期名称'),
      ),
      SwitchListTile.adaptive(
        contentPadding: EdgeInsets.zero,
        title: const Text('显示周末', style: TextStyle(fontSize: 13)),
        value: grid.weekends,
        onChanged: (v) => setState(() => grid.weekends = v),
      ),
      SwitchListTile.adaptive(
        contentPadding: EdgeInsets.zero,
        title: const Text('显示教师', style: TextStyle(fontSize: 13)),
        value: grid.showTeacher,
        onChanged: (v) => setState(() => grid.showTeacher = v),
      ),
      slider('行高', grid.rowHeight, 48, 120, (v) => grid.rowHeight = v),
      slider('字号', grid.fontSize, 9, 18, (v) => grid.fontSize = v),
      slider('圆角', grid.radius, 0, 18, (v) => grid.radius = v),
      const Text(
        '节次时间',
        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
      ),
      for (var i = 0; i < grid.slots.length; i++)
        Row(
          children: [
            SizedBox(
              width: 44,
              child: Text('第 ${i + 1} 节', style: const TextStyle(fontSize: 12)),
            ),
            Expanded(
              child: TextButton(
                onPressed: () => time(i, true),
                child: Text(minuteLabel(grid.slots[i].start)),
              ),
            ),
            const Text('—'),
            Expanded(
              child: TextButton(
                onPressed: () => time(i, false),
                child: Text(minuteLabel(grid.slots[i].end)),
              ),
            ),
            ActionIcon(
              CupertinoIcons.minus_circle,
              '删除第 ${i + 1} 节',
              grid.slots.length <= 1
                  ? null
                  : () => setState(() => grid.slots.removeAt(i)),
              compact: true,
            ),
          ],
        ),
      TextButton(
        onPressed: grid.slots.length >= 24
            ? null
            : () => setState(() {
                final start = math.min(1380, grid.slots.last.end + 10);
                grid.slots.add(LessonSlot(start, math.min(1440, start + 45)));
              }),
        child: const Text('添加节次'),
      ),
      if (error != null)
        Text(error!, style: const TextStyle(fontSize: 12, color: Colors.red)),
      const SizedBox(height: 12),
      FilledButton(
        onPressed: () async {
          for (var i = 0; i < grid.slots.length; i++) {
            final s = grid.slots[i];
            if (s.end <= s.start ||
                (i > 0 && s.start < grid.slots[i - 1].end)) {
              setState(() => error = '请检查节次：结束时间应晚于开始时间，各节次不能重叠');
              return;
            }
          }
          grid.termName = term.text.trim();
          await widget.store.dispatch({
            'type': 'preferences',
            'profiles': {},
            'courseGrid': grid.toJson(),
          });
          if (context.mounted) Navigator.pop(context);
        },
        child: const Text('保存'),
      ),
    ],
  );
}

class CourseEditor extends StatefulWidget {
  final AppStore store;
  final Course? initial;
  final Appearance? appearance;
  final DateTime date;
  final int? initialPeriod;
  const CourseEditor({
    super.key,
    required this.store,
    this.initial,
    this.appearance,
    this.initialPeriod,
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
  late String level = widget.initial == null
      ? (widget.appearance ?? widget.store.timetableAppearance)
            .levelSet
            .levels[widget.store.document.courses
                    .where((c) => !c.deleted)
                    .length %
                (widget.appearance ?? widget.store.timetableAppearance)
                    .levelSet
                    .levels
                    .length]
            .id
      : widget.store.courseLevel(widget.initial!);
  late DateTime term =
      widget.initial?.termStart ??
      widget.store.document.courses
          .where((c) => !c.deleted)
          .firstOrNull
          ?.termStart ??
      widget.date.subtract(Duration(days: widget.date.weekday - 1));
  late bool byPeriod =
      widget.initial == null || widget.initial?.startPeriod != null;
  late int startPeriod =
      (widget.initial?.startPeriod ?? widget.initialPeriod ?? 1).clamp(
        1,
        widget.store.courseGrid.slots.length,
      );
  late int endPeriod = (widget.initial?.endPeriod ?? (startPeriod + 1)).clamp(
    startPeriod,
    widget.store.courseGrid.slots.length,
  );
  String? error;
  bool busy = false, weeksExpanded = false;
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
    if (byPeriod) {
      start = widget.store.courseGrid.slots[startPeriod - 1].start;
      end = widget.store.courseGrid.slots[endPeriod - 1].end;
    }
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
        startPeriod: byPeriod ? startPeriod : null,
        endPeriod: byPeriod ? endPeriod : null,
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
        decoration: const InputDecoration(labelText: '课程名称', counterText: ''),
      ),
      const SizedBox(height: 16),
      Row(
        children: [
          Expanded(
            child: TextField(
              controller: room,
              maxLength: 160,
              decoration: const InputDecoration(
                labelText: '教室',
                counterText: '',
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: teacher,
              maxLength: 160,
              decoration: const InputDecoration(
                labelText: '教师',
                counterText: '',
              ),
            ),
          ),
        ],
      ),
      const SizedBox(height: 12),
      Row(
        children: [
          const Text('上课日期', style: TextStyle(fontSize: 12)),
          const Spacer(),
          DropdownButtonHideUnderline(
            child: DropdownButton<int>(
              value: weekday,
              items: [
                for (var i = 1; i <= 7; i++)
                  DropdownMenuItem(
                    value: i,
                    child: Text(
                      '星期${['一', '二', '三', '四', '五', '六', '日'][i - 1]}',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
              ],
              onChanged: (v) {
                if (v != null) setState(() => weekday = v);
              },
            ),
          ),
        ],
      ),
      const SizedBox(height: 10),
      CupertinoSlidingSegmentedControl<bool>(
        groupValue: byPeriod,
        children: const {true: Text('按节次'), false: Text('自定时间')},
        onValueChanged: (v) {
          if (v != null) setState(() => byPeriod = v);
        },
      ),
      if (byPeriod)
        Row(
          children: [
            Expanded(
              child: DropdownButton<int>(
                isExpanded: true,
                value: startPeriod,
                items: [
                  for (
                    var i = 1;
                    i <= widget.store.courseGrid.slots.length;
                    i++
                  )
                    DropdownMenuItem(value: i, child: Text('第 $i 节开始')),
                ],
                onChanged: (v) {
                  if (v != null) {
                    setState(() {
                      startPeriod = v;
                      if (endPeriod < v) endPeriod = v;
                    });
                  }
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: DropdownButton<int>(
                isExpanded: true,
                value: endPeriod,
                items: [
                  for (
                    var i = startPeriod;
                    i <= widget.store.courseGrid.slots.length;
                    i++
                  )
                    DropdownMenuItem(value: i, child: Text('第 $i 节结束')),
                ],
                onChanged: (v) {
                  if (v != null) setState(() => endPeriod = v);
                },
              ),
            ),
          ],
        ),
      if (!byPeriod)
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
      const SizedBox(height: 12),
      InkWell(
        onTap: () => setState(() => weeksExpanded = !weeksExpanded),
        borderRadius: BorderRadius.circular(7),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Row(
            children: [
              const Text('教学周', style: TextStyle(fontSize: 12)),
              const Spacer(),
              Text(
                '第 ${first.text}–${last.text} 周 · ${const ['每周', '单周', '双周'][parity]}',
                style: const TextStyle(fontSize: 12, color: muted),
              ),
              const SizedBox(width: 8),
              Icon(
                weeksExpanded
                    ? CupertinoIcons.chevron_up
                    : CupertinoIcons.chevron_down,
                size: 10,
                color: muted,
              ),
            ],
          ),
        ),
      ),
      if (weeksExpanded) ...[
        const SizedBox(height: 12),
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
      ],
      const SizedBox(height: 8),
      Row(
        children: [
          const Text('课程颜色', style: TextStyle(fontSize: 12)),
          const SizedBox(width: 16),
          Expanded(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                isExpanded: true,
                value:
                    (widget.appearance ?? widget.store.timetableAppearance)
                        .levelSet
                        .levels
                        .any((l) => l.id == level)
                    ? level
                    : (widget.appearance ?? widget.store.timetableAppearance)
                          .levelSet
                          .levels
                          .first
                          .id,
                items: [
                  for (final l
                      in (widget.appearance ?? widget.store.timetableAppearance)
                          .levelSet
                          .levels)
                    DropdownMenuItem(
                      value: l.id,
                      child: Row(
                        children: [
                          Container(
                            width: 16,
                            height: 16,
                            decoration: BoxDecoration(
                              color: l.color,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(l.name, style: const TextStyle(fontSize: 12)),
                        ],
                      ),
                    ),
                ],
                onChanged: (v) {
                  if (v != null) setState(() => level = v);
                },
              ),
            ),
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
