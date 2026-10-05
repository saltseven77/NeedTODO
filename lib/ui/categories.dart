import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../model.dart';
import 'components.dart';
import 'preferences.dart' show preferencesTheme;

class CategoryPicker extends StatelessWidget {
  final List<String> categories;
  final String value;
  final ValueChanged<String> onChanged;
  const CategoryPicker({
    super.key,
    required this.categories,
    required this.value,
    required this.onChanged,
  });
  @override
  Widget build(BuildContext context) {
    final names = {...categories, if (value.isNotEmpty) value}.toList()..sort();
    final desktop = {
      TargetPlatform.windows,
      TargetPlatform.macOS,
      TargetPlatform.linux,
    }.contains(Theme.of(context).platform);
    final rowHeight = desktop ? 30.0 : 40.0;
    Widget option(String label, bool selected, {bool create = false}) =>
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          decoration: BoxDecoration(
            color: selected ? const Color(0xffeff5fa) : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            children: [
              if (create) ...[
                const Icon(CupertinoIcons.plus, size: 13, color: blue),
                const SizedBox(width: 7),
              ],
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w400,
                    color: create || selected ? blue : ink,
                    fontFamily: 'Segoe UI',
                    fontFamilyFallback: const [
                      'PingFang SC',
                      'Microsoft YaHei UI',
                    ],
                  ),
                ),
              ),
              if (!create)
                SizedBox(
                  width: 16,
                  child: selected
                      ? const Icon(
                          CupertinoIcons.checkmark_alt,
                          size: 14,
                          color: blue,
                        )
                      : null,
                ),
            ],
          ),
        );
    final menu = PopupMenuButton<int>(
      tooltip: '任务类别',
      color: Colors.white,
      surfaceTintColor: Colors.transparent,
      elevation: 3,
      shadowColor: const Color(0x18000000),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: Color(0xffe7e9ec), width: .6),
      ),
      menuPadding: const EdgeInsets.all(4),
      clipBehavior: Clip.antiAlias,
      constraints: const BoxConstraints(minWidth: 160, maxWidth: 240),
      position: PopupMenuPosition.under,
      offset: const Offset(0, 6),
      itemBuilder: (context) => [
        PopupMenuItem(
          value: -1,
          height: rowHeight,
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: option('未分类', value.isEmpty),
        ),
        for (var index = 0; index < names.length; index++)
          PopupMenuItem(
            value: index,
            height: rowHeight,
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: option(names[index], value == names[index]),
          ),
        const PopupMenuDivider(height: 8),
        PopupMenuItem(
          value: -2,
          height: rowHeight,
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: option('新建类别', false, create: true),
        ),
      ],
      onSelected: (index) async {
        if (index == -2) {
          final name = await showPanel<String>(
            context,
            '新建类别',
            const _CategoryName(),
            width: 320,
          );
          if (name != null) onChanged(name == '未分类' ? '' : name);
        } else {
          onChanged(index == -1 ? '' : names[index]);
        }
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 160),
              child: Text(
                value.isEmpty ? '未分类' : value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, color: ink),
              ),
            ),
            const SizedBox(width: 5),
            const Icon(CupertinoIcons.chevron_down, size: 10, color: muted),
          ],
        ),
      ),
    );
    return Row(
      children: [
        const Text('类别', style: TextStyle(fontSize: 12, color: ink)),
        const Spacer(),
        menu,
      ],
    );
  }
}

class _CategoryName extends StatefulWidget {
  const _CategoryName();
  @override
  State<_CategoryName> createState() => _CategoryNameState();
}

class _CategoryNameState extends State<_CategoryName> {
  final text = TextEditingController();
  @override
  void dispose() {
    text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Theme(
    data: preferencesTheme(context),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: text,
          autofocus: true,
          maxLength: 24,
          style: const TextStyle(fontSize: 12, color: ink),
          decoration: const InputDecoration(
            labelText: '类别名称',
            hintText: '例如：学习、工作、生活',
            counterText: '',
          ),
          onChanged: (_) => setState(() {}),
          onSubmitted: (value) {
            if (value.trim().isNotEmpty) Navigator.pop(context, value.trim());
          },
        ),
        const SizedBox(height: 14),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: text.text.trim().isEmpty
                  ? null
                  : () => Navigator.pop(context, text.text.trim()),
              child: const Text('确定'),
            ),
          ],
        ),
      ],
    ),
  );
}

