import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../model.dart';
import 'components.dart';

class WidgetPreferences extends StatelessWidget {
  final Appearance appearance;
  final bool busy;
  final void Function(VoidCallback) change;
  final void Function(String) add;
  const WidgetPreferences({
    super.key,
    required this.appearance,
    required this.busy,
    required this.change,
    required this.add,
  });
  @override
  Widget build(BuildContext context) {
    final p = appearance.palette;
    Widget card(String kind, String name, String size) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AspectRatio(
          aspectRatio: kind == 'agenda' ? 1.95 : 1.45,
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: p.background.withValues(alpha: appearance.opacity),
              borderRadius: BorderRadius.circular(
                appearance.radius.clamp(0, 24),
              ),
            ),
            child: kind == 'agenda'
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '10月5日 星期一',
                              style: TextStyle(fontSize: 11, color: p.text),
                            ),
                          ),
                          Icon(CupertinoIcons.add, size: 14, color: p.text),
                        ],
                      ),
                      const SizedBox(height: 8),
                      for (final row in ['09:30  阅读与记录', '14:00  整理日程'])
                        Expanded(
                          child: Row(
                            children: [
                              Container(width: 2, height: 18, color: p.accent),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  row,
                                  style: TextStyle(fontSize: 10, color: p.text),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  )
                : Column(
                    children: [
                      Row(
                        children: [
                          Icon(
                            CupertinoIcons.chevron_left,
                            size: 12,
                            color: p.text,
                          ),
                          Expanded(
                            child: Text(
                              '2026年10月',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 11, color: p.text),
                            ),
                          ),
                          Icon(
                            CupertinoIcons.chevron_right,
                            size: 12,
                            color: p.text,
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Expanded(
                        child: LayoutBuilder(
                          builder: (_, c) => GridView.count(
                            physics: const NeverScrollableScrollPhysics(),
                            padding: EdgeInsets.zero,
                            crossAxisCount: 7,
                            childAspectRatio:
                                (c.maxWidth / 7) / (c.maxHeight / 5),
                            children: [
                              for (var n = 1; n <= 35; n++)
                                Center(
                                  child: Container(
                                    width: 17,
                                    height: 17,
                                    alignment: Alignment.center,
                                    decoration: n == 5
                                        ? BoxDecoration(
                                            color: p.accent,
                                            shape: BoxShape.circle,
                                          )
                                        : null,
                                    child: Text(
                                      n <= 31 ? '$n' : '',
                                      style: TextStyle(
                                        fontSize: 9,
                                        color: n == 5 ? Colors.white : p.text,
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
        const SizedBox(height: 4),
        TextButton(
          onPressed: busy ? null : () => add(kind),
          child: Text('添加$name · $size'),
        ),
      ],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: card('agenda', '日程', '4×2')),
            const SizedBox(width: 12),
            Expanded(child: card('calendar', '月历', '4×3')),
          ],
        ),
        const SizedBox(height: 14),
        const Text('外观', style: TextStyle(fontSize: 12, color: muted)),
        ColorField('底色', p.background, (v) => change(() => p.background = v)),
        ColorField('文字', p.text, (v) => change(() => p.text = v)),
        ColorField('强调色', p.accent, (v) => change(() => p.accent = v)),
        Row(
          children: [
            const SizedBox(
              width: 65,
              child: Text('透明度', style: TextStyle(fontSize: 12)),
            ),
            Expanded(
              child: Slider(
                value: appearance.opacity,
                onChanged: busy
                    ? null
                    : (v) => change(() => appearance.opacity = v),
              ),
            ),
          ],
        ),
        Row(
          children: [
            const SizedBox(
              width: 65,
              child: Text('圆角', style: TextStyle(fontSize: 12)),
            ),
            Expanded(
              child: Slider(
                value: appearance.radius.clamp(0, 24),
                max: 24,
                onChanged: busy
                    ? null
                    : (v) => change(() => appearance.radius = v),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
