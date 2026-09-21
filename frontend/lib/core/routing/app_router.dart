import 'package:flutter/material.dart';

class AppRouter {
  static const String home = '/';
  static const String onboarding = '/onboarding';
  static const String camera = '/camera';
  static const String results = '/results';

  static Route<dynamic> onGenerateRoute(RouteSettings settings) {
    switch (settings.name) {
      case '/':
        return _fadeRoute(const OnboardingPage(), settings);
      default:
        return _fadeRoute(const OnboardingPage(), settings);
    }
  }

  static PageRoute<T> _fadeRoute<T>(Widget page, RouteSettings settings) {
    return PageRouteBuilder<T>(
      settings: settings,
      pageBuilder: (context, animation, secondaryAnimation) => page,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        return FadeTransition(
          opacity: CurvedAnimation(
            parent: animation,
            curve: Curves.easeInOut,
          ),
          child: child,
        );
      },
    );
  }
}