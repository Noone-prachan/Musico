import 'package:flutter_test/flutter_test.dart';
import 'package:musico/models/music_track.dart';
import 'package:musico/models/video_track.dart';

void main() {
  group('local media records', () {
    test('video metadata round-trips for the offline library', () {
      const video = VideoTrack(
        id: 'video-123',
        title: 'Artist - Live session',
        path: r'C:\Musico\videos\session.mp4',
        addedAtMs: 456,
        byteSize: 789,
      );

      expect(VideoTrack.fromJson(video.toJson()).toJson(), video.toJson());
    });

    test('older audio records without optional license fields still load', () {
      final track = MusicTrack.fromJson({
        'id': 'import-123',
        'title': 'A saved song',
        'artist': 'Imported audio',
        'path': r'C:\Musico\music\song.mp3',
      });

      expect(track.license, isNull);
      expect(track.licenseUrl, isNull);
      expect(track.sourceUrl, isNull);
      expect(track.byteSize, 0);
    });

    test('formats imported filenames for display without changing stored data', () {
      const originalTitle =
          'Yabesh+Thapa+-+Kamal+Phool+(+Dada+pari+kanchi+)+_+OFFICIAL+LYRIC+VIDEO [xrP1fGAEwTw]';
      final track = MusicTrack.fromJson({
        'id': 'import-formatted',
        'title': originalTitle,
        'artist': 'Imported audio',
        'path': r'C:\Musico\music\track.mp3',
      });

      expect(track.displayMetadata.artist, 'Yabesh Thapa');
      expect(
        track.displayMetadata.title,
        'Kamal Phool (Dada pari kanchi) OFFICIAL LYRIC VIDEO',
      );
      expect(track.title, originalTitle);
    });

    test('renames track metadata without changing its audio file', () {
      final track = MusicTrack.fromJson({
        'id': 'rename-123',
        'title': 'Old title',
        'artist': 'Old artist',
        'path': r'C:\Musico\music\original-file.mp3',
        'durationMs': 12000,
        'clipStartMs': 1500,
        'clipEndMs': 9500,
      });

      final renamed = track.copyWith(title: 'New title', artist: 'New artist');

      expect(renamed.title, 'New title');
      expect(renamed.artist, 'New artist');
      expect(renamed.path, track.path);
      expect(renamed.clipStartMs, track.clipStartMs);
      expect(renamed.clipEndMs, track.clipEndMs);
    });

    test('saved playback trim survives a metadata round trip', () {
      final track = MusicTrack.fromJson({
        'id': 'import-456',
        'title': 'A trimmed song',
        'artist': 'Imported audio',
        'path': r'C:\Musico\music\trimmed.mp3',
        'durationMs': 12000,
        'clipStartMs': 1500,
        'clipEndMs': 9500,
      });

      final restored = MusicTrack.fromJson(track.toJson());
      expect(restored.clipStartMs, 1500);
      expect(restored.clipEndMs, 9500);
    });

    test('rejects invalid saved playback trim bounds', () {
      expect(
        () => MusicTrack.fromJson({
          'id': 'import-789',
          'title': 'Invalid trim',
          'artist': 'Imported audio',
          'path': r'C:\Musico\music\invalid.mp3',
          'clipStartMs': 5000,
          'clipEndMs': 4000,
        }),
        throwsFormatException,
      );
    });
  });
}
