import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:needtodo/updates.dart';

Map<String, dynamic> release() => {
  'tag_name': 'v1.0.10',
  'body': '修复与改进',
  'assets': [
    for (final name in [
      'Setup-1.0.10.exe',
      'Portable-1.0.10.zip',
      'Android-1.0.10.apk',
    ])
      {
        'name': 'NeedTODO-$name',
        'state': 'uploaded',
        'browser_download_url':
            'https://github.com/saltseven77/NeedTODO/releases/download/v1.0.10/NeedTODO-$name',
      },
  ],
};

void main() {
  test('release comparison is numeric and never downgrades', () {
    expect(newerVersion('v1.0.10', '1.0.9'), true);
    expect(newerVersion('v1.0.4', '1.0.5'), false);
    expect(newerVersion('v1.0.5', '1.0.5+14'), false);
    expect(newerVersion('v1.1.0-beta', '1.0.5'), false);
  });
  test('update offers the matching installer, portable zip or signed APK', () {
    expect(
      ReleaseUpdate.fromJson(release(), '1.0.5', platform: 'windows')!.url.path,
      endsWith('Setup-1.0.10.exe'),
    );
    expect(
      ReleaseUpdate.fromJson(
        release(),
        '1.0.5',
        platform: 'windows',
        portable: true,
      )!.url.path,
      endsWith('Portable-1.0.10.zip'),
    );
    expect(
      ReleaseUpdate.fromJson(release(), '1.0.5', platform: 'android')!.url.path,
      endsWith('Android-1.0.10.apk'),
    );
    expect(
      ReleaseUpdate.fromJson(
        {...release(), 'prerelease': true},
        '1.0.5',
        platform: 'windows',
      ),
      null,
    );
    final bad = release();
    (bad['assets'] as List).first['browser_download_url'] =
        'https://other.example/installer.exe';
    expect(
      ReleaseUpdate.fromJson(bad, '1.0.5', platform: 'windows')!.url.path,
      '/saltseven77/NeedTODO/releases/tag/v1.0.10',
    );
  });
  test(
    'public check needs no account and exposes notes for a newer version',
    () async {
      final updates = AppUpdates();
      final client = MockClient((request) async {
        expect(request.headers.containsKey('authorization'), false);
        return http.Response(
          jsonEncode(release()),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });
      final result = await updates.check(
        client: client,
        current: '1.0.5',
        platform: 'android',
        portable: false,
      );
      expect(result!.notes, '修复与改进');
      expect(updates.checking, false);
      expect(updates.error, null);
      client.close();
      updates.dispose();
    },
  );
  test(
    'failed check can retry and malformed responses are not called up to date',
    () async {
      final updates = AppUpdates();
      final failed = MockClient((_) async => http.Response('{}', 200));
      await updates.check(
        client: failed,
        current: '1.0.5',
        platform: 'windows',
      );
      expect(updates.error, isNotNull);
      expect(updates.checked, false);
      final recovered = MockClient(
        (_) async => http.Response(
          jsonEncode(release()),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        ),
      );
      expect(
        await updates.check(
          client: recovered,
          current: '1.0.5',
          platform: 'windows',
        ),
        isNotNull,
      );
      expect(updates.error, null);
      failed.close();
      recovered.close();
      updates.dispose();
    },
  );
}
