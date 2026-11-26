import 'package:flutter_test/flutter_test.dart';
import 'package:musico/services/lyrics_record_selector.dart';

void main() {
  group('selectLyricsRecord', () {
    test(
      'prefers timed lyrics among exact title, artist, and duration matches',
      () {
        final records = [
          {
            'trackName': 'Firfirey',
            'artistName': 'Artist',
            'duration': 180,
            'plainLyrics': 'Plain lyrics',
          },
          {
            'trackName': 'Firfirey (Official Music Video)',
            'artistName': 'Artist',
            'duration': 180,
            'syncedLyrics': '[00:01.00]Timed lyrics',
          },
        ];

        expect(
          selectLyricsRecord(
            records,
            title: 'Firfirey',
            artist: 'Artist',
            durationSeconds: 180,
          ),
          same(records.last),
        );
      },
    );

    test(
      'keeps duration as a match constraint before preferring timed lyrics',
      () {
        final records = [
          {
            'trackName': 'Firfirey',
            'artistName': 'Artist',
            'duration': 180,
            'plainLyrics': 'Plain lyrics',
          },
          {
            'trackName': 'Firfirey',
            'artistName': 'Artist',
            'duration': 187,
            'syncedLyrics': '[00:01.00]Timed lyrics',
          },
        ];

        expect(
          selectLyricsRecord(
            records,
            title: 'Firfirey',
            artist: 'Artist',
            durationSeconds: 180,
          ),
          same(records.first),
        );
      },
    );

    test('returns null when the known artist does not match', () {
      expect(
        selectLyricsRecord(
          [
            {
              'trackName': 'Firfirey',
              'artistName': 'Other Artist',
              'duration': 180,
              'syncedLyrics': '[00:01.00]Timed lyrics',
            },
          ],
          title: 'Firfirey',
          artist: 'Artist',
          durationSeconds: 180,
        ),
        isNull,
      );
    });
  });
}
