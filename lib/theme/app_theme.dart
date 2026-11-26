import 'package:material_ui/material_ui.dart';

abstract final class MusicoPalette {
  static const canvas = Color(0xFFF3EEE4);
  static const canvasAlt = Color(0xFFE9E1D4);
  static const paper = Color(0xFFFBF8F1);
  static const surface = Color(0xFFEDE5D8);
  static const glass = Color(0xFFE2D8C8);
  static const glassStrong = Color(0xFFB9AD9B);
  static const ink = Color(0xFF29251F);
  static const muted = Color(0xFF71695E);
  static const softInk = Color(0xFF4F493F);
  static const line = Color(0xFFD4CABB);
  static const forest = Color(0xFF465A4B);
  static const forestLight = Color(0xFF596C55);
  static const olive = forestLight;
  static const moss = Color(0xFF687657);
  static const terracotta = Color(0xFF98472F);
  static const clay = Color(0xFFE9DCCB);
  static const clayLight = Color(0xFFF2DED1);
  static const sky = Color(0xFFE2E6E7);
  static const white = Color(0xFFFFFFFF);
  static const success = Color(0xFF546A43);
  static const error = Color(0xFF9B3F35);
}

abstract final class MusicoTheme {
  static final WidgetStateProperty<MouseCursor?> _interactiveMouseCursor =
      WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.disabled)
            ? SystemMouseCursors.basic
            : SystemMouseCursors.click,
      );

  static ThemeData get light {
    final scheme =
        ColorScheme.fromSeed(
          seedColor: MusicoPalette.forest,
          brightness: Brightness.light,
          surface: MusicoPalette.paper,
          primary: MusicoPalette.forest,
          secondary: MusicoPalette.terracotta,
          tertiary: MusicoPalette.moss,
          error: MusicoPalette.error,
        ).copyWith(
          primary: MusicoPalette.forest,
          onPrimary: MusicoPalette.white,
          primaryContainer: const Color(0xFFDCE4D8),
          onPrimaryContainer: MusicoPalette.ink,
          secondary: MusicoPalette.terracotta,
          onSecondary: MusicoPalette.white,
          secondaryContainer: MusicoPalette.clayLight,
          onSecondaryContainer: const Color(0xFF4F2A1F),
          surface: MusicoPalette.paper,
          onSurface: MusicoPalette.ink,
          outline: MusicoPalette.line,
          surfaceContainerHighest: MusicoPalette.canvasAlt,
          surfaceContainerLow: MusicoPalette.surface,
          error: MusicoPalette.error,
          onError: MusicoPalette.white,
        );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      brightness: Brightness.light,
      scaffoldBackgroundColor: MusicoPalette.canvas,
      canvasColor: MusicoPalette.canvas,
      fontFamily: 'Manrope',
      textTheme: const TextTheme(
        displayLarge: TextStyle(
          color: MusicoPalette.ink,
          fontSize: 36,
          fontWeight: FontWeight.w700,
          letterSpacing: -1,
          height: 1.08,
        ),
        headlineMedium: TextStyle(
          color: MusicoPalette.ink,
          fontSize: 26,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.55,
          height: 1.15,
        ),
        bodyLarge: TextStyle(
          color: MusicoPalette.ink,
          fontSize: 15,
          height: 1.45,
        ),
        bodyMedium: TextStyle(
          color: MusicoPalette.ink,
          fontSize: 14,
          height: 1.4,
        ),
        bodySmall: TextStyle(
          color: MusicoPalette.muted,
          fontSize: 12,
          height: 1.4,
        ),
        titleLarge: TextStyle(
          color: MusicoPalette.ink,
          fontSize: 22,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.45,
        ),
        titleMedium: TextStyle(
          color: MusicoPalette.ink,
          fontSize: 16,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.15,
        ),
        titleSmall: TextStyle(
          color: MusicoPalette.ink,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
        labelLarge: TextStyle(
          color: MusicoPalette.ink,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
      iconTheme: const IconThemeData(color: MusicoPalette.softInk, size: 20),
      dialogTheme: DialogThemeData(
        backgroundColor: MusicoPalette.paper,
        surfaceTintColor: Colors.transparent,
        elevation: 8,
        shape: RoundedRectangleBorder(
          side: const BorderSide(color: MusicoPalette.line),
          borderRadius: BorderRadius.circular(14),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: MusicoPalette.paper,
        surfaceTintColor: Colors.transparent,
        elevation: 6,
        shape: RoundedRectangleBorder(
          side: const BorderSide(color: MusicoPalette.line),
          borderRadius: BorderRadius.circular(10),
        ),
        textStyle: const TextStyle(
          color: MusicoPalette.ink,
          fontSize: 13,
          fontWeight: FontWeight.w500,
        ),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: MusicoPalette.surface,
          borderRadius: BorderRadius.circular(6),
        ),
        textStyle: const TextStyle(color: MusicoPalette.ink, fontSize: 11),
        waitDuration: const Duration(milliseconds: 450),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: MusicoPalette.canvasAlt,
        indicatorColor: MusicoPalette.clayLight,
        elevation: 0,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            color: states.contains(WidgetState.selected)
                ? MusicoPalette.ink
                : MusicoPalette.muted,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected)
                ? MusicoPalette.terracotta
                : MusicoPalette.muted,
          ),
        ),
      ),
      navigationRailTheme: const NavigationRailThemeData(
        backgroundColor: MusicoPalette.paper,
        indicatorColor: MusicoPalette.clayLight,
        selectedIconTheme: IconThemeData(color: MusicoPalette.terracotta),
        unselectedIconTheme: IconThemeData(color: MusicoPalette.muted),
        selectedLabelTextStyle: TextStyle(
          color: MusicoPalette.ink,
          fontWeight: FontWeight.w600,
        ),
        unselectedLabelTextStyle: TextStyle(color: MusicoPalette.muted),
      ),
      dividerTheme: const DividerThemeData(
        color: MusicoPalette.line,
        thickness: 1,
        space: 1,
      ),
      dividerColor: MusicoPalette.line,
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: MusicoPalette.paper,
        isDense: true,
        hintStyle: const TextStyle(
          color: MusicoPalette.muted,
          fontSize: 13,
          fontWeight: FontWeight.w500,
        ),
        labelStyle: const TextStyle(color: MusicoPalette.muted, fontSize: 13),
        floatingLabelStyle: const TextStyle(color: MusicoPalette.forestLight),
        prefixIconColor: MusicoPalette.muted,
        suffixIconColor: MusicoPalette.muted,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderSide: const BorderSide(color: MusicoPalette.line),
          borderRadius: BorderRadius.circular(10),
        ),
        enabledBorder: OutlineInputBorder(
          borderSide: const BorderSide(color: MusicoPalette.line),
          borderRadius: BorderRadius.circular(10),
        ),
        focusedBorder: OutlineInputBorder(
          borderSide: const BorderSide(
            color: MusicoPalette.forestLight,
            width: 1.4,
          ),
          borderRadius: BorderRadius.circular(10),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(48, 48),
          padding: const EdgeInsets.symmetric(horizontal: 18),
          backgroundColor: MusicoPalette.forest,
          foregroundColor: MusicoPalette.white,
          disabledBackgroundColor: MusicoPalette.forest.withValues(alpha: .38),
          disabledForegroundColor: MusicoPalette.white.withValues(alpha: .85),
          elevation: 0,
          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
        ).copyWith(mouseCursor: _interactiveMouseCursor),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(48, 48),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          foregroundColor: MusicoPalette.terracotta,
          backgroundColor: MusicoPalette.paper,
          side: const BorderSide(color: MusicoPalette.line),
          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
        ).copyWith(mouseCursor: _interactiveMouseCursor),
      ),
      textButtonTheme: TextButtonThemeData(
        style: ButtonStyle(
          foregroundColor: WidgetStateProperty.all(MusicoPalette.terracotta),
          mouseCursor: _interactiveMouseCursor,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: ButtonStyle(mouseCursor: _interactiveMouseCursor),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: MusicoPalette.forestLight,
        thumbColor: MusicoPalette.forestLight,
        inactiveTrackColor: MusicoPalette.glassStrong,
        overlayColor: MusicoPalette.forest.withValues(alpha: .12),
        trackHeight: 3,
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: MusicoPalette.forestLight,
        linearTrackColor: MusicoPalette.glassStrong,
        circularTrackColor: MusicoPalette.glassStrong,
      ),
      switchTheme: SwitchThemeData(
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? MusicoPalette.forestLight
              : MusicoPalette.glassStrong,
        ),
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? MusicoPalette.canvas
              : MusicoPalette.muted,
        ),
      ),
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStateProperty.all(MusicoPalette.glassStrong),
        trackColor: WidgetStateProperty.all(Colors.transparent),
        radius: const Radius.circular(5),
        thickness: WidgetStateProperty.all(5),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: MusicoPalette.surface,
        contentTextStyle: const TextStyle(
          color: MusicoPalette.ink,
          fontSize: 12,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: MusicoPalette.canvasAlt,
        disabledColor: MusicoPalette.canvasAlt,
        selectedColor: MusicoPalette.clay,
        side: const BorderSide(color: MusicoPalette.line),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        labelStyle: const TextStyle(
          color: MusicoPalette.softInk,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
        secondaryLabelStyle: const TextStyle(
          color: MusicoPalette.ink,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? MusicoPalette.forest
                : MusicoPalette.paper,
          ),
          foregroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? MusicoPalette.white
                : MusicoPalette.softInk,
          ),
          side: WidgetStateProperty.all(
            const BorderSide(color: MusicoPalette.line),
          ),
        ),
      ),
      cardTheme: CardThemeData(
        color: MusicoPalette.paper,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          side: const BorderSide(color: MusicoPalette.line),
          borderRadius: BorderRadius.circular(11),
        ),
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: MusicoPalette.forestLight,
        selectionColor: MusicoPalette.forestLight.withValues(alpha: .20),
        selectionHandleColor: MusicoPalette.forestLight,
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: ZoomPageTransitionsBuilder(),
          TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
        },
      ),
    );
  }
}
