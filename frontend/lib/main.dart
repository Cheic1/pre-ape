import 'package:flutter/material.dart';
import 'package:pre_ape/core/theme/app_theme.dart';
import 'package:pre_ape/core/constants/app_colors.dart';
import 'package:pre_ape/core/routing/app_router.dart';

void main() {
  runApp(const PreAPEApp());
}

class PreAPEApp extends StatelessWidget {
  const PreAPEApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Pre-APE',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      home: const OnboardingPage(),
      onGenerateRoute: AppRouter.onGenerateRoute,
    );
  }
}