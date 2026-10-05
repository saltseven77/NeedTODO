import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../model.dart';

const ink = Color(0xff292c32),
    muted = Color(0xff858b94),
    blue = Color(0xff477cae),
    panel = Color(0xfff5f5f7);
ThemeData appTheme() => ThemeData(
  useMaterial3: true,
  fontFamily: 'Segoe UI',
  fontFamilyFallback: const ['PingFang SC', 'Microsoft YaHei UI', 'sans-serif'],
  colorScheme: ColorScheme.fromSeed(
    seedColor: blue,
    brightness: Brightness.light,
    surface: panel,
  ),
  scaffoldBackgroundColor: panel,
  splashFactory: NoSplash.splashFactory,
  highlightColor: Colors.transparent,
  hoverColor: const Color(0x08000000),
  chipTheme: const ChipThemeData(
    side: BorderSide.none,
    labelStyle: TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w400,
      color: ink,
      fontFamily: 'Segoe UI',
      fontFamilyFallback: ['PingFang SC', 'Microsoft YaHei UI'],
    ),
    backgroundColor: Color(0xffe9ebef),
    selectedColor: Color(0xffdce9f5),
    checkmarkColor: blue,
  ),
  sliderTheme: const SliderThemeData(
    trackHeight: 2,
    trackGap: 0,
    trackShape: RoundedRectSliderTrackShape(),
    thumbShape: RoundSliderThumbShape(
      enabledThumbRadius: 5,
      elevation: 0,
      pressedElevation: 1,
    ),
    overlayShape: RoundSliderOverlayShape(overlayRadius: 12),
    activeTrackColor: blue,
    inactiveTrackColor: Color(0xffdedfe4),
    thumbColor: blue,
    padding: EdgeInsets.symmetric(horizontal: 8),
  ),
  dividerColor: const Color(0xffe9eaed),
  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: const Color(0xfff0f1f4),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide.none,
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide.none,
    ),
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
  ),
  filledButtonTheme: FilledButtonThemeData(
    style: FilledButton.styleFrom(
      backgroundColor: blue,
      foregroundColor: Colors.white,
      minimumSize: const Size(44, 44),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
  ),
  textButtonTheme: TextButtonThemeData(
    style: TextButton.styleFrom(
      foregroundColor: blue,
      minimumSize: const Size(44, 44),
    ),
  ),
  iconButtonTheme: IconButtonThemeData(
    style: IconButton.styleFrom(
      minimumSize: const Size(40, 40),
      foregroundColor: muted,
    ),
  ),
  textTheme: const TextTheme(
    bodyLarge: TextStyle(fontSize: 13, fontWeight: FontWeight.w400, color: ink),
    bodyMedium: TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w400,
      color: ink,
    ),
    labelLarge: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
    titleSmall: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
    bodySmall: TextStyle(fontSize: 12, color: muted),
    titleLarge: TextStyle(
      fontSize: 18,
      fontWeight: FontWeight.w500,
      color: ink,
    ),
    titleMedium: TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w500,
      color: ink,
    ),
  ),
);

class ActionIcon extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final Color? color;
  final bool compact;
  const ActionIcon(
    this.icon,
    this.label,
    this.onPressed, {
    super.key,
    this.color,
    this.compact = false,
  });
  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: label,
    onPressed: onPressed,
    style: compact
        ? IconButton.styleFrom(
            minimumSize: const Size.square(28),
            maximumSize: const Size.square(28),
            padding: const EdgeInsets.all(3),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: VisualDensity.standard,
          )
        : null,
    icon: Icon(icon, size: compact ? 18 : 20, color: color),
  );
}

