import 'dart:convert';

import 'media_download.dart';

class SpotifyPlaylistTrack {
  const SpotifyPlaylistTrack({
    required this.title,
    required this.artist,
    this.album,
    this.spotifyUri,
  });

  final String title;
  final String? artist;
  final String? album;
  final String? spotifyUri;

  bool matchesDownload(MediaDownloadLink download) {
    if (download.category != MediaDownloadCategory.music ||
        SpotifyPlaylist._normalize(title) !=
            SpotifyPlaylist._normalize(download.title)) {
      return false;
    }
    return artist == null ||
        SpotifyPlaylist._normalize(artist!) ==
            SpotifyPlaylist._normalize(download.artist ?? '');
  }

  factory SpotifyPlaylistTrack.fromJson(Map<String, dynamic> json) {
    final title = json['title'];
    if (title is! String || title.trim().isEmpty) {
      throw const FormatException('A Spotify playlist track has no title.');
    }
    return SpotifyPlaylistTrack(
      title: title.trim(),
      artist: SpotifyPlaylist._optionalText(json['artist']),
      album: SpotifyPlaylist._optionalText(json['album']),
      spotifyUri: SpotifyPlaylist._optionalText(json['spotifyUri']),
    );
  }

  Map<String, dynamic> toJson() => {
    'title': title,
    if (artist != null) 'artist': artist,
    if (album != null) 'album': album,
    if (spotifyUri != null) 'spotifyUri': spotifyUri,
  };
}

class SpotifyPlaylist {
  const SpotifyPlaylist({
    required this.id,
    required this.name,
    required this.tracks,
  });

  static const maxFileSize = 10 * 1024 * 1024;
  static const maxPlaylists = 100;
  static const maxTracksPerPlaylist = 5000;

  final String id;
  final String name;
  final List<SpotifyPlaylistTrack> tracks;

  static List<SpotifyPlaylist> decodeExport(String contents) {
    if (utf8.encode(contents).length > maxFileSize) {
      throw const FormatException(
        'The Spotify export exceeds the 10 MB limit.',
      );
    }
    final decoded = jsonDecode(contents);
    final rawPlaylists = _extractPlaylists(decoded);
    if (rawPlaylists.isEmpty || rawPlaylists.length > maxPlaylists) {
      throw const FormatException(
        'The Spotify export must contain between 1 and 100 playlists.',
      );
    }

    return [
      for (var index = 0; index < rawPlaylists.length; index++)
        if (rawPlaylists[index] case final Map<String, dynamic> playlist)
          _fromExportPlaylist(playlist, index)
        else
          throw FormatException(
            'Spotify playlist ${index + 1} has an invalid format.',
          ),
    ];
  }

  static SpotifyPlaylist _fromExportPlaylist(
    Map<String, dynamic> json,
    int index,
  ) {
    final nestedPlaylist = _field(json, 'playlist');
    final playlist = nestedPlaylist is Map<String, dynamic>
        ? nestedPlaylist
        : json;
    final name = _playlistName(playlist) ?? _playlistName(json);
    if (name == null) {
      throw FormatException(
        'Spotify playlist ${index + 1} has no name. '
        'Expected a name, playlistName, or title field.',
      );
    }

    var rawItems =
        _field(playlist, 'items') ??
        _field(playlist, 'tracks') ??
        _field(json, 'items') ??
        _field(json, 'tracks');
    if (rawItems is Map<String, dynamic>) {
      if (_field(rawItems, 'next') case final String next?
          when next.isNotEmpty) {
        throw FormatException(
          'Spotify playlist "$name" is paginated; import a complete playlist export.',
        );
      }
      rawItems = _field(rawItems, 'items');
    }
    if (rawItems is! List || rawItems.length > maxTracksPerPlaylist) {
      throw FormatException(
        'Spotify playlist "$name" has an invalid or oversized track list.',
      );
    }

    final tracks = <SpotifyPlaylistTrack>[];
    for (final rawItem in rawItems) {
      if (rawItem is! Map<String, dynamic>) continue;
      final nestedTrack = _field(rawItem, 'track');
      final rawTrack = nestedTrack is Map<String, dynamic>
          ? nestedTrack
          : rawItem;
      final title = _firstText([
        _field(rawTrack, 'trackName'),
        _field(rawTrack, 'name'),
      ]);
      if (title == null) continue;

      tracks.add(
        SpotifyPlaylistTrack(
          title: title,
          artist: _firstText([
            _field(rawTrack, 'artistName'),
            _artistList(_field(rawTrack, 'artists')),
          ]),
          album: _firstText([
            _field(rawTrack, 'albumName'),
            if (_field(rawTrack, 'album') case final Map<String, dynamic> album)
              _field(album, 'name'),
          ]),
          spotifyUri: _firstText([
            _field(rawTrack, 'trackUri'),
            _field(rawTrack, 'uri'),
          ]),
        ),
      );
    }

    final uri = _firstText([
      _field(playlist, 'playlistUri'),
      _field(playlist, 'uri'),
    ]);
    final identity =
        uri ??
        [
          name.toLowerCase(),
          tracks.length,
          tracks.firstOrNull?.spotifyUri ?? tracks.firstOrNull?.title ?? '',
          tracks.lastOrNull?.spotifyUri ?? tracks.lastOrNull?.title ?? '',
        ].join('\u0000');

    return SpotifyPlaylist(
      id: 'spotify-${_stableHash(identity)}',
      name: name,
      tracks: List.unmodifiable(tracks),
    );
  }

