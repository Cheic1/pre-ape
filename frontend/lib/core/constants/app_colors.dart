import 'package:flutter/material.dart';

class AppColors {
  // Dark theme palette
  static const Color background = Color(0xFF0D1117);
  static const Color surface = Color(0xFF161B22);
  static const Color surfaceElevated = Color(0xFF1C2128);
  static const Color border = Color(0xFF30363D);
  
  // Emerald / Mint accents
  static const Color primary = Color(0xFF10B981);       // Emerald 500
  static const Color primaryDark = Color(0xFF059669);    // Emerald 600
  static const Color primaryGlow = Color(0xFF34D399);     // Emerald 400
  static const Color accent = Color(0xFF2DD4BF);          // Mint 400
  
  // Text
  static const Color textPrimary = Color(0xFFF0F6FC);
  static const Color textSecondary = Color(0xFF8B949E);
  static const Color textMuted = Color(0xFF6E7681);
  
  // Status
  static const Color success = Color(0xFF22C55E);
  static const Color warning = Color(0xFFF59E0B);
  static const Color error = Color(0xFFEF4444);
  
  // Gradients
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [Color(0xFF059669), Color(0xFF10B981)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
  
  static const LinearGradient surfaceGradient = LinearGradient(
    colors: [Color(0xFF161B22), Color(0xFF0D1117)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}