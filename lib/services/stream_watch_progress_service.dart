import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/stream_watch_progress.dart';

class StreamWatchProgressService {
  static const _storageKey = 'stream.watch_progress.v1';
  static const _maxEntries = 30;

  Future<List<StreamWatchProgress>> load({
    StreamWatchCategory? category,
  }) async {
    final entries = await _readAll();
    return entries.where((entry) {
      return entry.isResumable &&
          (category == null || entry.category == category);
    }).toList()..sort(
      (first, second) =>
          second.lastWatchedAtMs.compareTo(first.lastWatchedAtMs),
    );
  }

  Future<void> save(
    StreamWatchProgress progress, {
    bool completed = false,
  }) async {
    final preferences = await SharedPreferences.getInstance();
    final entries = await _readAll();
    entries.removeWhere((entry) => entry.storageKey == progress.storageKey);

    if (!completed && progress.isResumable) entries.add(progress);
    entries.sort(
      (first, second) =>
          second.lastWatchedAtMs.compareTo(first.lastWatchedAtMs),
    );
    if (entries.length > _maxEntries) {
      entries.removeRange(_maxEntries, entries.length);
    }

    final saved = await preferences.setString(
      _storageKey,
      jsonEncode(entries.map((entry) => entry.toJson()).toList()),
    );
    if (!saved) {
      throw StateError('Stream watch progress could not be saved.');
    }
  }

  Future<List<StreamWatchProgress>> _readAll() async {
    final preferences = await SharedPreferences.getInstance();
    final encoded = preferences.getString(_storageKey);
    if (encoded == null || encoded.isEmpty) return [];

    final decoded = jsonDecode(encoded);
    if (decoded is! List) {
      throw const FormatException('Saved stream watch progress is not a list.');
    }
    return decoded.map((value) {
      if (value is! Map<String, dynamic>) {
        throw const FormatException(
          'Saved stream watch progress contains an invalid entry.',
        );
      }
      return StreamWatchProgress.fromJson(value);
    }).toList();
  }
}
