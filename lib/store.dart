import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart' show Color;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import 'model.dart';
import 'storage.dart';

Document mergeDocuments(Document local, Document remote) {
  final tasks = {for (final t in remote.tasks) t.id: t};
  for (final t in local.tasks) {
    final previous = tasks[t.id];
    if (previous == null || !t.updated.isBefore(previous.updated)) {
      tasks[t.id] = t;
    }
  }
  final appearance = local.appearanceUpdated.isBefore(remote.appearanceUpdated)
      ? remote
      : local;
  return Document(
    journals: (() {
      final entries = {...remote.journals};
      for (final entry in local.journals.entries) {
        entries[entry.key] = entries[entry.key] == null
            ? entry.value.clone()
            : mergeJournalWeeks(entry.value, entries[entry.key]!);
      }
      return entries;
    })(),
    dateHeaders: (() {
      final entries = {...remote.dateHeaders};
      for (final entry in local.dateHeaders.entries) {
        if (entries[entry.key] == null ||
            !entry.value.updated.isBefore(entries[entry.key]!.updated)) {
          entries[entry.key] = entry.value;
        }
      }
      return entries;
    })(),
    tasks: tasks.values.toList(),
    list:
        (local.list.updated.isBefore(remote.list.updated)
                ? remote.list
                : local.list)
            .clone(),
    calendar:
        (local.calendar.updated.isBefore(remote.calendar.updated)
                ? remote.calendar
                : local.calendar)
            .clone(),
    reminders:
        (local.reminders.updated.isBefore(remote.reminders.updated)
                ? remote.reminders
                : local.reminders)
            .clone(),
    holidays: (() {
      final entries = {for (final h in remote.holidays) h.id: h};
      for (final h in local.holidays) {
        if (entries[h.id] == null ||
            !h.updated.isBefore(entries[h.id]!.updated)) {
          entries[h.id] = h;
        }
      }
      return entries.values.toList();
    })(),
    appearanceUpdated: appearance.appearanceUpdated,
  );
}

class AppStore extends ChangeNotifier {
  final JsonStorage storage;
  final FlutterSecureStorage vault;
  final Uri? peer;
  final String peerToken;
  final String api;
  final http.Client client;
  Document document = Document();
  Map<String, dynamic> _deviceSettings = {}, _sharedStyles = {};
  String get _settingsKey => '$_key-device-settings';
  Appearance get widgetAppearance => _deviceSettings['widgets'] == null
      ? Appearance(
          radius: 12,
          paletteId: 'widget',
          palettes: [
            Palette(
              'widget',
              '默认',
              const Color(0xffffffff),
              const Color(0xff292c32),
              document.list.palette.accent,
            ),
          ],
        )
      : Appearance.fromJson(object(_deviceSettings['widgets']));

  void _captureShared(Document shared) {
    _sharedStyles = {
      'list': shared.list.toJson(),
      'calendar': shared.calendar.toJson(),
      'reminders': shared.reminders.toJson(),
      'appearanceUpdated': shared.appearanceUpdated.toIso8601String(),
    };
  }

  Document _canonical(Document effective) {
    final copy = effective.clone();
    if (_sharedStyles.isNotEmpty) {
      copy.list = Appearance.fromJson(object(_sharedStyles['list']));
      copy.calendar = Appearance.fromJson(object(_sharedStyles['calendar']));
      copy.reminders = ReminderStyle.fromJson(
        object(_sharedStyles['reminders']),
      );
      copy.appearanceUpdated = DateTime.parse(
        _sharedStyles['appearanceUpdated'],
      );
    }
    return copy;
  }

  void _acceptShared(Document shared) {
    _captureShared(shared);
    document = shared;
    if (_deviceSettings['list'] != null) {
      document.list = Appearance.fromJson(object(_deviceSettings['list']));
    }
    if (_deviceSettings['calendar'] != null) {
      document.calendar = Appearance.fromJson(
        object(_deviceSettings['calendar']),
      );
    }
    if (_deviceSettings['reminders'] != null) {
      document.reminders = ReminderStyle.fromJson(
        object(_deviceSettings['reminders']),
      );
    }
  }

