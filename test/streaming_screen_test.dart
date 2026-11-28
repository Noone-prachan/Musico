import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:musico/models/media_title.dart';
import 'package:musico/models/stream_watch_progress.dart';
import 'package:musico/screens/streaming_screen.dart';
import 'package:musico/services/stream_watch_progress_service.dart';
import 'package:musico/state/app_state.dart';
import 'package:musico/widgets/search_autocomplete_field.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('Anime page has no duplicate category selector', (tester) async {
    final appState = AppState();

    await tester.pumpWidget(_watchApp(appState: appState, tab: 0));

    expect(find.widgetWithText(ChoiceChip, 'All'), findsNothing);
    expect(find.widgetWithText(ChoiceChip, 'TV shows'), findsNothing);
    expect(find.text('Browse all'), findsNothing);
    expect(find.text('Featured TV shows'), findsNothing);
    expect(find.text('Featured movies'), findsNothing);
    expect(find.text('New seasons'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    appState.dispose();
  });

  testWidgets('TV and Movies pages show their own featured shelves', (
    tester,
  ) async {
    final appState = AppState();

    await tester.pumpWidget(_watchApp(appState: appState, tab: 1));
    await _scrollToText(tester, 'Featured TV shows');
    expect(find.text('Featured TV shows'), findsOneWidget);
    expect(find.text('Featured movies'), findsNothing);

    await tester.pumpWidget(_watchApp(appState: appState, tab: 2));
    await _scrollToText(tester, 'Featured movies');
    expect(find.text('Featured movies'), findsOneWidget);
    expect(find.text('Featured TV shows'), findsNothing);
    expect(find.text('New seasons'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    appState.dispose();
  });

  testWidgets(
    'anime cards open from their title and keep Watchlist reachable',
    (tester) async {
      tester.view.physicalSize = const Size(800, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final appState = AppState()
        ..seasonTitles = const [
          MediaTitle(
            id: 1,
            title: 'Demon Slayer',
            imageUrl: null,
            format: 'TV',
            status: 'RELEASING',
            season: 'SPRING',
            seasonYear: 2026,
            genres: [],
            startDate: null,
            episodes: 12,
            airings: [],
          ),
        ];

      await tester.pumpWidget(_watchApp(appState: appState, tab: 0));
      await tester.pump();

      final watchlistButton = find.widgetWithText(TextButton, 'Watchlist');
      await tester.ensureVisible(watchlistButton);
      await tester.pumpAndSettle();
      expect(tester.getSize(watchlistButton).height, 48);
      await tester.tap(watchlistButton);
      await tester.pumpAndSettle();
      expect(appState.watchlist, hasLength(1));

      final posterTitle = find.text('Demon Slayer').first;
      await tester.ensureVisible(posterTitle);
      await tester.pumpAndSettle();
      await tester.tap(posterTitle);
      await tester.pumpAndSettle();
      final search = tester.widget<SearchAutocompleteField>(
        find.byType(SearchAutocompleteField).first,
      );
      expect(search.controller?.text, 'Demon Slayer');
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
      appState.dispose();
    },
  );

  testWidgets('Continue watching asks whether to resume or start over', (
    tester,
  ) async {
    await StreamWatchProgressService().save(
      const StreamWatchProgress(
        category: StreamWatchCategory.anime,
        catalogId: 'demon-slayer',
        title: 'Demon Slayer',
        episodeLabel: 'Episode 3',
        episodeId: 'episode-3',
        episodeNumber: 3,
        episodeIndex: 2,
        positionMs: 60000,
        durationMs: 120000,
        lastWatchedAtMs: 100,
      ),
    );
    final appState = AppState();

    await tester.pumpWidget(_watchApp(appState: appState, tab: 0));
    await tester.pumpAndSettle();

    expect(find.text('Continue watching'), findsOneWidget);
    await tester.tap(find.text('Demon Slayer').first);
    await tester.pumpAndSettle();

    expect(find.text('Continue watching?'), findsOneWidget);
    expect(find.text('Resume'), findsOneWidget);
    expect(find.text('Start from beginning'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    await tester.pumpWidget(_watchApp(appState: appState, tab: 2));
    await tester.pumpAndSettle();
    expect(find.text('Continue watching'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    appState.dispose();
  });
}

Widget _watchApp({required AppState appState, required int tab}) {
  return MaterialApp(
    home: Scaffold(
      body: SizedBox(
        width: 400,
        height: 800,
        child: StreamingScreen(appState: appState, initialTab: tab),
      ),
    ),
  );
}

Future<void> _scrollToText(WidgetTester tester, String text) async {
  final scrollable = find
      .byWidgetPredicate(
        (widget) =>
            widget is Scrollable && widget.axisDirection == AxisDirection.down,
      )
      .first;
  await tester.scrollUntilVisible(find.text(text), 300, scrollable: scrollable);
}
