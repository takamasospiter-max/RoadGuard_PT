import 'package:flutter/material.dart';

/// Tokens mirror the supplied traveller-app visual reference:
/// pill buttons, 18 px cards, Welcome-blue actions and a quiet blue-grey canvas.
abstract final class RoadColors {
  static const ink = Color(0xFF172733);
  static const panel = Color(0xFFF7F9FA);
  static const canvas = Color(0xFFEAF1F2);
  static const blue = Color(0xFF086CBD);
  static const blueBright = Color(0xFF1679CC);
  static const blueNav = Color(0xFF086CBD);
  static const blueDeep = Color(0xFF07539B);
  static const blueRoute = Color(0xFF06BAF2);
  static const deepBlue = Color(0xFF173441);
  static const blueMapAccent = Color(0xFF63CBEE);
  static const red = Color(0xFFDB2A2A);
  static const blush = Color(0xFFFEC6C6);
  static const sky = Color(0xFFEAF3FF);
  static const skySelect = Color(0xFFF2F7FF);
  static const blueTint = Color(0xFFDCEBFF);
  static const blueIllustrationStart = Color(0xFFDCEBFF);
  static const blueIllustrationEnd = Color(0xFF9CCBFA);
  static const bluePill = Color(0xFFE4F1FF);
  static const bluePillInk = Color(0xFF07539B);
  static const blueAvatar = Color(0xFFDCEBFF);
  static const cream = Color(0xFFFEF3C6);
  static const muted = Color(0xFF667983);
  static const mutedDeep = Color(0xFF596C76);
  static const successInk = Color(0xFF07539B);
  static const dangerInk = Color(0xFFA61D28);
  static const warningInk = Color(0xFF665015);
  static const darkSurface = Color(0xFF1C2A32);
  static const darkRaised = Color(0xFF2B3A43);

  // Reference-specific companions.
  static const cardBorder = Color(0xFFDFE7E9);
  static const fieldBorder = Color(0xFFD4E1E3);
  static const authFieldBorder = Color(0xFFCDDBDD);
  static const headingCircle = Color(0xFFEDF3F4);
  static const secondaryBg = Color(0xFFDCEBFF);
  static const secondaryInk = Color(0xFF07539B);
  static const ghostBg = Color(0xFFEFF3F4);
  static const ghostInk = Color(0xFF26404A);
  static const outlineSoft = Color(0xFFE5EBED);
  static const settingDivider = Color(0xFFE7EEEE);
  static const welcomeOverlayTop = Color(0x5500204D);
  static const welcomeOverlayMid = Color(0x3300183B);
  static const welcomeOverlayEnd = Color(0xED081321);
  static const welcomeButton = Color(0xFF086CBD);
  static const welcomeAi = Color(0xFF63CBEE);
  static const navBorder = Color(0xFFE1E8E8);
  static const navIdle = Color(0xFF657781);
  static const progressTrack = Color(0xFFC4D5D6);
  static const tripBanner = Color(0xFF07539B);
  static const tripBannerSoft = Color(0xFFB8D8FF);
  static const hazardAmber = Color(0xFFF5B52E);
  static const hazardAmberBorder = Color(0xFFFFE2A1);
  static const tripControlsBg = Color(0xFF0B141B);
  static const tripEta = Color(0xFF63CBEE);
  static const tripControlsMuted = Color(0xFFBDC6CB);
  static const tripControlsButton = Color(0xFF263A42);
  static const heroGradientStart = Color(0xFF102D42);
  static const heroGradientEnd = Color(0xFF086CBD);
  static const heroSoft = Color(0xFFB8D8FF);
  static const warnIconBg = Color(0xFFFFEADB);
  static const warnIconInk = Color(0xFFB95B23);
  static const searchFieldBg = Color(0xFFEEF4F7);
  static const toggleTrack = Color(0xFFBDC8CC);
  static const authError = Color(0xFFB32937);
  static const authBrand = Color(0xFF07539B);
  static const authNoteBg = Color(0xFFEAF3FF);
  static const authNoteInk = Color(0xFF355568);
  static const authScreenBg = Color(0xFFF6F9FA);
}

