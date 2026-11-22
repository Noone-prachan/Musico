import 'package:flutter_test/flutter_test.dart';
import 'package:musico/models/music_playlist.dart';

void main() {
  test('playlist metadata round-trips and de-duplicates track IDs', () {
    final playlist = MusicPlaylist.fromJson({
      'id': 'playlist-123',
      'name': 'Late night',
      'trackIds': ['track-a', 'track-b', 'track-a'],
      'createdAtMs': 456,
    });

    expect(playlist.trackIds, ['track-a', 'track-b']);
    expect(
      MusicPlaylist.fromJson(playlist.toJson()).toJson(),
      playlist.toJson(),
    );
  });

  test('rejects non-text playlist track IDs', () {
    expect(
      () => MusicPlaylist.fromJson({
        'id': 'playlist-123',
        'name': 'Late night',
        'trackIds': ['track-a', 42],
      }),
      throwsFormatException,
    );
  });
}
