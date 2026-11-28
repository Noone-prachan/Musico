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

  final candidates = (matchingArtist.isNotEmpty ? matchingArtist : titleMatches)
      .where(hasLyricsRecord)
      .toList();
  if (candidates.isEmpty) return null;

  var bestCandidates = candidates;
  if (durationSeconds > 0) {
    final withDuration = candidates
        .where((record) => (record['duration'] as num?) != null)
        .toList();
    if (withDuration.isNotEmpty) {
      final closestDifference = withDuration
          .map(
            (record) =>
                ((record['duration'] as num).toDouble() - durationSeconds)
                    .abs(),
          )
          .reduce((a, b) => a < b ? a : b);
      bestCandidates = withDuration
          .where(
            (record) =>
                ((record['duration'] as num).toDouble() - durationSeconds)
                    .abs() ==
                closestDifference,
          )
          .toList();
    }
  }

  final synced = bestCandidates
      .where((record) => _hasSyncedLyrics(record))
      .toList();
  final preferred = synced.isNotEmpty ? synced : bestCandidates;

  if (preferred.length == 1 || hasKnownArtist) {
    return preferred.first;
  }
  return null;
}

bool hasSyncedLyricsRecord(Map<String, dynamic> record) =>
    _hasSyncedLyrics(record);

bool hasLyricsRecord(Map<String, dynamic> record) =>
    _hasSyncedLyrics(record) ||
    ((record['plainLyrics'] as String?)?.trim().isNotEmpty ?? false);

bool _hasSyncedLyrics(Map<String, dynamic> record) =>
    (record['syncedLyrics'] as String?)?.trim().isNotEmpty ?? false;