  Future<void> _loadDeviceSettings() async {
    _deviceSettings = await storage.read(_settingsKey) ?? {};
  }

  Map<String, dynamic>? account;
  bool local = false, ready = false, syncing = false;
  String? error;
  String _token = '';
  int revision = 0;
  int generation = 0;
  Future<void> _writes = Future.value();
  Timer? _timer;
  HttpServer? _ipc;
  Process? _calendar;
  bool _openingCalendar = false;
  final String _ipcToken = base64UrlEncode(
    List.generate(32, (_) => Random.secure().nextInt(256)),
  );
  String? bindingTicket;
  void Function()? onDocumentChanged;
  Future<void> Function(ReminderStyle)? onReminderTest;
  Future<void> Function()? onFlushDrafts;
  final Map<String, JournalWeek> pendingJournals = {};
  final Map<String, int> pendingJournalVersions = {};
  int bufferJournal(JournalWeek week) {
    pendingJournals[week.key] = week;
    return pendingJournalVersions[week.key] =
        (pendingJournalVersions[week.key] ?? 0) + 1;
  }

  Future<void> flushDrafts() async {
    await onFlushDrafts?.call();
    for (final entry in pendingJournals.entries.toList()) {
      final version = pendingJournalVersions[entry.key] ?? 0;
      final snapshot = entry.value.clone();
      await dispatch({
        'type': 'journal',
        'week': entry.key,
        'value': snapshot.toJson(),
      });
      if ((pendingJournalVersions[entry.key] ?? 0) == version) {
        pendingJournals.remove(entry.key);
        pendingJournalVersions.remove(entry.key);
      }
    }
  }

