import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import 'model.dart';
import 'storage.dart';

class CalendarDay {
  final String name;
  final bool off;
  const CalendarDay(this.name, this.off);
}

/// Public holiday data only; no personal schedule is sent to the provider.
class HolidayCalendar extends ChangeNotifier {
  final JsonStorage storage;
  final http.Client client;
  final days = <String, CalendarDay>{};
  final _years = <int, Map<String, CalendarDay>>{};
  final _loaded = <int>{};
  bool _disposed = false;
  HolidayCalendar(this.storage, {http.Client? client})
    : client = client ?? http.Client();

  static Map<String, CalendarDay> parse(Map<String, dynamic> json, int year) {
    if (json['year'] != year || json['days'] is! List) {
      throw const FormatException('无效日历');
    }
    final result = <String, CalendarDay>{};
    for (final value in (json['days'] as List).take(500)) {
      final row = object(value),
          date = DateTime.tryParse(object(value)['date']?.toString() ?? '');
      if (date == null ||
          date.year < year - 1 ||
          date.year > year + 1 ||
          row['isOffDay'] is! bool ||
          row['name'] is! String) {
        continue;
      }
      result[dayKey(date)] = CalendarDay(row['name'], row['isOffDay']);
    }
    return result;
  }

  Future<void> loadAround(int year) async {
    // An announcement can contain dates in December of the previous year.
    await Future.wait([year - 1, year, year + 1].map(loadYear));
  }

  Future<void> loadYear(int year) async {
    if (_disposed || !_loaded.add(year)) return;
    Map<String, dynamic>? cached;
    try {
      cached = await storage.read('holiday-$year');
    } catch (_) {}
    void apply(Map<String, dynamic> value) {
      final parsed = parse(value, year);
      if (!_disposed) {
        _years[year] = parsed;
        days.clear();
        for (final y in _years.keys.toList()..sort()) {
          days.addAll(_years[y]!);
        }
        notifyListeners();
      }
    }

    try {
      if (cached?['data'] != null) {
        apply(object(cached!['data']));
      } else {
        apply(
          object(
            jsonDecode(
              await rootBundle.loadString('assets/holidays/$year.json'),
            ),
          ),
        );
      }
    } catch (_) {}
    final fetched = DateTime.tryParse(cached?['fetched'] ?? '');
    if (fetched != null &&
        DateTime.now().difference(fetched) < const Duration(days: 1)) {
      return;
    }
    for (final host in [
      'https://raw.githubusercontent.com/NateScarlet/holiday-cn/master',
      'https://cdn.jsdelivr.net/gh/NateScarlet/holiday-cn@master',
    ]) {
      if (_disposed) return;
      try {
        final response = await client
            .get(Uri.parse('$host/$year.json'))
            .timeout(const Duration(seconds: 5));
        if (response.statusCode == 404) return;
        if (response.statusCode != 200 || response.bodyBytes.length > 256000) {
          continue;
        }
        final value = object(jsonDecode(utf8.decode(response.bodyBytes)));
        apply(value);
        await storage.write('holiday-$year', {
          'fetched': DateTime.now().toIso8601String(),
          'data': value,
        });
        return;
      } catch (_) {}
    }
  }

  @override
  void dispose() {
    _disposed = true;
    client.close();
    super.dispose();
  }
}
