import 'package:flutter_test/flutter_test.dart';
import 'package:needtodo/platform_services.dart';

void main() {
  test('startup restores each choice and accepts the old list entry', () {
    const exe = r'D:\我的程序\Need TODO\needtodo.exe';
    for (final selection in [
      const StartupSelection(list: true),
      const StartupSelection(calendar: true),
      const StartupSelection(list: true, calendar: true),
    ]) {
      final restored = StartupSelection.fromCommand(
        selection.command(exe),
        exe,
      );
      expect(restored.list, selection.list);
      expect(restored.calendar, selection.calendar);
      final launch = StartupSelection.launch(selection.arguments)!;
      expect(launch.list, selection.list);
      expect(launch.calendar, selection.calendar);
    }
    expect(StartupSelection.fromCommand('"$exe"', exe).list, true);
    expect(StartupSelection.fromCommand('"$exe"', exe).calendar, false);
    expect(
      StartupSelection.fromCommand(
        '"$exe.old" --startup --startup-list',
        exe,
      ).enabled,
      false,
    );
    expect(StartupSelection.fromCommand('', exe).enabled, false);
    expect(const StartupSelection().enabled, false);
    expect(StartupSelection.launch([]), isNull);
    expect(StartupSelection.launch(['--calendar', '1234', 'secret']), isNull);
  });
}
