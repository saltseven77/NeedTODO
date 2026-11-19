import 'model.dart';

class LessonSlot {
  final int start, end;
  const LessonSlot(this.start, this.end);
  Map<String, dynamic> toJson() => {'start': start, 'end': end};
}

class CourseGrid {
  String termName;
  double rowHeight, fontSize, radius;
  bool weekends, showTeacher;
  List<LessonSlot> slots;
  CourseGrid({
    this.termName = '本学期',
    this.rowHeight = 64,
    this.fontSize = 12,
    this.radius = 7,
    this.weekends = true,
    this.showTeacher = false,
    List<LessonSlot>? slots,
  }) : slots =
           slots ??
           const [
             LessonSlot(480, 525),
             LessonSlot(530, 575),
             LessonSlot(600, 645),
             LessonSlot(650, 695),
             LessonSlot(810, 855),
             LessonSlot(860, 905),
             LessonSlot(930, 975),
             LessonSlot(980, 1025),
             LessonSlot(1110, 1155),
             LessonSlot(1160, 1205),
             LessonSlot(1210, 1255),
             LessonSlot(1260, 1305),
           ];
  factory CourseGrid.fromJson(Map<String, dynamic> j) {
    final slots = <LessonSlot>[];
    for (final v in j['slots'] is List ? j['slots'] : []) {
      final m = object(v);
      final a = m['start'], b = m['end'];
      if (a is int &&
          b is int &&
          a >= 0 &&
          a < b &&
          b <= 1440 &&
          (slots.isEmpty || a >= slots.last.end) &&
          slots.length < 24) {
        slots.add(LessonSlot(a, b));
      }
    }
    return CourseGrid(
      termName: j['termName'] is String ? j['termName'] : '本学期',
      rowHeight: number(j['rowHeight'], 64, 48, 120),
      fontSize: number(j['fontSize'], 12, 9, 18),
      radius: number(j['radius'], 7, 0, 18),
      weekends: j['weekends'] != false,
      showTeacher: j['showTeacher'] == true,
      slots: slots.isEmpty ? null : slots,
    );
  }
  Map<String, dynamic> toJson() => {
    'termName': termName,
    'rowHeight': rowHeight,
    'fontSize': fontSize,
    'radius': radius,
    'weekends': weekends,
    'showTeacher': showTeacher,
    'slots': slots.map((s) => s.toJson()).toList(),
  };
  (int, int) span(Course c) {
    if (c.startPeriod != null && c.endPeriod != null) {
      final a = (c.startPeriod! - 1).clamp(0, slots.length - 1);
      return (a, (c.endPeriod! - 1).clamp(a, slots.length - 1));
    }
    final overlapping = <int>[
      for (var i = 0; i < slots.length; i++)
        if (c.start < slots[i].end && c.end > slots[i].start) i,
    ];
    if (overlapping.isNotEmpty) return (overlapping.first, overlapping.last);
    var nearest = 0;
    for (var i = 1; i < slots.length; i++) {
      if ((slots[i].start - c.start).abs() <
          (slots[nearest].start - c.start).abs()) {
        nearest = i;
      }
    }
    return (nearest, nearest);
  }
}

class Course {
  final String id, name, room, teacher, level;
  final DateTime termStart, updated;
  final int weekday, start, end, firstWeek, lastWeek, parity;
  final bool deleted;
  final int? startPeriod, endPeriod, color, textColor;
  Course({
    String? id,
    required this.name,
    required this.termStart,
    this.room = '',
    this.teacher = '',
    this.level = 'normal',
    this.weekday = 1,
    this.start = 540,
    this.end = 630,
    this.firstWeek = 1,
    this.lastWeek = 20,
    this.parity = 0,
    this.deleted = false,
    this.startPeriod,
    this.endPeriod,
    this.color,
    this.textColor,
    DateTime? updated,
  }) : id = id ?? newId(),
       updated = updated ?? DateTime.now().toUtc();
  int weekOn(DateTime date) {
    final monday = termStart.subtract(Duration(days: termStart.weekday - 1));
    final days = DateTime.utc(
      date.year,
      date.month,
      date.day,
    ).difference(DateTime.utc(monday.year, monday.month, monday.day)).inDays;
    return days < 0 ? 0 : days ~/ 7 + 1;
  }

  bool occursOn(DateTime date) {
    final week = weekOn(date);
    return !deleted &&
        date.weekday == weekday &&
        week >= firstWeek &&
        week <= lastWeek &&
        (parity == 0 || week % 2 == (parity == 1 ? 1 : 0));
  }

  Map<String, dynamic> toJson() => deleted
      ? {'id': id, 'deleted': true, 'updated': updated.toIso8601String()}
      : {
          'id': id,
          'name': name,
          if (startPeriod != null) 'startPeriod': startPeriod,
          if (endPeriod != null) 'endPeriod': endPeriod,
          if (color != null) 'color': color,
          if (textColor != null) 'textColor': textColor,
          'room': room,
          'teacher': teacher,
          'level': level,
          'termStart': dayKey(termStart),
          'weekday': weekday,
          'start': start,
          'end': end,
          'firstWeek': firstWeek,
          'lastWeek': lastWeek,
          'parity': parity,
          'updated': updated.toIso8601String(),
        };
  factory Course.fromJson(Map<String, dynamic> j) => Course(
    id: j['id'],
    startPeriod: j['startPeriod'] is int ? j['startPeriod'] : null,
    endPeriod: j['endPeriod'] is int ? j['endPeriod'] : null,
    color: j['color'] is int ? j['color'] : null,
    textColor: j['textColor'] is int ? j['textColor'] : null,
    name: j['name'] ?? '',
    room: j['room'] ?? '',
    teacher: j['teacher'] ?? '',
    level: j['level'] ?? 'normal',
    termStart: DateTime.tryParse(j['termStart'] ?? '') ?? DateTime(2000),
    weekday: j['weekday'] ?? 1,
    start: j['start'] ?? 540,
    end: j['end'] ?? 630,
    firstWeek: j['firstWeek'] ?? 1,
    lastWeek: j['lastWeek'] ?? 20,
    parity: j['parity'] ?? 0,
    deleted: j['deleted'] == true,
    updated:
        DateTime.tryParse(j['updated'] ?? '') ??
        DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
  );
}