// Reuse byte identity so MemoryImage can reuse its decoded image cache.
// Bound this cache: previews can temporarily contain multiple large images.
final _imageCache = <String, Uint8List>{};
int _imageCacheBytes = 0;
Uint8List? imageBytes(String data) {
  try {
    if (!data.startsWith('data:image/')) return null;
    final cached = _imageCache[data];
    if (cached != null) {
      _imageCache.remove(data);
      _imageCache[data] = cached;
      return cached;
    }
    final bytes = base64Decode(data.split(',').last);
    const budget = 32 * 1024 * 1024;
    while (_imageCache.isNotEmpty && _imageCacheBytes + bytes.length > budget) {
      _imageCacheBytes -= _imageCache.remove(_imageCache.keys.first)!.length;
    }
    if (bytes.length <= budget) {
      _imageCache[data] = bytes;
      _imageCacheBytes += bytes.length;
    }
    return bytes;
  } catch (_) {
    return null;
  }
}

class Identity extends StatelessWidget {
  final String data;
  final double size;
  const Identity({super.key, this.data = '', this.size = 32});
  @override
  Widget build(BuildContext context) {
    final bytes = imageBytes(data);
    return ClipRRect(
      borderRadius: BorderRadius.circular(size * .3),
      child: bytes == null
          ? Image.asset('assets/potato.png', width: size, height: size)
          : Image.memory(
              bytes,
              width: size,
              height: size,
              fit: BoxFit.cover,
              gaplessPlayback: true,
              errorBuilder: (_, _, _) =>
                  Image.asset('assets/potato.png', width: size, height: size),
            ),
    );
  }
}

class Surface extends StatelessWidget {
  final Appearance appearance;
  final Widget child;
  const Surface({super.key, required this.appearance, required this.child});
  @override
  Widget build(BuildContext context) {
    final a = appearance, p = a.palette, bytes = imageBytes(a.background);
    Widget content = Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(
          color: p.background.withValues(alpha: p.background.a * a.opacity),
        ),
        if (bytes != null)
          Opacity(
            opacity: a.imageOpacity,
            child: ImageFiltered(
              enabled: a.effect == 'glass',
              imageFilter: ui.ImageFilter.blur(
                sigmaX: a.effectAmount * 14,
                sigmaY: a.effectAmount * 14,
              ),
              child: Image.memory(
                bytes,
                fit: BoxFit.cover,
                gaplessPlayback: true,
                errorBuilder: (_, _, _) => const SizedBox.shrink(),
              ),
            ),
          ),
        if (a.effect == 'paper')
          IgnorePointer(
            child: CustomPaint(
              painter: PaperPainter(a.effectColor, a.effectAmount),
            ),
          ),
        if (a.effect == 'jelly')
          IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(-.7, -.9),
                  radius: 1.7,
                  colors: [
                    a.effectColor.withValues(alpha: a.effectAmount * .6),
                    a.effectColor.withValues(alpha: a.effectAmount * .06),
                  ],
                ),
                boxShadow: [
                  BoxShadow(
                    color: a.effectColor.withValues(
                      alpha: a.effectAmount * .16,
                    ),
                    blurRadius: 26,
                  ),
                ],
              ),
            ),
          ),
        DefaultTextStyle(
          style: TextStyle(
            color: p.text,
            fontSize: 13,
            fontWeight: FontWeight.w400,
            fontFamily: 'Segoe UI',
            fontFamilyFallback: const ['PingFang SC', 'Microsoft YaHei UI'],
          ),
          child: IconTheme(
            data: IconThemeData(color: p.text),
            child: child,
          ),
        ),
      ],
    );
    if (a.effect == 'glass') {
      content = BackdropFilter(
        filter: ui.ImageFilter.blur(
          sigmaX: 3 + a.effectAmount * 22,
          sigmaY: 3 + a.effectAmount * 22,
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(
              color: a.effectColor.withValues(alpha: a.effectAmount * .15),
            ),
            content,
          ],
        ),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(a.radius),
      child: content,
    );
  }
}

