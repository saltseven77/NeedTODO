part of 'journal.dart';

Offset journalLocalPoint(JournalSticker item, Offset point) {
  final d = point - Offset(item.x + item.width / 2, item.y + item.height / 2),
      a = item.rotation * math.pi / 180;
  return Offset(
    d.dx * math.cos(a) + d.dy * math.sin(a) + item.width / 2,
    -d.dx * math.sin(a) + d.dy * math.cos(a) + item.height / 2,
  );
}

double _segmentDistance(Offset p, Offset a, Offset b) {
  final d = b - a, length = d.distanceSquared;
  if (length == 0) return (p - a).distance;
  final t = (((p - a).dx * d.dx + (p - a).dy * d.dy) / length).clamp(0, 1);
  return (p - (a + d * t.toDouble())).distance;
}

bool journalHits(
  JournalSticker item,
  Offset point,
  double scale, {
  bool selected = false,
}) {
  final p = journalLocalPoint(item, point), tolerance = 6 / scale;
  final bounds = Offset.zero & Size(item.width, item.height);
  if (!bounds.inflate(tolerance).contains(p)) return false;
  if (selected) return true;
  if (item.kind == 'highlight') {
    if (item.style.ink.a == 0 || item.points.isEmpty) return false;
    Offset at(Offset q) => Offset(q.dx * item.width, q.dy * item.height);
    final radius = item.strokeWidth / 2 + tolerance;
    if (item.points.length == 1) {
      return (p - at(item.points.first)).distance <= radius;
    }
    for (var i = 1; i < item.points.length; i++) {
      if (_segmentDistance(p, at(item.points[i - 1]), at(item.points[i])) <=
          radius) {
        return true;
      }
    }
    return false;
  }
  if (item.kind == 'image' ||
      item.kind == 'note' ||
      item.kind == 'list' ||
      item.style.paper.a > .02) {
    return bounds.contains(p);
  }
  final width = item.style.borderWidth / 2 + tolerance;
  if (item.kind == 'line') return (p.dy - item.height / 2).abs() <= width;
  if (item.kind == 'circle') {
    final d = Offset(
      (p.dx - item.width / 2) / (item.width / 2),
      (p.dy - item.height / 2) / (item.height / 2),
    ).distance;
    if ((d - 1).abs() * math.min(item.width, item.height) / 2 <= width) {
      return true;
    }
  } else if (item.kind == 'rect') {
    if (bounds.contains(p) &&
        (p.dx < width ||
            p.dy < width ||
            item.width - p.dx < width ||
            item.height - p.dy < width)) {
      return true;
    }
  } else if (item.kind == 'grid' || item.kind == 'dots') {
    if (bounds.contains(p)) return true;
  }
  if (item.text.isEmpty || item.style.ink.a == 0) return false;
  final pad = item.kind == 'text'
      ? math.min(8.0, math.min(item.width, item.height) / 4)
      : math.min(
          12 + item.style.borderWidth,
          math.min(item.width, item.height) / 4,
        );
  final painter = TextPainter(
    text: TextSpan(text: item.text, style: _noteFont(item.style, 1)),
    textDirection: TextDirection.ltr,
  )..layout(maxWidth: math.max(4, item.width - pad * 2));
  final centered = item.kind == 'circle' || item.kind == 'line';
  final top = centered
      ? math.max(pad, (item.height - painter.height) / 2)
      : pad;
  for (final line in painter.computeLineMetrics()) {
    final left = centered ? (item.width - line.width) / 2 : pad + line.left;
    if (Rect.fromLTWH(
      left,
      top + line.baseline - line.ascent,
      line.width,
      line.ascent + line.descent,
    ).inflate(tolerance).contains(p)) {
      return true;
    }
  }
  return false;
}

class _JournalPickSurface extends LeafRenderObjectWidget {
  final bool Function(Offset) hit;
  const _JournalPickSurface(this.hit);
  @override
  RenderObject createRenderObject(BuildContext context) => _JournalPickBox(hit);
  @override
  void updateRenderObject(
    BuildContext context,
    covariant _JournalPickBox renderObject,
  ) => renderObject.hit = hit;
}