  AppStore(
    this.storage, {
    this.peer,
    this.peerToken = '',
    this.api = const String.fromEnvironment(
      'NEEDTODO_API_URL',
      defaultValue: 'https://api.whatineedtodotoday.xyz',
    ),
    this.vault = const FlutterSecureStorage(),
    http.Client? httpClient,
  }) : client = httpClient ?? http.Client();
  bool get entered => local || account != null;
  bool get githubBound => (account?['githubLogin'] as String? ?? '').isNotEmpty;
  bool get canCloudSync => account != null && githubBound;
  String get _key => account == null
      ? 'local'
      : 'user-${base64UrlEncode(utf8.encode(account!['id'])).replaceAll('=', '')}';
  Future<void> load() async {
    if (peer != null) {
      await _refreshPeer();
      ready = true;
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        _refreshPeer().catchError((Object e) {
          setError('清单已关闭，请重新打开月历');
        });
      });
    } else {
      final prefs = await storage.read('session') ?? {};
      local = prefs['local'] == true;
      account = prefs['account'] == null ? null : object(prefs['account']);
      if (account != null) {
        try {
          _token = await vault.read(key: 'session') ?? '';
        } catch (_) {
          _token = '';
        }
        if (_token.isEmpty) account = null;
      }
      final saved = await storage.read(_key);
      await _loadDeviceSettings();
      try {
        if (saved != null) {
          _acceptShared(Document.fromJson(object(saved['document'] ?? saved)));
          revision = saved['revision'] ?? 0;
        }
      } catch (_) {
        setError('数据无法读取，已保留原文件');
      }
      if (saved == null) _acceptShared(Document());
      ready = true;
      _timer = Timer.periodic(const Duration(seconds: 45), (_) {
        if (canCloudSync) sync().catchError((Object e) => setError(e));
      });
    }
    notifyListeners();
    onDocumentChanged?.call();
    if (account != null && peer == null) {
      unawaited(
        refreshAccount()
            .then((_) => sync())
            .catchError((Object e) => setError(e)),
      );
    }
  }

  void setError(Object e) {
    final message = e.toString().replaceFirst('Exception: ', '');
    if (error == message) return;
    error = message;
    notifyListeners();
  }

  void clearNotificationError() {
    if (error?.startsWith('系统通知') != true && error != '提醒暂不可用，请检查系统通知权限') {
      return;
    }
    error = null;
    notifyListeners();
  }

  Future<void> _persist(Document next, {bool shared = false}) async {
    await storage.write(_key, {
      'document': (shared ? next : _canonical(next)).toJson(),
      'revision': revision,
    });
  }

  Future<void> dispatch(Map<String, dynamic> action) async {
    if (peer != null) {
      final r = await client
          .post(
            peer!.resolve('/action'),
            headers: {
              'authorization': peerToken,
              'content-type': 'application/json',
            },
            body: jsonEncode(action),
          )
          .timeout(const Duration(seconds: 15));
      if (r.statusCode != 200) throw Exception('保存失败，请重试');
      _applyPeerSnapshot(object(jsonDecode(r.body)));
      return;
    }
    if (action['type'] == 'testReminder') {
      if (onReminderTest == null) throw StateError('提醒服务未就绪');
      await onReminderTest!(
        action['reminders'] == null
            ? document.reminders.clone()
            : ReminderStyle.fromJson(object(action['reminders'])),
      );
      return;
    }
    final op = _writes.then((_) async {
      if (_sharedStyles.isEmpty) _captureShared(document);
      final next = document.clone();
      final settings = {..._deviceSettings};
      bool settingsOnly = false;
      switch (action['type']) {
        case 'journal':
          final key = action['week'] as String;
          final incoming = JournalWeek.fromJson(key, object(action['value']));
          next.journals[key] = next.journals[key] == null
              ? incoming
              : mergeJournalWeeks(incoming, next.journals[key]!);
        case 'dateHeader':
          next.dateHeaders[action['date'] as String] = DateHeaderStyle(
            color: action['color'] == null
                ? null
                : readColor(
                    action['color'],
                    next.calendar.palette.accent.withValues(alpha: 0),
                  ),
            updated: DateTime.now().toUtc(),
          );
        case 'toggleTask':
          final index = next.tasks.indexWhere(
            (t) => t.id == action['id'] && !t.deleted,
          );
          if (index >= 0) {
            next.tasks[index] = next.tasks[index].copy(
              done: !next.tasks[index].done,
            );
          }
        case 'task':
          final task = Todo.fromJson(object(action['task']));
          final index = next.tasks.indexWhere((t) => t.id == task.id);
          if (index < 0) {
            next.tasks.add(task);
          } else {
            next.tasks[index] = task;
          }
        case 'appearance':
          settingsOnly = true;
          final appearance = Appearance.fromJson(object(action['value']))
            ..updated = DateTime.now().toUtc();
          if (action['layout'] == 'calendar') {
            next.calendar = appearance;
            settings['calendar'] = appearance.toJson();
          } else {
            next.list = appearance;
            settings['list'] = appearance.toJson();
          }
          next.appearanceUpdated = DateTime.now().toUtc();
        case 'preferences':
          settingsOnly = true;
          final profiles = object(action['profiles']);
          for (final entry in profiles.entries) {
            final appearance = Appearance.fromJson(object(entry.value))
              ..updated = DateTime.now().toUtc();
            if (entry.key == 'calendar') next.calendar = appearance;
            if (entry.key == 'list') next.list = appearance;
            settings[entry.key] = appearance.toJson();
          }
          if (profiles.isNotEmpty) {
            next.appearanceUpdated = DateTime.now().toUtc();
          }
          if (action['reminders'] != null) {
            next.reminders = ReminderStyle.fromJson(object(action['reminders']))
              ..updated = DateTime.now().toUtc();
            settings['reminders'] = next.reminders.toJson();
          }
          if (action['widgets'] != null) {
            settings['widgets'] = Appearance.fromJson(object(action['widgets']))
                .toJson();
          }
        case 'holiday':
          final h = Holiday.fromJson(object(action['value']));
          next.holidays.removeWhere((e) => e.id == h.id);
          next.holidays.add(h);
        default:
          throw Exception('未知操作');
      }
      if (settingsOnly) {
        await storage.write(_settingsKey, settings);
        _deviceSettings = settings;
      } else {
        await _persist(next);
      }
      document = next;
      generation++;
      notifyListeners();
      if (action['type'] != 'journal') onDocumentChanged?.call();
    });
    _writes = op.catchError((Object _) {});
    return op;
  }

  Future<void> toggleTask(Todo task) =>
      dispatch({'type': 'toggleTask', 'id': task.id});

  Future<void> saveTask(Todo task) =>
      dispatch({'type': 'task', 'task': task.toJson()});
  Future<void> saveAppearance(String layout, Appearance value) => dispatch({
    'type': 'appearance',
    'layout': layout,
    'value': value.toJson(),
  });
  Future<void> enterLocal() async {
    await _writes;
    final saved = await storage.read('local');
    final next = saved == null
        ? Document()
        : Document.fromJson(object(saved['document'] ?? saved));
    await storage.write('session', {'local': true});
    account = null;
    local = true;
    revision = 0;
    await _loadDeviceSettings();
    _acceptShared(next);
    generation++;
    notifyListeners();
    onDocumentChanged?.call();
  }

  Future<Map<String, dynamic>> request(
    String method,
    String path, [
    Map<String, dynamic>? body,
  ]) async {
    final base = Uri.tryParse(api);
    if (base == null || !base.hasAuthority) throw Exception('账号服务暂未开放，可使用本机模式');
    if (base.scheme != 'https' &&
        !['127.0.0.1', 'localhost', '10.0.2.2'].contains(base.host)) {
      throw Exception('账号服务需要 HTTPS');
    }
    final uri = Uri.parse('${api.replaceFirst(RegExp(r'/$'), '')}$path');
    final encoded = body == null ? null : jsonEncode(body);
    final bearer = _token;
    final retryable =
        method == 'GET' || (method == 'PUT' && path == '/v2/sync');
    http.Response? received;
    for (var attempt = 0; attempt < (retryable ? 3 : 1); attempt++) {
      final abort = Completer<void>();
      final req = http.AbortableRequest(method, uri, abortTrigger: abort.future)
        ..headers.addAll({
          'content-type': 'application/json',
          if (bearer.isNotEmpty) 'authorization': 'Bearer $bearer',
        })
        ..persistentConnection = attempt == 0;
      if (encoded != null) req.body = encoded;
      try {
        // The deadline includes the entire response body, not just its headers.
        received =
            await (() async => http.Response.fromStream(
              await client.send(req),
            ))().timeout(
              Duration(seconds: path == '/v2/sync' ? 45 : 20),
              onTimeout: () {
                if (!abort.isCompleted) abort.complete();
                throw TimeoutException('Account response timed out');
              },
            );
        if (retryable &&
            [502, 503, 504].contains(received.statusCode) &&
            attempt < 2) {
          await Future<void>.delayed(
            Duration(milliseconds: 400 * (attempt + 1)),
          );
          continue;
        }
        break;
      } on http.ClientException {
        if (!retryable || attempt == 2) throw Exception('网络连接中断，请稍后重试；本机数据已保留');
      } on SocketException {
        if (!retryable || attempt == 2) {
          throw Exception('无法连接账号服务，请检查网络；本机数据已保留');
        }
      } on TimeoutException {
        if (!retryable || attempt == 2) throw Exception('同步连接超时，请稍后重试；本机数据已保留');
      }
      await Future<void>.delayed(Duration(milliseconds: 400 * (attempt + 1)));
    }
    final response = received!;
    final result = object(jsonDecode(response.body));
    if (response.statusCode == 409 && path == '/v2/sync') {
      return {...result, 'conflict': true};
    }
    if (response.statusCode >= 400) {
      throw Exception(result['message'] ?? '连接失败，请稍后再试');
    }
    return result;
  }

  Future<void> authenticate(
    String username,
    String password,
    bool register,
  ) async {
    await flushDrafts();
    final result = await request(
      'POST',
      register ? '/v2/auth/register' : '/v2/auth/login',
      {'username': username, 'password': password},
    );
    final token = result['token'];
    final user = object(result['account']);
    if (token is! String || user['id'] is! String) throw Exception('登录响应无效');
    await _writes;
    await vault.write(key: 'session', value: token);
    await storage.write('session', {'local': false, 'account': user});
    account = user;
    _token = token;
    local = false;
    revision = 0;
    generation++;
    final saved = await storage.read(_key);
    await _loadDeviceSettings();
    _acceptShared(
      saved == null ? Document() : Document.fromJson(object(saved['document'])),
    );
    revision = saved?['revision'] ?? 0;
    notifyListeners();
    onDocumentChanged?.call();
    try {
      await sync();
    } catch (e) {
      setError(e);
    }
  }

  Future<void> logout() async {
    await flushDrafts();
    if (peer != null) throw Exception('请在清单中退出账号');
    _calendar?.kill();
    _calendar = null;
    bindingTicket = null;
    if (_token.isNotEmpty) {
      try {
        await request('POST', '/v2/auth/logout');
      } catch (_) {}
    }
    await _writes;
    await vault.delete(key: 'session');
    await storage.write('session', {'local': false});
    _token = '';
    account = null;
    local = false;
    document = Document();
    _deviceSettings = {};
    _sharedStyles = {};
    generation++;
    notifyListeners();
    onDocumentChanged?.call();
  }

  Future<void> sync() async {
    if (!canCloudSync || syncing || peer != null) return;
    final uid = account!['id'];
    syncing = true;
    notifyListeners();
    try {
      var remote = await request('GET', '/v2/sync');
      if (remote['document'] != null) {
        final download = _writes.then((_) async {
          if (account?['id'] != uid) return;
          final next = mergeDocuments(
            _canonical(document),
            Document.fromJson(object(remote['document'])),
          );
          final previousRevision = revision;
          revision = remote['revision'];
          try {
            await _persist(next, shared: true);
          } catch (_) {
            revision = previousRevision;
            rethrow;
          }
          _acceptShared(next);
          generation++;
          if (error?.contains('连接') == true || error?.contains('同步') == true) {
            error = null;
          }
          notifyListeners();
          onDocumentChanged?.call();
        });
        _writes = download.catchError((Object _) {});
        await download;
      }
      for (var attempt = 0; attempt < 4; attempt++) {
        if (account?['id'] != uid) return;
        final sentGeneration = generation;
        final merged = remote['document'] == null
            ? _canonical(document)
            : mergeDocuments(
                _canonical(document),
                Document.fromJson(object(remote['document'])),
              );
        if (remote['document'] != null &&
            jsonEncode(merged.toJson()) ==
                jsonEncode(
                  Document.fromJson(object(remote['document'])).toJson(),
                )) {
          revision = remote['revision'];
          if (error?.contains('连接') == true || error?.contains('同步') == true) {
            error = null;
          }
          return;
        }
        final response = await request('PUT', '/v2/sync', {
          'revision': remote['revision'],
          'document': merged.toJson(),
        });
        if (response['conflict'] == true) {
          remote = response;
          continue;
        }
        if (account?['id'] != uid) return;
        final commit = _writes.then((_) async {
          if (account?['id'] != uid) return;
          final next = sentGeneration == generation
              ? merged
              : mergeDocuments(_canonical(document), merged);
          final previousRevision = revision;
          revision = response['revision'];
          try {
            await _persist(next, shared: true);
          } catch (_) {
            revision = previousRevision;
            rethrow;
          }
          _acceptShared(next);
          generation++;
          notifyListeners();
          onDocumentChanged?.call();
        });
        _writes = commit.catchError((Object _) {});
        await commit;
        return;
      }
      throw Exception('同步繁忙，请稍后重试');
    } finally {
      syncing = false;
      notifyListeners();
    }
  }

  Future<void> refreshAccount() async {
    if (account == null || peer != null) return;
    final uid = account!['id'];
    final result = await request('GET', '/v2/account');
    if (account?['id'] != uid) return;
    account = object(result['account']);
    await storage.write('session', {'local': false, 'account': account});
    notifyListeners();
  }

  Future<void> bindGithub() async {
    if (account == null) return;
    final r = await request('POST', '/v2/github/bind');
    bindingTicket = r['ticket'];
    if (!await launchUrl(
      Uri.parse(r['url']),
      mode: LaunchMode.externalApplication,
    )) {
      throw Exception('无法打开浏览器');
    }
    final uid = account!['id'];
    for (var i = 0; i < 120; i++) {
      await Future<void>.delayed(const Duration(seconds: 3));
      if (account?['id'] != uid || bindingTicket != r['ticket']) return;
      final status = await request('POST', '/v2/github/status', {
        'ticket': r['ticket'],
      });
      if (status['status'] == 'failed') throw Exception('GitHub 绑定失败');
      if (status['status'] == 'complete') {
        account = object(status['account']);
        await storage.write('session', {'local': false, 'account': account});
        bindingTicket = null;
        notifyListeners();
        await sync();
        return;
      }
    }
    throw Exception('授权已超时');
  }

  Future<Map<String, dynamic>> startRecovery() async {
    final result = await request('POST', '/v2/github/recover');
    if (!await launchUrl(
      Uri.parse(result['url']),
      mode: LaunchMode.externalApplication,
    )) {
      throw Exception('无法打开浏览器');
    }
    return result;
  }

  Future<Map<String, dynamic>> recoveryStatus(String ticket) =>
      request('POST', '/v2/github/recovery-status', {'ticket': ticket});

  Future<void> openCalendar() async {
    if (!Platform.isWindows || !entered || _openingCalendar) return;
    _openingCalendar = true;
    try {
      if (_calendar != null) {
        calendarOpenSignal++;
        return;
      }
      _ipc ??= await HttpServer.bind(InternetAddress.loopbackIPv4, 0)
        ..listen(_handlePeer);
      _calendar = await Process.start(Platform.resolvedExecutable, [
        '--calendar',
        '${_ipc!.port}',
        _ipcToken,
      ]);
      _calendar!.stdout.drain<void>();
      _calendar!.stderr.drain<void>();
      _calendar!.exitCode.then((_) {
        _calendar = null;
      });
    } finally {
      _openingCalendar = false;
    }
  }

  int calendarOpenSignal = 0;
  int remoteOpenSignal = 0;
  Map<String, dynamic> get snapshot => {
    'document': document.toJson(),
    'local': local,
    'account': account,
    'signal': calendarOpenSignal,
    'generation': generation,
  };
  Future<void> _handlePeer(HttpRequest req) async {
    try {
      if (req.headers.value('authorization') != _ipcToken) {
        req.response.statusCode = 403;
        return;
      }
      if (req.method == 'POST' && req.uri.path == '/action') {
        final bytes = await utf8.decoder.bind(req).join();
        if (bytes.length > 24000000) throw Exception();
        await dispatch(object(jsonDecode(bytes)));
      }
      req.response.headers.contentType = ContentType.json;
      req.response.write(jsonEncode(snapshot));
    } catch (_) {
      req.response.statusCode = 400;
    } finally {
      await req.response.close();
    }
  }

  bool _refreshing = false;
  Future<void> _refreshPeer() async {
    if (_refreshing) return;
    _refreshing = true;
    try {
      final r = await client
          .get(peer!, headers: {'authorization': peerToken})
          .timeout(const Duration(seconds: 4));
      if (r.statusCode != 200) throw Exception();
      _applyPeerSnapshot(object(jsonDecode(r.body)));
    } finally {
      _refreshing = false;
    }
  }

  int _peerGeneration = -1;
  void _applyPeerSnapshot(Map<String, dynamic> snapshot) {
    final incoming = snapshot['generation'] as int? ?? 0;
    // A polling GET can finish after a newer action response.
    if (incoming < _peerGeneration) return;
    final signal = snapshot['signal'] as int? ?? 0;
    final changed = incoming != _peerGeneration;
    final recovered = error == '清单已关闭，请重新打开月历';
    if (!changed && signal == remoteOpenSignal && !recovered) return;
    if (changed) {
      document = Document.fromJson(object(snapshot['document']));
      local = snapshot['local'] == true;
      account = snapshot['account'] == null
          ? null
          : object(snapshot['account']);
      _peerGeneration = incoming;
    }
    remoteOpenSignal = signal;
    if (recovered) error = null;
    notifyListeners();
  }

  Future<void> shutdown() async {
    await flushDrafts();
    _timer?.cancel();
    _calendar?.kill();
    await _writes;
    await storage.flush();
    await _ipc?.close(force: true);
    client.close();
  }
}
