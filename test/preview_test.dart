import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:needtodo/app.dart';
import 'package:needtodo/model.dart';
import 'package:needtodo/course.dart';
import 'package:needtodo/ui/components.dart';
import 'package:needtodo/ui/timetable.dart';
import 'package:needtodo/store.dart';
import 'package:needtodo/platform_services.dart';
import 'package:needtodo/ui/floating_note.dart';

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
    await tester.drag(
      find.byType(SingleChildScrollView).first,
      const Offset(0, 420),
    );
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
    final now = DateTime.now();
    store.document.courses = [
      Course(
        name: '高等数学',
        room: '教学楼 A-301',
        termStart: now,
        weekday: 1,
        startPeriod: 1,
        endPeriod: 2,
        color: 0xfff5daec,
        textColor: 0xff64526c,
      ),
      Course(
        name: '大学英语',
        room: '外语楼 B-205',
        termStart: now,
        weekday: 1,
        startPeriod: 3,
        endPeriod: 4,
        color: 0xfff5daec,
        textColor: 0xff64526c,
      ),
      Course(
        name: 'Python 程序设计',
        room: '信息楼 机房2',
        termStart: now,
        weekday: 2,
        startPeriod: 5,
        endPeriod: 6,
        color: 0xfff1c4df,
        textColor: 0xff64526c,
      ),
      Course(
        name: '电子电路实验',
        room: '实训楼 实验室',
        termStart: now,
        weekday: 2,
        startPeriod: 7,
        endPeriod: 8,
        color: 0xffe0d8f4,
        textColor: 0xff64526c,
      ),
      Course(
        name: '数据结构',
        room: '教学楼 A-405',
        termStart: now,
        weekday: 3,
        startPeriod: 1,
        endPeriod: 2,
        color: 0xfff1c4df,
        textColor: 0xff64526c,
      ),
      Course(
        name: '大学体育（篮球）',
        room: '体育馆 篮球场',
        termStart: now,
        weekday: 3,
        startPeriod: 5,
        endPeriod: 6,
        color: 0xffc3b2ed,
        textColor: 0xff514668,
      ),
      Course(
        name: '线性代数',
        room: '教学楼 C-102',
        termStart: now,
        weekday: 4,
        startPeriod: 3,
        endPeriod: 4,
        color: 0xffc3b2ed,
        textColor: 0xff514668,
      ),
      Course(
        name: '思想道德与法治',
        room: '综合楼 阶梯1',
        termStart: now,
        weekday: 5,
        startPeriod: 5,
        endPeriod: 6,
        color: 0xffe0d8f4,
        textColor: 0xff64526c,
      ),
    ];
    for (final size in [const Size(390, 844), const Size(1100, 800)]) {
      tester.view.physicalSize = size;
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: appTheme(),
            home: Scaffold(
              body: SafeArea(
                child: Timetable(key: UniqueKey(), store: store),
              ),
            ),
          ),
        ),
      );
      await shot(size.width < 760 ? 'timetable-phone' : 'timetable-desktop');
    }
    tester.view.physicalSize = const Size(480, 860);
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundary,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: appTheme(),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showPanel<void>(
                  context,
                  '编辑课程',
                  CourseEditor(
                    store: store,
                    initial: store.document.courses.first,
                    date: now,
                  ),
                  width: 420,
                ),
                child: const Text('打开课程编辑'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开课程编辑'));
    await shot('course-editor');
    tester.view.physicalSize = const Size(380, 330);
    final noteDesktop = DesktopController(MemoryStorage(), calendar: false)
      ..collapsed = true
      ..noteVisible = true;
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundary,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: appTheme(),
          home: FloatingNote(
            desktop: noteDesktop,
            appearance: store.document.list,
            tasks: store.document.tasks,
            open: () {},
            menu: () {},
          ),
        ),
      ),
    );
    await shot('floating-note');
    await tester.pumpWidget(const SizedBox());
    noteDesktop.dispose();
  });
}
