import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../model.dart';
import 'components.dart';

class WidgetPreferences extends StatelessWidget {
  final Appearance appearance;
  final bool busy;
  final void Function(VoidCallback) change;
  final void Function(String) add;
  final VoidCallback? chooseBackground;
  const WidgetPreferences({
    super.key,
    required this.appearance,
    required this.busy,
    required this.change,
    required this.add,
    this.chooseBackground,
  });
  @override
  Widget build(BuildContext context) {
    final p = appearance.palette;
    final background = imageBytes(appearance.background);
    Widget card(String kind, String name, String size) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AspectRatio(
          aspectRatio: kind == 'agenda' ? 1.95 : 1.45,
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: p.background.withValues(
                alpha: p.background.a * appearance.opacity,
              ),
              image: background == null
                  ? null
                  : DecorationImage(
                      image: MemoryImage(background),
                      fit: BoxFit.cover,
                      opacity: appearance.imageOpacity,
                    ),
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
    Widget colour(String label, Color value, ValueChanged<Color> update) =>
        SizedBox(
          height: 44,
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(fontSize: 13, color: ink),
                ),
              ),
              TextButton(
                onPressed: busy
                    ? null
                    : () async {
                        final result = await showPanel<Color>(
                          context,
                          label,
                          ColorEditor(initial: value, onPreview: update),
                          width: 410,
                        );
                        update(result ?? value);
                      },
                child: Container(
                  width: 25,
                  height: 25,
                  decoration: BoxDecoration(
                    color: value,
                    borderRadius: BorderRadius.circular(7),
                    border: Border.all(
                      color: const Color(0xffdedfe3),
                      width: .7,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
    Widget adjustment(
      String label,
      double value,
      double max,
      String summary,
      ValueChanged<double> update,
    ) => SizedBox(
      height: 52,
      child: Row(
        children: [
          SizedBox(
            width: 76,
            child: Text(
              label,
              style: const TextStyle(fontSize: 13, color: ink),
            ),
          ),
          Expanded(
            child: Slider(
              value: value,
              max: max,
              onChanged: busy ? null : update,
            ),
          ),
          SizedBox(
            width: 38,
            child: Text(
              summary,
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 12, color: muted),
            ),
          ),
        ],
      ),
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
        const SizedBox(height: 20),
        const Padding(
          padding: EdgeInsets.only(left: 2, bottom: 10),
          child: Text('外观', style: TextStyle(fontSize: 12, color: muted)),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xffe9eaed), width: .5),
          ),
          child: Column(
            children: [
              SizedBox(
                height: 44,
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        '背景图片',
                        style: TextStyle(fontSize: 13, color: ink),
                      ),
                    ),
                    TextButton(
                      onPressed: busy ? null : chooseBackground,
                      child: Text(background == null ? '选择图片' : '更换图片'),
                    ),
                    if (background != null)
                      IconButton(
                        tooltip: '移除背景图片',
                        onPressed: busy
                            ? null
                            : () => change(() => appearance.background = ''),
                        icon: const Icon(CupertinoIcons.xmark, size: 15),
                      ),
                  ],
                ),
              ),
              const Divider(height: 1, thickness: .5, color: Color(0xffeceef1)),
              colour('底色', p.background, (v) => change(() => p.background = v)),
              colour('文字', p.text, (v) => change(() => p.text = v)),
              colour('强调色', p.accent, (v) => change(() => p.accent = v)),
              const Divider(height: 1, thickness: .5, color: Color(0xffeceef1)),
              if (background != null)
                adjustment(
                  '图片透明度',
                  appearance.imageOpacity,
                  1,
                  '${(appearance.imageOpacity * 100).round()}%',
                  (v) => change(() => appearance.imageOpacity = v),
                ),
              adjustment(
                '透明度',
                appearance.opacity,
                1,
                '${(appearance.opacity * 100).round()}%',
                (v) => change(() => appearance.opacity = v),
              ),
              adjustment(
                '圆角',
                appearance.radius.clamp(0, 24),
                24,
                '${appearance.radius.round()}',
                (v) => change(() => appearance.radius = v),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
      ],
    );
  }
}
