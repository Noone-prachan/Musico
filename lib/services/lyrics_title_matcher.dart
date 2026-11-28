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

bool lyricsSearchTitleMatches(String requestedTitle, String candidateTitle) {
  final normalizedTitle = normalizeLyricsTitle(requestedTitle).trim();
  final normalizedCandidate = normalizeLyricsTitle(candidateTitle).trim();
  if (normalizedTitle.isEmpty || normalizedCandidate.isEmpty) return false;
  if (lyricsTitleMatches(normalizedTitle, normalizedCandidate)) return true;

  final pattern =
      r'(^|[^a-z0-9])' + RegExp.escape(normalizedTitle) + r'([^a-z0-9]|$)';
  return RegExp(pattern, caseSensitive: false).hasMatch(normalizedCandidate);
}
