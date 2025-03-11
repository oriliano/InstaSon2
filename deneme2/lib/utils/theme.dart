import 'package:flutter/material.dart';

class AppTheme {
  // Renk paleti
  static const Color primaryColor = Color(0xFF405DE6); // Instagram mavisi
  static const Color accentColor = Color(0xFFE1306C); // Instagram pembe/kırmızı
  static const Color backgroundColor = Colors.white;
  static const Color secondaryBackgroundColor = Color(0xFFF8F8F8);
  static const Color textColor = Color(0xFF262626);
  static const Color secondaryTextColor = Color(0xFF8E8E8E);
  static const Color borderColor = Color(0xFFDBDBDB);
  static const Color errorColor = Color(0xFFED4956);
  static const Color successColor = Color(0xFF58C322);

  // Gradyan renkler (Instagram logosu için)
  static const List<Color> gradientColors = [
    Color(0xFF405DE6), // Mavi
    Color(0xFF5851DB), // Mor
    Color(0xFF833AB4), // Mor
    Color(0xFFC13584), // Pembe
    Color(0xFFE1306C), // Kırmızı
    Color(0xFFFD1D1D), // Kırmızı
    Color(0xFFF56040), // Turuncu
    Color(0xFFF77737), // Turuncu
    Color(0xFFFCAF45), // Sarı
    Color(0xFFFFDC80), // Sarı
  ];

  // Metin stilleri
  static const TextStyle headingStyle = TextStyle(
    fontSize: 24,
    fontWeight: FontWeight.bold,
    color: textColor,
  );

  static const TextStyle subheadingStyle = TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.w600,
    color: textColor,
  );

  static const TextStyle bodyStyle = TextStyle(
    fontSize: 14,
    color: textColor,
  );

  static const TextStyle captionStyle = TextStyle(
    fontSize: 12,
    color: secondaryTextColor,
  );

  // Buton stilleri
  static final ButtonStyle primaryButtonStyle = ElevatedButton.styleFrom(
    backgroundColor: primaryColor,
    foregroundColor: Colors.white,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(8),
    ),
    padding: const EdgeInsets.symmetric(vertical: 12),
  );

  static final ButtonStyle secondaryButtonStyle = OutlinedButton.styleFrom(
    foregroundColor: primaryColor,
    side: const BorderSide(color: primaryColor),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(8),
    ),
    padding: const EdgeInsets.symmetric(vertical: 12),
  );

  // Input dekorasyon
  static InputDecoration inputDecoration(String label, {String? hintText}) {
    return InputDecoration(
      labelText: label,
      hintText: hintText,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: borderColor),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: borderColor),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: primaryColor, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: errorColor),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    );
  }

  // Ana tema
  static ThemeData get lightTheme {
    return ThemeData(
      primaryColor: const Color(0xFF800000), // Bordo
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF800000),
        secondary: const Color(0xFF0000CD), // Mavi
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.white,
        foregroundColor: Color(0xFF800000),
        elevation: 0,
        centerTitle: true,
      ),
      scaffoldBackgroundColor: Colors.white,
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF800000),
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: const Color(0xFF800000),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(
            color: Color(0xFF800000),
            width: 2,
          ),
        ),
      ),
    );
  }

  static ThemeData get darkTheme {
    return ThemeData.dark().copyWith(
      primaryColor: const Color(0xFF800000), // Bordo
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF800000),
        secondary: const Color(0xFF0000CD), // Mavi
        brightness: Brightness.dark,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFF121212),
        foregroundColor: Color(0xFF800000),
        elevation: 0,
        centerTitle: true,
      ),
      scaffoldBackgroundColor: const Color(0xFF121212),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF800000),
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: const Color(0xFF800000),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(
            color: Color(0xFF800000),
            width: 2,
          ),
        ),
      ),
    );
  }
}
