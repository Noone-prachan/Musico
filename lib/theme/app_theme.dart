import 'package:material_ui/material_ui.dart';

/// Muted dark surfaces with violet actions and a restrained playback accent.
abstract final class MusicoPalette {
  static const canvas = Color(0xFF0D0E12);
  static const canvasAlt = Color(0xFF15161C);
  static const paper = Color(0xFF13141A);
  static const surface = Color(0xFF1B1C23);
  static const glass = Color(0x0FFFFFFF);
  static const glassStrong = Color(0x1AFFFFFF);
  static const ink = Color(0xFFF1F0F2);
  static const muted = Color(0xFFB0AEB6);
  static const softInk = Color(0xFFD4D2D8);
  static const line = Color(0xFF2B2C33);
  static const forest = Color(0xFF8978C8);
  static const forestLight = Color(0xFF61558F);
  static const olive = Color(0xFFCEE08B);
  static const moss = Color(0xFF8AB69B);
  static const terracotta = Color(0xFFC9929D);
  static const clay = Color(0xFF2E2024);
  static const sky = Color(0xFF202127);
  static const white = Color(0xFFFFFFFF);
  static const success = Color(0xFF8AB69B);
  static const error = Color(0xFFFF8A80);
}

abstract final class MusicoTheme {
  static final WidgetStateProperty<MouseCursor?> _interactiveMouseCursor =
      WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.disabled)
            ? SystemMouseCursors.basic
            : SystemMouseCursors.click,
      );

  static ThemeData get dark {
    final scheme =
        ColorScheme.fromSeed(
          seedColor: MusicoPalette.forest,
          brightness: Brightness.dark,
          surface: MusicoPalette.paper,
          primary: MusicoPalette.forest,
          secondary: MusicoPalette.terracotta,
          tertiary: MusicoPalette.olive,
          error: MusicoPalette.error,
        ).copyWith(
          surface: MusicoPalette.paper,
          onSurface: MusicoPalette.ink,
          outline: MusicoPalette.line,
          surfaceContainerHighest: MusicoPalette.canvasAlt,
          surfaceContainerLow: MusicoPalette.surface,
        );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: Colors.transparent,
      canvasColor: Colors.transparent,
      fontFamily: 'Space Grotesk',
      textTheme: const TextTheme(
        displayLarge: TextStyle(
          color: MusicoPalette.ink,
          fontSize: 40,
          fontWeight: FontWeight.w700,
          letterSpacing: -1.2,
          height: 1.02,
        ),
        headlineMedium: TextStyle(
          color: MusicoPalette.ink,
          fontSize: 28,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.6,
          height: 1.08,
        ),
        bodyLarge: TextStyle(color: MusicoPalette.ink, fontSize: 15),
        bodyMedium: TextStyle(color: MusicoPalette.ink, fontSize: 14),
        bodySmall: TextStyle(color: MusicoPalette.muted, fontSize: 12),
        titleLarge: TextStyle(
          color: MusicoPalette.ink,
          fontSize: 24,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.7,
        ),
        titleMedium: TextStyle(
          color: MusicoPalette.ink,
          fontSize: 17,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.2,
        ),
        titleSmall: TextStyle(
          color: MusicoPalette.ink,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
      iconTheme: const IconThemeData(color: MusicoPalette.softInk, size: 20),
      dialogTheme: DialogThemeData(
        backgroundColor: const Color(0xFF17112B),
        surfaceTintColor: Colors.transparent,
        elevation: 24,
        shape: RoundedRectangleBorder(
          side: const BorderSide(color: MusicoPalette.glassStrong),
          borderRadius: BorderRadius.circular(14),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: const Color(0xFF1B1433),
        surfaceTintColor: Colors.transparent,
        elevation: 12,
        shape: RoundedRectangleBorder(
          side: const BorderSide(color: MusicoPalette.glassStrong),
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
          color: const Color(0xFF211A3A),
          border: Border.all(color: MusicoPalette.glassStrong),
          borderRadius: BorderRadius.circular(8),
        ),
        textStyle: const TextStyle(color: MusicoPalette.ink, fontSize: 11),
        waitDuration: const Duration(milliseconds: 450),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: MusicoPalette.canvasAlt,
        indicatorColor: MusicoPalette.forest.withValues(alpha: .16),
        elevation: 0,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            color: states.contains(WidgetState.selected)
                ? MusicoPalette.white
                : MusicoPalette.muted,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected)
                ? MusicoPalette.forest
                : MusicoPalette.muted,
          ),
        ),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: Colors.transparent,
        indicatorColor: MusicoPalette.forest.withValues(alpha: .16),
        selectedIconTheme: const IconThemeData(color: MusicoPalette.forest),
        unselectedIconTheme: const IconThemeData(color: MusicoPalette.muted),
        selectedLabelTextStyle: const TextStyle(
          color: MusicoPalette.ink,
          fontWeight: FontWeight.w600,
        ),
        unselectedLabelTextStyle: const TextStyle(color: MusicoPalette.muted),
      ),
      dividerTheme: const DividerThemeData(
        color: MusicoPalette.glass,
        thickness: 1,
        space: 1,
      ),
      dividerColor: MusicoPalette.glass,
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: MusicoPalette.glass,
        isDense: true,
        hintStyle: const TextStyle(
          color: MusicoPalette.muted,
          fontSize: 13,
          fontWeight: FontWeight.w500,
        ),
        labelStyle: const TextStyle(color: MusicoPalette.muted, fontSize: 13),
        floatingLabelStyle: const TextStyle(color: MusicoPalette.softInk),
        prefixIconColor: MusicoPalette.muted,
        suffixIconColor: MusicoPalette.muted,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderSide: const BorderSide(color: MusicoPalette.glassStrong),
          borderRadius: BorderRadius.circular(10),
        ),
        enabledBorder: OutlineInputBorder(
          borderSide: const BorderSide(color: MusicoPalette.glass),
          borderRadius: BorderRadius.circular(10),
        ),
        focusedBorder: OutlineInputBorder(
          borderSide: const BorderSide(color: MusicoPalette.forest, width: 1.5),
          borderRadius: BorderRadius.circular(14),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(44, 44),
          padding: const EdgeInsets.symmetric(horizontal: 20),
          backgroundColor: MusicoPalette.forest,
          foregroundColor: MusicoPalette.white,
          disabledBackgroundColor: MusicoPalette.forest.withValues(alpha: .38),
          disabledForegroundColor: MusicoPalette.white.withValues(alpha: .7),
          elevation: 0,
          textStyle: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            letterSpacing: .1,
          ),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ).copyWith(mouseCursor: _interactiveMouseCursor),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(44, 44),
          padding: const EdgeInsets.symmetric(horizontal: 17),
          foregroundColor: MusicoPalette.ink,
          backgroundColor: MusicoPalette.glass,
          side: const BorderSide(color: MusicoPalette.glassStrong),
          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ).copyWith(mouseCursor: _interactiveMouseCursor),
      ),
      textButtonTheme: TextButtonThemeData(
        style: ButtonStyle(
          foregroundColor: WidgetStateProperty.all(MusicoPalette.softInk),
          mouseCursor: _interactiveMouseCursor,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: ButtonStyle(
          foregroundColor: WidgetStateProperty.all(MusicoPalette.softInk),
          mouseCursor: _interactiveMouseCursor,
        ),
      ),
      sliderTheme: const SliderThemeData(
        activeTrackColor: MusicoPalette.olive,
        thumbColor: MusicoPalette.olive,
        inactiveTrackColor: MusicoPalette.glassStrong,
        overlayColor: Color(0x33CEE08B),
        trackHeight: 3,
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
        shape: RoundedRectangleBorder(
          side: const BorderSide(color: MusicoPalette.glassStrong),
          borderRadius: BorderRadius.circular(10),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: MusicoPalette.glass,
        disabledColor: MusicoPalette.glass,
        selectedColor: MusicoPalette.forest,
        side: const BorderSide(color: MusicoPalette.glassStrong),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        labelStyle: const TextStyle(
          color: MusicoPalette.softInk,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
        secondaryLabelStyle: const TextStyle(
          color: MusicoPalette.white,
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
                : Colors.transparent,
          ),
          foregroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? MusicoPalette.white
                : MusicoPalette.muted,
          ),
          side: WidgetStateProperty.all(
            const BorderSide(color: MusicoPalette.glassStrong),
          ),
        ),
      ),
      cardTheme: CardThemeData(
        color: MusicoPalette.paper,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          side: const BorderSide(color: MusicoPalette.glass),
          borderRadius: BorderRadius.circular(12),
        ),
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
