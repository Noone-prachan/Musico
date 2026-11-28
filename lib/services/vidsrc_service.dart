import 'dart:convert';
import 'package:http/http.dart' as http;

/// Port of `cool-dev-guy/vidsrc.ts` for extracting HLS streams from VidSrc.
class VidSrcService {
  VidSrcService(this._client);

  final http.Client _client;

  Future<({String url, String referer})?> resolveMovie(String imdbOrTmdbId) {
    return _scrape(
      'https://vidsrc.net/embed/movie?imdb=$imdbOrTmdbId',
      fallbackUrl: 'https://vidsrc.mov/embed/movie/$imdbOrTmdbId',
    );
  }

  Future<({String url, String referer})?> resolveEpisode(
    String imdbOrTmdbId,
    int season,
    int episode,
  ) {
    return _scrape(
      'https://vidsrc.net/embed/tv?imdb=$imdbOrTmdbId&season=$season&episode=$episode',
      fallbackUrl: 'https://vidsrc.mov/embed/tv/$imdbOrTmdbId/$season/$episode',
    );
  }

  Future<({String url, String referer})?> _scrape(
    String url, {
    String? fallbackUrl,
  }) async {
    try {
      var embedResp = await _getText(url);
      if (embedResp == null && fallbackUrl != null) {
        embedResp = await _getText(fallbackUrl);
      }
      if (embedResp == null) return null;

      final iframeMatch = RegExp(
        r'<iframe[^>]+src="([^"]+)"',
        caseSensitive: false,
      ).firstMatch(embedResp);
      if (iframeMatch == null) return null;
      var base = iframeMatch.group(1)!;
      if (base.startsWith('//')) base = 'https:$base';
      final baseUri = Uri.tryParse(base);
      if (baseUri == null) return null;
      final baseOrigin = '${baseUri.scheme}://${baseUri.host}';

      final hashes = RegExp(
        r'data-hash="([^"]+)"',
      ).allMatches(embedResp).map((m) => m.group(1)!).toList();

      for (final hash in hashes) {
        final rcpHtml = await _getText('$baseOrigin/rcp/$hash', referer: base);
        if (rcpHtml == null) continue;
        final srcMatch = RegExp(r"src:\s*'([^']*)'").firstMatch(rcpHtml);
        if (srcMatch == null) continue;
        final src = srcMatch.group(1)!;
        if (!src.startsWith('/prorcp/')) continue;
        final prorcp = src.substring('/prorcp/'.length);
        final stream = await _handleProRcp(baseOrigin, prorcp);
        if (stream != null && stream.isNotEmpty) {
          return (url: stream, referer: '$baseOrigin/');
        }
      }
    } on Object {
      return null;
    }
    return null;
  }

  Future<String?> _handleProRcp(String baseOrigin, String prorcp) async {
    final html = await _getText('$baseOrigin/prorcp/$prorcp', referer: '$baseOrigin/');
    if (html == null) return null;

    final scriptMatches = RegExp(
      r'<script\s+src="/([^"]*\.js)\?_=([^"]*)"></script>',
    ).allMatches(html).toList();
    if (scriptMatches.isEmpty) return null;

    final chosen = scriptMatches.length >= 2 &&
            scriptMatches.last.group(1)!.contains('cpt.js')
        ? scriptMatches[scriptMatches.length - 2]
        : scriptMatches.last;
    final scriptPath = '${chosen.group(1)}?_=${chosen.group(2)}';
    final jsCode = await _getText('$baseOrigin/$scriptPath', referer: '$baseOrigin/');
    if (jsCode == null) return null;

    final decryptMatch = RegExp(r'\{\}\}window\[([^"]+)\("([^"]+)"\)').firstMatch(jsCode);
    if (decryptMatch == null) return null;
    final fnName = decryptMatch.group(1)!.trim();
    final encodedId = decryptMatch.group(2)!.trim();
    final elementId = _decrypt(encodedId, fnName);
    if (elementId == null) return null;

    final dataMatch = RegExp(
      'id="${RegExp.escape(elementId)}"[^>]*>([^<]+)<',
    ).firstMatch(html);
    if (dataMatch == null) return null;
    return _decrypt(dataMatch.group(1)!.trim(), encodedId);
  }

