import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../updates.dart';

final updateNavigatorKey = GlobalKey<NavigatorState>();

Future<void> showReleaseUpdate(BuildContext context, ReleaseUpdate update) =>
    showCupertinoDialog<void>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: Text('泥土豆 ${update.version}'),
        content: Padding(
          padding: const EdgeInsets.only(top: 12),
          child: SizedBox(
            width: 300,
            height: 200,
            child: SingleChildScrollView(
              child: Text(
                update.notes.isEmpty ? '有新版本可供下载。' : update.notes,
                textAlign: TextAlign.left,
                style: const TextStyle(fontSize: 12, height: 1.6),
              ),
            ),
          ),
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(context),
            child: const Text('稍后'),
          ),
          CupertinoDialogAction(
            onPressed: () async {
              final navigatorContext = Navigator.of(context).context;
              bool opened = false;
              try {
                opened = await launchUrl(
                  update.url,
                  mode: LaunchMode.externalApplication,
                );
              } catch (_) {}

              if (context.mounted) {
                Navigator.pop(context);
                if (!opened && navigatorContext.mounted) {
                  await showCupertinoDialog<void>(
                    context: navigatorContext,
                    builder: (context) => CupertinoAlertDialog(
                      title: const Text('无法打开下载链接'),
                      content: SelectableText(update.url.toString()),
                      actions: [
                        CupertinoDialogAction(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('好'),
                        ),
                      ],
                    ),
                  );
                }
              }
            },
            child: const Text('下载更新'),
          ),
        ],
      ),
    );

class UpdatePreferences extends StatelessWidget {
  const UpdatePreferences({super.key});
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: appUpdates,
    builder: (context, _) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                appUpdates.version.isEmpty
                    ? '泥土豆'
                    : '当前版本 ${appUpdates.version}',
                style: const TextStyle(fontSize: 12),
              ),
            ),
            TextButton(
              onPressed: appUpdates.checking
                  ? null
                  : () async {
                      final update = await appUpdates.check();
                      if (update != null && context.mounted) {
                        await showReleaseUpdate(context, update);
                      }
                    },
              child: Text(
                appUpdates.checking
                    ? '检查中…'
                    : appUpdates.available != null
                    ? '发现新版本'
                    : '检查更新',
              ),
            ),
          ],
        ),
        if (appUpdates.error != null ||
            (appUpdates.checked && appUpdates.available == null))
          Text(
            appUpdates.error ?? '已是最新版本',
            style: const TextStyle(fontSize: 11, color: Color(0xff8b8e94)),
          ),
        if (appUpdates.error != null)
          TextButton(
            onPressed: () => launchUrl(
              Uri.parse(
                'https://github.com/saltseven77/NeedTODO/releases/latest',
              ),
              mode: LaunchMode.externalApplication,
            ),
            child: const Text('前往下载页'),
          ),
      ],
    ),
  );
}
