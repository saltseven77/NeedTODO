import 'dart:math';

import 'package:flutter/material.dart';

String newId() =>
    '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}${Random.secure().nextInt(1 << 32).toRadixString(36)}';
String dayKey(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
DateTime dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);
String periodKey(String scope, DateTime d) => scope == 'month'
    ? dayKey(d).substring(0, 7)
    : dayKey(scope == 'week' ? d.subtract(Duration(days: d.weekday - 1)) : d);
Color readColor(dynamic value, Color fallback) {
  if (value is int) return Color(value);
  if (value is String) {
    final n = int.tryParse(value.replaceFirst('#', ''), radix: 16);
    if (n != null) {
      return Color(
        value.replaceFirst('#', '').length <= 6 ? n | 0xff000000 : n,
      );
    }
  }
  return fallback;
}

Map<String, dynamic> object(dynamic value) =>
    value is Map ? Map<String, dynamic>.from(value) : {};
double number(dynamic value, double fallback, double min, double max) =>
    value is num && value.isFinite
    ? value.toDouble().clamp(min, max)
    : fallback;

class Todo {
  final String id, title, date, scope, level, category;
  final bool done, deleted;
  final DateTime updated, created;
  final int? startMinute, endMinute;
  final String timePeriod;
  final DateTime? reminder;
  Todo({
    String? id,
    required this.title,
    required this.date,
    this.scope = 'day',
    this.level = 'normal',
    this.category = '',
    this.done = false,
    this.deleted = false,
    DateTime? updated,
    this.reminder,
    DateTime? created,
    this.startMinute,
    this.endMinute,
    this.timePeriod = '',
  }) : id = id ?? newId(),
       created = created ?? DateTime.now().toUtc(),
       updated = updated ?? DateTime.now().toUtc();
  Todo copy({
    String? title,
    String? date,
    String? scope,
    String? level,
    String? category,
    bool? done,
    bool? deleted,
    DateTime? reminder,
    int? startMinute,
    int? endMinute,
    String? timePeriod,
    bool clearTime = false,
    bool clearReminder = false,
  }) => Todo(
    id: id,
    title: title ?? this.title,
    date: date ?? this.date,
    scope: scope ?? this.scope,
    level: level ?? this.level,
    category: category ?? this.category,
    done: done ?? this.done,
    deleted: deleted ?? this.deleted,
    created: created,
    startMinute: clearTime ? null : startMinute ?? this.startMinute,
    endMinute: clearTime ? null : endMinute ?? this.endMinute,
    timePeriod: timePeriod ?? this.timePeriod,
    reminder: clearReminder ? null : reminder ?? this.reminder,
  );
  Map<String, dynamic> toJson() => deleted
      ? {'id': id, 'deleted': true, 'updated': updated.toIso8601String()}
      : {
          'id': id,
          'title': title,
          'date': date,
          'scope': scope,
          'level': level,
          'category': category,
          'done': done,
          'deleted': deleted,
          'updated': updated.toIso8601String(),
          'created': created.toIso8601String(),
          'startMinute': startMinute,
          'endMinute': endMinute,
          'timePeriod': timePeriod,
          'reminder': reminder?.toUtc().toIso8601String(),
        };
  factory Todo.fromJson(Map<String, dynamic> j) {
    final date = j['date'] as String? ?? dayKey(DateTime.now());
    if (DateTime.tryParse(date) == null) throw const FormatException('日期无效');
    return Todo(
      id: j['id'],
      title: j['title'] ?? '',
      date: date,
      scope: ['day', 'week', 'month'].contains(j['scope']) ? j['scope'] : 'day',
      level: j['level'] ?? 'normal',
      category: j['category'] is String ? (j['category'] as String).trim() : '',
      done: j['done'] ?? j['completedAt'] != null,
      deleted: j['deleted'] == true,
      updated:
          DateTime.tryParse(j['updated'] ?? j['createdAt'] ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      created:
          DateTime.tryParse(j['created'] ?? j['createdAt'] ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      startMinute: j['startMinute'] is int
          ? (j['startMinute'] as int).clamp(0, 1439)
          : null,
      endMinute: j['endMinute'] is int
          ? (j['endMinute'] as int).clamp(1, 1440)
          : null,
      timePeriod: ['上午', '下午', '晚上'].contains(j['timePeriod'])
          ? j['timePeriod']
          : '',
      reminder: DateTime.tryParse(j['reminder'] ?? j['reminderAt'] ?? ''),
    );
  }
}

class Palette {
  String id, name;
  Color background, text, accent, line;
  Palette(
    this.id,
    this.name,
    this.background,
    this.text,
    this.accent, [
    this.line = const Color(0x20808080),
  ]);
  Palette clone() => Palette.fromJson(toJson());
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'background': background.toARGB32(),
    'text': text.toARGB32(),
    'accent': accent.toARGB32(),
    'line': line.toARGB32(),
  };
  factory Palette.fromJson(Map<String, dynamic> j) {
    final c = j['colors'] == null ? j : object(j['colors']);
    Color color(String key, Color fallback) {
      final value = readColor(c[key], fallback);
      return c['${key}Alpha'] is num
          ? value.withValues(alpha: number(c['${key}Alpha'], 1, 0, 1))
          : value;
    }

    return Palette(
      j['id'] ?? newId(),
      j['name'] ?? '配色',
      color('background', const Color(0xfffafaf9)),
      color('text', const Color(0xff303238)),
      color('accent', const Color(0xff537da5)),
      color('line', const Color(0x20808080)),
    );
  }
}

List<Palette> defaultPalettes() => [
  Palette(
    'paper',
    '暖纸',
    const Color(0xfffafaf9),
    const Color(0xff303238),
    const Color(0xff537da5),
  ),
  Palette(
    'sage',
    '青苔',
    const Color(0xffe4ede1),
    const Color(0xff304e3d),
    const Color(0xff3c7151),
  ),
  Palette(
    'night',
    '晚墨',
    const Color(0xff222c26),
    const Color(0xfff1f4ed),
    const Color(0xffbad1a0),
  ),
  Palette(
    'sand',
    '沙棕',
    const Color(0xfff0e4d1),
    const Color(0xff594331),
    const Color(0xffa86e39),
  ),
  Palette(
    'blue',
    '雾蓝',
    const Color(0xfff4f6f8),
    const Color(0xff34475e),
    const Color(0xff527ca7),
  ),
];

class Level {
  String id, name;
  Color color;
  Color? textColor;
  Level(this.id, this.name, this.color, [this.textColor]);
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'color': color.toARGB32(),
    'textColor': textColor?.toARGB32(),
  };
  factory Level.fromJson(Map<String, dynamic> j) => Level(
    j['id'] ?? newId(),
    j['name'] ?? '普通',
    readColor(j['color'], const Color(0x268198ae)),
    j['textColor'] == null
        ? null
        : readColor(j['textColor'], const Color(0xff303238)),
  );
}

