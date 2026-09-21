import 'package:flutter/material.dart';
import 'package:pre_ape/core/constants/app_colors.dart';
import 'package:pre_ape/core/constants/app_text_styles.dart';

class AppTheme {
  static ThemeData get darkTheme => ThemeData(
    brightness: Brightness.dark,
    scaffoldBackgroundColor: AppColors.background,
    primaryColor: AppColors.primary,
    primaryColorDark: AppColors.primaryDark,
    cardColor: AppColors.surface,
    dividerColor: AppColors.border,
    
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleTextStyle: AppTextStyles.headlineMedium,
      iconTheme: IconThemeData(color: AppColors.textPrimary),
    ),
    
    cardTheme: const CardThemeData(
      color: AppColors.surface,
      elevation: 0,
      shape: ContinuousRectangleBorder(
        side: BorderSide(color: AppColors.border, width: 1),
      ),
    ),
    
    inputDecorationTheme: const InputDecorationTheme(
      border: UnderlineInputBorder(
        side: BorderSide(color: AppColors.border, width: 1),
      ),
      focusedBorder: UnderlineInputBorder(
        side: BorderSide(color: AppColors.primary, width: 2),
      ),
      labelStyle: AppTextStyles.labelLarge,
      hintStyle: AppTextStyles.bodyMedium,
    ),
    
    sliderTheme: SliderThemeData(
      trackShape: const RoundedRectSliderTrackShape(),
      trackHeight: 6,
      activeTrackColor: AppColors.primary,
      inactiveTrackColor: AppColors.border,
      thumbColor: AppColors.primary,
      thumbShape: const RoundSliderThumbShape(
        enabledThumbRadius: 10,
        elevation: 4,
        shadowColor: AppColors.primaryGlow,
      ),
      overlayColor: AppColors.primaryGlow.withValues(alpha: 0.2),
      valueIndicatorColor: AppColors.primary,
      valueIndicatorTextStyle: const TextStyle(color: Colors.white, fontSize: 14),
    ),
    
    iconTheme: const IconThemeData(color: AppColors.textSecondary, size: 24),
    useMaterial3: true,
  );
}

extension BuildContextX on BuildContext {
  // Convenience accessors
  Color get bg => AppColors.background;
  Color get surface => AppColors.surface;
  Color get primary => AppColors.primary;
  Color get text => AppColors.textPrimary;
  Color get textSecondary => AppColors.textSecondary;
  Color get border => AppColors.border;
}