import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';

import '../model.dart';
import '../platform_services.dart';
import '../store.dart';
import 'components.dart';
import 'settings.dart';
part 'journal_elements.dart';

const _paper = Colors.white, _rule = Color(0xffe1e3e5);
const _notes = <String, Color>{
  '奶油黄': Color(0xffffefb3),
  '雾蓝': Color(0xffdceaf3),
  '鼠尾草': Color(0xffe1eadc),
  '樱花粉': Color(0xfff6dfe4),
  '淡紫': Color(0xffe9e1f3),
  '米杏': Color(0xfff2e6d9),
};
const _patterns = {'blank': '空白', 'dots': '圆点', 'grid': '方格', 'lines': '横线'};
const _fontSizes = [
  8,
  10,
  12,
  13,
  14,
  16,
  18,
  20,
  24,
  28,
  32,
  36,
  48,
  64,
  96,
  128,
];
const _fonts = {
  'Segoe UI': '系统',
  'SimSun': '宋体',
  'KaiTi': '楷体',
  'Consolas': '等宽',
};
const _kinds = {
  'text': '文本',
  'rect': '方框',
  'circle': '圆形',
  'line': '横线',
  'grid': '方格贴纸',
  'dots': '圆点贴纸',
  'image': '图片',
};

TextStyle _noteFont(NoteStyle style, double scale) => TextStyle(
  fontFamily: style.font,
  fontFamilyFallback: const ['PingFang SC', 'Microsoft YaHei UI', 'Segoe UI'],
  fontSize: math.max(1, style.fontSize * scale),
  fontWeight:
      FontWeight.values[(style.fontWeight / 100).round().clamp(1, 9) - 1],
  color: style.ink,
  height: 1.6,
);

class JournalWorkspace extends StatefulWidget {
  final AppStore store;
  final Color accent;
  final DesktopController? desktop;
  final DateTime? initialDate;
  const JournalWorkspace({
    super.key,
    required this.store,
    required this.accent,
    this.desktop,
    this.initialDate,
  });
  @override
  State<JournalWorkspace> createState() => _JournalWorkspaceState();
}

