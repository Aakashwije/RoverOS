import 'package:flutter/material.dart';

import 'app_colors.dart';

/// 4pt spacing scale. Layouts compose from these instead of ad-hoc numbers.
abstract final class AppSpacing {
  static const double xxs = 2;
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;
  static const double xxxl = 32;
  static const double huge = 48;

  /// Minimum interactive size. Driving happens one-handed, often in motion, so
  /// ROVEROS targets are larger than the 48dp Material floor.
  static const double minTouchTarget = 56;

  static const EdgeInsets screenPadding = EdgeInsets.symmetric(horizontal: lg);
  static const EdgeInsets cardPadding = EdgeInsets.all(lg);
}

abstract final class AppRadii {
  static const double xs = 6;
  static const double sm = 10;
  static const double md = 14;
  static const double lg = 20;
  static const double xl = 28;
  static const double pill = 999;

  static const BorderRadius cardRadius = BorderRadius.all(Radius.circular(md));
  static const BorderRadius sheetRadius = BorderRadius.vertical(
    top: Radius.circular(xl),
  );
  static const BorderRadius pillRadius = BorderRadius.all(
    Radius.circular(pill),
  );
}

abstract final class AppShadows {
  /// Soft ambient lift for panels on the dark background.
  static const List<BoxShadow> card = [
    BoxShadow(color: Color(0x66000000), blurRadius: 16, offset: Offset(0, 6)),
  ];

  static const List<BoxShadow> raised = [
    BoxShadow(color: Color(0x80000000), blurRadius: 28, offset: Offset(0, 12)),
  ];

  /// Coloured bloom used sparingly for live/active controls.
  static List<BoxShadow> glow(
    Color color, {
    double blur = 24,
    double opacity = 0.35,
  }) => [
    BoxShadow(
      color: color.withValues(alpha: opacity),
      blurRadius: blur,
      spreadRadius: 1,
    ),
  ];

  static List<BoxShadow> get accentGlow => glow(AppColors.accent);
}

/// Animation timing. Keeping durations in one place stops the dashboard from
/// feeling like several apps stitched together.
abstract final class AppDurations {
  static const Duration instant = Duration(milliseconds: 90);
  static const Duration fast = Duration(milliseconds: 160);
  static const Duration normal = Duration(milliseconds: 260);
  static const Duration slow = Duration(milliseconds: 420);
  static const Duration deliberate = Duration(milliseconds: 650);

  /// Continuous loops.
  static const Duration pulse = Duration(milliseconds: 1600);
  static const Duration radarSweep = Duration(milliseconds: 2400);
  static const Duration splash = Duration(milliseconds: 1500);

  static const Curve emphasized = Curves.easeOutCubic;
  static const Curve standard = Curves.easeOutQuart;
  static const Curve spring = Curves.elasticOut;
}
