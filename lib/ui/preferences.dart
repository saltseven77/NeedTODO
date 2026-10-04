import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../model.dart';
import '../platform_services.dart';
import '../store.dart';
import 'components.dart';
import 'settings.dart';

/// Fixed neutral appearance, independent of the workspace's user palette.
ThemeData preferencesTheme(BuildContext context) {
  final theme = appTheme();
  final touch =
      MediaQuery.sizeOf(context).shortestSide < 600 && !Platform.isWindows;
  return theme.copyWith(
    visualDensity: touch ? VisualDensity.standard : VisualDensity.compact,
    textTheme: theme.textTheme.copyWith(
      bodyMedium: const TextStyle(fontSize: 12, color: ink),
      bodySmall: const TextStyle(fontSize: 11, color: muted),
    ),
    inputDecorationTheme: InputDecorationTheme(
      isDense: true,
      filled: true,
      fillColor: const Color(0xfff1f2f5),
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(7),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(7),
        borderSide: BorderSide.none,
      ),
      counterStyle: const TextStyle(fontSize: 10),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: blue,
        textStyle: const TextStyle(
          fontSize: 11,
          fontFamily: 'Segoe UI',
          fontFamilyFallback: ['PingFang SC', 'Microsoft YaHei UI'],
        ),
        minimumSize: Size(30, touch ? 40 : 30),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: blue,
        foregroundColor: Colors.white,
        textStyle: const TextStyle(
          fontSize: 12,
          fontFamily: 'Segoe UI',
          fontFamilyFallback: ['PingFang SC', 'Microsoft YaHei UI'],
        ),
        minimumSize: Size(56, touch ? 40 : 32),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        foregroundColor: muted,
        minimumSize: Size.square(touch ? 36 : 28),
        maximumSize: Size.square(touch ? 40 : 30),
        padding: const EdgeInsets.all(5),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    ),
    sliderTheme: theme.sliderTheme.copyWith(
      trackHeight: 2,
      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
      overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
    ),
  );
}