class LevelSet {
  String id, name;
  List<Level> levels;
  LevelSet(this.id, this.name, this.levels);
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'levels': levels.map((e) => e.toJson()).toList(),
  };
  factory LevelSet.fromJson(Map<String, dynamic> j) => LevelSet(
    j['id'] ?? newId(),
    j['name'] ?? '分级',
    (j['levels'] as List? ?? []).map((e) => Level.fromJson(object(e))).toList(),
  );
}

List<LevelSet> defaultLevels() => [
  LevelSet('mist', '薄雾', [
    Level('normal', '普通', const Color(0x248198ae)),
    Level('important', '重要', const Color(0x38b49a73)),
    Level('urgent', '紧急', const Color(0x40bb7b7b)),
  ]),
  LevelSet('warm', '暖调', [
    Level('normal', '普通', const Color(0x269da68e)),
    Level('important', '重要', const Color(0x38b69a82)),
    Level('urgent', '紧急', const Color(0x40b6959b)),
  ]),
  LevelSet('gray', '素灰', [
    Level('normal', '普通', const Color(0x1889929b)),
    Level('important', '重要', const Color(0x3889929b)),
    Level('urgent', '紧急', const Color(0x5889929b)),
  ]),
];

class Appearance {
  String name, avatar, background, floatingImage, effect, paletteId, levelSetId;
  DateTime updated;
  double radius, opacity, imageOpacity, effectAmount;
  Color effectColor;
  List<Palette> palettes;
  List<LevelSet> levelSets;
  Appearance({
    this.name = '泥土豆',
    DateTime? updated,
    this.avatar = '',
    this.background = '',
    this.floatingImage = '',
    this.radius = 22,
    this.opacity = 1,
    this.imageOpacity = .55,
    this.effect = 'default',
    this.effectAmount = .35,
    this.effectColor = const Color(0xffc8d9e7),
    this.paletteId = 'paper',
    this.levelSetId = 'mist',
    List<Palette>? palettes,
    List<LevelSet>? levelSets,
  }) : updated = updated ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
       palettes = palettes ?? defaultPalettes(),
       levelSets = levelSets ?? defaultLevels();
  Palette get palette =>
      palettes.where((p) => p.id == paletteId).firstOrNull ?? palettes.first;
  LevelSet get levelSet =>
      levelSets.where((p) => p.id == levelSetId).firstOrNull ?? levelSets.first;
  Color taskColor(String level) =>
      (levelSet.levels.where((e) => e.id == level).firstOrNull ??
              levelSet.levels.first)
          .color;
  Color taskTextColor(String level) =>
      levelSet.levels.where((e) => e.id == level).firstOrNull?.textColor ??
      palette.text;
  Appearance clone() => Appearance.fromJson(toJson());
  Map<String, dynamic> toJson() => {
    'name': name,
    'updated': updated.toUtc().toIso8601String(),
    'avatar': avatar,
    'background': background,
    'floatingImage': floatingImage,
    'radius': radius,
    'opacity': opacity,
    'imageOpacity': imageOpacity,
    'effect': effect,
    'effectAmount': effectAmount,
    'effectColor': effectColor.toARGB32(),
    'paletteId': paletteId,
    'levelSetId': levelSetId,
    'palettes': palettes.map((p) => p.toJson()).toList(),
    'levelSets': levelSets.map((p) => p.toJson()).toList(),
  };
  factory Appearance.fromJson(Map<String, dynamic> j) {
    final p = (j['palettes'] as List? ?? j['colorSets'] as List? ?? [])
        .take(7)
        .map((e) => Palette.fromJson(object(e)))
        .toList();
    final groups = (j['levelSets'] as List? ?? [])
        .take(7)
        .map((e) => LevelSet.fromJson(object(e)))
        .where((e) => e.levels.isNotEmpty)
        .toList();
    return Appearance(
      name: j['name'] ?? j['calendarName'] ?? '泥土豆',
      updated: DateTime.tryParse(j['updated'] ?? ''),
      avatar: j['avatar'] ?? j['calendarAvatar'] ?? '',
      background: j['background'] ?? '',
      floatingImage: j['floatingImage'] ?? '',
      radius: number(j['radius'], 22, 0, 48),
      opacity: number(j['opacity'], 1, 0, 1),
      imageOpacity: number(j['imageOpacity'], .55, 0, 1),
      effect: ['default', 'glass', 'paper', 'jelly'].contains(j['effect'])
          ? j['effect']
          : 'default',
      effectAmount: number(j['effectAmount'], .35, 0, 1),
      effectColor: readColor(j['effectColor'], const Color(0xffc8d9e7)),
      paletteId: j['paletteId'] ?? j['selectedColorSet'] ?? 'paper',
      levelSetId: j['levelSetId'] ?? 'mist',
      palettes: p.isEmpty ? null : p,
      levelSets: groups.isEmpty ? null : groups,
    );
  }
}

