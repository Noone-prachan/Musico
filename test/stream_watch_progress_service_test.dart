import 'package:flutter_test/flutter_test.dart';
import 'package:musico/models/stream_watch_progress.dart';
import 'package:musico/services/stream_watch_progress_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('saves resumable entries and filters them by category', () async {
    final service = StreamWatchProgressService();
    final anime = _progress(StreamWatchCategory.anime, 'anime-1');
    final movie = _progress(StreamWatchCategory.movie, 'tt1234567');

    await service.save(anime);
    await service.save(movie);

    expect(
      (await service.load(category: StreamWatchCategory.anime))
          .map((entry) => entry.storageKey)
          .toList(),
      [anime.storageKey],
    );
    expect(
      (await service.load(category: StreamWatchCategory.movie))
          .map((entry) => entry.storageKey)
          .toList(),
      [movie.storageKey],
    );
    expect((await service.load()).length, 2);
  });

  test(
    'removes completed or too-short progress from continue watching',
    () async {
      final service = StreamWatchProgressService();
      final entry = _progress(StreamWatchCategory.tvShow, 'tt7654321');

      await service.save(entry);
      await service.save(entry, completed: true);
      expect(await service.load(), isEmpty);

      const tooShort = StreamWatchProgress(
        category: StreamWatchCategory.movie,
        catalogId: 'tt0000001',
        title: 'Short playback',
        episodeLabel: 'Movie',
        episodeIndex: 0,
        positionMs: 12000,
        durationMs: 60000,
        lastWatchedAtMs: 1,
      );
      await service.save(tooShort);
      expect(await service.load(), isEmpty);
    },
  );
}

StreamWatchProgress _progress(StreamWatchCategory category, String catalogId) =>
    StreamWatchProgress(
      category: category,
      catalogId: catalogId,
      title: 'Test title',
      episodeLabel: 'Episode 2',
      episodeIndex: 1,
      positionMs: 60000,
      durationMs: 120000,
      lastWatchedAtMs: 100,
    );
