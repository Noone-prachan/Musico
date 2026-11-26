import 'lyrics_title_matcher.dart';

Map<String, dynamic>? selectLyricsRecord(
  List<Map<String, dynamic>> records, {
  required String title,
  required String artist,
  required int durationSeconds,
}) {
  final titleMatches = records
      .where(
        (record) => lyricsTitleMatches(
          title,
          record['trackName'] as String? ?? record['name'] as String? ?? '',
        ),
      )
      .toList();
  final normalizedArtist = artist.trim().toLowerCase();
  final hasKnownArtist =
      normalizedArtist.isNotEmpty &&
      normalizedArtist != 'imported audio' &&
      normalizedArtist != 'wikimedia commons contributor';
  final matchingArtist = hasKnownArtist
      ? titleMatches
            .where(
              (record) =>
                  (record['artistName'] as String? ?? '')
                      .trim()
                      .toLowerCase() ==
                  normalizedArtist,
            )
            .toList()
      : titleMatches;
  if (hasKnownArtist && matchingArtist.isEmpty) return null;

  final candidates = matchingArtist.isNotEmpty ? matchingArtist : titleMatches;
  if (candidates.isEmpty) return null;

  final durationMatches = durationSeconds > 0
      ? candidates
            .where(
              (record) =>
                  (((record['duration'] as num?)?.toDouble() ?? -100) -
                          durationSeconds)
                      .abs() <=
                  2,
            )
            .toList()
      : <Map<String, dynamic>>[];
  final matchingDuration = durationMatches.isNotEmpty
      ? durationMatches
      : candidates;
  final synced = matchingDuration
      .where((record) => _hasSyncedLyrics(record))
      .toList();
  final preferred = synced.isNotEmpty ? synced : matchingDuration;

  if (durationMatches.isNotEmpty || preferred.length == 1 || hasKnownArtist) {
    return preferred.first;
  }
  return null;
}

bool hasSyncedLyricsRecord(Map<String, dynamic> record) =>
    _hasSyncedLyrics(record);

bool _hasSyncedLyrics(Map<String, dynamic> record) =>
    (record['syncedLyrics'] as String?)?.trim().isNotEmpty ?? false;
