import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class TerraTheme {
  // Brand Palette
  static const Color primary = Color(0xff316342);
  static const Color olive900 = Color(0xff3D4A2A);
  static const Color olive600 = Color(0xff6B7A4C);
  static const Color olive100 = Color(0xffE8ECDE);
  static const Color gold500 = Color(0xffC9A227);
  static const Color gold200 = Color(0xffF0DFA0);
  static const Color cream50 = Color(0xffFAF8F2);
  static const Color charcoal800 = Color(0xff2B2B26);
  static const Color neutral500 = Color(0xff8A8A80);

  // Status Colors
  static const Color success = Color(0xff10B981);
  static const Color warning = Color(0xffF59E0B);
  static const Color error = Color(0xffC0392B);

  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      colorScheme: const ColorScheme.light(
        primary: primary,
        secondary: olive600,
        surface: cream50,
        error: error,
        onPrimary: Colors.white,
        onSecondary: Colors.white,
        onSurface: charcoal800,
      ),
      scaffoldBackgroundColor: cream50,
      textTheme: GoogleFonts.nunitoSansTextTheme().copyWith(
        displayLarge: GoogleFonts.nunitoSans(
          fontSize: 32,
          fontWeight: FontWeight.bold,
          color: charcoal800,
          letterSpacing: -0.02,
        ),
        headlineMedium: GoogleFonts.nunitoSans(
          fontSize: 24,
          fontWeight: FontWeight.w600,
          color: charcoal800,
        ),
        headlineSmall: GoogleFonts.nunitoSans(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: charcoal800,
        ),
        bodyLarge: GoogleFonts.nunitoSans(
          fontSize: 16,
          fontWeight: FontWeight.normal,
          color: charcoal800,
        ),
        bodyMedium: GoogleFonts.nunitoSans(
          fontSize: 14,
          fontWeight: FontWeight.normal,
          color: charcoal800,
        ),
        labelLarge: GoogleFonts.nunitoSans(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: charcoal800,
        ),
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: Color(0x1a3d4a2a)),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: gold500,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          textStyle: GoogleFonts.nunitoSans(
            fontWeight: FontWeight.bold,
            fontSize: 14,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: Color(0x1a3d4a2a)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: Color(0x1a3d4a2a)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: primary, width: 2),
        ),
        labelStyle: const TextStyle(color: neutral500),
      ),
    );
  }
}
