/// Minimal HLS master-playlist parser.
///
/// Musico only needs two things out of a master playlist: the video renditions
/// (so the player can offer a real quality list) and the audio renditions (so
/// non-English dubs can be picked even when mpv does not expose them as
/// separate tracks).
class HlsPlaylist {
  const HlsPlaylist({required this.variants, required this.audioTracks});

  static const empty = HlsPlaylist(variants: [], audioTracks: []);

  final List<HlsVariant> variants;
  final List<HlsAudioRendition> audioTracks;

  bool get isEmpty => variants.isEmpty && audioTracks.isEmpty;

  static HlsPlaylist parse(String body) {
    if (!body.contains('#EXTM3U')) return empty;
    final variants = <HlsVariant>[];
    final audio = <HlsAudioRendition>[];
    final lines = body.split('\n');
    for (var index = 0; index < lines.length; index++) {
      final line = lines[index].trim();
      if (line.startsWith('#EXT-X-STREAM-INF:')) {
        final attributes = _attributes(
          line.substring('#EXT-X-STREAM-INF:'.length),
        );
        String? uri;
        for (var next = index + 1; next < lines.length; next++) {
          final candidate = lines[next].trim();
          if (candidate.isEmpty) continue;
          if (candidate.startsWith('#')) break;
          uri = candidate;
          break;
        }
        if (uri == null) continue;
        final height = _height(attributes['RESOLUTION']);
        final bandwidth = int.tryParse(attributes['BANDWIDTH'] ?? '');
        variants.add(
          HlsVariant(
            uri: uri,
            height: height,
            bandwidth: bandwidth,
            name: attributes['NAME'],
          ),
        );
      } else if (line.startsWith('#EXT-X-MEDIA:')) {
        final attributes = _attributes(line.substring('#EXT-X-MEDIA:'.length));
        if ((attributes['TYPE'] ?? '').toUpperCase() != 'AUDIO') continue;
        final language = attributes['LANGUAGE'];
        final name = attributes['NAME'] ?? language;
        if (name == null || name.trim().isEmpty) continue;
        audio.add(
          HlsAudioRendition(
            name: name.trim(),
            language: language?.trim().toLowerCase(),
            isDefault: (attributes['DEFAULT'] ?? '').toUpperCase() == 'YES',
            uri: attributes['URI'],
          ),
        );
      }
    }
    variants.sort((a, b) => (b.height ?? 0).compareTo(a.height ?? 0));
    return HlsPlaylist(variants: variants, audioTracks: audio);
  }

  static Map<String, String> _attributes(String source) {
    final attributes = <String, String>{};
    var depth = 0;
    var quote = false;
    final buffer = StringBuffer();
    final pairs = <String>[];
    for (var index = 0; index < source.length; index++) {
      final char = source[index];
      if (char == '"') quote = !quote;
      if (!quote && char == ',') {
        pairs.add(buffer.toString());
        buffer.clear();
        continue;
      }
      buffer.write(char);
      if (!quote && char == '=') depth++;
    }
    pairs.add(buffer.toString());
    for (final pair in pairs) {
      final equals = pair.indexOf('=');
      if (equals <= 0) continue;
      final key = pair.substring(0, equals).trim();
      var value = pair.substring(equals + 1).trim();
      if (value.length >= 2 && value.startsWith('"') && value.endsWith('"')) {
        value = value.substring(1, value.length - 1);
      }
      if (key.isNotEmpty) attributes[key] = value;
    }
    return attributes;
  }

  static int? _height(String? resolution) {
    if (resolution == null) return null;
    final match = RegExp(r'(\d{2,4})\s*[xX]\s*(\d{2,4})').firstMatch(resolution);
    if (match == null) return null;
    return int.tryParse(match.group(2)!);
  }
}

class HlsVariant {
  const HlsVariant({
    required this.uri,
    this.height,
    this.bandwidth,
    this.name,
  });

  final String uri;
  final int? height;
  final int? bandwidth;
  final String? name;

  String get label {
    if (height != null && height! > 0) return '${height}p';
    if (bandwidth != null) return '${(bandwidth! / 1000000).toStringAsFixed(1)} Mbps';
    return name ?? uri;
  }
}

class HlsAudioRendition {
  const HlsAudioRendition({
    required this.name,
    this.language,
    this.isDefault = false,
    this.uri,
  });

  final String name;
  final String? language;
  final bool isDefault;
  final String? uri;
}
