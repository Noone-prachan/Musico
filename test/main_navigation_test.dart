import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:musico/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('Playlists in More opens the playlists page', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MusicoApp());
    await tester.pump();

    await tester.tap(find.text('More').last);
    await tester.pump(const Duration(milliseconds: 220));
    await tester.tap(find.text('Playlists'));
    await tester.pump(const Duration(milliseconds: 220));

    expect(find.text('0 playlists'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Desktop sidebar Playlists opens the playlists page', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MusicoApp());
    await tester.pump();

    await tester.tap(find.text('Playlists').first);
    await tester.pump(const Duration(milliseconds: 220));

    expect(find.text('0 playlists'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('mouse back button returns from Playlists to Home', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MusicoApp());
    await tester.pump();
    await tester.tap(find.text('More').last);
    await tester.pump(const Duration(milliseconds: 220));
    await tester.tap(find.text('Playlists'));
    await tester.pump(const Duration(milliseconds: 220));
    expect(find.text('0 playlists'), findsOneWidget);

    final mouse = await tester.createGesture(
      kind: PointerDeviceKind.mouse,
      buttons: kBackMouseButton,
    );
    await mouse.down(const Offset(20, 20));
    await mouse.up();
    await tester.pumpAndSettle();

    expect(find.text('0 playlists'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('system Back returns from Playlists to Home', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MusicoApp());
    await tester.pump();
    await tester.tap(find.text('More').last);
    await tester.pump(const Duration(milliseconds: 220));
    await tester.tap(find.text('Playlists'));
    await tester.pump(const Duration(milliseconds: 220));
    expect(find.text('0 playlists'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.text('0 playlists'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