  Future<String?> _getText(String url, {String? referer}) async {
    try {
      final response = await _client
          .get(
            Uri.parse(url),
            headers: {
              'User-Agent':
                  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
              if (referer != null) 'Referer': referer,
            },
          )
          .timeout(const Duration(seconds: 12));
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return response.body;
      }
    } on Object {
      return null;
    }
    return null;
  }

  static String? _decrypt(String param, String type) {
    switch (type) {
      case 'LXVUMCoAHJ':
        return _shiftBase64(param, 3);
      case 'GuxKGDsA2T':
        return _shiftBase64(param, 7);
      case 'laM1dAi3vO':
        return _shiftBase64(param, 5);
      case 'nZlUnj2VSo':
        return _caesarShift(param);
      case 'Iry9MQXnLs':
        return _iry9(param);
      case 'IGLImMhWrI':
        return _rot13ReverseBase64(param);
      case 'GTAxQyTyBx':
        return _everySecondReverseBase64(param);
      case 'C66jPHx8qu':
        return _xorHexReverse(param, 'X9a(O;FMV2-7VO5x;Ao :dN1NoFs?j,');
      case 'MyL1IRSfHe':
        return _myL1(param);
      case 'detdj7JHiK':
        return _detdj(param);
      case 'bMGyx71TzQLfdonN':
        return _chunkReverse3(param);
      default:
        return null;
    }
  }

  static String _b64Decode(String input) {
    final normalized = input.replaceAll('-', '+').replaceAll('_', '/');
    final padded = normalized.padRight((normalized.length + 3) ~/ 4 * 4, '=');
    return utf8.decode(base64Decode(padded), allowMalformed: true);
  }

  static String _shiftBase64(String param, int shift) {
    final rev = param.split('').reversed.join();
    final decoded = _b64Decode(rev);
    return String.fromCharCodes(decoded.codeUnits.map((c) => c - shift));
  }

  static String _chunkReverse3(String input) {
    final chunks = <String>[];
    for (var i = 0; i < input.length; i += 3) {
      final end = (i + 3).clamp(0, input.length);
      chunks.add(input.substring(i, end));
    }
    return chunks.reversed.join();
  }

  static String _iry9(String input) {
    const key = 'pWB9V)[*4I`nJpp?ozyB~dbr9yt!_n4u';
    final hexDecoded = StringBuffer();
    for (var i = 0; i + 1 < input.length; i += 2) {
      hexDecoded.writeCharCode(int.parse(input.substring(i, i + 2), radix: 16));
    }
    final bytes = hexDecoded.toString().codeUnits;
    final xored = List<int>.generate(
      bytes.length,
      (i) => (bytes[i] ^ key.codeUnitAt(i % key.length)) - 3,
    );
    return _b64Decode(String.fromCharCodes(xored));
  }

  static String _rot13ReverseBase64(String input) {
    final rev = input.split('').reversed.join();
    final rot = rev.replaceAllMapped(RegExp(r'[a-zA-Z]'), (m) {
      final c = m.group(0)!.codeUnitAt(0);
      final isLower = c >= 97;
      final base = isLower ? 97 : 65;
      return String.fromCharCode(base + ((c - base + 13) % 26));
    });
    return _b64Decode(rot.split('').reversed.join());
  }

  static String _everySecondReverseBase64(String input) {
    final rev = input.split('').reversed.join();
    final buf = StringBuffer();
    for (var i = 0; i < rev.length; i += 2) {
      buf.write(rev[i]);
    }
    return _b64Decode(buf.toString());
  }

  static String _xorHexReverse(String input, String key) {
    final rev = input.split('').reversed.join();
    final out = StringBuffer();
    for (var i = 0; i + 1 < rev.length; i += 2) {
      final byte = int.parse(rev.substring(i, i + 2), radix: 16);
      out.writeCharCode(byte ^ key.codeUnitAt((i ~/ 2) % key.length));
    }
    return out.toString();
  }

  static String _myL1(String input) {
    final rev = input.split('').reversed.join();
    final shifted = String.fromCharCodes(rev.codeUnits.map((c) => c - 1));
    final out = StringBuffer();
    for (var i = 0; i + 1 < shifted.length; i += 2) {
      out.writeCharCode(int.parse(shifted.substring(i, i + 2), radix: 16));
    }
    return out.toString();
  }

  static String _detdj(String input) {
    final sliced = input.substring(10, input.length - 16);
    const key = '3SAY~#%Y(V%>5d/Yg"\$G[Lh1rK4a;7ok';
    final decoded = _b64Decode(sliced);
    final out = StringBuffer();
    for (var i = 0; i < decoded.length; i++) {
      out.writeCharCode(decoded.codeUnitAt(i) ^ key.codeUnitAt(i % key.length));
    }
    return out.toString();
  }

  static String _caesarShift(String input) {
    return input.replaceAllMapped(RegExp(r'[a-zA-Z]'), (m) {
      final c = m.group(0)!.codeUnitAt(0);
      final base = c >= 97 ? 97 : 65;
      return String.fromCharCode(base + ((c - base + 3) % 26));
    });
  }
}
