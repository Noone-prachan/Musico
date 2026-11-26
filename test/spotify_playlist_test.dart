import 'package:flutter_test/flutter_test.dart';
import 'package:musico/models/spotify_playlist.dart';

void main() {
  group('Spotify playlist metadata', () {
    test('imports account-export track metadata', () {
      final playlist = SpotifyPlaylist.decodeExport('''
      {
        "playlists": [{
          "name": "Road songs",
          "items": [{
            "track": {
              "trackName": "Night Drive",
              "artistName": "Sample Artist",
              "albumName": "After Hours",
              "trackUri": "spotify:track:abc123"
            }
          }, {
            "track": null
          }]
        }]
      }
      ''').single;
      final track = playlist.tracks.single;

      expect(playlist.name, 'Road songs');
      expect(track.album, 'After Hours');
      expect(track.spotifyUri, 'spotify:track:abc123');
      expect(
        SpotifyPlaylist.fromJson(playlist.toJson()).tracks.single.title,
        'Night Drive',
      );
    });

    test(
      'imports Spotify playlist API metadata and rejects partial exports',
      () {
        final playlist = SpotifyPlaylist.decodeExport('''
      {
        "name": "API playlist",
        "tracks": {
          "items": [{
            "track": {
              "name": "Open Song",
              "artists": [{"name": "Artist A"}, {"name": "Artist B"}],
              "album": {"name": "Album"},
              "uri": "spotify:track:xyz"
            }
          }]
        }
      }
      ''').single;

        expect(playlist.tracks.single.artist, 'Artist A, Artist B');
        expect(playlist.tracks.single.album, 'Album');
        expect(
          () => SpotifyPlaylist.decodeExport('''
        {"name":"Partial","tracks":{"items":[],"next":"https://api.spotify.com/next"}}
        '''),
          throwsFormatException,
        );
      },
    );

    test('imports playlist collections and normalized Spotify field names', () {
      final playlists = SpotifyPlaylist.decodeExport('''
      {
        "items": [{
          "Playlist Name": "Road songs",
          "tracks": {
            "items": [{
              "track": {
                "Track Name": "Night Drive",
                "Artist Name": "Sample Artist"
              }
            }]
          }
        }]
      }
      ''');

      expect(playlists.single.name, 'Road songs');
      expect(playlists.single.tracks.single.title, 'Night Drive');
      expect(playlists.single.tracks.single.artist, 'Sample Artist');
    });

    test('rejects invalid and oversized playlist exports', () {
      expect(
        () => SpotifyPlaylist.decodeExport('{"playlists":[]}'),
        throwsFormatException,
      );
      expect(
        () => SpotifyPlaylist.decodeExport('x' * (10 * 1024 * 1024 + 1)),
        throwsFormatException,
      );
    });
  });
}
