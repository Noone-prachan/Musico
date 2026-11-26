import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:musico/widgets/search_autocomplete_field.dart';

void main() {
  testWidgets('filters suggestions and submits the selected completion', (
    tester,
  ) async {
    String? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SearchAutocompleteField(
            suggestions: const ['Dune', 'Dune: Part Two', 'Interstellar'],
            decoration: const InputDecoration(hintText: 'Search titles'),
            onSelected: (value) => selected = value,
          ),
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), 'dun');
    await tester.pumpAndSettle();

    expect(find.text('Dune'), findsOneWidget);
    expect(find.text('Dune: Part Two'), findsOneWidget);
    expect(find.text('Interstellar'), findsNothing);

    await tester.tap(find.text('Dune: Part Two'));
    await tester.pumpAndSettle();
    expect(selected, 'Dune: Part Two');
  });

  testWidgets('clearing search hides suggestions until new input is entered', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SearchAutocompleteField(
            suggestions: const ['Dune', 'Dune: Part Two', 'Interstellar'],
            decoration: const InputDecoration(hintText: 'Search titles'),
          ),
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), 'dun');
    await tester.pumpAndSettle();
    expect(find.text('Dune: Part Two'), findsOneWidget);

    await tester.tap(find.byTooltip('Clear search'));
    await tester.pumpAndSettle();

    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '',
    );
    expect(find.text('Dune'), findsNothing);
    expect(find.text('Dune: Part Two'), findsNothing);

    await tester.enterText(find.byType(TextField), 'inter');
    await tester.pumpAndSettle();
    expect(find.text('Interstellar'), findsOneWidget);
  });

  testWidgets('system back dismisses suggestions and keeps the current route', (
    tester,
  ) async {
    final focusNode = FocusNode();
    addTearDown(focusNode.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SearchAutocompleteField(
            suggestions: const ['Dune', 'Dune: Part Two', 'Interstellar'],
            decoration: const InputDecoration(hintText: 'Search titles'),
            focusNode: focusNode,
          ),
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), 'dun');
    await tester.pumpAndSettle();
    expect(find.text('Dune: Part Two'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(focusNode.hasFocus, isFalse);
    expect(find.text('Dune: Part Two'), findsNothing);
    expect(find.byType(Scaffold), findsOneWidget);
  });
}
