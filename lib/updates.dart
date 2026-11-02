import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

bool newerVersion(String candidate, String current) {
  List<int>? parse(String value) {
    final match = RegExp(r'^v?(\d+)\.(\d+)\.(\d+)(?:\+\d+)?$')
        .firstMatch(value);
    return match == null
        ? null
        : [for (var i = 1; i <= 3; i++) int.parse(match[i]!)];
  }

  final a = parse(candidate), b = parse(current);
  if (a == null || b == null) return false;
  for (var i = 0; i < 3; i++) {
    if (a[i] != b[i]) return a[i] > b[i];
  }
  return false;
}

class ReleaseUpdate {
  final String version, notes;
  final Uri url;
  ReleaseUpdate(this.version, this.notes, this.url);
  static ReleaseUpdate? fromJson(
    Map<String, dynamic> data,
    String current, {
    required String platform,
    bool portable = false,
  }) {
    final tag = data['tag_name'];
    if (data['draft'] == true ||
        data['prerelease'] == true ||
        tag is! String ||
        !newerVersion(tag, current)) {
      return null;
    }
    final version = tag.replaceFirst(RegExp(r'^v'), '');
    final name = platform == 'android'
        ? 'NeedTODO-Android-$version.apk'
        : platform == 'windows'
        ? (portable
              ? 'NeedTODO-Portable-$version.zip'
              : 'NeedTODO-Setup-$version.exe')
        : '';
    Uri url = Uri.parse(
      'https://github.com/saltseven77/NeedTODO/releases/tag/v$version',
    );
    for (final asset in data['assets'] is List ? data['assets'] as List : []) {
      if (asset is! Map ||
          asset['name'] != name ||
          asset['state'] != 'uploaded') {
        continue;
      }
      final candidate = Uri.tryParse(
        asset['browser_download_url']?.toString() ?? '',
      );
      if (candidate != null &&
          candidate.scheme == 'https' &&
          candidate.host == 'github.com' &&
          candidate.path.startsWith(
            '/saltseven77/NeedTODO/releases/download/v$version/',
          )) {
        url = candidate;
      }
    }
    return ReleaseUpdate(
      version,
      data['body'] is String ? data['body'] : '',
      url,
    );
  }
}

final appUpdates = AppUpdates();

class AppUpdates extends ChangeNotifier {
  String version = '';
  bool checking = false, checked = false;
  String? error;
  ReleaseUpdate? available;
  Future<ReleaseUpdate?> check({
    http.Client? client,
    String? current,
    String? platform,
    bool? portable,
  }) async {
    if (checking) return available;
    checking = true;
    error = null;
    notifyListeners();
    final connection = client ?? http.Client();
    try {
      version = current ?? (await PackageInfo.fromPlatform()).version;
      final response = await connection
          .get(
            Uri.parse(
              'https://api.github.com/repos/saltseven77/NeedTODO/releases/latest',
            ),
            headers: {
              'accept': 'application/vnd.github+json',
              'user-agent': 'NeedTODO/$version',
            },
          )
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) throw const FormatException();
      final data = jsonDecode(utf8.decode(response.bodyBytes));
      if (data is! Map<String, dynamic> ||
          data['tag_name'] is! String ||
          !RegExp(r'^v?\d+\.\d+\.\d+$').hasMatch(data['tag_name'])) {
        throw const FormatException();
      }
      available = ReleaseUpdate.fromJson(
        data,
        version,
        platform: platform ?? Platform.operatingSystem,
        portable:
            portable ??
            (Platform.isWindows &&
                File(
                  '${File(Platform.resolvedExecutable).parent.path}/portable.flag',
                ).existsSync()),
      );
      checked = true;
      return available;
    } catch (_) {
      error = '暂时无法检查更新，请稍后重试';
      return null;
    } finally {
      if (client == null) connection.close();
      checking = false;
      notifyListeners();
    }
  }
}