class PaperPainter extends CustomPainter {
  final Color color;
  final double amount;
  PaperPainter(this.color, this.amount);
  @override
  void paint(Canvas canvas, Size size) {
    final random = math.Random(72),
        paint = Paint()..color = color.withValues(alpha: amount * .28);
    for (var i = 0; i < math.min(5000, size.width * size.height / 60); i++) {
      canvas.drawCircle(
        Offset(
          random.nextDouble() * size.width,
          random.nextDouble() * size.height,
        ),
        .45,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(PaperPainter old) =>
      old.color != color || old.amount != amount;
}

Future<T?> showPanel<T>(
  BuildContext context,
  String title,
  Widget child, {
  double width = 420,
  bool fixedHeight = false,
}) {
  Widget content(BuildContext context) => ConstrainedBox(
    constraints: BoxConstraints(
      minHeight: fixedHeight
          ? (MediaQuery.sizeOf(context).height -
                    MediaQuery.viewInsetsOf(context).bottom -
                    44)
                .clamp(120, 680)
          : 0,
      maxHeight:
          (MediaQuery.sizeOf(context).height -
                  MediaQuery.viewInsetsOf(context).bottom -
                  44)
              .clamp(120, 680),
      maxWidth: width,
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 6, 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: ink,
                  ),
                ),
              ),
              ActionIcon(
                CupertinoIcons.xmark,
                '关闭',
                () => Navigator.pop(context),
              ),
            ],
          ),
        ),
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: child,
          ),
        ),
      ],
    ),
  );
  if (MediaQuery.sizeOf(context).width >= 600 ||
      Theme.of(context).platform == TargetPlatform.windows) {
    return showDialog<T>(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: panel,
        surfaceTintColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        child: SizedBox(width: width, child: content(context)),
      ),
    );
  }
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: panel,
    constraints: BoxConstraints(maxWidth: width),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
    ),
    builder: (context) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: content(context),
    ),
  );
}

class Section extends StatelessWidget {
  final String title;
  final Widget child;
  final Widget? trailing;
  const Section(this.title, this.child, {super.key, this.trailing});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  color: muted,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            ?trailing,
          ],
        ),
        const SizedBox(height: 12),
        child,
      ],
    ),
  );
}

class SettingSlider extends StatelessWidget {
  final String label;
  final double value, min, max;
  final ValueChanged<double> onChanged;
  final String? suffix;
  const SettingSlider(
    this.label,
    this.value,
    this.onChanged, {
    super.key,
    this.min = 0,
    this.max = 1,
    this.suffix,
  });
  @override
  Widget build(BuildContext context) => Column(
    children: [
      Row(
        children: [
          Expanded(child: Text(label, style: const TextStyle(fontSize: 13))),
          Text(
            suffix ?? '${(value * 100).round()}%',
            style: const TextStyle(color: muted, fontSize: 12),
          ),
        ],
      ),
      SizedBox(
        height: 30,
        child: Slider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          onChanged: onChanged,
        ),
      ),
    ],
  );
}

Future<DateTime?> chooseDate(BuildContext context, DateTime initial) =>
    showPanel<DateTime>(
      context,
      '选择日期',
      DateChooser(initial: initial),
      width: 420,
    );

class DateChooser extends StatefulWidget {
  final DateTime initial;
  const DateChooser({super.key, required this.initial});
  @override
  State<DateChooser> createState() => _DateChooserState();
}

