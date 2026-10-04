import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:needtodo/app.dart';
import 'package:needtodo/model.dart';
import 'package:needtodo/store.dart';
import 'package:needtodo/platform_services.dart';

import 'memory_storage.dart';

void main() {
  testWidgets('export phone and tablet previews', (tester) async {
    if (!Platform.isWindows) return;
    final icons = FontLoader('packages/cupertino_icons/CupertinoIcons')
      ..addFont(
        rootBundle.load('packages/cupertino_icons/assets/CupertinoIcons.ttf'),
      );
    await icons.load();
    final material = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await material.load();
    final font = File('C:/Windows/Fonts/msyh.ttc');
    if (font.existsSync()) {
      final loader = FontLoader('Segoe UI')
        ..addFont(Future.value(ByteData.sublistView(font.readAsBytesSync())));
      await loader.load();
    }
    final store = AppStore(MemoryStorage())
      ..ready = true
      ..local = true;
    final today = dayKey(DateTime.now());
    store.document.tasks = [
      Todo(title: '整理本周计划', date: today, level: 'important', category: '工作'),
      Todo(title: '读完一本书的第一章', date: today, category: '学习'),
      Todo(title: '散步 30 分钟', date: today, done: true, category: '生活'),
      Todo(title: '设计评审', date: today, level: 'urgent'),
      Todo(
        title: '项目讨论',
        date: today,
        startMinute: 540,
        endMinute: 660,
        level: 'important',
      ),
      Todo(title: '整理方案', date: today, startMinute: 570, endMinute: 780),
    ];
    store.document.holidays = [
      Holiday(
        name: '休假',
        start: today,
        end: dayKey(DateTime.now().add(const Duration(days: 4))),
      ),
    ];
    final boundary = GlobalKey();
    final directory = Directory('.cache/previews')..createSync(recursive: true);
    Future<void> shot(String name) async {
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        final image =
            await (boundary.currentContext!.findRenderObject()
                    as RenderRepaintBoundary)
                .toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        File('${directory.path}/$name.png')
            .writeAsBytesSync(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }

    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundary,
        child: NeedTodoApp(store: store),
      ),
    );
    await tester.runAsync(
      () => precacheImage(
        const AssetImage('assets/potato.png'),
        boundary.currentContext!,
      ),
    );
    await shot('phone-list');
    await tester.tap(find.byTooltip('详细添加'));
    await shot('task-editor');
    await tester.tap(find.byTooltip('任务类别'));
    await shot('category-menu');
    await tester.tap(find.text('新建类别'));
    await shot('category-create');
    await tester.tap(find.text('取消').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('关闭'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('24小时'));
    await tester.pumpAndSettle();
    await shot('timeline');
    await tester.tap(find.text('任务'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('月计划'));
    await shot('month-categories');
    await tester.tap(find.text('日计划'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('月历'));
    await shot('phone-calendar');
    tester.view.physicalSize = const Size(1024, 768);
    await shot('tablet-calendar');
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundary,
        child: NeedTodoApp(
          key: UniqueKey(),
          store: store,
          desktop: DesktopController(MemoryStorage(), calendar: true),
        ),
      ),
    );
    await shot('desktop-calendar');
    await tester.tap(find.byTooltip('设置'));
    await shot('settings');
    await tester.tap(find.byTooltip('编辑配色'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('线条'));
    await shot('color-editor');
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('日程'));
    await tester.tap(find.text('日程'));
    await shot('reminder-settings');
    await tester.pumpWidget(const SizedBox());
  });
}
