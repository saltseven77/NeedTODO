import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:needtodo/app.dart';
import 'package:needtodo/model.dart';
import 'package:needtodo/platform_services.dart';
import 'package:needtodo/store.dart';
import 'package:needtodo/ui/preferences.dart';

import 'memory_storage.dart';

void main() {
  testWidgets(
    'phone daily, weekly, monthly and calendar views omit completion fractions',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = AppStore(MemoryStorage())
        ..ready = true
        ..local = true;
      store.document.tasks = [
        Todo(title: '待办', date: dayKey(DateTime.now()), category: '生活'),
        Todo(
          title: '已完成',
          date: dayKey(DateTime.now()),
          done: true,
          category: '生活',
        ),
      ];
      final fraction = find.byWidgetPredicate(
        (w) => w is Text && RegExp(r'^\d+\s*/\s*\d+$').hasMatch(w.data ?? ''),
      );
      await tester.pumpWidget(NeedTodoApp(store: store));
      await tester.pumpAndSettle();
      await tester.tap(find.text('任务'));
      await tester.pumpAndSettle();
      expect(fraction, findsNothing);
      await tester.tap(find.text('周计划'));
      await tester.pumpAndSettle();
      expect(fraction, findsNothing);
      await tester.tap(find.text('月计划'));
      await tester.pumpAndSettle();
      expect(fraction, findsNothing);
      await tester.tap(find.byTooltip('月历'));
      await tester.pumpAndSettle();
      expect(fraction, findsNothing);
      await tester.pumpWidget(const SizedBox());
      await store.shutdown();
    },
  );
  testWidgets(
    'settings omit exit software and widgets offer background images',
    (tester) async {
      final store = AppStore(MemoryStorage())..local = true;
      final services = PlatformServices(android: true);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: SettingsView(
                store: store,
                services: services,
                layout: 'list',
                preview: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('组件'));
      await tester.pumpAndSettle();
      expect(find.text('背景图片'), findsOneWidget);
      expect(find.text('选择图片'), findsOneWidget);
      expect(find.text('退出软件'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      services.dispose();
      await store.shutdown();
    },
  );
}