class _JournalPickBox extends RenderBox {
  bool Function(Offset) hit;
  _JournalPickBox(this.hit);
  @override
  void performLayout() => size = constraints.biggest;
  @override
  bool hitTestSelf(Offset position) => hit(position);
}

List<JournalSticker> orderedJournalItems(List<JournalSticker> values) {
  final indices = {for (var i = 0; i < values.length; i++) values[i].id: i};
  return values.where((e) => !e.deleted).toList()..sort((a, b) {
    final order = a.layer.compareTo(b.layer);
    return order != 0 ? order : indices[a.id]!.compareTo(indices[b.id]!);
  });
}

class JournalCanvas extends StatefulWidget {
  final NoteStyle style;
  final List<JournalSticker> items;
  final String? selectedId;
  final Color accent, markerColor;
  final double scale, width, height, markerWidth;
  final Widget? text;
  final bool drawing;
  final ValueChanged<String?> select;
  final ValueChanged<Offset>? writeAt;
  final ValueChanged<JournalSticker>? addStroke;
  final void Function(JournalSticker, {bool save}) update;
  final VoidCallback finish;
  final GlobalKey? regionKey;
  final String? editing;
  final ValueChanged<String?>? editItem;
  final void Function(JournalSticker, Offset, Offset)? drop;
  const JournalCanvas({
    super.key,
    required this.style,
    required this.items,
    required this.selectedId,
    required this.accent,
    required this.scale,
    required this.width,
    required this.height,
    required this.select,
    required this.update,
    required this.finish,
    this.text,
    this.writeAt,
    this.drawing = false,
    this.markerColor = const Color(0x66efcf58),
    this.markerWidth = 18,
    this.addStroke,
    this.regionKey,
    this.editing,
    this.editItem,
    this.drop,
  });
  @override
  State<JournalCanvas> createState() => _JournalCanvasState();
}

class _JournalCanvasState extends State<JournalCanvas> {
  List<Offset> stroke = [];
  Timer? hold;
  bool straight = false;
  Offset? holdAnchor;
  Offset? doubleTapPosition;
  JournalSticker? pressed, dragTarget;
  Offset? downGlobal, dragGlobal, grab;
  bool dragged = false;
  List<JournalSticker> hits(Offset p) =>
      orderedJournalItems(widget.items).reversed
          .where((e) => journalHits(e, p, widget.scale))
          .toList();
  JournalSticker? pick(Offset p) => hits(p).firstOrNull;
  bool pickSurface(Offset p) {
    final point = p / widget.scale;
    final edited = widget.items
        .where((e) => !e.deleted && e.id == widget.editing)
        .firstOrNull;
    if (edited != null &&
        journalHits(edited, point, widget.scale, selected: true) &&
        (pick(point) == null || pick(point)?.id == edited.id)) {
      return false;
    }
    if (pick(point) != null) return true;
    final selected = widget.items
        .where((e) => !e.deleted && e.id == widget.selectedId)
        .firstOrNull;
    return selected != null &&
        journalHits(selected, point, widget.scale, selected: true);
  }

  void press(PointerDownEvent e) {
    final p = e.localPosition / widget.scale;
    pressed = pick(p);
    final selected = widget.items
        .where((e) => !e.deleted && e.id == widget.selectedId)
        .firstOrNull;
    dragTarget =
        selected != null &&
            journalHits(selected, p, widget.scale, selected: true)
        ? selected
        : pressed;
    grab = dragTarget == null ? null : p - Offset(dragTarget!.x, dragTarget!.y);
    downGlobal = e.position;
    dragGlobal = e.position;
    dragged = false;
  }

  void moveObject(DragUpdateDetails e) {
    final entry = dragTarget;
    if (entry == null) return;
    final delta =
        (e.globalPosition - (dragGlobal ?? downGlobal ?? e.globalPosition)) /
        widget.scale;
    dragGlobal = e.globalPosition;
    entry.x = (entry.x + delta.dx)
        .clamp(0, math.max(0, widget.width / widget.scale - entry.width))
        .toDouble();
    entry.y = (entry.y + delta.dy)
        .clamp(0, math.max(0, widget.height / widget.scale - entry.height))
        .toDouble();
    widget.update(entry, save: false);
  }