class _DateChooserState extends State<DateChooser> {
  bool monthPicker = false;
  late DateTime month = DateTime(widget.initial.year, widget.initial.month),
      selected = widget.initial;
  @override
  Widget build(BuildContext context) {
    final start = month.subtract(Duration(days: month.weekday - 1));
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            ActionIcon(
              CupertinoIcons.chevron_left,
              '上个月',
              () =>
                  setState(() => month = DateTime(month.year, month.month - 1)),
            ),
            Expanded(
              child: TextButton(
                onPressed: () => setState(() => monthPicker = !monthPicker),
                child: Text(
                  '${month.year}年 ${month.month}月',
                  style: const TextStyle(
                    color: ink,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
            ActionIcon(
              CupertinoIcons.chevron_right,
              '下个月',
              () =>
                  setState(() => month = DateTime(month.year, month.month + 1)),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (monthPicker)
          SizedBox(
            height: 150,
            child: CupertinoDatePicker(
              mode: CupertinoDatePickerMode.monthYear,
              initialDateTime: month,
              onDateTimeChanged: (d) =>
                  setState(() => month = DateTime(d.year, d.month)),
            ),
          ),
        Row(
          children: ['一', '二', '三', '四', '五', '六', '日']
              .map(
                (s) => Expanded(
                  child: Center(
                    child: Text(
                      s,
                      style: const TextStyle(color: muted, fontSize: 12),
                    ),
                  ),
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 8),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 7,
            mainAxisSpacing: 2,
            crossAxisSpacing: 2,
          ),
          itemCount: 42,
          itemBuilder: (context, i) {
            final day = start.add(Duration(days: i)),
                active = dayKey(day) == dayKey(selected);
            return TextButton(
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                backgroundColor: active ? blue : null,
                foregroundColor: active
                    ? Colors.white
                    : day.month == month.month
                    ? ink
                    : muted.withValues(alpha: .4),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: () => setState(() => selected = day),
              child: Text('${day.day}'),
            );
          },
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            TextButton(
              onPressed: () => setState(() {
                selected = DateTime.now();
                month = DateTime(selected.year, selected.month);
              }),
              child: const Text('今天'),
            ),
            const Spacer(),
            FilledButton(
              onPressed: () => Navigator.pop(context, selected),
              child: const Text('选择'),
            ),
          ],
        ),
      ],
    );
  }
}

class ColorField extends StatelessWidget {
  final String label;
  final Color color;
  final ValueChanged<Color> onChanged;
  const ColorField(this.label, this.color, this.onChanged, {super.key});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      children: [
        Expanded(child: Text(label, style: const TextStyle(fontSize: 13))),
        TextButton(
          onPressed: () async {
            final result = await showPanel<Color>(
              context,
              label,
              ColorEditor(initial: color, onPreview: onChanged),
              width: 410,
            );
            if (result == null) {
              onChanged(color);
            } else {
              onChanged(result);
            }
          },
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(7),
                  boxShadow: const [
                    BoxShadow(color: Color(0x20808080), blurRadius: 2),
                  ],
                ),
              ),
              if (label.isNotEmpty) const SizedBox(width: 10),
              if (label.isNotEmpty)
                Text(
                  '#${color.toARGB32().toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}',
                  style: const TextStyle(color: muted, fontSize: 12),
                ),
            ],
          ),
        ),
      ],
    ),
  );
}

class ColorEditor extends StatefulWidget {
  final Color initial;
  final ValueChanged<Color> onPreview;
  const ColorEditor({
    super.key,
    required this.initial,
    required this.onPreview,
  });
  @override
  State<ColorEditor> createState() => _ColorEditorState();
}

class _ColorEditorState extends State<ColorEditor> {
  late HSVColor hsv = HSVColor.fromColor(widget.initial);
  late final hex = TextEditingController(
    text: widget.initial
        .toARGB32()
        .toRadixString(16)
        .padLeft(8, '0')
        .substring(2)
        .toUpperCase(),
  );
  void update(HSVColor value) {
    setState(() => hsv = value);
    hex.text = value
        .toColor()
        .toARGB32()
        .toRadixString(16)
        .padLeft(8, '0')
        .substring(2)
        .toUpperCase();
    widget.onPreview(value.toColor());
  }

  @override
  void dispose() {
    hex.dispose();
    super.dispose();
  }