class MonthOverview extends StatelessWidget {
  final bool showCounts;
  final List<Todo> tasks;
  final Appearance appearance;
  final DateTime month, today;
  final ValueChanged<Todo> edit, toggle;
  const MonthOverview({
    super.key,
    this.showCounts = true,
    required this.tasks,
    required this.appearance,
    required this.month,
    required this.today,
    required this.edit,
    required this.toggle,
  });
  @override
  Widget build(BuildContext context) {
    final items = tasksForPeriod(tasks, 'month', month), p = appearance.palette;
    final last = DateTime(month.year, month.month + 1, 0);
    final cutoff = today.isAfter(last) ? last : today;
    final checkins = monthCheckins(tasks, month, cutoff);
    final groups = <String, List<Todo>>{};
    for (final task in items) {
      groups.putIfAbsent(task.category, () => []).add(task);
    }
    final names = groups.keys.where((name) => name.isNotEmpty).toList()..sort();
    if (groups.containsKey('')) names.add('');
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '完美打卡 ${checkins.perfect} 天',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: p.text,
                ),
              ),
            ],
          ),
        ),
        if (items.isEmpty)
          Padding(
            padding: const EdgeInsets.all(24),
            child: Center(
              child: Text(
                '本月暂无任务',
                style: TextStyle(
                  fontSize: 13,
                  color: p.text.withValues(alpha: .5),
                ),
              ),
            ),
          ),
        for (final name in names)
          _CategoryProgress(
            showCounts: showCounts,
            key: ValueKey('category-$name'),
            name: name,
            tasks: groups[name]!,
            appearance: appearance,
            edit: edit,
            toggle: toggle,
          ),
      ],
    );
  }
}

class _CategoryProgress extends StatefulWidget {
  final bool showCounts;
  final String name;
  final List<Todo> tasks;
  final Appearance appearance;
  final ValueChanged<Todo> edit, toggle;
  const _CategoryProgress({
    super.key,
    required this.showCounts,
    required this.name,
    required this.tasks,
    required this.appearance,
    required this.edit,
    required this.toggle,
  });
  @override
  State<_CategoryProgress> createState() => _CategoryProgressState();
}

class _CategoryProgressState extends State<_CategoryProgress> {
  bool expanded = false;
  @override
  Widget build(BuildContext context) {
    final p = widget.appearance.palette,
        done = widget.tasks.where((task) => task.done).length;
    final base = p.text.computeLuminance() < .45
        ? Color.alphaBlend(p.background.withValues(alpha: .25), Colors.white)
        : p.background.withValues(alpha: 1);
    final rowColor = Color.alphaBlend(
      p.accent.withValues(alpha: expanded ? .17 : .025),
      base,
    );
    final ordered = [...widget.tasks]
      ..sort((a, b) => compareTaskTime(a, b, byDate: true));
    return Material(
      color: Colors.transparent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Ink(
            decoration: BoxDecoration(
              color: rowColor,
              borderRadius: BorderRadius.circular(8),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(6),
              onTap: () => setState(() => expanded = !expanded),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 12,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.name.isEmpty ? '未分类' : widget.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w400,
                          color: p.text,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 64,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(1),
                        child: LinearProgressIndicator(
                          value: done / widget.tasks.length,
                          minHeight: 2,
                          color: p.accent,
                          backgroundColor: p.accent.withValues(alpha: .13),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    if (widget.showCounts)
                      SizedBox(
                        width: 38,
                        child: Text(
                          '$done / ${widget.tasks.length}',
                          textAlign: TextAlign.right,
                          style: TextStyle(
                            fontSize: 11,
                            color: p.text.withValues(alpha: .6),
                          ),
                        ),
                      ),
                    const SizedBox(width: 10),
                    AnimatedRotation(
                      turns: expanded ? .5 : 0,
                      duration: const Duration(milliseconds: 150),
                      child: Icon(
                        CupertinoIcons.chevron_down,
                        size: 10,
                        color: p.text.withValues(alpha: .5),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 150),
            alignment: Alignment.topCenter,
            child: expanded
                ? Padding(
                    padding: const EdgeInsets.only(
                      left: 2,
                      right: 4,
                      bottom: 10,
                    ),
                    child: Column(
                      children: [
                        for (final task in ordered)
                          Row(
                            children: [
                              SizedBox(
                                width: 32,
                                child: IconButton(
                                  padding: EdgeInsets.zero,
                                  tooltip: task.done ? '取消完成' : '完成',
                                  onPressed: () => widget.toggle(task),
                                  icon: Icon(
                                    task.done
                                        ? CupertinoIcons
                                              .check_mark_circled_solid
                                        : CupertinoIcons.circle,
                                    size: 17,
                                    color: p.accent,
                                  ),
                                ),
                              ),
                              Expanded(
                                child: InkWell(
                                  onTap: () => widget.edit(task),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 7,
                                    ),
                                    child: Text(
                                      task.title,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: p.text.withValues(
                                          alpha: task.done ? .5 : 1,
                                        ),
                                        decoration: task.done
                                            ? TextDecoration.lineThrough
                                            : null,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                '${DateTime.parse(task.date).day}日',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: p.text.withValues(alpha: .45),
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                  )
                : const SizedBox.shrink(),
          ),
          const SizedBox(height: 6),
        ],
      ),
    );
  }
}