  void endMove() {
    if (dragTarget != null && dragGlobal != null && grab != null) {
      widget.drop?.call(dragTarget!, dragGlobal!, grab!);
    }
    widget.finish();
  }

  void chooseAtRelease(PointerUpEvent e) {
    if (dragged || pressed == null) return;
    final entry = pressed!;
    final p = journalLocalPoint(entry, e.localPosition / widget.scale);
    if (entry.kind == 'list' &&
        entry.listType == 'check' &&
        p.dx >= 8 &&
        p.dx < 33 &&
        p.dy >= 8) {
      final line =
          ((p.dy - 8) / math.max(24 / widget.scale, entry.style.fontSize * 1.6))
              .floor();
      if (line < entry.text.split('\n').length) {
        if (entry.checked.contains(line)) {
          entry.checked.remove(line);
        } else {
          entry.checked.add(line);
        }
        widget.update(entry, save: true);
      }
    }
    widget.select(entry.id);
  }

  bool hitsItem(Offset p) => widget.items.where((e) => !e.deleted).any((e) {
    final center = Offset(e.x + e.width / 2, e.y + e.height / 2),
        d = p - center;
    final angle = e.rotation * math.pi / 180;
    final local = Offset(
      d.dx * math.cos(angle) + d.dy * math.sin(angle),
      -d.dx * math.sin(angle) + d.dy * math.cos(angle),
    );
    return local.dx.abs() <= e.width / 2 && local.dy.abs() <= e.height / 2;
  });
  Offset point(Offset position) => Offset(
    (position.dx / widget.scale).clamp(0, widget.width / widget.scale),
    (position.dy / widget.scale).clamp(0, widget.height / widget.scale),
  );
  @override
  void dispose() {
    hold?.cancel();
    super.dispose();
  }

  void begin(Offset value) {
    hold?.cancel();
    setState(() {
      stroke = [point(value)];
      straight = false;
      holdAnchor = null;
    });
  }

  void extend(Offset value) {
    final next = point(value);
    if (stroke.isEmpty || (next - stroke.last).distance < .6) return;
    setState(() {
      if (straight) {
        stroke = [stroke.first, next];
      } else if (stroke.length < 8000) {
        stroke.add(next);
      }
    });
    if (!straight &&
        (holdAnchor == null || (next - holdAnchor!).distance > 2.5)) {
      holdAnchor = next;
      hold?.cancel();
      hold = Timer(const Duration(milliseconds: 500), () {
        if (!mounted || stroke.length < 2) return;
        setState(() {
          stroke = [stroke.first, stroke.last];
          straight = true;
        });
      });
    }
  }

  void complete() {
    hold?.cancel();
    if (stroke.isEmpty) return;
    final pad = widget.markerWidth / 2 + 1;
    final left = math.max(0.0, stroke.map((p) => p.dx).reduce(math.min) - pad);
    final top = math.max(0.0, stroke.map((p) => p.dy).reduce(math.min) - pad);
    final right = math.min(
      widget.width / widget.scale,
      stroke.map((p) => p.dx).reduce(math.max) + pad,
    );
    final bottom = math.min(
      widget.height / widget.scale,
      stroke.map((p) => p.dy).reduce(math.max) + pad,
    );
    final width = math.max(4.0, right - left),
        height = math.max(4.0, bottom - top);
    final entry = JournalSticker(
      kind: 'highlight',
      x: left,
      y: top,
      width: width,
      height: height,
      strokeWidth: widget.markerWidth,
      points: stroke
          .map(
            (p) => Offset(
              ((p.dx - left) / width).clamp(0, 1),
              ((p.dy - top) / height).clamp(0, 1),
            ),
          )
          .toList(),
      style: NoteStyle(ink: widget.markerColor),
      layer:
          widget.items
              .where((e) => !e.deleted && e.kind == 'highlight' && e.layer < 0)
              .fold(-10000, (layer, e) => math.max(layer, e.layer)) +
          1,
    );
    widget.addStroke?.call(entry);
    setState(() {
      stroke = [];
      straight = false;
    });
  }

