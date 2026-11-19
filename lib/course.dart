import 'model.dart';

class Course {
  final String id, name, room, teacher, level;
  final DateTime termStart, updated;
  final int weekday, start, end, firstWeek, lastWeek, parity;
  final bool deleted;
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