class ReminderStyle {
  String avatar, background, message;
  bool timeline;
  DateTime updated;
  ReminderStyle({
    this.avatar = '',
    this.background = '',
    this.message = '该开始这件小事了',
    this.timeline = false,
    DateTime? updated,
  }) : updated = updated ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
  Map<String, dynamic> toJson() => {
    'avatar': avatar,
    'background': background,
    'message': message,
    'timeline': timeline,
    'updated': updated.toUtc().toIso8601String(),
  };
  factory ReminderStyle.fromJson(Map<String, dynamic> j) => ReminderStyle(
    avatar: j['avatar'] ?? '',
    background: j['background'] ?? '',
    message: j['message'] ?? '该开始这件小事了',
    timeline: j['timeline'] == true,
    updated: DateTime.tryParse(j['updated'] ?? ''),
  );
  ReminderStyle clone() => ReminderStyle.fromJson(toJson());
}

class Holiday {
  final String id, name, start, end;
  final bool deleted;
  final DateTime updated;
  Holiday({
    String? id,
    required this.name,
    required this.start,
    required this.end,
    this.deleted = false,
    DateTime? updated,
  }) : id = id ?? newId(),
       updated = updated ?? DateTime.now().toUtc();
  bool contains(DateTime date) =>
      !deleted &&
      dayKey(date).compareTo(start) >= 0 &&
      dayKey(date).compareTo(end) <= 0;
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'start': start,
    'end': end,
    'deleted': deleted,
    'updated': updated.toIso8601String(),
  };
  factory Holiday.fromJson(Map<String, dynamic> j) => Holiday(
    id: j['id'],
    name: j['name'] ?? '',
    start: j['start'] ?? '',
    end: j['end'] ?? '',
    deleted: j['deleted'] == true,
    updated: DateTime.tryParse(j['updated'] ?? ''),
  );
}

