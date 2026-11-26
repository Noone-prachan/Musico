import 'package:material_ui/material_ui.dart';

import '../theme/app_theme.dart';

class SearchAutocompleteField extends StatefulWidget {
  const SearchAutocompleteField({
    required this.suggestions,
    required this.decoration,
    this.controller,
    this.focusNode,
    this.initialText = '',
    this.autofocus = false,
    this.textInputAction = TextInputAction.search,
    this.minQueryLength = 0,
    this.onChanged,
    this.onSubmitted,
    this.onSelected,
    super.key,
  });

  final List<String> suggestions;
  final InputDecoration decoration;
  final TextEditingController? controller;
  final FocusNode? focusNode;
  final String initialText;
  final bool autofocus;
  final TextInputAction textInputAction;
  final int minQueryLength;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final ValueChanged<String>? onSelected;

  @override
  State<SearchAutocompleteField> createState() =>
      _SearchAutocompleteFieldState();
}

class _SearchAutocompleteFieldState extends State<SearchAutocompleteField> {
  late final TextEditingController _internalController = TextEditingController(
    text: widget.initialText,
  );
  late final FocusNode _internalFocusNode = FocusNode();
  late FocusNode _listenedFocusNode;
  bool _hideSuggestionsWhenEmpty = false;
  bool _handlingFieldSubmit = false;
  bool _selectionHandledOnSubmit = false;

  TextEditingController get _controller =>
      widget.controller ?? _internalController;

  FocusNode get _focusNode => widget.focusNode ?? _internalFocusNode;

  @override
  void initState() {
    super.initState();
    _listenedFocusNode = _focusNode;
    _listenedFocusNode.addListener(_handleFocusChange);
  }

  @override
  void didUpdateWidget(covariant SearchAutocompleteField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode) {
      _listenedFocusNode.removeListener(_handleFocusChange);
      _listenedFocusNode = _focusNode;
      _listenedFocusNode.addListener(_handleFocusChange);
    }
    if (widget.controller == null &&
        widget.initialText != oldWidget.initialText &&
        widget.initialText != _internalController.text) {
      _internalController.value = TextEditingValue(
        text: widget.initialText,
        selection: TextSelection.collapsed(offset: widget.initialText.length),
      );
    }
  }

  @override
  void dispose() {
    _listenedFocusNode.removeListener(_handleFocusChange);
    _internalController.dispose();
    _internalFocusNode.dispose();
    super.dispose();
  }

  void _handleFocusChange() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return PopScope<void>(
      canPop: !_focusNode.hasFocus,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _focusNode.hasFocus) _focusNode.unfocus();
      },
      child: Autocomplete<String>(
        textEditingController: _controller,
        focusNode: _focusNode,
        optionsBuilder: (value) {
          if (_hideSuggestionsWhenEmpty && value.text.trim().isEmpty) {
            return const [];
          }
          final query = value.text.trim().toLowerCase();
          if (query.length < widget.minQueryLength) return const [];
          final seen = <String>{};
          final options = <String>[];
          for (final rawSuggestion in widget.suggestions) {
            final suggestion = rawSuggestion.trim();
            final normalized = suggestion.toLowerCase();
            if (suggestion.isEmpty ||
                normalized == query ||
                !normalized.contains(query) ||
                !seen.add(normalized)) {
              continue;
            }
            options.add(suggestion);
            if (options.length == 6) break;
          }
          return options;
        },
        onSelected: (suggestion) {
          if (_handlingFieldSubmit) _selectionHandledOnSubmit = true;
          widget.onChanged?.call(suggestion);
          widget.onSelected?.call(suggestion);
        },
        fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) =>
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: controller,
              builder: (context, value, _) => TextField(
                controller: controller,
                focusNode: focusNode,
                autofocus: widget.autofocus,
                textInputAction: widget.textInputAction,
                onChanged: (text) {
                  if (text.isNotEmpty) _hideSuggestionsWhenEmpty = false;
                  widget.onChanged?.call(text);
                },
                onSubmitted: (value) {
                  _selectionHandledOnSubmit = false;
                  _handlingFieldSubmit = true;
                  try {
                    onFieldSubmitted();
                  } finally {
                    _handlingFieldSubmit = false;
                  }
                  if (!_selectionHandledOnSubmit) {
                    widget.onSubmitted?.call(value);
                  }
                },
                decoration: widget.decoration.copyWith(
                  suffixIcon:
                      widget.decoration.suffixIcon ??
                      (value.text.isEmpty
                          ? null
                          : IconButton(
                              tooltip: 'Clear search',
                              onPressed: () {
                                _hideSuggestionsWhenEmpty = true;
                                controller.clear();
                                widget.onChanged?.call('');
                              },
                              icon: const Icon(Icons.close_rounded, size: 17),
                            )),
                ),
              ),
            ),
        optionsViewBuilder: (context, onSelected, options) {
          final items = options.toList(growable: false);
          return Align(
            alignment: Alignment.topLeft,
            child: Material(
              color: MusicoPalette.paper,
              elevation: 3,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
                side: const BorderSide(color: MusicoPalette.line),
              ),
              clipBehavior: Clip.antiAlias,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 260),
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  shrinkWrap: true,
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    final highlighted =
                        AutocompleteHighlightedOption.of(context) == index;
                    return ListTile(
                      dense: true,
                      selected: highlighted,
                      selectedTileColor: MusicoPalette.canvasAlt,
                      leading: const Icon(Icons.search_rounded, size: 18),
                      title: Text(
                        items[index],
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onTap: () => onSelected(items[index]),
                    );
                  },
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