  factory SpotifyPlaylist.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final name = json['name'];
    final rawTracks = json['tracks'];
    if (id is! String ||
        id.isEmpty ||
        name is! String ||
        name.trim().isEmpty ||
        rawTracks is! List ||
        rawTracks.length > maxTracksPerPlaylist) {
      throw const FormatException('A saved Spotify playlist is invalid.');
    }
    return SpotifyPlaylist(
      id: id,
      name: name,
      tracks: List.unmodifiable([
        for (final track in rawTracks)
          if (track case final Map<String, dynamic> jsonTrack)
            SpotifyPlaylistTrack.fromJson(jsonTrack)
          else
            throw const FormatException(
              'A saved Spotify playlist track is invalid.',
            ),
      ]),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'tracks': tracks.map((track) => track.toJson()).toList(),
  };

  static String? _artistList(Object? value) {
    if (value is! List) return null;
    final names = <String>[];
    for (final artist in value) {
      final name = artist is Map<String, dynamic>
          ? _optionalText(artist['name'])
          : _optionalText(artist);
      if (name != null) names.add(name);
    }
    return names.isEmpty ? null : names.join(', ');
  }

  static List<dynamic> _extractPlaylists(Object? decoded) {
    if (decoded is List<dynamic>) return decoded;
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException(
        'The Spotify export does not contain playlist metadata.',
      );
    }

    final playlists = _field(decoded, 'playlists');
    if (playlists is List<dynamic>) return playlists;
    if (playlists is Map<String, dynamic>) {
      final nestedItems = _field(playlists, 'items');
      if (_playlistName(playlists) != null) return [playlists];
      if (nestedItems is List<dynamic>) {
        _throwIfPaginated(_field(playlists, 'next'));
        return nestedItems;
      }
    }

    final nestedPlaylist = _field(decoded, 'playlist');
    if (nestedPlaylist is Map<String, dynamic>) return [nestedPlaylist];

    final items = _field(decoded, 'items');
    if (_playlistName(decoded) == null && items is List<dynamic>) {
      _throwIfPaginated(_field(decoded, 'next'));
      return items;
    }
    return [decoded];
  }

  static void _throwIfPaginated(Object? next) {
    if (next is String && next.isNotEmpty) {
      throw const FormatException(
        'The Spotify playlist list is paginated; import a complete export.',
      );
    }
  }

  static String? _playlistName(Map<String, dynamic> json) => _firstText([
    _field(json, 'name'),
    _field(json, 'playlistName'),
    _field(json, 'title'),
  ]);

  static Object? _field(Map<String, dynamic> json, String key) {
    final normalizedKey = _normalizeKey(key);
    for (final entry in json.entries) {
      if (_normalizeKey(entry.key) == normalizedKey) return entry.value;
    }
    return null;
  }

  static String _normalizeKey(String key) =>
      key.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

  static String? _firstText(Iterable<Object?> values) {
    for (final value in values) {
      final text = _optionalText(value);
      if (text != null) return text;
    }
    return null;
  }

  static String? _optionalText(Object? value) {
    if (value is! String || value.trim().isEmpty) return null;
    return value.trim();
  }

  static String _normalize(String value) =>
      value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  static String _stableHash(String value) {
    var hash = 0x811c9dc5;
    for (final codeUnit in value.codeUnits) {
      hash = ((hash ^ codeUnit) * 0x01000193) & 0xffffffff;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }
}
