final RegExp _lyricsReleaseSuffix = RegExp(
  r'\s*(?:[-–—|]\s*)?[\(\[\{]?\s*(?:official\s+(?:(?:music|lyrics?)\s+)?(?:video|audio|visualizer|mv)|(?:music|lyrics?)\s+(?:video|audio|visualizer))\s*[\)\]\}]?\s*$',
  caseSensitive: false,
);

String normalizeLyricsTitle(String value) {
  final title = value.trim().replaceAll(RegExp(r'\s+'), ' ');
  final normalized = title.replaceFirst(_lyricsReleaseSuffix, '').trim();
  return normalized.isEmpty ? title : normalized;
}

bool lyricsTitleMatches(String requestedTitle, String candidateTitle) =>
    normalizeLyricsTitle(requestedTitle).toLowerCase() ==
    normalizeLyricsTitle(candidateTitle).toLowerCase();
