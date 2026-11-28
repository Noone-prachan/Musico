import 'package:flutter_test/flutter_test.dart';
import 'package:musico/services/synced_lyrics_parser.dart';

void main() {
  test('prefers timestamped lyrics and falls back to plain lyrics', () {
    final synced = parseLyricsContent(
      plainLyrics: 'Plain line',
      syncedLyrics: '[00:01.00]Timed line',
    );
    final plain = parseLyricsContent(
      plainLyrics: 'Plain line',
      syncedLyrics: '[00:99.00]Invalid timing',
    );

    expect(synced?.text, 'Timed line');
    expect(synced?.syncedLines, hasLength(1));
    expect(plain?.text, 'Plain line');
    expect(plain?.syncedLines, isEmpty);
    expect(parseLyricsContent(), isNull);
  });

  test('parses timed lines and repeated timestamps', () {
    final lines = parseSyncedLyrics(
      '[ar:Artist]\n'
      '[00:01.2]First line\n'
      '[00:04.00][00:02.50]Repeated line\n'
      '[00:08.125]Last line',
    );

    expect(lines, hasLength(4));
    expect(lines[0].timestamp, const Duration(seconds: 1, milliseconds: 200));
    expect(lines[1].timestamp, const Duration(seconds: 2, milliseconds: 500));
    expect(lines[1].text, 'Repeated line');
    expect(lines[2].timestamp, const Duration(seconds: 4));
    expect(lines[3].timestamp, const Duration(seconds: 8, milliseconds: 125));
  });

  test('finds the active line at the playback position', () {
    final lines = parseSyncedLyrics(
      '[00:01.00]First line\n[00:03.00]Second line',
    );

    expect(currentSyncedLyricIndex(lines, Duration.zero), -1);
    expect(currentSyncedLyricIndex(lines, const Duration(seconds: 1)), 0);
    expect(currentSyncedLyricIndex(lines, const Duration(seconds: 4)), 1);
  });

  test('scales lyric timestamps to match a different track duration', () {
    final lines = parseSyncedLyrics(
      '[00:30.00]First line\n[02:00.00]Last line',
    );

    final aligned = alignSyncedLyricsToDuration(
      lines,
      sourceDuration: const Duration(minutes: 3),
      targetDuration: const Duration(minutes: 2),
    );

    expect(aligned[0].timestamp, const Duration(seconds: 20));
    expect(aligned[1].timestamp, const Duration(seconds: 80));
  });

  test('leaves timings alone when durations are close or unavailable', () {
    final lines = parseSyncedLyrics('[00:30.00]Line');

    expect(
      alignSyncedLyricsToDuration(
        lines,
        sourceDuration: const Duration(minutes: 3),
        targetDuration: const Duration(minutes: 3, seconds: 2),
      ),
      same(lines),
    );
    expect(
      alignSyncedLyricsToDuration(
        lines,
        sourceDuration: Duration.zero,
        targetDuration: const Duration(minutes: 2),
      ),
      same(lines),
    );
  });

  test('ignores malformed timestamps and empty lines', () {
    final lines = parseSyncedLyrics(
      '[00:99.00]Invalid seconds\n'
      '[00:01.00]\n'
      '[offset:-150]Metadata',
    );

    expect(lines, isEmpty);
  });
}
