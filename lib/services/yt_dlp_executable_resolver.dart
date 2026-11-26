import 'dart:io';

String? findYtDlpExecutable({
  required String applicationDirectory,
  String? userProfile,
}) {
  final candidates = <String>[
    '$applicationDirectory${Platform.pathSeparator}bin${Platform.pathSeparator}yt-dlp.exe',
    if (userProfile != null && userProfile.isNotEmpty) ...[
      '$userProfile\\AppData\\Roaming\\Python\\Python314\\Scripts\\yt-dlp.exe',
      '$userProfile\\AppData\\Local\\Python\\pythoncore-3.14-64\\Scripts\\yt-dlp.exe',
      '$userProfile\\AppData\\Local\\Programs\\Python\\Python314\\Scripts\\yt-dlp.exe',
      '$userProfile\\AppData\\Roaming\\Python\\Python313\\Scripts\\yt-dlp.exe',
    ],
  ];

  for (final candidate in candidates) {
    if (File(candidate).existsSync()) return candidate;
  }
  return null;
}

List<String> ytDlpRuntimeArguments({required String applicationDirectory}) {
  final denoExecutable = File(
    '$applicationDirectory${Platform.pathSeparator}bin'
    '${Platform.pathSeparator}deno.exe',
  );
  if (!denoExecutable.existsSync()) return const [];
  return ['--js-runtimes', 'deno:${denoExecutable.path}'];
}