class _JournalWorkspaceState extends State<JournalWorkspace>
    with WidgetsBindingObserver {
  late DateTime start;
  late JournalWeek draft;
  String? selectedDay, selectedSticker;
  bool boardPage = false, dirty = false, saving = false;
  String? error;
  Timer? timer;
  bool highlighting = false;
  bool selecting = true;
  String? editingSticker;
  JournalWeek? seenSource;
  final Map<String, GlobalKey> canvasKeys = {};
  final FocusNode journalFocus = FocusNode();
  List<(String?, JournalSticker)> get allObjects => [
    for (final date in dates)
      for (final entry in orderedJournalItems(draft.day(dayKey(date)).stickers))
        (dayKey(date), entry),
    for (final entry in orderedJournalItems(draft.board)) (null, entry),
  ];
  Color markerColor = const Color(0x66efcf58);
  double markerWidth = 18;
  double get weekContentHeight => dates.fold(
    0.0,
    (height, date) => height + draft.day(dayKey(date)).height + 8,
  );
  double get pageContentHeight => math.max(draft.height, weekContentHeight);
  late final Future<void> Function() flushHandler = flush;
  String get key => dayKey(start);
  List<DateTime> get dates =>
      List.generate(7, (i) => DateTime(start.year, start.month, start.day + i));
  List<JournalSticker> get items =>
      selectedDay == null ? draft.board : draft.day(selectedDay!).stickers;
  JournalSticker? get item =>
      items.where((e) => e.id == selectedSticker && !e.deleted).firstOrNull;
  NoteStyle get style =>
      item?.style ??
      (selectedDay == null ? draft.style : draft.day(selectedDay!).style);
  @override
  void initState() {
    super.initState();
    final now = dayOnly(widget.initialDate ?? DateTime.now());
    start = DateTime(now.year, now.month, now.day - now.weekday + 1);
    selectedDay = dayKey(now);
    load();
    widget.store.addListener(refresh);
    widget.store.onFlushDrafts = flushHandler;
    WidgetsBinding.instance.addObserver(this);
  }

  void load() {
    seenSource = widget.store.document.journals[key];
    draft =
        widget.store.pendingJournals[key]?.clone() ??
        widget.store.document.journals[key]?.clone() ??
        JournalWeek(key);
    dirty = widget.store.pendingJournals.containsKey(key);
    for (final date in dates) {
      draft.day(dayKey(date));
    }
  }

  void refresh() {
    if (!mounted || dirty || saving) return;
    final incoming = widget.store.document.journals[key];
    if (incoming != null && !identical(incoming, seenSource)) {
      setState(load);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) unawaited(flush());
  }

  @override
  void dispose() {
    timer?.cancel();
    if (dirty) unawaited(flush());
    if (widget.store.onFlushDrafts == flushHandler) {
      widget.store.onFlushDrafts = null;
    }
    widget.store.removeListener(refresh);
    WidgetsBinding.instance.removeObserver(this);
    journalFocus.dispose();
    super.dispose();
  }

  void changed({bool save = true}) {
    dirty = true;
    widget.store.bufferJournal(draft);
    if (mounted) setState(() => error = null);
    timer?.cancel();
    if (save) {
      timer = Timer(
        const Duration(milliseconds: 450),
        () => unawaited(flush()),
      );
    }
  }

  Future<void> flush() async {
    timer?.cancel();
    if (!dirty) return;
    final snapshot = draft.clone();
    final version = widget.store.pendingJournalVersions[snapshot.key] ?? 0;
    dirty = false;
    saving = true;
    try {
      await widget.store.dispatch({
        'type': 'journal',
        'week': snapshot.key,
        'value': snapshot.toJson(),
      });
      if ((widget.store.pendingJournalVersions[snapshot.key] ?? 0) == version) {
        widget.store.pendingJournals.remove(snapshot.key);
        widget.store.pendingJournalVersions.remove(snapshot.key);
        if (key == snapshot.key) {
          seenSource = widget.store.document.journals[key];
        }
      }
    } catch (e) {
      dirty = true;
      error = e.toString().replaceFirst('Exception: ', '');
    } finally {
      saving = false;
      if (mounted) setState(() {});
    }
  }

  Future<void> turn(DateTime date) async {
    await flush();
    if (error != null || !mounted) return;
    setState(() {
      final day = dayOnly(date);
      start = DateTime(day.year, day.month, day.day - day.weekday + 1);
      selectedDay = dayKey(day);
      selectedSticker = null;
      load();
    });
  }

  void select(String? day, [String? id, bool edit = false]) {
    if (!edit) FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      selectedDay = day;
      selectedSticker = id;
      selecting = !edit;
      editingSticker = edit ? id : null;
      highlighting = false;
    });
    if (!edit) journalFocus.requestFocus();
  }

  void deleteSelection() {
    final entry = item;
    if (entry == null) return;
    FocusManager.instance.primaryFocus?.unfocus();
    entry.deleted = true;
    entry.updated = DateTime.now().toUtc();
    entry.image = '';
    entry.points = [];
    selectedSticker = null;
    editingSticker = null;
    selecting = true;
    changed();
    journalFocus.requestFocus();
  }

  void writeSelection(String? day, String? id) {
    select(day, id, true);
    if (item != null &&
        !['text', 'note', 'list'].contains(item!.kind) &&
        item!.text.isEmpty) {
      unawaited(properties());
    }
  }

  String objectName(JournalSticker entry) {
    const names = {'note': '便签', 'list': '列表', 'highlight': '笔迹', ..._kinds};
    final text = entry.text.split('\n').first.trim();
    return '${names[entry.kind]}${text.isEmpty ? '' : ' · ${text.length > 14 ? '${text.substring(0, 14)}…' : text}'}';
  }

  void dropObject(
    String? source,
    JournalSticker entry,
    Offset global,
    Offset grab,
  ) {
    for (final region in [for (final date in dates) dayKey(date), 'board']) {
      final box = canvasKeys[region]?.currentContext?.findRenderObject();
      if (box is! RenderBox) continue;
      final point = box.globalToLocal(global);
      if (!box.size.contains(point)) continue;
      final destination = region == 'board' ? null : region;
      if (destination == source) return;
      final moved = JournalSticker.fromJson(entry.toJson());
      final target = destination == null
          ? draft.board
          : draft.day(destination).stickers;
      final areaWidth = destination == null ? 420.0 : 360.0;
      final scale = box.size.width / areaWidth;
      if (moved.width > areaWidth) {
        moved.height *= areaWidth / moved.width;
        moved.width = areaWidth;
      }
      moved.x = (point.dx / scale - grab.dx)
          .clamp(0, areaWidth - moved.width)
          .toDouble();
      moved.y = (point.dy / scale - grab.dy)
          .clamp(0, (destination == null ? 3600 : 1200) - moved.height)
          .toDouble();
      moved.layer =
          target
              .where((e) => !e.deleted)
              .fold(0, (value, e) => math.max(value, e.layer)) +
          1;
      moved.updated = DateTime.now().toUtc();
      entry.deleted = true;
      entry.updated = moved.updated;
      target.add(moved);
      selectedDay = destination;
      selectedSticker = moved.id;
      editingSticker = null;
      selecting = true;
      grow(moved);
      if (source != null && draft.day(source).autoHeight) {
        fitDay(draft.day(source));
      }
      changed();
      return;
    }
  }

  void markStyle() {
    if (selectedDay != null &&
        item == null &&
        draft.day(selectedDay!).autoHeight) {
      fitDay(draft.day(selectedDay!));
    }
    final now = DateTime.now().toUtc();
    if (item != null) {
      item!.updated = now;
    } else if (selectedDay != null) {
      draft.day(selectedDay!).updated = now;
    } else {
      draft.updated = now;
    }
    changed();
  }

  Future<void> colour(String target) async {
    await widget.desktop?.editing(true);
    try {
      if (!mounted) return;
      final result = await showPanel<Color>(
        context,
        target == 'paper'
            ? '区域底色'
            : target == 'border'
            ? '边框颜色'
            : item?.kind == 'highlight'
            ? '笔迹颜色'
            : '字体颜色',
        ColorEditor(
          initial: target == 'paper'
              ? (style.paper.a == 0
                    ? style.paper.withValues(alpha: 1)
                    : style.paper)
              : target == 'border'
              ? style.edge
              : style.ink,
          onPreview: (_) {},
        ),
        width: 360,
      );
      if (result == null || !mounted) return;
      if (target == 'paper') {
        style.paper = result;
      } else if (target == 'border') {
        if (style.border == null && style.borderWidth == 0 && result.a > 0) {
          style.borderWidth = 1;
        }
        style.border = result;
      } else {
        style.ink = result;
      }
      markStyle();
    } finally {
      await widget.desktop?.editing(false);
    }
  }

  Future<void> customFont() async {
    var family = style.font;
    final value = await showPanel<String>(
      context,
      '字体',
      Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextFormField(
            initialValue: family,
            onChanged: (value) => family = value,
            maxLength: 80,
            decoration: const InputDecoration(labelText: '已安装的字体名称'),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: () => Navigator.pop(context, family.trim()),
            child: const Text('使用字体'),
          ),
        ],
      ),
      width: 340,
    );
    if (value != null && value.isNotEmpty && mounted) {
      style.font = value;
      markStyle();
    }
  }

  Future<void> customSize() async {
    var size = '${style.fontSize}';
    final form = GlobalKey<FormState>();
    final result = await showPanel<double>(
      context,
      '字号',
      Form(
        key: form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              initialValue: size,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(labelText: '字号'),
              onChanged: (v) => size = v,
              validator: (v) {
                final n = double.tryParse(v ?? '');
                return n != null && n.isFinite && n >= 8 && n <= 128
                    ? null
                    : '请输入 8–128';
              },
            ),
            const SizedBox(height: 14),
            FilledButton(
              onPressed: () {
                if (form.currentState!.validate()) {
                  Navigator.pop(context, double.parse(size));
                }
              },
              child: const Text('完成'),
            ),
          ],
        ),
      ),
      width: 320,
    );
    if (result == null || !mounted) return;
    style.fontSize = result;
    markStyle();
  }

  Future<void> properties() async {
    final initial = item;
    if (initial == null) return;
    var width = '${initial.width}',
        height = '${initial.height}',
        stroke =
            '${initial.kind == 'highlight' ? initial.strokeWidth : initial.style.borderWidth}',
        rotation = '${initial.rotation}',
        text = initial.text;
    final maxWidth = selectedDay == null ? 420.0 : 360.0;
    final form = GlobalKey<FormState>();
    Widget value(
      String label,
      String initial,
      ValueChanged<String> update,
      double min,
      double max,
    ) => TextFormField(
      key: ValueKey('sticker-property-$label'),
      initialValue: initial,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(labelText: label),
      onChanged: update,
      validator: (v) {
        final n = double.tryParse(v ?? '');
        return n != null && n.isFinite && n >= min && n <= max
            ? null
            : '请输入 $min–$max';
      },
    );
    final result = await showPanel<bool>(
      context,
      initial.kind == 'highlight' ? '大小与线宽' : '大小与文字',
      Form(
        key: form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: value('宽度', width, (v) => width = v, 4, maxWidth),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: value('高度', height, (v) => height = v, 4, 1200),
                ),
              ],
            ),
            const SizedBox(height: 12),
            value(
              initial.kind == 'highlight' ? '线宽' : '边框粗细',
              stroke,
              (v) => stroke = v,
              initial.kind == 'highlight' ? 1 : 0,
              initial.kind == 'highlight' ? 96 : 12,
            ),
            const SizedBox(height: 12),
            value('旋转角度', rotation, (v) => rotation = v, -360, 360),
            const SizedBox(height: 12),
            if (initial.kind != 'highlight')
              TextFormField(
                key: const ValueKey('sticker-property-text'),
                initialValue: text,
                minLines: 2,
                maxLines: 5,
                maxLength: 50000,
                decoration: const InputDecoration(
                  labelText: '文字',
                  counterText: '',
                ),
                onChanged: (v) => text = v,
              ),
            const SizedBox(height: 14),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: () {
                  if (form.currentState!.validate()) {
                    Navigator.pop(context, true);
                  }
                },
                child: const Text('完成'),
              ),
            ),
          ],
        ),
      ),
      width: 360,
    );
    if (result != true || !mounted) return;
    final entry = item;
    if (entry == null || entry.id != initial.id) return;
    entry.width = double.parse(width);
    entry.height = double.parse(height);
    entry.x = entry.x.clamp(0, maxWidth - entry.width).toDouble();
    entry.y = entry.y
        .clamp(0, (selectedDay == null ? 3600 : 1200) - entry.height)
        .toDouble();
    if (entry.kind == 'highlight') {
      entry.strokeWidth = double.parse(stroke);
    } else {
      entry.style.borderWidth = double.parse(stroke);
    }
    entry.rotation = double.parse(rotation);
    entry.text = text;
    entry.updated = DateTime.now().toUtc();
    grow(entry);
    changed();
  }

  Future<void> add(
    String kind, {
    Offset? position,
    Color? paper,
    String listType = 'bullet',
  }) async {
    String image = '';
    if (kind == 'image') {
      await widget.desktop?.editing(true);
      try {
        if (!mounted) return;
        image = await pickImage(context) ?? '';
      } catch (e) {
        if (mounted) {
          setState(() => error = e.toString().replaceFirst('Exception: ', ''));
        }
        return;
      } finally {
        await widget.desktop?.editing(false);
      }
      if (image.isEmpty || !mounted) return;
    }
    final entry = JournalSticker(
      kind: kind,
      image: image,
      layer:
          items
              .where((e) => !e.deleted)
              .fold(0, (value, e) => math.max(value, e.layer)) +
          1,
      listType: listType,
      style: style.clone(),
      x: position?.dx ?? 16,
      y: position?.dy ?? 16,
      width: ['text', 'note', 'list'].contains(kind)
          ? 210
          : kind == 'line'
          ? 160
          : 110,
      height: kind == 'line'
          ? 24
          : kind == 'text'
          ? 86
          : 110,
    );
    final areaWidth = selectedDay == null ? 420.0 : 360.0;
    entry.x = entry.x.clamp(0, areaWidth - entry.width).toDouble();
    if (kind == 'note') {
      entry.style.paper = paper ?? _notes.values.first;
      entry.style.border = null;
      entry.style.borderWidth = 0;
      entry.height = 130;
    } else if (kind == 'list') {
      entry.style.paper = Colors.transparent;
      entry.style.border = null;
      entry.height = 100;
    } else if (kind != 'text') {
      entry.style.border = kind == 'image' ? null : widget.accent;
      entry.style.paper = Colors.transparent;
    }
    items.add(entry);
    selectedSticker = entry.id;
    selecting = !['text', 'note', 'list'].contains(kind);
    editingSticker = selecting ? null : entry.id;
    grow(entry);
    changed();
  }

  void reorder(String action) {
    final entry = item;
    if (entry == null) return;
    final ordered = orderedJournalItems(items),
        index = ordered.indexWhere((e) => e.id == entry.id);
    final target = action == 'front'
        ? ordered.length - 1
        : action == 'back'
        ? 0
        : (index + (action == 'up' ? 1 : -1)).clamp(0, ordered.length - 1);
    ordered.removeAt(index);
    ordered.insert(target, entry);
    final now = DateTime.now().toUtc();
    bool foreground = false;
    for (var i = 0; i < ordered.length; i++) {
      if (ordered[i].kind != 'highlight' ||
          (ordered[i].id == entry.id && action == 'front')) {
        foreground = true;
      }
      final layer = foreground ? i + 1 : i - ordered.length;
      if (ordered[i].layer != layer) {
        ordered[i].layer = layer;
        ordered[i].updated = now;
      }
    }
    changed();
  }

  Future<void> rotateSelection() async {
    final id = item?.id;
    if (id == null) return;
    var angle = '${item!.rotation.round()}';
    final form = GlobalKey<FormState>();
    final result = await showPanel<double>(
      context,
      '旋转',
      Form(
        key: form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              initialValue: angle,
              decoration: const InputDecoration(labelText: '角度'),
              keyboardType: const TextInputType.numberWithOptions(
                signed: true,
                decimal: true,
              ),
              onChanged: (v) => angle = v,
              validator: (v) {
                final value = double.tryParse(v ?? '');
                return value != null && value.isFinite && value.abs() <= 360
                    ? null
                    : '请输入 -360–360';
              },
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () {
                if (form.currentState!.validate()) {
                  Navigator.pop(context, double.parse(angle));
                }
              },
              child: const Text('完成'),
            ),
          ],
        ),
      ),
      width: 300,
    );
    if (result == null || !mounted || item?.id != id) return;
    item!.rotation = result;
    markStyle();
  }

  Future<void> chooseMarkerColor() async {
    final value = await showPanel<Color>(
      context,
      '荧光笔颜色',
      ColorEditor(initial: markerColor, onPreview: (_) {}),
      width: 360,
    );
    if (value != null && mounted) setState(() => markerColor = value);
  }

  void grow(JournalSticker entry) {
    final bottom = (entry.y + entry.height + 12).clamp(64, 3600).toDouble();
    if (selectedDay == null) {
      if (bottom > draft.height) {
        draft.height = bottom;
        draft.updated = DateTime.now().toUtc();
      }
    } else {
      final day = draft.day(selectedDay!);
      if (bottom > day.height) {
        day.height = bottom.clamp(64, 1200).toDouble();
        day.updated = DateTime.now().toUtc();
      }
    }
  }

  void editText(String date, String text) {
    final day = draft.day(date);
    day.text = text;
    day.updated = DateTime.now().toUtc();
    if (day.autoHeight) fitDay(day);
    changed();
  }

  void fitDay(JournalDay day) {
    final painter = TextPainter(
      text: TextSpan(
        text: day.text.isEmpty ? ' ' : day.text,
        style: _noteFont(day.style, 1),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: 344);
    day.height = math.max(64, painter.height + 24).clamp(64, 1200).toDouble();
    for (final entry in day.stickers.where((e) => !e.deleted)) {
      day.height = math
          .max(day.height, entry.y + entry.height + 12)
          .clamp(64, 1200)
          .toDouble();
    }
  }

  Widget menu(
    String label,
    Map<String, String> values,
    String current,
    ValueChanged<String> choose,
  ) => PopupMenuButton<String>(
    tooltip: label,
    initialValue: current,
    color: Colors.white,
    surfaceTintColor: Colors.transparent,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    onSelected: choose,
    itemBuilder: (_) => values.entries
        .map(
          (e) => PopupMenuItem(
            value: e.key,
            height: 38,
            child: Text(
              e.value,
              style: TextStyle(
                fontSize: 12,
                color: e.key == current ? widget.accent : ink,
              ),
            ),
          ),
        )
        .toList(),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 100),
            child: Text(
              current.isEmpty ? label : (values[current] ?? current),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12),
            ),
          ),
          const SizedBox(width: 5),
          const Icon(CupertinoIcons.chevron_down, size: 10, color: muted),
        ],
      ),
    ),
  );
  Widget icon(
    IconData icon,
    String label,
    VoidCallback action, {
    Color? color,
  }) => IconButton(
    tooltip: label,
    onPressed: action,
    visualDensity: VisualDensity.compact,
    iconSize: 17,
    color: color ?? ink,
    padding: const EdgeInsets.all(7),
    constraints: const BoxConstraints(minHeight: 32, minWidth: 32),
    icon: Icon(icon),
  );
  Widget toolbar() => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
    child: Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 3,
      runSpacing: 1,
      children: [
        PopupMenuButton<String>(
          tooltip: '选择对象',
          enabled: allObjects.isNotEmpty,
          color: Colors.white,
          surfaceTintColor: Colors.transparent,
          onSelected: (id) {
            final choice = allObjects.firstWhere((e) => e.$2.id == id);
            select(choice.$1, id);
            setState(() => boardPage = choice.$1 == null);
          },
          itemBuilder: (_) => allObjects
              .map(
                (choice) => PopupMenuItem(
                  value: choice.$2.id,
                  height: 38,
                  child: Text(
                    '${choice.$1 == null ? '右页' : '${int.parse(choice.$1!.substring(5, 7))}月${int.parse(choice.$1!.substring(8))}日'} · ${objectName(choice.$2)}',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              )
              .toList(),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: const Color(0xffeff0f2),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 145),
                  child: Text(
                    item == null ? '选择对象' : objectName(item!),
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(CupertinoIcons.chevron_down, size: 10, color: muted),
              ],
            ),
          ),
        ),
        TextButton(
          onPressed: () => select(selectedDay, selectedSticker),
          child: Text(
            '选择',
            style: TextStyle(
              fontSize: 12,
              color: selecting && !highlighting ? widget.accent : muted,
            ),
          ),
        ),
        TextButton(
          onPressed: () => writeSelection(selectedDay, selectedSticker),
          child: Text(
            '书写',
            style: TextStyle(
              fontSize: 12,
              color: !selecting && !highlighting ? widget.accent : muted,
            ),
          ),
        ),
        if (!highlighting && item?.kind != 'highlight') ...[
          menu(
            '字体',
            {
              ..._fonts,
              if (!_fonts.containsKey(style.font)) style.font: style.font,
              'custom': '自定义字体…',
            },
            style.font,
            (v) {
              if (v == 'custom') {
                unawaited(customFont());
              } else {
                style.font = v;
                markStyle();
              }
            },
          ),
          menu(
            '字号',
            {
              for (final n in _fontSizes) '$n': '$n',
              if (!_fontSizes.contains(style.fontSize))
                '${style.fontSize}': '${style.fontSize}',
              'custom': '自定义字号…',
            },
            style.fontSize % 1 == 0
                ? '${style.fontSize.round()}'
                : '${style.fontSize}',
            (v) {
              if (v == 'custom') {
                unawaited(customSize());
              } else {
                style.fontSize = double.parse(v);
                markStyle();
              }
            },
          ),
          menu(
            '字体粗细',
            const {
              '100': '极细',
              '200': '纤细',
              '300': '细体',
              '400': '常规',
              '500': '中等',
              '600': '半粗',
              '700': '粗体',
              '800': '特粗',
              '900': '黑体',
            },
            '${style.fontWeight}',
            (v) {
              style.fontWeight = int.parse(v);
              markStyle();
            },
          ),
        ],
        if (!highlighting)
          icon(
            CupertinoIcons.textformat,
            item?.kind == 'highlight' ? '笔迹颜色' : '字体颜色',
            () => unawaited(colour('ink')),
            color: style.ink,
          ),
        if (!highlighting && item?.kind != 'highlight')
          Tooltip(
            message: '区域底色',
            child: InkWell(
              borderRadius: BorderRadius.circular(6),
              onTap: () => unawaited(colour('paper')),
              child: Padding(
                padding: const EdgeInsets.all(7),
                child: Container(
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(
                    color: Color.alphaBlend(style.paper, _paper),
                    border: Border.all(
                      color: muted.withValues(alpha: .6),
                      width: .8,
                    ),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
            ),
          ),
        if (item != null) ...[
          if (item!.kind != 'highlight')
            icon(
              CupertinoIcons.rectangle,
              '边框颜色',
              () => unawaited(colour('border')),
              color: style.edge,
            ),
          icon(
            CupertinoIcons.slider_horizontal_3,
            item!.kind == 'highlight' ? '大小与线宽' : '大小与文字',
            () => unawaited(properties()),
          ),
        ],
        if (item == null)
          menu('纸张背景', _patterns, style.pattern, (v) {
            style.pattern = v;
            markStyle();
          }),
        PopupMenuButton<String>(
          tooltip: '添加贴纸或文本',
          color: Colors.white,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          onSelected: (v) => unawaited(add(v)),
          itemBuilder: (_) => _kinds.entries
              .where((e) => e.key != 'image')
              .map(
                (e) => PopupMenuItem(
                  value: e.key,
                  height: 38,
                  child: Text(e.value, style: const TextStyle(fontSize: 12)),
                ),
              )
              .toList(),
          child: const Padding(
            padding: EdgeInsets.all(8),
            child: Icon(CupertinoIcons.add, size: 18),
          ),
        ),
        icon(CupertinoIcons.photo, '上传图片贴纸', () => unawaited(add('image'))),
        PopupMenuButton<String>(
          tooltip: '便签纸',
          surfaceTintColor: Colors.transparent,
          color: Colors.white,
          onSelected: (name) => unawaited(add('note', paper: _notes[name])),
          itemBuilder: (_) => _notes.entries
              .map(
                (e) => PopupMenuItem(
                  value: e.key,
                  height: 38,
                  child: Row(
                    children: [
                      Container(width: 16, height: 16, color: e.value),
                      const SizedBox(width: 12),
                      Text(e.key, style: const TextStyle(fontSize: 12)),
                    ],
                  ),
                ),
              )
              .toList(),
          child: const Padding(
            padding: EdgeInsets.all(8),
            child: Icon(CupertinoIcons.square, size: 17),
          ),
        ),
        PopupMenuButton<String>(
          tooltip: '快速列表',
          surfaceTintColor: Colors.transparent,
          color: Colors.white,
          onSelected: (value) => unawaited(add('list', listType: value)),
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'bullet', child: Text('圆点列表')),
            PopupMenuItem(value: 'number', child: Text('数字列表')),
            PopupMenuItem(value: 'check', child: Text('勾选列表')),
          ],
          child: const Padding(
            padding: EdgeInsets.all(8),
            child: Icon(CupertinoIcons.list_bullet, size: 17),
          ),
        ),
        icon(CupertinoIcons.pencil, highlighting ? '退出荧光笔' : '荧光笔', () {
          FocusManager.instance.primaryFocus?.unfocus();
          setState(() {
            highlighting = !highlighting;
            selecting = true;
            editingSticker = null;
            if (highlighting) selectedSticker = null;
          });
        }, color: highlighting ? widget.accent : ink),
        if (highlighting) ...[
          icon(
            CupertinoIcons.circle_fill,
            '荧光笔颜色',
            () => unawaited(chooseMarkerColor()),
            color: markerColor.withValues(alpha: 1),
          ),
          menu(
            '笔宽',
            const {'6': '6', '12': '12', '18': '18', '24': '24', '36': '36'},
            '${markerWidth.round()}',
            (v) => setState(() => markerWidth = double.parse(v)),
          ),
        ],
        if (items.any((e) => !e.deleted))
          PopupMenuButton<String>(
            tooltip: '图层顺序',
            color: Colors.white,
            surfaceTintColor: Colors.transparent,
            onSelected: (value) {
              if (value.startsWith('item:')) {
                select(selectedDay, value.substring(5));
              } else {
                reorder(value);
              }
            },
            itemBuilder: (_) {
              final ordered = orderedJournalItems(items).reversed.toList();
              const names = {
                'note': '便签纸',
                'list': '列表',
                'highlight': '荧光笔',
                ..._kinds,
              };
              return [
                if (item != null) ...[
                  for (final e in const {
                    'front': '置于顶层',
                    'up': '上移一层',
                    'down': '下移一层',
                    'back': '置于底层',
                  }.entries)
                    PopupMenuItem(
                      value: e.key,
                      height: 36,
                      child: Text(
                        e.value,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  const PopupMenuDivider(),
                ],
                for (var i = 0; i < ordered.length; i++)
                  PopupMenuItem(
                    value: 'item:${ordered[i].id}',
                    height: 36,
                    child: Text(
                      '${names[ordered[i].kind]} · ${i + 1}',
                      style: TextStyle(
                        fontSize: 12,
                        color: ordered[i].id == selectedSticker
                            ? widget.accent
                            : ink,
                      ),
                    ),
                  ),
              ];
            },
            child: const Padding(
              padding: EdgeInsets.all(8),
              child: Icon(CupertinoIcons.square_stack, size: 17),
            ),
          ),
        if (item != null) ...[
          icon(
            CupertinoIcons.rotate_right,
            '旋转',
            () => unawaited(rotateSelection()),
          ),
        ],
        if (item != null) icon(CupertinoIcons.trash, '删除贴纸', deleteSelection),
        if (selectedDay != null && item == null)
          icon(CupertinoIcons.arrow_up_down, '按内容调整高度', () {
            final day = draft.day(selectedDay!);
            day.autoHeight = true;
            fitDay(day);
            day.updated = DateTime.now().toUtc();
            changed();
          }),
      ],
    ),
  );
  Widget canvas(
    String? date,
    double scale,
    double width,
    double height, {
    Widget? text,
  }) {
    final region = date == null ? draft.style : draft.day(date).style;
    final elements = date == null ? draft.board : draft.day(date).stickers;
    return JournalCanvas(
      key: ValueKey('journal-canvas-${date ?? 'board'}'),
      style: region,
      items: elements,
      selectedId: selectedDay == date ? selectedSticker : null,
      accent: widget.accent,
      scale: scale,
      width: width,
      height: height,
      text: text,
      regionKey: canvasKeys.putIfAbsent(date ?? 'board', GlobalKey.new),
      editing: !selecting && selectedDay == date
          ? (editingSticker ?? 'base')
          : null,
      editItem: (id) => writeSelection(date, id),
      drop: (entry, global, grab) => dropObject(date, entry, global, grab),
      drawing: highlighting,
      markerColor: markerColor,
      markerWidth: markerWidth,
      addStroke: (entry) {
        selectedDay = date;
        (date == null ? draft.board : draft.day(date).stickers).add(entry);
        selectedSticker = entry.id;
        grow(entry);
        changed();
      },
      select: (id) => select(date, id),
      writeAt: date == null
          ? (point) {
              select(null);
              unawaited(add('text', position: point));
            }
          : null,
      update: (entry, {bool save = true}) {
        selectedDay = date;
        selectedSticker = entry.id;
        entry.updated = DateTime.now().toUtc();
        grow(entry);
        changed(save: save);
      },
      finish: () => changed(),
    );
  }

  Widget weekPage(double width) {
    final scale = width / 420;
    return DecoratedBox(
      key: const ValueKey('journal-week-page'),
      decoration: BoxDecoration(
        color: _paper,
        border: Border.all(color: _rule, width: .7),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Column(
        children: [
          SizedBox(
            height: 40 * scale,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 16 * scale),
              child: Row(
                children: [
                  Text(
                    '${start.year}年 ${start.month}月',
                    style: TextStyle(fontSize: 12 * scale, color: muted),
                  ),
                  const Spacer(),
                ],
              ),
            ),
          ),
          for (final date in dates)
            Builder(
              builder: (context) {
                final dateKey = dayKey(date),
                    day = draft.day(dateKey),
                    selected =
                        selectedDay == dateKey && selectedSticker == null;
                return DecoratedBox(
                  key: ValueKey('journal-day-$dateKey'),
                  decoration: BoxDecoration(
                    color: day.style.paper,
                    border: Border(
                      top: const BorderSide(color: _rule, width: .7),
                    ),
                  ),
                  child: Column(
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: 56 * scale,
                            child: InkWell(
                              onTap: () => select(dateKey),
                              child: Padding(
                                padding: EdgeInsets.only(
                                  top: 10 * scale,
                                  bottom: 10 * scale,
                                ),
                                child: Column(
                                  children: [
                                    Text(
                                      '${date.day}',
                                      style: TextStyle(
                                        fontSize: 17 * scale,
                                        fontWeight: FontWeight.w300,
                                        color: ink.withValues(alpha: .62),
                                      ),
                                    ),
                                    Text(
                                      [
                                        'MON',
                                        'TUE',
                                        'WED',
                                        'THU',
                                        'FRI',
                                        'SAT',
                                        'SUN',
                                      ][date.weekday - 1],
                                      style: TextStyle(
                                        fontSize: 8.5 * scale,
                                        fontWeight: FontWeight.w300,
                                        color: muted.withValues(alpha: .8),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          Expanded(
                            child: canvas(
                              dateKey,
                              scale,
                              360 * scale,
                              day.height * scale,
                              text: Padding(
                                padding: EdgeInsets.symmetric(
                                  horizontal: 8 * scale,
                                  vertical: 8 * scale,
                                ),
                                child: JournalText(
                                  key: ValueKey('journal-text-$dateKey'),
                                  text: day.text,
                                  style: _noteFont(day.style, scale),
                                  autofocus:
                                      !selecting &&
                                      editingSticker == null &&
                                      selectedDay == dateKey,
                                  onFocus: () => select(dateKey, null, true),
                                  onChanged: (value) =>
                                      editText(dateKey, value),
                                ),
                              ),
                            ),
                          ),
                          SizedBox(width: 4 * scale),
                        ],
                      ),
                      MouseRegion(
                        cursor: SystemMouseCursors.resizeRow,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onVerticalDragUpdate: (e) {
                            day.autoHeight = false;
                            day.height = (day.height + e.delta.dy / scale)
                                .clamp(64, 1200)
                                .toDouble();
                            day.updated = DateTime.now().toUtc();
                            changed(save: false);
                          },
                          onVerticalDragEnd: (_) => changed(),
                          child: SizedBox(
                            height: 8 * scale,
                            child: Center(
                              child: Container(
                                width: 22,
                                height: 1,
                                color: selected
                                    ? widget.accent.withValues(alpha: .5)
                                    : Colors.transparent,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          SizedBox(
            height:
                (pageContentHeight - weekContentHeight) * scale + 14 * scale,
          ),
        ],
      ),
    );
  }

  Widget freePage(double width) {
    final scale = width / 420;
    return DecoratedBox(
      key: const ValueKey('journal-free-page'),
      decoration: BoxDecoration(
        color: Color.alphaBlend(draft.style.paper, _paper),
        border: Border.all(color: _rule, width: .7),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Column(
        children: [
          SizedBox(
            height: 40 * scale,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => select(null),
            ),
          ),
          canvas(null, scale, width, pageContentHeight * scale),
          MouseRegion(
            cursor: SystemMouseCursors.resizeRow,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onVerticalDragUpdate: (e) {
                draft.height = (draft.height + e.delta.dy / scale)
                    .clamp(320, 3600)
                    .toDouble();
                draft.updated = DateTime.now().toUtc();
                changed(save: false);
              },
              onVerticalDragEnd: (_) => changed(),
              child: SizedBox(
                height: 14 * scale,
                child: Center(
                  child: Container(width: 28, height: 2, color: _rule),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Focus(
    focusNode: journalFocus,
    autofocus: true,
    onKeyEvent: (_, event) {
      if (event is! KeyDownEvent) return KeyEventResult.ignored;
      if (event.logicalKey == LogicalKeyboardKey.escape) {
        select(selectedDay);
        return KeyEventResult.handled;
      }
      if (selecting &&
          item != null &&
          (event.logicalKey == LogicalKeyboardKey.delete ||
              event.logicalKey == LogicalKeyboardKey.backspace)) {
        deleteSelection();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    },
    child: LayoutBuilder(
      builder: (context, c) {
        final wide = c.maxWidth >= 760;
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 6, 8, 3),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${start.month}月${start.day}日 — ${dates.last.month}月${dates.last.day}日',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  icon(
                    CupertinoIcons.chevron_left,
                    '上一周日记',
                    () => unawaited(
                      turn(start.subtract(const Duration(days: 7))),
                    ),
                  ),
                  icon(
                    CupertinoIcons.chevron_right,
                    '下一周日记',
                    () => unawaited(turn(start.add(const Duration(days: 7)))),
                  ),
                  TextButton(
                    onPressed: () => unawaited(turn(DateTime.now())),
                    style: TextButton.styleFrom(
                      minimumSize: const Size(40, 32),
                      padding: const EdgeInsets.symmetric(horizontal: 7),
                    ),
                    child: const Text('本周', style: TextStyle(fontSize: 12)),
                  ),
                ],
              ),
            ),
            if (!wide)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 5,
                ),
                child: CupertinoSlidingSegmentedControl<bool>(
                  groupValue: boardPage,
                  backgroundColor: const Color(0xffe8e9e7),
                  thumbColor: Colors.white,
                  onValueChanged: (value) {
                    if (value != null) {
                      setState(() {
                        boardPage = value;
                        selectedDay = value ? null : dayKey(start);
                        selectedSticker = null;
                      });
                    }
                  },
                  children: const {
                    false: Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: 22,
                        vertical: 5,
                      ),
                      child: Text('本周', style: TextStyle(fontSize: 12)),
                    ),
                    true: Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: 22,
                        vertical: 5,
                      ),
                      child: Text('自由页', style: TextStyle(fontSize: 12)),
                    ),
                  },
                ),
              ),
            toolbar(),
            if (error != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        error!,
                        style: const TextStyle(
                          color: Colors.redAccent,
                          fontSize: 11,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () => unawaited(flush()),
                      child: const Text('重试'),
                    ),
                  ],
                ),
              ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(12, 6, 12, 20),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1120),
                    child: LayoutBuilder(
                      builder: (context, pages) {
                        final width = wide
                            ? (pages.maxWidth - 16) / 2
                            : pages.maxWidth;
                        return wide
                            ? Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(child: weekPage(width)),
                                  const SizedBox(width: 16),
                                  Expanded(child: freePage(width)),
                                ],
                              )
                            : boardPage
                            ? freePage(width)
                            : weekPage(width);
                      },
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    ),
  );
}

class JournalText extends StatefulWidget {
  final String text;
  final TextStyle style;
  final ValueChanged<String> onChanged;
  final VoidCallback onFocus;
  final bool autofocus;
  final bool centered;
  final bool expands;
  final ValueChanged<String>? onSubmitted;
  const JournalText({
    super.key,
    required this.text,
    required this.style,
    required this.onChanged,
    required this.onFocus,
    this.autofocus = false,
    this.centered = false,
    this.expands = true,
    this.onSubmitted,
  });
  @override
  State<JournalText> createState() => _JournalTextState();
}

class _JournalTextState extends State<JournalText> {
  late final controller = TextEditingController(text: widget.text);
  final focus = FocusNode();
  @override
  void didUpdateWidget(JournalText old) {
    super.didUpdateWidget(old);
    if (!focus.hasFocus && controller.text != widget.text) {
      controller.text = widget.text;
    }
    if (widget.autofocus && !old.autofocus) focus.requestFocus();
  }

  @override
  void dispose() {
    controller.dispose();
    focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    focusNode: focus,
    autofocus: widget.autofocus,
    expands: widget.expands,
    maxLines: widget.expands ? null : 1,
    minLines: null,
    maxLength: 50000,
    buildCounter: (
      _, {
      required currentLength,
      required isFocused,
      required maxLength,
    }) => null,
    style: widget.style,
    textAlign: widget.centered ? TextAlign.center : TextAlign.start,
    textAlignVertical: widget.centered
        ? TextAlignVertical.center
        : TextAlignVertical.top,
    cursorColor: widget.style.color,
    scrollPadding: const EdgeInsets.all(64),
    decoration: const InputDecoration(
      filled: false,
      isDense: true,
      contentPadding: EdgeInsets.zero,
      border: InputBorder.none,
      enabledBorder: InputBorder.none,
      focusedBorder: InputBorder.none,
    ),
    onTap: widget.onFocus,
    onChanged: widget.onChanged,
    onSubmitted: widget.onSubmitted,
    textInputAction: widget.expands
        ? TextInputAction.newline
        : TextInputAction.next,
  );
}

class JournalPattern extends CustomPainter {
  final String pattern;
  final Color colour;
  final double scale, strokeWidth;
  JournalPattern(
    this.pattern,
    this.colour,
    this.scale, {
    this.strokeWidth = .65,
  });
  @override
  void paint(Canvas canvas, Size size) {
    if (pattern == 'blank') return;
    final pen = Paint()
      ..color = colour
      ..strokeWidth = strokeWidth;
    final step = (pattern == 'lines' ? 24 : 16) * scale;
    for (double y = step; y < size.height; y += step) {
      if (pattern == 'dots') {
        for (double x = step; x < size.width; x += step) {
          canvas.drawCircle(
            Offset(x, y),
            math.max(.85 * scale, strokeWidth / 2),
            pen,
          );
        }
      } else {
        canvas.drawLine(Offset(0, y), Offset(size.width, y), pen);
      }
    }
    if (pattern == 'grid') {
      for (double x = step; x < size.width; x += step) {
        canvas.drawLine(Offset(x, 0), Offset(x, size.height), pen);
      }
    }
  }

  @override
  bool shouldRepaint(JournalPattern old) =>
      old.pattern != pattern ||
      old.colour != colour ||
      old.scale != scale ||
      old.strokeWidth != strokeWidth;
}

class JournalShape extends CustomPainter {
  final String kind;
  final Color ink, paper;
  final double scale, borderWidth;
  JournalShape(
    this.kind,
    this.ink,
    this.paper,
    this.scale, {
    this.borderWidth = 1,
  });
  @override
  void paint(Canvas canvas, Size size) {
    final stroke = borderWidth * scale;
    final inset = stroke / 2;
    final bounds = Rect.fromLTWH(
      inset,
      inset,
      math.max(0, size.width - stroke),
      math.max(0, size.height - stroke),
    );
    final fill = Paint()..color = paper;
    final pen = Paint()
      ..color = ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    if (kind == 'circle') {
      canvas.drawOval(bounds, fill);
      if (stroke > 0) canvas.drawOval(bounds, pen);
    } else if (kind == 'line') {
      canvas.drawRect(Offset.zero & size, fill);
      if (stroke > 0) {
        canvas.drawLine(
          Offset(0, size.height / 2),
          Offset(size.width, size.height / 2),
          pen,
        );
      }
    } else {
      canvas.drawRect(bounds, fill);
      if (stroke <= 0) return;
      if (kind == 'rect') {
        canvas.drawRect(bounds, pen);
      } else {
        JournalPattern(
          kind,
          ink,
          scale,
          strokeWidth: stroke,
        ).paint(canvas, size);
      }
    }
  }

  @override
  bool shouldRepaint(JournalShape old) =>
      old.kind != kind ||
      old.ink != ink ||
      old.paper != paper ||
      old.scale != scale ||
      old.borderWidth != borderWidth;
}