  bool get validHex => RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(hex.text);

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      LayoutBuilder(
        builder: (context, c) {
          void select(Offset position) => update(
            hsv
                .withSaturation((position.dx / c.maxWidth).clamp(0, 1))
                .withValue((1 - position.dy / 160).clamp(0, 1)),
          );
          return GestureDetector(
            key: const ValueKey('color-plane'),
            behavior: HitTestBehavior.opaque,
            onPanDown: (d) => select(d.localPosition),
            onPanUpdate: (d) => select(d.localPosition),
            child: SizedBox(
              width: double.infinity,
              height: 160,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.white,
                            HSVColor.fromAHSV(1, hsv.hue, 1, 1).toColor(),
                          ],
                        ),
                      ),
                    ),
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.transparent, Colors.black],
                        ),
                      ),
                    ),
                    Positioned(
                      left: (hsv.saturation * c.maxWidth - 6).clamp(
                        0,
                        c.maxWidth - 12,
                      ),
                      top: ((1 - hsv.value) * 160 - 6).clamp(0, 148),
                      child: Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: hsv.toColor().withValues(alpha: 1),
                          border: Border.all(color: Colors.white, width: 2),
                          boxShadow: const [
                            BoxShadow(color: Colors.black38, blurRadius: 2),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
      const SizedBox(height: 12),
      Row(
        children: [
          const Text('预览', style: TextStyle(fontSize: 12, color: muted)),
          const SizedBox(width: 12),
          ColorSample(color: widget.initial),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8),
            child: Icon(CupertinoIcons.arrow_right, size: 12, color: muted),
          ),
          ColorSample(key: const ValueKey('live-color'), color: hsv.toColor()),
          const Spacer(),
          Text(
            '#${hex.text.toUpperCase()}',
            style: const TextStyle(fontSize: 11, color: muted),
          ),
        ],
      ),
      const SizedBox(height: 12),
      SettingSlider(
        '色相',
        hsv.hue,
        (v) => update(hsv.withHue(v)),
        max: 360,
        suffix: '${hsv.hue.round()}°',
      ),
      SettingSlider('不透明度', hsv.alpha, (v) => update(hsv.withAlpha(v))),
      const SizedBox(height: 8),
      TextField(
        controller: hex,
        style: const TextStyle(fontSize: 12),
        maxLength: 6,
        decoration: const InputDecoration(
          prefixText: '#',
          labelText: 'HEX',
          counterText: '',
          isDense: true,
        ),
        onChanged: (v) {
          setState(() {
            if (validHex) {
              hsv = HSVColor.fromColor(Color(int.parse('ff$v', radix: 16)))
                  .withAlpha(hsv.alpha);
            }
          });
          if (validHex) widget.onPreview(hsv.toColor());
        },
      ),
      const SizedBox(height: 12),
      Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: validHex
                ? () => Navigator.pop(context, hsv.toColor())
                : null,
            child: const Text('完成'),
          ),
        ],
      ),
    ],
  );
}

class ColorSample extends StatelessWidget {
  final Color color;
  const ColorSample({super.key, required this.color});
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 38,
    height: 26,
    child: ClipRRect(
      borderRadius: BorderRadius.circular(5),
      child: CustomPaint(painter: _ColorSamplePainter(color)),
    ),
  );
}

class _ColorSamplePainter extends CustomPainter {
  final Color color;
  _ColorSamplePainter(this.color);
  @override
  void paint(Canvas canvas, Size size) {
    for (double y = 0; y < size.height; y += 6) {
      for (double x = 0; x < size.width; x += 6) {
        canvas.drawRect(
          Rect.fromLTWH(x, y, 6, 6),
          Paint()
            ..color = ((x ~/ 6 + y ~/ 6) % 2 == 0
                ? Colors.white
                : const Color(0xffdfe1e5)),
        );
      }
    }
    canvas.drawRect(Offset.zero & size, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_ColorSamplePainter old) => old.color != color;
}

class ReminderPreview extends StatelessWidget {
  final ReminderStyle style;
  const ReminderPreview({super.key, required this.style});
  @override
  Widget build(BuildContext context) {
    final bytes = imageBytes(style.background);
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(
        height: 110,
        child: Stack(
          fit: StackFit.expand,
          children: [
            const ColoredBox(color: Color(0xfff3f4f6)),
            if (bytes != null)
              Image.memory(bytes, fit: BoxFit.cover, gaplessPlayback: true),
            if (bytes != null) const ColoredBox(color: Color(0xbfffffff)),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Identity(data: style.avatar, size: 32),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      style.message.isEmpty ? '日程提醒' : style.message,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        color: ink,
                        height: 1.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
