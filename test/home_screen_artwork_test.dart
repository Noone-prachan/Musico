import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:musico/models/music_track.dart';
import 'package:musico/screens/home_screen.dart';
import 'package:musico/state/app_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('Continue listening shows the current track artwork', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const artworkPath = r'C:\artwork\current-track.jpg';
    final appState = AppState()
      ..currentTrack = const MusicTrack(
        id: 'track-1',
        title: 'Current track',
        artist: 'Current artist',
        path: 'current-track.mp3',
        durationMs: 60000,
        addedAtMs: 0,
        license: null,
        licenseUrl: null,
        sourceUrl: null,
        commonsPageId: null,
        byteSize: 0,
        artworkPath: artworkPath,
      );
    addTearDown(appState.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HomeScreen(appState: appState, onNavigate: (_) {}),
        ),
      ),
    );
    await tester.pump();
    await tester.ensureVisible(find.text('Current track'));

    final trackTile = find.ancestor(
      of: find.text('Current track'),
      matching: find.byType(ListTile),
    );
    final artwork = tester.widget<Image>(
      find.descendant(of: trackTile, matching: find.byType(Image)),
    );
    expect(
      artwork.image,
      isA<FileImage>().having(
        (image) => image.file.path,
        'artwork path',
        artworkPath,
      ),
    );
  });
}
