import 'package:flutter_test/flutter_test.dart';
import 'package:musico/services/lyrics_title_matcher.dart';

void main() {
  group('lyrics title matching', () {
    test('ignores common music-video suffixes', () {
      expect(
        lyricsTitleMatches('Firfirey OFFICIAL MUSIC VIDEO', 'Firfirey'),
        isTrue,
      );
      expect(
        lyricsTitleMatches('Firfirey [Official Music Video]', 'Firfirey'),
        isTrue,
      );
    });

    test('keeps meaningful title differences', () {
      expect(lyricsTitleMatches('Firfirey Official Audio', 'Firfirey'), isTrue);
      expect(lyricsTitleMatches('Firfirey Live', 'Firfirey'), isFalse);
    });
  });
}
