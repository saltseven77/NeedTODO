import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:needtodo/model.dart';
import 'package:needtodo/store.dart';
import 'package:needtodo/platform_services.dart';
import 'package:needtodo/ui/preferences.dart';

import 'memory_storage.dart';

const user = {'id': 'shared-user', 'username': 'test', 'githubLogin': 'linked'};

class SharedCloud {
  Document document = Document();
  int revision = 0;
  final sent = <Document>[];
}

class DeviceStore extends AppStore {
  final SharedCloud cloud;
  DeviceStore(super.storage, this.cloud);
  @override
  Future<Map<String, dynamic>> request(
    String method,
    String path, [
    Map<String, dynamic>? body,
  ]) async {
    if (path == '/v2/account') return {'account': user};
    if (method == 'GET') {
      return {'revision': cloud.revision, 'document': cloud.document.toJson()};
    }
    cloud.document = Document.fromJson(object(body!['document']));
    cloud.sent.add(cloud.document.clone());
    return {'revision': ++cloud.revision, 'document': cloud.document.toJson()};
  }
}

void main() {
  test('device appearance persists and stays out of cloud sync while schedules remain shared', () async {
    FlutterSecureStorage.setMockInitialValues({'session': 'fixture-token'});
    final cloud = SharedCloud();
    cloud.document.calendar.palette.background = Colors.grey;
    cloud.document.calendar.updated = DateTime.now().toUtc();
    final desktopStorage = MemoryStorage(), phoneStorage = MemoryStorage();
    final desktop = DeviceStore(desktopStorage, cloud)..account = {...user};
    final phone = DeviceStore(phoneStorage, cloud)..account = {...user};
    await desktop.sync();
    await phone.sync();
    expect(
      desktop.document.calendar.palette.background,
      phone.document.calendar.palette.background,
    );
    final custom = phone.document.calendar.clone();
    custom.palette.background = Colors.white;
    await phone.saveAppearance('calendar', custom);
    await phone.saveTask(Todo(title: 'Shared schedule', date: '2026-10-05'));
    await phone.sync();
    await desktop.sync();
    expect(phone.document.calendar.palette.background, Colors.white);
    expect(
      desktop.document.calendar.palette.background.toARGB32(),
      Colors.grey.toARGB32(),
    );
    expect(desktop.document.tasks.single.title, 'Shared schedule');
    expect(
      cloud.document.calendar.palette.background.toARGB32(),
      Colors.grey.toARGB32(),
    );
    final other = desktop.document.calendar.clone();
    other.palette.background = Colors.black;
    await desktop.saveAppearance('calendar', other);
    await desktop.sync();
    await phone.sync();
    expect(desktop.document.calendar.palette.background, Colors.black);
    expect(phone.document.calendar.palette.background, Colors.white);
    expect(
      cloud.sent.every(
        (d) =>
            d.calendar.palette.background.toARGB32() == Colors.grey.toARGB32(),
      ),
      true,
    );
    await phoneStorage.write('session', {'local': false, 'account': user});
    await phone.shutdown();
    final reopened = DeviceStore(phoneStorage, cloud);
    await reopened.load();
    await reopened.sync();
    expect(reopened.document.calendar.palette.background, Colors.white);
    expect(reopened.document.tasks.single.title, 'Shared schedule');
    expect(reopened.widgetAppearance.palette.background, Colors.white);
    await reopened.shutdown();
    await desktop.shutdown();
  });

  testWidgets('widget chooser offers both sizes without device labels', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = AppStore(MemoryStorage())..local = true;
    final services = PlatformServices(android: true);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: SettingsView(
                store: store,
                services: services,
                layout: 'calendar',
                preview: (_) {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('组件'));
    await tester.pumpAndSettle();
    expect(find.text('添加日程 · 4×2'), findsOneWidget);
    expect(find.text('添加月历 · 4×3'), findsOneWidget);
    expect(find.text('电脑'), findsNothing);
    expect(find.text('手机'), findsNothing);
    expect(find.text('透明度'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    services.dispose();
    await store.shutdown();
  });
}