List<Todo> tasksForPeriod(List<Todo> tasks, String scope, DateTime date) {
  final start = scope == 'month'
      ? DateTime(date.year, date.month)
      : scope == 'week'
      ? dayOnly(date).subtract(Duration(days: date.weekday - 1))
      : dayOnly(date);
  final end = scope == 'month'
      ? DateTime(date.year, date.month + 1)
      : start.add(Duration(days: scope == 'week' ? 7 : 1));
  return tasks
      .where(
        (t) =>
            !t.deleted &&
            (scope == 'month' || t.scope != 'month') &&
            (scope != 'day' || t.scope == 'day') &&
            t.date.compareTo(dayKey(start)) >= 0 &&
            t.date.compareTo(dayKey(end)) < 0,
      )
      .toList();
}

String minuteLabel(int minute) =>
    '${(minute ~/ 60).toString().padLeft(2, '0')}:${(minute % 60).toString().padLeft(2, '0')}';

int compareTaskTime(Todo a, Todo b, {bool byDate = false}) {
  if (byDate) {
    final date = a.date.compareTo(b.date);
    if (date != 0) return date;
  }
  int time(Todo task) => task.startMinute ?? 1440;
  final timeOrder = time(a).compareTo(time(b));
  return timeOrder != 0 ? timeOrder : a.created.compareTo(b.created);
}

String taskTimeLabel(Todo task) => task.startMinute == null
    ? ''
    : '${minuteLabel(task.startMinute!)}–${minuteLabel(task.endMinute ?? task.startMinute!)}';

int minuteAfterStart(int minute) => (minute + 1).clamp(1, 1440);
List<String> taskCategories(List<Todo> tasks) =>
    tasks
        .where((task) => !task.deleted && task.category.isNotEmpty)
        .map((task) => task.category)
        .toSet()
        .toList()
      ..sort();

class MonthCheckins {
  final int perfect, planned;
  const MonthCheckins(this.perfect, this.planned);
}

MonthCheckins monthCheckins(List<Todo> tasks, DateTime month, DateTime today) {
  final start = DateTime(month.year, month.month),
      end = DateTime(month.year, month.month + 1);
  final cutoff = dayKey(dayOnly(today));
  final days = <String, List<Todo>>{};
  for (final task in tasks) {
    if (task.deleted ||
        task.scope != 'day' ||
        task.date.compareTo(dayKey(start)) < 0 ||
        task.date.compareTo(dayKey(end)) >= 0 ||
        task.date.compareTo(cutoff) > 0) {
      continue;
    }
    days.putIfAbsent(task.date, () => []).add(task);
  }
  return MonthCheckins(
    days.values.where((day) => day.every((task) => task.done)).length,
    days.length,
  );
}

