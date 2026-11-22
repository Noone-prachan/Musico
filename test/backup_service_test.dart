import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:musico/services/backup_service.dart';

void main() {
  group('Side B backup archive', () {
    late Directory temporaryDirectory;
    late Directory stagingDirectory;
    late Directory mediaDirectory;

    setUp(() async {
      temporaryDirectory = await Directory.systemTemp.createTemp(
        'musico-backup',
      );
      stagingDirectory = Directory(
        '${temporaryDirectory.path}${Platform.pathSeparator}staging',
      );
      mediaDirectory = Directory(
        '${temporaryDirectory.path}${Platform.pathSeparator}media',
      );
      await mediaDirectory.create();
    });

    tearDown(() async {
      if (await temporaryDirectory.exists()) {
        await temporaryDirectory.delete(recursive: true);
      }
    });

    test('round-trips the manifest and media files', () async {
      final musicFile = File(
        '${mediaDirectory.path}${Platform.pathSeparator}song.mp3',
      );
      await musicFile.writeAsBytes([1, 2, 3, 4]);
      final service = MusicoBackupService();
      final archiveFile = await service.createArchive(
        temporaryDirectory: temporaryDirectory,
        manifest: const {'format': 'side-b-backup', 'schemaVersion': 1},
        assets: [
          BackupAsset(archivePath: 'media/music/000000.mp3', file: musicFile),
        ],
      );

      final restored = await service.extractArchive(
        archiveFile: archiveFile,
        stagingDirectory: stagingDirectory,
      );

      expect(restored.manifest['format'], 'side-b-backup');
      expect(restored.assets['media/music/000000.mp3']!.path, endsWith('.mp3'));
      expect(await restored.assets['media/music/000000.mp3']!.readAsBytes(), [
        1,
        2,
        3,
        4,
      ]);
    });

    test('rejects archive paths outside the media layout', () async {
      final service = MusicoBackupService();
      await expectLater(
        service.createArchive(
          temporaryDirectory: temporaryDirectory,
          manifest: const {'format': 'side-b-backup', 'schemaVersion': 1},
          assets: [
            BackupAsset(
              archivePath: 'media/music/../../outside.mp3',
              file: File(
                '${mediaDirectory.path}${Platform.pathSeparator}song.mp3',
              ),
            ),
          ],
        ),
        throwsFormatException,
      );
    });
  });
}