  Widget element(JournalSticker entry, {bool controls = false}) => Positioned(
    key: ValueKey('${controls ? 'selection' : 'sticker'}-${entry.id}'),
    left: entry.x * widget.scale - 16,
    top: entry.y * widget.scale - 28,
    width: entry.width * widget.scale + 32,
    height: entry.height * widget.scale + 44,
    child: JournalItem(
      item: entry,
      selected: entry.id == widget.selectedId,
      editable: widget.editing == entry.id,
      showControls: controls,
      controlsOnly: controls,
      accent: widget.accent,
      scale: widget.scale,
      onSelect: () {
        if (!controls && widget.editing == entry.id) {
          widget.editItem?.call(entry.id);
        } else {
          widget.select(entry.id);
        }
      },
      move: (delta) {
        entry.x = (entry.x + delta.dx / widget.scale)
            .clamp(0, math.max(0, widget.width / widget.scale - entry.width))
            .toDouble();
        entry.y = (entry.y + delta.dy / widget.scale)
            .clamp(0, math.max(0, widget.height / widget.scale - entry.height))
            .toDouble();
        widget.update(entry, save: false);
      },
      resize: (delta) {
        entry.width = (entry.width + delta.dx / widget.scale)
            .clamp(4, math.max(4, widget.width / widget.scale - entry.x))
            .toDouble();
        entry.height = (entry.height + delta.dy / widget.scale)
            .clamp(4, 1200)
            .toDouble();
        widget.update(entry, save: false);
      },
      rotate: (degrees) {
        entry.rotation = degrees;
        widget.update(entry, save: false);
      },
      edit: (value) {
        entry.text = value;
        final painter =
            TextPainter(
              text: TextSpan(
                text: value.isEmpty ? ' ' : value,
                style: _noteFont(entry.style, 1),
              ),
              textDirection: TextDirection.ltr,
            )..layout(
              maxWidth: math.max(
                4,
                entry.width - (entry.kind == 'list' ? 40 : 16),
              ),
            );
        entry.height = math
            .max(entry.height, painter.height + 24)
            .clamp(4, 1200)
            .toDouble();
        widget.update(entry, save: true);
      },
      change: () => widget.update(entry, save: true),
      finish: widget.finish,
    ),
  );
  @override
  Widget build(BuildContext context) {
    final ordered = orderedJournalItems(widget.items);
    return SizedBox(
      key: widget.regionKey,
      width: widget.width,
      height: widget.height,
      child: ClipRect(
        child: MouseRegion(
          cursor: widget.drawing
              ? SystemMouseCursors.precise
              : MouseCursor.defer,
          child: GestureDetector(
            dragStartBehavior: DragStartBehavior.down,
            behavior: HitTestBehavior.opaque,
            onTap: null,
            onTapUp: widget.drawing
                ? (e) {
                    begin(e.localPosition);
                    complete();
                  }
                : null,
            onPanStart: widget.drawing ? (e) => begin(e.localPosition) : null,
            onPanUpdate: widget.drawing ? (e) => extend(e.localPosition) : null,
            onPanEnd: widget.drawing ? (_) => complete() : null,
            onPanCancel: widget.drawing
                ? () {
                    hold?.cancel();
                    setState(() => stroke = []);
                  }
                : null,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  child: IgnorePointer(
                    ignoring: widget.drawing,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => widget.select(null),
                      onDoubleTapDown: widget.writeAt != null
                          ? (e) => doubleTapPosition =
                                e.localPosition / widget.scale
                          : null,
                      onDoubleTap:
                          widget.text != null && widget.editing != 'base'
                          ? () => widget.editItem?.call(null)
                          : widget.writeAt != null
                          ? () {
                              final p = doubleTapPosition;
                              if (p != null && !hitsItem(p)) widget.writeAt!(p);
                              doubleTapPosition = null;
                            }
                          : null,
                      onDoubleTapCancel: widget.writeAt != null
                          ? () => doubleTapPosition = null
                          : null,
                      child: CustomPaint(
                        painter: JournalPattern(
                          widget.style.pattern,
                          widget.style.ink.withValues(
                            alpha: widget.style.ink.a * .17,
                          ),
                          widget.scale,
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned.fill(
                  child: IgnorePointer(
                    ignoring: widget.drawing,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        for (final entry in ordered.where((e) => e.layer <= 0))
                          element(entry),
                        if (widget.text != null)
                          Positioned.fill(
                            child: IgnorePointer(
                              ignoring: widget.editing != 'base',
                              child: widget.text!,
                            ),
                          ),
                        for (final entry in ordered.where((e) => e.layer > 0))
                          element(entry),
                      ],
                    ),
                  ),
                ),
                if (!widget.drawing)
                  Positioned.fill(
                    child: Listener(
                      onPointerDown: press,
                      onPointerUp: chooseAtRelease,
                      child: GestureDetector(
                        behavior: HitTestBehavior.deferToChild,
                        dragStartBehavior: DragStartBehavior.down,
                        onDoubleTap: () {
                          if (pressed != null) {
                            widget.editItem?.call(pressed!.id);
                          }
                        },
                        onPanStart: (_) {
                          dragged = true;
                          if (dragTarget != null) widget.select(dragTarget!.id);
                        },
                        onPanUpdate: moveObject,
                        onPanEnd: (_) => endMove(),
                        onPanCancel: endMove,
                        child: _JournalPickSurface(pickSurface),
                      ),
                    ),
                  ),
                if (!widget.drawing)
                  for (final entry in ordered.where(
                    (e) => e.id == widget.selectedId,
                  ))
                    element(entry, controls: true),
                if (stroke.isNotEmpty)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: CustomPaint(
                        painter: JournalMarker(
                          stroke
                              .map(
                                (p) => Offset(
                                  p.dx / (widget.width / widget.scale),
                                  p.dy / (widget.height / widget.scale),
                                ),
                              )
                              .toList(),
                          widget.markerColor,
                          widget.markerWidth * widget.scale,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class JournalItem extends StatefulWidget {
  final JournalSticker item;
  final bool selected;
  final bool showControls, controlsOnly;
  final bool editable;
  final Color accent;
  final double scale;
  final VoidCallback onSelect, finish, change;
  final ValueChanged<Offset> move, resize;
  final ValueChanged<double> rotate;
  final ValueChanged<String> edit;
  const JournalItem({
    super.key,
    required this.item,
    required this.selected,
    required this.accent,
    required this.scale,
    required this.onSelect,
    required this.move,
    required this.resize,
    required this.rotate,
    required this.edit,
    required this.change,
    required this.finish,
    this.showControls = true,
    this.controlsOnly = false,
    this.editable = true,
  });
  @override
  State<JournalItem> createState() => _JournalItemState();
}

class _JournalItemState extends State<JournalItem> {
  Offset? previous;
  double? startAngle, startRotation;
  static const frame = Color(0xffaeb3ba);
  Offset delta(DragUpdateDetails e) {
    final change = e.globalPosition - (previous ?? e.globalPosition);
    previous = e.globalPosition;
    return change;
  }

  Offset localDelta(Offset d) {
    final angle = widget.item.rotation * math.pi / 180;
    return Offset(
      d.dx * math.cos(angle) + d.dy * math.sin(angle),
      -d.dx * math.sin(angle) + d.dy * math.cos(angle),
    );
  }

  void dragStart(DragStartDetails e) {
    previous = e.globalPosition;
    widget.onSelect();
  }

  Widget handle(String type) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onPanStart: dragStart,
    onPanUpdate: (e) {
      final d = delta(e);
      if (type == 'resize') {
        widget.resize(localDelta(d));
      } else {
        widget.move(d);
      }
    },
    onPanEnd: (_) {
      previous = null;
      widget.finish();
    },
    child: SizedBox(
      key: ValueKey('$type-${widget.item.id}'),
      width: 22,
      height: 22,
      child: Center(
        child: Container(
          width: 5,
          height: 5,
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            border: Border.all(color: frame, width: .8),
          ),
        ),
      ),
    ),
  );
  @override
  Widget build(BuildContext context) {
    final item = widget.item, scale = widget.scale;
    final bytes = item.kind == 'image' ? imageBytes(item.image) : null;
    Widget content;
    if (item.kind == 'text' || item.kind == 'note') {
      content = Padding(
        padding: EdgeInsets.all(
          math.min(8, math.min(item.width, item.height) / 4) * scale,
        ),
        child: JournalText(
          text: item.text,
          style: _noteFont(item.style, scale),
          onChanged: widget.edit,
          onFocus: widget.onSelect,
          autofocus: widget.editable && widget.selected,
        ),
      );
    } else if (item.kind == 'image') {
      content = bytes == null
          ? const SizedBox()
          : Image.memory(
              bytes,
              fit: BoxFit.contain,
              gaplessPlayback: true,
              errorBuilder: (_, _, _) => const Center(
                child: Icon(CupertinoIcons.photo, color: muted, size: 18),
              ),
            );
    } else if (item.kind == 'highlight') {
      content = CustomPaint(
        painter: JournalMarker(
          item.points,
          item.style.ink,
          item.strokeWidth * scale,
        ),
      );
    } else if (item.kind == 'list') {
      content = Padding(
        padding: EdgeInsets.all(8 * scale),
        child: JournalList(
          item: item,
          scale: scale,
          selected: widget.selected && widget.editable,
          select: widget.onSelect,
          edit: widget.edit,
          change: widget.change,
        ),
      );
    } else {
      content = CustomPaint(
        painter: JournalShape(
          item.kind,
          item.style.edge,
          item.style.paper,
          scale,
          borderWidth: item.style.borderWidth,
        ),
      );
    }
    if (!['text', 'note', 'list'].contains(item.kind)) {
      content = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onSelect,
        onPanStart: dragStart,
        onPanUpdate: (e) => widget.move(delta(e)),
        onPanEnd: (_) {
          previous = null;
          widget.finish();
        },
        child: content,
      );
    }
    final box = <String>['text', 'note', 'list', 'image'].contains(item.kind);
    return Transform.rotate(
      angle: item.rotation * math.pi / 180,
      alignment: Alignment.topLeft,
      origin: Offset(16 + item.width * scale / 2, 28 + item.height * scale / 2),
      child: MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(gestureSettings: const DeviceGestureSettings(touchSlop: 2)),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            if (!widget.controlsOnly)
              Positioned(
                left: 16,
                top: 28,
                width: item.width * scale,
                height: item.height * scale,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: box ? item.style.paper : null,
                    border:
                        box &&
                            item.style.border != null &&
                            item.style.borderWidth > 0
                        ? Border.all(
                            color: item.style.edge,
                            width: item.style.borderWidth * scale,
                          )
                        : null,
                  ),
                  child: IgnorePointer(
                    ignoring: !widget.editable,
                    child: content,
                  ),
                ),
              ),
            if (!widget.controlsOnly &&
                !['text', 'note', 'list', 'highlight'].contains(item.kind) &&
                item.text.isNotEmpty)
              Positioned(
                left: 16,
                top: 28,
                width: item.width * scale,
                height: item.height * scale,
                child: IgnorePointer(
                  ignoring: !widget.editable,
                  child: Padding(
                    padding: EdgeInsets.all(
                      math.min(
                            12 + item.style.borderWidth,
                            math.min(item.width, item.height) / 4,
                          ) *
                          scale,
                    ),
                    child: JournalText(
                      key: ValueKey('sticker-label-${item.id}'),
                      text: item.text,
                      centered: item.kind == 'circle' || item.kind == 'line',
                      style: _noteFont(item.style, scale),
                      onChanged: widget.edit,
                      onFocus: widget.onSelect,
                      autofocus: widget.editable && widget.selected,
                    ),
                  ),
                ),
              ),
            if (widget.selected && widget.showControls) ...[
              Positioned(
                left: 16,
                top: 28,
                width: item.width * scale,
                height: item.height * scale,
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: frame.withValues(alpha: .65),
                        width: .6,
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 5,
                top: 17,
                child: MouseRegion(
                  cursor: SystemMouseCursors.move,
                  child: handle('move'),
                ),
              ),
              Positioned(
                right: 5,
                bottom: 5,
                child: MouseRegion(
                  cursor: SystemMouseCursors.resizeUpLeftDownRight,
                  child: handle('resize'),
                ),
              ),
              Positioned(
                left: 16 + item.width * scale / 2 - 11,
                top: 2,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onPanStart: (e) {
                    final box = context.findRenderObject() as RenderBox;
                    final center = box.localToGlobal(
                      Offset(
                        16 + item.width * scale / 2,
                        28 + item.height * scale / 2,
                      ),
                    );
                    startAngle = math.atan2(
                      e.globalPosition.dy - center.dy,
                      e.globalPosition.dx - center.dx,
                    );
                    startRotation = item.rotation;
                  },
                  onPanUpdate: (e) {
                    final box = context.findRenderObject() as RenderBox;
                    final center = box.localToGlobal(
                      Offset(
                        16 + item.width * scale / 2,
                        28 + item.height * scale / 2,
                      ),
                    );
                    final angle = math.atan2(
                      e.globalPosition.dy - center.dy,
                      e.globalPosition.dx - center.dx,
                    );
                    widget.rotate(
                      (((startRotation ?? 0) +
                                  (angle - (startAngle ?? angle)) *
                                      180 /
                                      math.pi +
                                  180) %
                              360) -
                          180,
                    );
                  },
                  onPanEnd: (_) => widget.finish(),
                  child: Tooltip(
                    message: '旋转',
                    child: SizedBox(
                      key: ValueKey('rotate-${item.id}'),
                      width: 22,
                      height: 22,
                      child: Center(
                        child: Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            border: Border.all(color: frame, width: .8),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class JournalMarker extends CustomPainter {
  final List<Offset> points;
  final Color color;
  final double width;
  JournalMarker(this.points, this.color, this.width);
  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;
    final paint = Paint()
      ..color = color
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    Offset at(Offset p) => Offset(p.dx * size.width, p.dy * size.height);
    final first = at(points.first);
    if (points.length == 1) {
      canvas.drawCircle(first, width / 2, Paint()..color = color);
      return;
    }
    final path = Path()..moveTo(first.dx, first.dy);
    for (var i = 1; i < points.length - 1; i++) {
      final here = at(points[i]), next = at(points[i + 1]);
      path.quadraticBezierTo(
        here.dx,
        here.dy,
        (here.dx + next.dx) / 2,
        (here.dy + next.dy) / 2,
      );
    }
    final end = at(points.last);
    path.lineTo(end.dx, end.dy);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(JournalMarker old) =>
      old.points != points || old.color != color || old.width != width;
}

class JournalList extends StatefulWidget {
  final JournalSticker item;
  final double scale;
  final bool selected;
  final VoidCallback select, change;
  final ValueChanged<String> edit;
  const JournalList({
    super.key,
    required this.item,
    required this.scale,
    required this.selected,
    required this.select,
    required this.change,
    required this.edit,
  });
  @override
  State<JournalList> createState() => _JournalListState();
}

class _JournalListState extends State<JournalList> {
  int? focusIndex;
  @override
  Widget build(BuildContext context) {
    final lines = widget.item.text.split('\n'),
        style = _noteFont(widget.item.style, widget.scale);
    return SingleChildScrollView(
      child: Column(
        children: [
          for (var i = 0; i < lines.length; i++)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 25 * widget.scale,
                  height: math.max(24, style.fontSize! * 1.6),
                  child: widget.item.listType == 'check'
                      ? InkWell(
                          onTap: () {
                            widget.select();
                            if (widget.item.checked.contains(i)) {
                              widget.item.checked.remove(i);
                            } else {
                              widget.item.checked.add(i);
                            }
                            widget.change();
                          },
                          child: Icon(
                            widget.item.checked.contains(i)
                                ? CupertinoIcons.checkmark_square
                                : CupertinoIcons.square,
                            color: widget.item.style.ink,
                            size: math.max(10, style.fontSize!),
                          ),
                        )
                      : Center(
                          child: Text(
                            widget.item.listType == 'number'
                                ? '${i + 1}.'
                                : '•',
                            style: style,
                          ),
                        ),
                ),
                Expanded(
                  child: JournalText(
                    key: ValueKey('list-${widget.item.id}-$i'),
                    text: lines[i],
                    style: style,
                    expands: false,
                    autofocus: focusIndex == i || (widget.selected && i == 0),
                    onFocus: widget.select,
                    onSubmitted: (_) {
                      lines.insert(i + 1, '');
                      widget.edit(lines.join('\n'));
                      setState(() => focusIndex = i + 1);
                    },
                    onChanged: (v) {
                      lines[i] = v;
                      widget.edit(lines.join('\n'));
                    },
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