class Document {
  List<Todo> tasks;
  Appearance list, calendar;
  ReminderStyle reminders;
  List<Holiday> holidays;
  Map<String, JournalWeek> journals;
  Map<String, DateHeaderStyle> dateHeaders;
  DateTime appearanceUpdated;
  Document({
    List<Todo>? tasks,
    Appearance? list,
    Appearance? calendar,
    ReminderStyle? reminders,
    List<Holiday>? holidays,
    Map<String, JournalWeek>? journals,
    Map<String, DateHeaderStyle>? dateHeaders,
    DateTime? appearanceUpdated,
  }) : journals = journals ?? {},
       dateHeaders = dateHeaders ?? {},
       reminders = reminders ?? ReminderStyle(),
       holidays = holidays ?? [],
       tasks = tasks ?? [],
       list = list ?? Appearance(),
       calendar = calendar ?? Appearance(paletteId: 'blue'),
       appearanceUpdated =
           appearanceUpdated ??
           DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
  Map<String, dynamic> toJson() => {
    'version': 2,
    'journals': journals.map((key, value) => MapEntry(key, value.toJson())),
    'dateHeaders': dateHeaders.map(
      (key, value) => MapEntry(key, value.toJson()),
    ),
    'reminders': reminders.toJson(),
    'holidays': holidays.map((e) => e.toJson()).toList(),
    'tasks': tasks.map((e) => e.toJson()).toList(),
    'list': list.toJson(),
    'calendar': calendar.toJson(),
    'appearanceUpdated': appearanceUpdated.toUtc().toIso8601String(),
  };
  factory Document.fromJson(Map<String, dynamic> j) {
    final profiles = object(j['profiles']);
    final legacyUpdated = j['appearanceUpdated'];
    return Document(
      journals: object(j['journals']).map(
        (key, value) => MapEntry(key, JournalWeek.fromJson(key, object(value))),
      ),
      dateHeaders: object(j['dateHeaders']).map(
        (key, value) => MapEntry(key, DateHeaderStyle.fromJson(object(value))),
      ),
      reminders: ReminderStyle.fromJson(
        object(
          j['reminders'] ??
              {'message': object(j['list'])['reminderMessage'] ?? '该开始这件小事了'},
        ),
      ),
      holidays: (j['holidays'] as List? ?? [])
          .map((e) => Holiday.fromJson(object(e)))
          .toList(),
      tasks: (j['tasks'] as List? ?? [])
          .map((t) => Todo.fromJson(object(t)))
          .toList(),
      list: Appearance.fromJson({
        'updated': legacyUpdated,
        ...object(j['list'] ?? object(profiles['list'])['settings']),
      }),
      calendar: Appearance.fromJson({
        'updated': legacyUpdated,
        ...object(j['calendar'] ?? object(profiles['calendar'])['settings']),
      }),
      appearanceUpdated:
          DateTime.tryParse(j['appearanceUpdated'] ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );
  }
  Document clone() => Document.fromJson(toJson());
}

final _journalEpoch = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

class DateHeaderStyle {
  final Color? color;
  final DateTime updated;
  DateHeaderStyle({this.color, DateTime? updated})
    : updated = updated ?? _journalEpoch;
  Map<String, dynamic> toJson() => {
    'color': color?.toARGB32(),
    'updated': updated.toUtc().toIso8601String(),
  };
  factory DateHeaderStyle.fromJson(Map<String, dynamic> j) => DateHeaderStyle(
    color: j['color'] == null
        ? null
        : readColor(j['color'], Colors.transparent),
    updated: DateTime.tryParse(j['updated'] ?? ''),
  );
}

Color calendarDateHeaderColor(
  DateTime date,
  DateTime now,
  Appearance appearance, [
  DateHeaderStyle? override,
]) {
  if (override?.color != null) return override!.color!;
  final day = dayOnly(date),
      today = dayOnly(now),
      accent = appearance.palette.accent;
  return day == today
      ? accent.withValues(alpha: accent.a * .7)
      : day.isBefore(today)
      ? accent.withValues(alpha: accent.a * .5)
      : Colors.transparent;
}

class NoteStyle {
  Color paper, ink;
  Color? border;
  String pattern, font;
  double fontSize, borderWidth;
  int fontWeight;
  bool get bold => fontWeight >= 600;
  set bold(bool value) => fontWeight = value ? 600 : 400;
  Color get edge => border ?? ink;
  NoteStyle({
    this.paper = const Color(0x00ffffff),
    this.ink = const Color(0xff343834),
    this.pattern = 'blank',
    this.font = 'Segoe UI',
    this.fontSize = 13,
    bool bold = false,
    int? fontWeight,
    this.border,
    this.borderWidth = 1,
  }) : fontWeight = fontWeight ?? (bold ? 600 : 400);
  Map<String, dynamic> toJson() => {
    'paper': paper.toARGB32(),
    'ink': ink.toARGB32(),
    'pattern': pattern,
    'font': font,
    'fontSize': fontSize,
    'bold': bold,
    'fontWeight': fontWeight,
    'border': border?.toARGB32(),
    'borderWidth': borderWidth,
  };
  factory NoteStyle.fromJson(Map<String, dynamic> j) => NoteStyle(
    paper: readColor(j['paper'], const Color(0x00ffffff)),
    ink: readColor(j['ink'], const Color(0xff343834)),
    pattern: ['blank', 'dots', 'grid', 'lines'].contains(j['pattern'])
        ? j['pattern']
        : 'blank',
    font: j['font'] is String
        ? (j['font'] as String).substring(
            0,
            (j['font'] as String).length.clamp(0, 80),
          )
        : 'Segoe UI',
    fontSize: number(j['fontSize'], 13, 8, 128),
    bold: j['bold'] == true,
    fontWeight: j['fontWeight'] == null
        ? null
        : (number(j['fontWeight'], 400, 100, 900) / 100).round() * 100,
    border: j['border'] == null
        ? null
        : readColor(j['border'], const Color(0xff343834)),
    borderWidth: number(j['borderWidth'], 1, 0, 12),
  );
  NoteStyle clone() => NoteStyle.fromJson(toJson());
}

class JournalSticker {
  final String id;
  String kind, text, image;
  double x, y, width, height, rotation, strokeWidth;
  int layer;
  String listType;
  List<int> checked;
  List<Offset> points;
  NoteStyle style;
  bool deleted;
  DateTime updated;
  JournalSticker({
    String? id,
    this.kind = 'text',
    this.text = '',
    this.image = '',
    this.x = 20,
    this.y = 20,
    this.width = 180,
    this.height = 90,
    this.rotation = 0,
    this.layer = 0,
    this.strokeWidth = 18,
    this.listType = 'bullet',
    List<int>? checked,
    List<Offset>? points,
    NoteStyle? style,
    this.deleted = false,
    DateTime? updated,
  }) : id = id ?? newId(),
       style = style ?? NoteStyle(),
       checked = checked ?? [],
       points = points ?? [],
       updated = updated ?? DateTime.now().toUtc();
  Map<String, dynamic> toJson() => deleted
      ? {'id': id, 'deleted': true, 'updated': updated.toIso8601String()}
      : {
          'id': id,
          'kind': kind,
          'text': text,
          'image': image,
          'x': x,
          'y': y,
          'width': width,
          'height': height,
          'rotation': rotation,
          'layer': layer,
          'strokeWidth': strokeWidth,
          'listType': listType,
          'checked': checked,
          'points': points.map((p) => [p.dx, p.dy]).toList(),
          'style': style.toJson(),
          'updated': updated.toIso8601String(),
        };
  factory JournalSticker.fromJson(Map<String, dynamic> j) => JournalSticker(
    id: j['id'],
    kind:
        [
          'text',
          'image',
          'rect',
          'circle',
          'line',
          'grid',
          'dots',
          'note',
          'list',
          'highlight',
        ].contains(j['kind'])
        ? j['kind']
        : 'text',
    text: j['text'] is String ? j['text'] : '',
    image: j['image'] is String ? j['image'] : '',
    x: number(j['x'], 20, 0, 420),
    y: number(j['y'], 20, 0, 3600),
    width: number(j['width'], 180, 4, 420),
    height: number(j['height'], 90, 4, 3600),
    rotation: number(j['rotation'], 0, -360, 360),
    layer: number(j['layer'], 0, -1000000, 1000000).round(),
    strokeWidth: number(j['strokeWidth'], 18, 1, 96),
    listType: ['bullet', 'number', 'check'].contains(j['listType'])
        ? j['listType']
        : 'bullet',
    checked: (j['checked'] as List? ?? [])
        .whereType<int>()
        .where((i) => i >= 0 && i < 50000)
        .toList(),
    points: (j['points'] as List? ?? [])
        .whereType<List>()
        .where((p) => p.length == 2)
        .take(8000)
        .map((p) => Offset(number(p[0], 0, 0, 1), number(p[1], 0, 0, 1)))
        .toList(),
    style: NoteStyle.fromJson(object(j['style'])),
    deleted: j['deleted'] == true,
    updated: DateTime.tryParse(j['updated'] ?? '') ?? _journalEpoch,
  );
}

List<JournalSticker> journalItems(dynamic values) =>
    (values as List? ?? []).asMap().entries.map((entry) {
      final data = object(entry.value),
          item = JournalSticker.fromJson(object(entry.value));
      if (!data.containsKey('layer')) item.layer = entry.key + 1;
      return item;
    }).toList();

class JournalDay {
  String text;
  double height;
  bool autoHeight;
  NoteStyle style;
  List<JournalSticker> stickers;
  DateTime updated;
  JournalDay({
    this.text = '',
    this.height = 64,
    this.autoHeight = true,
    NoteStyle? style,
    List<JournalSticker>? stickers,
    DateTime? updated,
  }) : style = style ?? NoteStyle(),
       stickers = stickers ?? [],
       updated = updated ?? _journalEpoch;
  Map<String, dynamic> toJson() => {
    'text': text,
    'height': height,
    'autoHeight': autoHeight,
    'style': style.toJson(),
    'stickers': stickers.map((e) => e.toJson()).toList(),
    'updated': updated.toIso8601String(),
  };
  factory JournalDay.fromJson(Map<String, dynamic> j) => JournalDay(
    text: j['text'] is String ? j['text'] : '',
    height: number(j['height'], 64, 64, 1200),
    autoHeight: j['autoHeight'] != false,
    style: NoteStyle.fromJson(object(j['style'])),
    stickers: journalItems(j['stickers']),
    updated: DateTime.tryParse(j['updated'] ?? ''),
  );
}

class JournalWeek {
  final String key;
  Map<String, JournalDay> days;
  List<JournalSticker> board;
  NoteStyle style;
  double height;
  DateTime updated;
  JournalWeek(
    this.key, {
    Map<String, JournalDay>? days,
    List<JournalSticker>? board,
    NoteStyle? style,
    this.height = 512,
    DateTime? updated,
  }) : days = days ?? {},
       board = board ?? [],
       style = style ?? NoteStyle(paper: Colors.white),
       updated = updated ?? _journalEpoch;
  JournalDay day(String date) => days.putIfAbsent(date, () => JournalDay());
  Map<String, dynamic> toJson() => {
    'days': days.map((key, value) => MapEntry(key, value.toJson())),
    'board': board.map((e) => e.toJson()).toList(),
    'style': style.toJson(),
    'height': height,
    'updated': updated.toIso8601String(),
  };
  factory JournalWeek.fromJson(String key, Map<String, dynamic> j) =>
      JournalWeek(
        key,
        days: object(j['days']).map(
          (date, value) => MapEntry(date, JournalDay.fromJson(object(value))),
        ),
        board: journalItems(j['board']),
        style: (() {
          final value = NoteStyle.fromJson(object(j['style']));
          if (value.paper == const Color(0xfffaf9f5)) {
            value.paper = Colors.white;
          }
          return value;
        })(),
        height: number(j['height'], 512, 320, 3600),
        updated: DateTime.tryParse(j['updated'] ?? ''),
      );
  JournalWeek clone() => JournalWeek.fromJson(key, toJson());
}

JournalWeek mergeJournalWeeks(JournalWeek local, JournalWeek remote) {
  List<JournalSticker> items(List<JournalSticker> a, List<JournalSticker> b) {
    final result = {for (final item in b) item.id: item};
    for (final item in a) {
      if (result[item.id] == null ||
          !item.updated.isBefore(result[item.id]!.updated)) {
        result[item.id] = item;
      }
    }
    return result.values.toList();
  }

  final latest = local.updated.isBefore(remote.updated) ? remote : local;
  final result = latest.clone();
  result.board = items(local.board, remote.board);
  result.days = {...remote.days};
  for (final entry in local.days.entries) {
    final other = remote.days[entry.key];
    if (other == null) {
      result.days[entry.key] = JournalDay.fromJson(entry.value.toJson());
      continue;
    }
    final day = JournalDay.fromJson(
      (entry.value.updated.isBefore(other.updated) ? other : entry.value)
          .toJson(),
    );
    day.stickers = items(entry.value.stickers, other.stickers);
    result.days[entry.key] = day;
  }
  return result;
}

String dateLabel(DateTime date) =>
    '${date.month}月${date.day}日 · 周${['一', '二', '三', '四', '五', '六', '日'][date.weekday - 1]}';
String periodLabel(String scope, DateTime date) {
  if (scope == 'month') return '${date.year}年 ${date.month}月';
  if (scope == 'week') {
    final start = dayOnly(date).subtract(Duration(days: date.weekday - 1)),
        end = dayOnly(date).add(Duration(days: 7 - date.weekday));
    return '${start.month}月${start.day}日 — ${end.month}月${end.day}日';
  }
  return '${date.month}月${date.day}日';
}