ThemeData roadTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final scheme =
      ColorScheme.fromSeed(
        seedColor: RoadColors.blue,
        brightness: brightness,
      ).copyWith(
        primary: dark ? RoadColors.sky : RoadColors.blue,
        onPrimary: dark ? RoadColors.ink : Colors.white,
        primaryContainer: dark ? RoadColors.darkRaised : RoadColors.bluePill,
        onPrimaryContainer: dark ? RoadColors.sky : RoadColors.bluePillInk,
        secondary: dark ? RoadColors.welcomeAi : RoadColors.secondaryInk,
        onSecondary: dark ? RoadColors.ink : Colors.white,
        secondaryContainer: dark
            ? const Color(0xFF15345B)
            : RoadColors.secondaryBg,
        onSecondaryContainer: dark
            ? RoadColors.welcomeAi
            : RoadColors.secondaryInk,
        tertiary: dark ? RoadColors.cream : RoadColors.warningInk,
        onTertiary: dark ? RoadColors.ink : Colors.white,
        tertiaryContainer: dark ? const Color(0xFF3A3423) : RoadColors.cream,
        onTertiaryContainer: dark ? RoadColors.cream : RoadColors.warningInk,
        error: dark ? RoadColors.blush : RoadColors.red,
        onError: dark ? RoadColors.dangerInk : Colors.white,
        errorContainer: dark ? const Color(0xFF4B252E) : RoadColors.blush,
        onErrorContainer: dark ? RoadColors.blush : RoadColors.dangerInk,
        surface: dark ? RoadColors.ink : Colors.white,
        onSurface: dark ? Colors.white : RoadColors.ink,
        onSurfaceVariant: dark ? RoadColors.sky : RoadColors.muted,
        surfaceContainerLowest: dark ? const Color(0xFF101624) : Colors.white,
        surfaceContainerLow: dark ? RoadColors.darkSurface : RoadColors.panel,
        surfaceContainer: dark
            ? RoadColors.darkRaised
            : const Color(0xFFEDF2F3),
        surfaceContainerHigh: dark
            ? const Color(0xFF33415B)
            : const Color(0xFFE6EDEE),
        surfaceContainerHighest: dark
            ? const Color(0xFF3D4B64)
            : const Color(0xFFDFE7E9),
        surfaceDim: dark ? RoadColors.ink : const Color(0xFFDFE7E9),
        surfaceBright: dark ? RoadColors.darkRaised : Colors.white,
        surfaceTint: Colors.transparent,
        outline: dark ? const Color(0xFF899BB5) : const Color(0xFF65758C),
        outlineVariant: dark ? const Color(0xFF3D4B64) : RoadColors.cardBorder,
        inverseSurface: dark ? RoadColors.sky : RoadColors.ink,
        onInverseSurface: dark ? RoadColors.ink : Colors.white,
        inversePrimary: dark ? RoadColors.ink : RoadColors.sky,
      );
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    brightness: brightness,
  );
  final text = base.textTheme
      .apply(bodyColor: scheme.onSurface, displayColor: scheme.onSurface)
      .copyWith(
        displaySmall: TextStyle(
          fontSize: 32,
          height: 1.12,
          letterSpacing: -.6,
          fontWeight: FontWeight.w800,
          color: scheme.onSurface,
        ),
        headlineLarge: TextStyle(
          fontSize: 29,
          height: 1.15,
          letterSpacing: -.4,
          fontWeight: FontWeight.w800,
          color: scheme.onSurface,
        ),
        // Reference content headings are 26 px bold.
        headlineMedium: TextStyle(
          fontSize: 26,
          height: 1.18,
          letterSpacing: -.3,
          fontWeight: FontWeight.w700,
          color: scheme.onSurface,
        ),
        headlineSmall: TextStyle(
          fontSize: 20,
          height: 1.25,
          fontWeight: FontWeight.w700,
          color: scheme.onSurface,
        ),
        titleLarge: TextStyle(
          fontSize: 19,
          height: 1.3,
          fontWeight: FontWeight.w700,
          color: scheme.onSurface,
        ),
        titleMedium: TextStyle(
          fontSize: 16,
          height: 1.35,
          fontWeight: FontWeight.w700,
          color: scheme.onSurface,
        ),
        titleSmall: TextStyle(
          fontSize: 14,
          height: 1.35,
          fontWeight: FontWeight.w600,
          color: scheme.onSurface,
        ),
        bodyLarge: TextStyle(
          fontSize: 16,
          height: 1.45,
          color: scheme.onSurface,
        ),
        bodyMedium: TextStyle(
          fontSize: 14,
          height: 1.5,
          color: scheme.onSurface,
        ),
        bodySmall: TextStyle(
          fontSize: 12,
          height: 1.5,
          color: scheme.onSurfaceVariant,
        ),
        labelLarge: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w700,
          color: scheme.onSurface,
        ),
        labelMedium: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: scheme.onSurface,
        ),
        labelSmall: TextStyle(
          fontSize: 11,
          height: 1.3,
          color: scheme.onSurfaceVariant,
        ),
      );
  return base.copyWith(
    scaffoldBackgroundColor: dark ? RoadColors.ink : RoadColors.panel,
    textTheme: text,
    appBarTheme: AppBarThemeData(
      backgroundColor: dark ? RoadColors.ink : Colors.white,
      foregroundColor: scheme.onSurface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: text.titleLarge,
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: dark ? RoadColors.darkSurface : Colors.white,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: scheme.outlineVariant),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: dark ? RoadColors.darkSurface : Colors.white,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: text.headlineSmall,
      contentTextStyle: text.bodyMedium,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      modalBackgroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(27)),
      ),
      showDragHandle: false,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: RoadColors.blue,
        foregroundColor: Colors.white,
        minimumSize: const Size(48, 44),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        shape: const StadiumBorder(),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: dark ? RoadColors.sky : RoadColors.blueDeep,
        minimumSize: const Size(48, 44),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        side: BorderSide(color: dark ? RoadColors.sky : RoadColors.blue),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        shape: const StadiumBorder(),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: dark ? RoadColors.sky : RoadColors.blueDeep,
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: RoadColors.blue,
        foregroundColor: Colors.white,
        shape: const StadiumBorder(),
      ),
    ),
    inputDecorationTheme: InputDecorationThemeData(
      filled: true,
      fillColor: dark ? RoadColors.darkRaised : Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 13, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(13),
        borderSide: const BorderSide(color: RoadColors.fieldBorder),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(13),
        borderSide: const BorderSide(color: RoadColors.fieldBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(13),
        borderSide: const BorderSide(color: RoadColors.blue, width: 1.6),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      height: 69,
      elevation: 0,
      backgroundColor: Colors.white,
      indicatorColor: Colors.transparent,
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          color: states.contains(WidgetState.selected)
              ? RoadColors.blueNav
              : RoadColors.navIdle,
          size: 23,
        ),
      ),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          fontSize: 11,
          fontWeight: states.contains(WidgetState.selected)
              ? FontWeight.w600
              : FontWeight.w500,
          color: states.contains(WidgetState.selected)
              ? RoadColors.blueNav
              : RoadColors.navIdle,
        ),
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (states) =>
            states.contains(WidgetState.selected) ? Colors.white : Colors.white,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? RoadColors.blueBright
            : RoadColors.toggleTrack,
      ),
      trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
    ),
    chipTheme: base.chipTheme.copyWith(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      side: BorderSide.none,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    dividerTheme: DividerThemeData(
      color: dark ? scheme.outlineVariant : RoadColors.settingDivider,
      thickness: 1,
    ),
  );
}
