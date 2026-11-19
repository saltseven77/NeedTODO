import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:needtodo/model.dart';
import 'package:needtodo/ui/categories.dart';

void main() {
  testWidgets(
    'durations and expansion arrows align across different text lengths',
    (tester) async {
      tester.view.physicalSize = const Size(360, 780);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MonthOverview(
              tasks: [
                Todo(
                  title: 'a',
                  date: '2026-11-01',
                  category: '学校',
                  startMinute: 0,
                  endMinute: 60,
                ),
                Todo(
                  title: 'b',
                  date: '2026-11-01',
                  category: '很长的分类名称',
                  startMinute: 0,
                  endMinute: 135,
                ),
                Todo(
                  title: 'c',
                  date: '2026-11-01',
                  category: '生活',
                  startMinute: 0,
                  endMinute: 300,
                ),
              ],
              appearance: Appearance(),
              month: DateTime(2026, 11),
              today: DateTime(2026, 11, 19),
              edit: (_) {},
              toggle: (_) {},
            ),
          ),
        ),
      );
      final arrows = find.byIcon(CupertinoIcons.chevron_down);
      expect(arrows, findsNWidgets(3));
      final right = tester.getRect(arrows.first).right;
      for (var i = 1; i < 3; i++) {
        expect(tester.getRect(arrows.at(i)).right, closeTo(right, .01));
      }
      final durations = ['1 小时', '2 小时 15 分钟', '5 小时'];
      final textRight = tester.getRect(find.text(durations.first)).right;
      for (final duration in durations) {
        expect(
          tester.getRect(find.text(duration)).right,
          closeTo(textRight, .01),
        );
      }
      expect(tester.takeException(), isNull);
    },
  );
}
