import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';

class BackupAsset {
  const BackupAsset({required this.archivePath, required this.file});

  final String archivePath;
  final File file;
}

class RestoredBackup {
  const RestoredBackup({required this.manifest, required this.assets});

  final Map<String, dynamic> manifest;
  final Map<String, File> assets;
}

class MusicoBackupService {
  static const manifestPath = 'manifest.json';
  static const _maxEntries = 10000;
  static const _maxManifestSize = 10 * 1024 * 1024;
  static const _maxExpandedSize = 20 * 1024 * 1024 * 1024;

  Future<File> createArchive({
    required Directory temporaryDirectory,
    required Map<String, dynamic> manifest,
    required List<BackupAsset> assets,
  }) async {
    await temporaryDirectory.create(recursive: true);
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final manifestFile = File(
      '${temporaryDirectory.path}${Platform.pathSeparator}musico-$stamp-manifest.json',
    );
    final archiveFile = File(
      '${temporaryDirectory.path}${Platform.pathSeparator}musico-$stamp.zip',
    );
    await manifestFile.writeAsString(jsonEncode(manifest), flush: true);

    final archivePaths = <String>{manifestPath};
    for (final asset in assets) {
      if (!_isValidAssetPath(asset.archivePath) ||
          !archivePaths.add(asset.archivePath)) {
        await manifestFile.delete();
        throw const FormatException(
          'The backup contains an invalid media path.',
        );
      }
      if (!await asset.file.exists()) {
        await manifestFile.delete();
        throw FileSystemException(
          'A library file is missing and cannot be backed up.',
          asset.file.path,
        );
      }
    }

    final encoder = ZipFileEncoder();
    encoder.create(archiveFile.path, level: ZipFileEncoder.store);
    var closed = false;
    try {
      await encoder.addFile(manifestFile, manifestPath);
      for (final asset in assets) {
        await encoder.addFile(asset.file, asset.archivePath);
      }
      await encoder.close();
      closed = true;
      return archiveFile;
    } on Object {
      if (!closed) {
        try {
          await encoder.close();
        } on Object catch (error, stackTrace) {
          stderr.writeln(
            'Could not close the incomplete backup archive: $error',
          );
          stderr.writeln(stackTrace);
        }
      }
      if (await archiveFile.exists()) await archiveFile.delete();
      rethrow;
    } finally {
      if (await manifestFile.exists()) await manifestFile.delete();
    }
  }

  Future<RestoredBackup> extractArchive({
    required File archiveFile,
    required Directory stagingDirectory,
  }) async {
    await stagingDirectory.create(recursive: true);
    final input = InputFileStream(archiveFile.path);
    final extracted = <String, File>{};
    try {
      final archive = ZipDecoder().decodeStream(
        input,
        verify: true,
        throwOnError: true,
      );
      if (archive.files.isEmpty || archive.files.length > _maxEntries) {
        throw const FormatException(
          'The backup archive has an invalid file count.',
        );
      }
      var expandedSize = 0;
      final entries = <String, ArchiveFile>{};
      for (final entry in archive.files) {
        if (!entry.isFile ||
            entry.isSymbolicLink ||
            (!_isValidAssetPath(entry.name) && entry.name != manifestPath) ||
            entries.containsKey(entry.name)) {
          throw const FormatException(
            'The backup archive contains an invalid entry.',
          );
        }
        expandedSize += entry.size;
        if (expandedSize > _maxExpandedSize) {
          throw const FormatException(
            'The backup archive is too large to restore.',
          );
        }
        entries[entry.name] = entry;
      }

      final manifestEntry = entries.remove(manifestPath);
      if (manifestEntry == null || manifestEntry.size > _maxManifestSize) {
        throw const FormatException(
          'The backup manifest is missing or too large.',
        );
      }
      final manifestBytes = manifestEntry.readBytes();
      if (manifestBytes == null) {
        throw const FormatException('The backup manifest could not be read.');
      }
      final decodedManifest = jsonDecode(utf8.decode(manifestBytes));
      if (decodedManifest is! Map<String, dynamic>) {
        throw const FormatException(
          'The backup manifest has an invalid format.',
        );
      }

      var index = 0;
      for (final entry in entries.entries) {
        final extension = entry.key.substring(entry.key.lastIndexOf('.'));
        final file = File(
          '${stagingDirectory.path}${Platform.pathSeparator}asset-${index++}$extension',
        );
        final output = OutputFileStream(file.path);
        try {
          entry.value.writeContent(output);
          await output.close();
        } on Object {
          await output.close();
          rethrow;
        }
        extracted[entry.key] = file;
      }
      return RestoredBackup(
        manifest: decodedManifest,
        assets: Map.unmodifiable(extracted),
      );
    } finally {
      await input.close();
    }
  }

  bool _isValidAssetPath(String path) =>
      RegExp(r'^media/(music|videos)/[0-9]{6}\.[A-Za-z0-9]{1,10}$')
          .hasMatch(path);
}
