import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// IRIS Theme — Rainbow/Spectrum identity
class BitpayTheme {
  // ── Backgrounds ─────────────────────────────────────────────
  static const Color bg  = Color(0xFF06080F);
  static const Color s1  = Color(0xFF0C0E1A);
  static const Color s2  = Color(0xFF111426);
  static const Color s3  = Color(0xFF171B32);

  // ── Rainbow spectrum stops ───────────────────────────────────
  static const Color red    = Color(0xFFFF3B5C);
  static const Color orange = Color(0xFFFF7A2F);
  static const Color yellow = Color(0xFFFFD60A);
  static const Color green  = Color(0xFF00E676);
  static const Color cyan   = Color(0xFF00CFFF);
  static const Color blue   = Color(0xFF2979FF);
  static const Color violet = Color(0xFFAA00FF);

  // ── Primary — violet-to-cyan gradient start/end ──────────────
  static const Color primary      = Color(0xFF7C3AFF); // vibrant violet
  static const Color primaryLight = Color(0xFFBB86FC);
  static const Color primaryDark  = Color(0x307C3AFF);

  // ── Accent (second brand color — electric cyan) ──────────────
  static const Color accent      = Color(0xFF00CFFF);
  static const Color accentDark  = Color(0x3000CFFF);

  // ── Semantic ─────────────────────────────────────────────────
  static const Color success = Color(0xFF00E676);
  static const Color danger  = Color(0xFFFF3B5C);
  static const Color warning = Color(0xFFFFD60A);

  // ── Text ─────────────────────────────────────────────────────
  static const Color textPrimary   = Color(0xFFF0F4FF);
  static const Color textSecondary = Color(0xFF8094C8);
  static const Color textTertiary  = Color(0xFF3D4F7A);

  // ── Borders ──────────────────────────────────────────────────
  static const Color bdr  = Color(0x14FFFFFF);
  static const Color bdr2 = Color(0x28FFFFFF);

  // ── Full spectrum gradient (horizontal rainbow) ───────────────
  static const LinearGradient rainbowGradient = LinearGradient(
    colors: [red, orange, yellow, green, cyan, blue, violet],
    stops: [0.0, 0.17, 0.33, 0.50, 0.67, 0.83, 1.0],
  );

  // ── Primary brand gradient (violet → cyan) ───────────────────
  static const LinearGradient brandGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [violet, primary, accent],
    stops: [0.0, 0.5, 1.0],
  );

  // ── Card/surface shimmer gradient ───────────────────────────
  static const LinearGradient surfaceGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF111426), Color(0xFF0C0E1A)],
  );

  static ThemeData get darkTheme {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: bg,
      primaryColor: primary,
      colorScheme: const ColorScheme.dark(
        primary: primary,
        secondary: accent,
        tertiary: green,
        surface: s1,
        background: bg,
        error: danger,
      ),
      textTheme: GoogleFonts.outfitTextTheme(ThemeData.dark().textTheme).copyWith(
        displayLarge: GoogleFonts.outfit(
          color: textPrimary, fontWeight: FontWeight.w800,
          fontSize: 34, letterSpacing: -0.5,
        ),
        displayMedium: GoogleFonts.outfit(
          color: textPrimary, fontWeight: FontWeight.w700, fontSize: 24,
        ),
        bodyLarge: GoogleFonts.outfit(color: textPrimary, fontSize: 16),
        bodyMedium: GoogleFonts.outfit(color: textSecondary, fontSize: 13),
        labelSmall: GoogleFonts.jetBrainsMono(color: textSecondary, fontSize: 11),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          padding: const EdgeInsets.symmetric(vertical: 16),
          textStyle: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.w700),
          elevation: 0,
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: MaterialStateProperty.resolveWith((s) =>
            s.contains(MaterialState.selected) ? accent : textTertiary),
        trackColor: MaterialStateProperty.resolveWith((s) =>
            s.contains(MaterialState.selected) ? accentDark : s2),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: bg,
        elevation: 0,
        centerTitle: false,
      ),
    );
  }
}