class SettingsView extends StatefulWidget {
  final AppStore store;
  final String layout;
  final ValueChanged<Appearance?> preview;
  final DesktopController? desktop;
  const SettingsView({
    super.key,
    required this.store,
    required this.layout,
    required this.preview,
    this.desktop,
  });
  @override
  State<SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends State<SettingsView> {
  late String tab = widget.layout;
  late final drafts = {
    'list': widget.store.document.list.clone(),
    'calendar': widget.store.document.calendar.clone(),
  };
  late final reminders = widget.store.document.reminders.clone();
  final dirtyProfiles = <String>{};
  bool remindersDirty = false, startupLoading = true;
  StartupSelection startup = const StartupSelection();
  String get activeLayout => tab == 'calendar' ? 'calendar' : 'list';
  Appearance get draft => drafts[activeLayout]!;
  @override
  void initState() {
    super.initState();
    if (Platform.isWindows) {
      WindowsStartup.selection()
          .then((v) {
            if (mounted) setState(() => startup = v);
          })
          .catchError((Object _) {})
          .whenComplete(() {
            if (mounted) setState(() => startupLoading = false);
          });
    }
  }

  void changeReminder(VoidCallback fn) {
    setState(fn);
    remindersDirty = true;
  }

  Future<void> changeStartup(StartupSelection next) => run(() async {
    await WindowsStartup.setSelection(next);
    if (mounted) setState(() => startup = next);
  });

  bool busy = false, editingPalette = false, editingLevels = false;
  String? error;
  void change(VoidCallback fn) {
    setState(fn);
    dirtyProfiles.add(activeLayout);
    widget.preview(activeLayout == widget.layout ? draft.clone() : null);
  }

  Future<void> run(Future<void> Function() fn) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await fn();
    } catch (e) {
      if (mounted) {
        setState(() => error = e.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Widget field(
    String label,
    String value,
    ValueChanged<String> edit, {
    String? id,
    int max = 24,
  }) => TextFormField(
    key: ValueKey(id == null ? '$tab-$label' : '$tab-$id'),
    initialValue: value,
    maxLength: max,
    style: const TextStyle(fontSize: 12),
    decoration: InputDecoration(hintText: label, counterText: ''),
    onChanged: edit,
  );
  Widget tools(List<Widget> children) =>
      Row(mainAxisSize: MainAxisSize.min, children: children);
  Widget section(String title, Widget child, {Widget? actions}) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: muted,
                ),
              ),
            ),
            ?actions,
          ],
        ),
        const SizedBox(height: 9),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xffe9eaed), width: .5),
          ),
          child: child,
        ),
      ],
    ),
  );
  Widget slider(
    String label,
    double value,
    ValueChanged<double> onChanged, {
    double max = 1,
  }) => SizedBox(
    height: 34,
    child: Row(
      children: [
        SizedBox(
          width: label.isEmpty ? 0 : 72,
          child: Text(
            label,
            style: const TextStyle(fontSize: 11, color: muted),
          ),
        ),
        Expanded(
          child: Slider(
            value: value.clamp(0, max),
            min: 0,
            max: max,
            onChanged: onChanged,
          ),
        ),
        SizedBox(
          width: 35,
          child: Text(
            max == 1 ? '${(value * 100).round()}%' : '${value.round()}',
            textAlign: TextAlign.right,
            style: const TextStyle(fontSize: 10, color: muted),
          ),
        ),
      ],
    ),
  );
  Widget toggle(String label, bool value, ValueChanged<bool>? onChanged) =>
      SizedBox(
        height: 38,
        child: Row(
          children: [
            Expanded(child: Text(label, style: const TextStyle(fontSize: 12))),
            Transform.scale(
              scale: .72,
              alignment: Alignment.centerRight,
              child: CupertinoSwitch(
                value: value,
                onChanged: onChanged,
                activeTrackColor: const Color(0xff659772),
              ),
            ),
          ],
        ),
      );
  Widget swatch(Color value, ValueChanged<Color> onChanged, String label) =>
      SizedBox(
        width: 32,
        height: 32,
        child: Tooltip(
          message: label,
          child: InkWell(
            borderRadius: BorderRadius.circular(7),
            onTap: () async {
              final initial = value;
              final result = await showPanel<Color>(
                context,
                label,
                ColorEditor(initial: value, onPreview: onChanged),
                width: 360,
              );
              onChanged(result ?? initial);
            },
            child: Center(
              child: Container(
                width: 21,
                height: 21,
                decoration: BoxDecoration(
                  color: value,
                  borderRadius: BorderRadius.circular(6),
                  boxShadow: const [
                    BoxShadow(color: Color(0x1a000000), blurRadius: 2),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
  Widget preset(
    String name,
    bool selected,
    Widget sample,
    VoidCallback choose,
  ) => Semantics(
    button: true,
    selected: selected,
    label: name,
    child: InkWell(
      onTap: choose,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(5),
        decoration: BoxDecoration(
          color: selected ? const Color(0xffedf3fa) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? const Color(0xffa1badb) : Colors.transparent,
          ),
        ),
        child: Column(
          children: [
            sample,
            const SizedBox(height: 4),
            Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 10, color: selected ? blue : muted),
            ),
          ],
        ),
      ),
    ),
  );
  @override
  Widget build(BuildContext context) {
    final p = draft.palette, levels = draft.levelSet;
    return Theme(
      data: preferencesTheme(context),
      child: Builder(
        builder: (context) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            CupertinoSlidingSegmentedControl<String>(
              groupValue: tab,
              children: const {
                'list': Text('清单'),
                'calendar': Text('月历'),
                'reminders': Text('日程'),
                'account': Text('账号'),
              },
              onValueChanged: (v) {
                if (v == null) return;
                setState(() {
                  tab = v;
                  editingPalette = false;
                  editingLevels = false;
                });
                widget.preview(v == widget.layout ? drafts[v]!.clone() : null);
              },
            ),
            const SizedBox(height: 18),
            if (tab == 'list' || tab == 'calendar') ...[
              Row(
                children: [
                  Tooltip(
                    message: '更换头像',
                    child: InkWell(
                      onTap: () => run(() async {
                        final v = await pickImage(context, crop: true);
                        if (v != null) change(() => draft.avatar = v);
                      }),
                      child: Identity(data: draft.avatar, size: 36),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: field(
                      '名称',
                      draft.name,
                      (v) => change(() => draft.name = v),
                    ),
                  ),
                  if (draft.avatar.isNotEmpty)
                    ActionIcon(
                      CupertinoIcons.xmark,
                      '重置头像',
                      () => change(() => draft.avatar = ''),
                    ),
                ],
              ),
              const SizedBox(height: 20),
              section(
                '外观',
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    GridView(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            mainAxisExtent: 60,
                            mainAxisSpacing: 6,
                            crossAxisSpacing: 6,
                          ),
                      children: draft.palettes
                          .map(
                            (v) => preset(
                              v.name,
                              v.id == draft.paletteId,
                              Container(
                                height: 27,
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 5,
                                ),
                                decoration: BoxDecoration(
                                  color: v.background.withValues(alpha: 1),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Container(
                                      width: 9,
                                      height: 3,
                                      color: v.accent,
                                    ),
                                    const SizedBox(height: 4),
                                    Container(
                                      width: 38,
                                      height: 2,
                                      color: v.text.withValues(alpha: .3),
                                    ),
                                    const SizedBox(height: 3),
                                    Container(
                                      width: 24,
                                      height: 2,
                                      color: v.text.withValues(alpha: .15),
                                    ),
                                  ],
                                ),
                              ),
                              () => change(() => draft.paletteId = v.id),
                            ),
                          )
                          .toList(),
                    ),
                    if (editingPalette) ...[
                      const SizedBox(height: 10),
                      field(
                        '配色名称',
                        p.name,
                        (v) => change(() => p.name = v),
                        id: p.id,
                        max: 16,
                      ),
                      const SizedBox(height: 6),
                      ...[
                        (
                          label: '背景',
                          color: p.background,
                          set: (Color v) => change(() => p.background = v),
                        ),
                        (
                          label: '文字',
                          color: p.text,
                          set: (Color v) => change(() => p.text = v),
                        ),
                        (
                          label: '强调',
                          color: p.accent,
                          set: (Color v) => change(() => p.accent = v),
                        ),
                        (
                          label: '线条',
                          color: p.line,
                          set: (Color v) => change(() => p.line = v),
                        ),
                      ].map(
                        (v) => Row(
                          children: [
                            Expanded(
                              child: Text(
                                v.label,
                                style: const TextStyle(fontSize: 12),
                              ),
                            ),
                            swatch(v.color, v.set, v.label),
                            SizedBox(
                              width: 140,
                              child: slider(
                                '',
                                v.color.a,
                                (a) => v.set(v.color.withValues(alpha: a)),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
                actions: tools([
                  Text(
                    '${draft.palettes.length}/7',
                    style: const TextStyle(fontSize: 10, color: muted),
                  ),
                  ActionIcon(
                    CupertinoIcons.add,
                    '新增配色',
                    draft.palettes.length >= 7
                        ? null
                        : () => change(() {
                            final c = p.clone()
                              ..id = newId()
                              ..name = '新配色';
                            draft.palettes.add(c);
                            draft.paletteId = c.id;
                            editingPalette = true;
                          }),
                  ),
                  ActionIcon(
                    CupertinoIcons.pencil,
                    '编辑配色',
                    () => setState(() => editingPalette = true),
                  ),
                  ActionIcon(
                    CupertinoIcons.trash,
                    '删除配色',
                    draft.palettes.length <= 1
                        ? null
                        : () => change(() {
                            draft.palettes.remove(p);
                            draft.paletteId = draft.palettes.first.id;
                          }),
                  ),
                ]),
              ),
              section(
                '日程颜色',
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    GridView(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            mainAxisExtent: 60,
                            mainAxisSpacing: 6,
                            crossAxisSpacing: 6,
                          ),
                      children: draft.levelSets
                          .map(
                            (s) => preset(
                              s.name,
                              s.id == draft.levelSetId,
                              SizedBox(
                                height: 27,
                                child: Column(
                                  children: s.levels
                                      .take(3)
                                      .map(
                                        (l) => Container(
                                          height: 7,
                                          margin: const EdgeInsets.only(
                                            bottom: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: l.color,
                                            borderRadius: BorderRadius.circular(
                                              3,
                                            ),
                                          ),
                                          alignment: Alignment.centerLeft,
                                          child: Container(
                                            width: 22,
                                            height: 2,
                                            margin: const EdgeInsets.only(
                                              left: 6,
                                            ),
                                            color: muted.withValues(alpha: .25),
                                          ),
                                        ),
                                      )
                                      .toList(),
                                ),
                              ),
                              () => change(() => draft.levelSetId = s.id),
                            ),
                          )
                          .toList(),
                    ),
                    if (editingLevels) ...[
                      const SizedBox(height: 10),
                      field(
                        '颜色组名称',
                        levels.name,
                        (v) => change(() => levels.name = v),
                        id: levels.id,
                        max: 16,
                      ),
                      const SizedBox(height: 8),
                    ],
                    ...levels.levels.map(
                      (level) => Padding(
                        padding: const EdgeInsets.only(top: 5),
                        child: Row(
                          children: [
                            Expanded(
                              child: field(
                                '分级',
                                level.name,
                                (v) => change(() => level.name = v),
                                id: '${levels.id}-${level.id}',
                                max: 16,
                              ),
                            ),
                            const SizedBox(width: 8),
                            swatch(
                              level.color,
                              (v) => change(() => level.color = v),
                              '分级颜色',
                            ),
                            swatch(
                              level.textColor ?? p.text,
                              (v) => change(() => level.textColor = v),
                              '标签文字颜色',
                            ),
                            ActionIcon(
                              CupertinoIcons.minus_circle,
                              '删除分级',
                              levels.levels.length <= 1
                                  ? null
                                  : () => change(
                                      () => levels.levels.remove(level),
                                    ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton(
                        onPressed: levels.levels.length >= 8
                            ? null
                            : () => change(
                                () => levels.levels.add(
                                  Level(
                                    newId(),
                                    '新分级',
                                    const Color(0x308198ae),
                                  ),
                                ),
                              ),
                        child: const Text('添加分级'),
                      ),
                    ),
                  ],
                ),
                actions: tools([
                  ActionIcon(
                    CupertinoIcons.add,
                    '新增颜色组',
                    draft.levelSets.length >= 7
                        ? null
                        : () => change(() {
                            final s = LevelSet.fromJson(levels.toJson())
                              ..id = newId()
                              ..name = '新颜色组';
                            draft.levelSets.add(s);
                            draft.levelSetId = s.id;
                            editingLevels = true;
                          }),
                  ),
                  ActionIcon(
                    CupertinoIcons.pencil,
                    '编辑颜色组',
                    () => setState(() => editingLevels = true),
                  ),
                  ActionIcon(
                    CupertinoIcons.trash,
                    '删除颜色组',
                    draft.levelSets.length <= 1
                        ? null
                        : () => change(() {
                            draft.levelSets.remove(levels);
                            draft.levelSetId = draft.levelSets.first.id;
                          }),
                  ),
                ]),
              ),
              section(
                '背景',
                Row(
                  children: [
                    SizedBox(
                      width: 65,
                      height: 65,
                      child: InkWell(
                        onTap: () => change(() => draft.background = ''),
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          decoration: BoxDecoration(
                            color: const Color(0xfff1f2f5),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                CupertinoIcons.nosign,
                                size: 20,
                                color: muted,
                              ),
                              SizedBox(height: 6),
                              Text(
                                '无背景',
                                style: TextStyle(fontSize: 10, color: muted),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: InkWell(
                        onTap: () => run(() async {
                          final v = await pickImage(
                            context,
                            crop: true,
                            ratio: activeLayout == 'calendar' ? 1.5 : .7,
                          );
                          if (v != null) change(() => draft.background = v);
                        }),
                        borderRadius: BorderRadius.circular(8),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            height: 65,
                            color: const Color(0xfff1f2f5),
                            child: imageBytes(draft.background) == null
                                ? const Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        CupertinoIcons.photo,
                                        size: 18,
                                        color: muted,
                                      ),
                                      SizedBox(width: 8),
                                      Text(
                                        '选择图片',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: muted,
                                        ),
                                      ),
                                    ],
                                  )
                                : Image.memory(
                                    imageBytes(draft.background)!,
                                    fit: BoxFit.cover,
                                    gaplessPlayback: true,
                                  ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (draft.background.isNotEmpty)
                slider(
                  '图片透明度',
                  draft.imageOpacity,
                  (v) => change(() => draft.imageOpacity = v),
                ),
              section(
                '效果',
                Column(
                  children: [
                    SizedBox(
                      width: double.infinity,
                      child: CupertinoSlidingSegmentedControl<String>(
                        groupValue: draft.effect,
                        padding: const EdgeInsets.all(3),
                        backgroundColor: const Color(0xffeff0f3),
                        children: {
                          for (final e in const {
                            'default': '默认',
                            'glass': '毛玻璃',
                            'paper': '纸张',
                            'jelly': '果冻',
                          }.entries)
                            e.key: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 3),
                              child: Text(
                                e.value,
                                style: const TextStyle(fontSize: 11),
                              ),
                            ),
                        },
                        onValueChanged: (v) {
                          if (v != null) change(() => draft.effect = v);
                        },
                      ),
                    ),
                    const SizedBox(height: 8),
                    slider(
                      '不透明度',
                      draft.opacity,
                      (v) => change(() => draft.opacity = v),
                    ),
                    slider(
                      '圆角',
                      draft.radius,
                      (v) => change(() => draft.radius = v),
                      max: 48,
                    ),
                    if (draft.effect != 'default') ...[
                      slider(
                        '效果强度',
                        draft.effectAmount,
                        (v) => change(() => draft.effectAmount = v),
                      ),
                      Row(
                        children: [
                          const Expanded(
                            child: Text(
                              '效果颜色',
                              style: TextStyle(fontSize: 11, color: muted),
                            ),
                          ),
                          swatch(
                            draft.effectColor,
                            (v) => change(() => draft.effectColor = v),
                            '效果颜色',
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              if (widget.desktop != null && activeLayout == widget.layout)
                section(
                  '窗口',
                  Column(
                    children: [
                      if (activeLayout == 'list')
                        Row(
                          children: [
                            const Expanded(
                              child: Text(
                                '悬浮球',
                                style: TextStyle(fontSize: 12),
                              ),
                            ),
                            InkWell(
                              onTap: () => run(() async {
                                final v = await pickImage(context);
                                if (v != null) {
                                  change(() => draft.floatingImage = v);
                                }
                              }),
                              child: Identity(
                                data: draft.floatingImage,
                                size: 28,
                              ),
                            ),
                            TextButton(
                              onPressed: () =>
                                  change(() => draft.floatingImage = ''),
                              child: const Text('重置'),
                            ),
                          ],
                        ),
                      toggle(
                        activeLayout == 'calendar' ? '锁定到桌面' : '锁定位置',
                        widget.desktop!.locked,
                        (v) => run(() async {
                          await widget.desktop!.setLocked(v);
                          if (mounted) setState(() {});
                        }),
                      ),
                    ],
                  ),
                ),
              if (Platform.isAndroid || Platform.isIOS)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: () => run(() async {
                      final ok = await native.invokeMethod<bool>('widgetPin');
                      if (ok != true && context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('长按桌面添加「泥土豆」小组件')),
                        );
                      }
                    }),
                    child: const Text('添加桌面小组件'),
                  ),
                ),
            ],
            if (tab == 'reminders') ...[
              section(
                '日程视图',
                toggle(
                  '默认显示24小时时间轴',
                  reminders.timeline,
                  (v) => changeReminder(() => reminders.timeline = v),
                ),
              ),
              section(
                '日程提醒',
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: Text('头像', style: TextStyle(fontSize: 12)),
                        ),
                        Tooltip(
                          message: '更换提醒头像',
                          child: InkWell(
                            onTap: () => run(() async {
                              final image = await pickImage(
                                context,
                                crop: true,
                              );
                              if (image != null && mounted) {
                                changeReminder(() => reminders.avatar = image);
                              }
                            }),
                            child: Identity(data: reminders.avatar, size: 32),
                          ),
                        ),
                        TextButton(
                          onPressed: () =>
                              changeReminder(() => reminders.avatar = ''),
                          child: const Text('重置'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    field(
                      '提醒语',
                      reminders.message,
                      (v) => changeReminder(() => reminders.message = v),
                      max: 80,
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Expanded(
                          child: Text('背景图', style: TextStyle(fontSize: 12)),
                        ),
                        TextButton(
                          onPressed: () => run(() async {
                            final image = await pickImage(
                              context,
                              crop: true,
                              ratio: 2.6,
                            );
                            if (image != null && mounted) {
                              changeReminder(
                                () => reminders.background = image,
                              );
                            }
                          }),
                          child: const Text('选择图片'),
                        ),
                        if (reminders.background.isNotEmpty)
                          TextButton(
                            onPressed: () =>
                                changeReminder(() => reminders.background = ''),
                            child: const Text('移除'),
                          ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    ReminderPreview(style: reminders),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: busy
                            ? null
                            : () => run(
                                () => widget.store.dispatch({
                                  'type': 'testReminder',
                                  'reminders': reminders.toJson(),
                                }),
                              ),
                        child: const Text('3秒后测试提醒'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (tab == 'account' && Platform.isWindows)
              section(
                '开机自启动',
                Column(
                  children: [
                    toggle(
                      '清单',
                      startup.list,
                      busy || startupLoading
                          ? null
                          : (v) => changeStartup(
                              StartupSelection(
                                list: v,
                                calendar: startup.calendar,
                              ),
                            ),
                    ),
                    toggle(
                      '桌面月历',
                      startup.calendar,
                      busy || startupLoading
                          ? null
                          : (v) => changeStartup(
                              StartupSelection(list: startup.list, calendar: v),
                            ),
                    ),
                  ],
                ),
              ),
            if (tab == 'account' && widget.store.peer != null)
              const Text(
                '请在主窗口管理账号',
                style: TextStyle(fontSize: 12, color: muted),
              ),
            if (tab == 'account' && widget.store.peer == null)
              section(
                '账号',
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.store.account?['username'] ?? '本机使用',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                    if (widget.store.account != null) ...[
                      TextButton(
                        onPressed: busy ? null : () => run(widget.store.sync),
                        child: const Text('同步'),
                      ),
                      TextButton(
                        onPressed: busy
                            ? null
                            : () => run(widget.store.bindGithub),
                        child: const Text('GitHub'),
                      ),
                    ],
                    TextButton(
                      onPressed: busy
                          ? null
                          : () => run(() async {
                              await widget.store.logout();
                              if (context.mounted) Navigator.pop(context);
                            }),
                      child: Text(widget.store.local ? '登录' : '退出'),
                    ),
                  ],
                ),
              ),
            if (error != null)
              Text(
                error!,
                style: const TextStyle(fontSize: 11, color: Colors.redAccent),
              ),
            Row(
              children: [
                const Spacer(),
                FilledButton(
                  onPressed:
                      busy || drafts.values.any((a) => a.name.trim().isEmpty)
                      ? null
                      : () => run(() async {
                          await widget.store.dispatch({
                            'type': 'preferences',
                            'profiles': {
                              for (final key in dirtyProfiles)
                                key: drafts[key]!.toJson(),
                            },
                            if (remindersDirty) 'reminders': reminders.toJson(),
                          });
                          if (context.mounted) Navigator.pop(context);
                        }),
                  child: const Text('保存'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
