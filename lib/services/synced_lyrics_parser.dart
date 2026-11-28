class SyncedLyricLine {
  const SyncedLyricLine({required this.timestamp, required this.text});

  final Duration timestamp;
  final String text;
}

class LyricsContent {
  const LyricsContent({required this.text, required this.syncedLines});

  final String text;
  final List<SyncedLyricLine> syncedLines;
}

final RegExp _lyricTimestamp = RegExp(r'\[(\d+):([0-5]\d)(?:\.(\d{1,3}))?\]');

LyricsContent? parseLyricsContent({String? plainLyrics, String? syncedLyrics}) {
  final syncedLines = parseSyncedLyrics(syncedLyrics ?? '');
  final text = syncedLines.isNotEmpty
      ? syncedLines.map((line) => line.text).join('\n')
      : plainLyrics?.trim();
  if (text == null || text.isEmpty) return null;
  return LyricsContent(text: text, syncedLines: syncedLines);
}

List<SyncedLyricLine> parseSyncedLyrics(String lyrics) {
  final parsed = <SyncedLyricLine>[];
  for (final line in lyrics.split(RegExp(r'\r?\n'))) {
    final timestamps = _lyricTimestamp.allMatches(line).toList();
    if (timestamps.isEmpty) continue;

    final text = line.substring(timestamps.last.end).trim();
    if (text.isEmpty) continue;

    for (final timestamp in timestamps) {
      final minutes = int.tryParse(timestamp.group(1)!);
      final seconds = int.tryParse(timestamp.group(2)!);
      final fraction = timestamp.group(3);
      if (minutes == null || seconds == null) continue;

      final milliseconds = fraction == null
          ? 0
          : int.parse(fraction.padRight(3, '0'));
      parsed.add(
        SyncedLyricLine(
          timestamp: Duration(
            minutes: minutes,
            seconds: seconds,
            milliseconds: milliseconds,
          ),
          text: text,
        ),
      );
    }
  }
  parsed.sort((a, b) => a.timestamp.compareTo(b.timestamp));
  return parsed;
}

List<SyncedLyricLine> alignSyncedLyricsToDuration(
  List<SyncedLyricLine> lines, {
  required Duration sourceDuration,
  required Duration targetDuration,
}) {
  final sourceMs = sourceDuration.inMilliseconds;
  final targetMs = targetDuration.inMilliseconds;
  if (lines.isEmpty ||
      sourceMs <= 0 ||
      targetMs <= 0 ||
      (sourceMs - targetMs).abs() <=
          const Duration(seconds: 3).inMilliseconds) {
    return lines;
  }

  return [
    for (final line in lines)
      SyncedLyricLine(
        timestamp: Duration(
          milliseconds: (line.timestamp.inMilliseconds * targetMs / sourceMs)
              .round()
              .clamp(0, targetMs)
              .toInt(),
        ),
        text: line.text,
      ),
  ];
}

int currentSyncedLyricIndex(List<SyncedLyricLine> lines, Duration position) {
  var low = 0;
  var high = lines.length - 1;
  var active = -1;
  while (low <= high) {
    final middle = low + ((high - low) >> 1);
    if (lines[middle].timestamp <= position) {
      active = middle;
      low = middle + 1;
    } else {
      high = middle - 1;
    }
  }
  return active;
}
