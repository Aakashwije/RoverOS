import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Type scale for the dashboard.
///
/// Numeric readouts use tabular figures so animated values do not shift width
/// digit-to-digit — the difference between a cheap-feeling counter and an
/// instrument cluster.
abstract final class AppTypography {
  static const List<FontFeature> _tabular = [FontFeature.tabularFigures()];

  /// Hero telemetry number (speed, battery on the drive HUD).
  static const TextStyle displayValue = TextStyle(
    fontSize: 52,
    fontWeight: FontWeight.w700,
    height: 1.0,
    letterSpacing: -2,
    fontFeatures: _tabular,
    color: AppColors.textPrimary,
  );

  /// Card-sized telemetry number.
  static const TextStyle metricValue = TextStyle(
    fontSize: 30,
    fontWeight: FontWeight.w700,
    height: 1.05,
    letterSpacing: -0.8,
    fontFeatures: _tabular,
    color: AppColors.textPrimary,
  );

  static const TextStyle metricUnit = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.2,
    color: AppColors.textSecondary,
  );

  static const TextStyle titleLarge = TextStyle(
    fontSize: 26,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.4,
    color: AppColors.textPrimary,
  );

  static const TextStyle titleMedium = TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.2,
    color: AppColors.textPrimary,
  );

  static const TextStyle body = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w500,
    height: 1.4,
    color: AppColors.textSecondary,
  );

  static const TextStyle bodySmall = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w500,
    height: 1.35,
    color: AppColors.textSecondary,
  );

  /// All-caps instrument label — the visual signature of the panel styling.
  static const TextStyle label = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w700,
    letterSpacing: 1.4,
    color: AppColors.textTertiary,
  );

  static const TextStyle labelStrong = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w800,
    letterSpacing: 1.2,
    color: AppColors.textPrimary,
  );

  static const TextStyle button = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w800,
    letterSpacing: 0.8,
    color: AppColors.textPrimary,
  );

  /// The ROVEROS wordmark.
  static const TextStyle wordmark = TextStyle(
    fontSize: 34,
    fontWeight: FontWeight.w900,
    letterSpacing: 6,
    color: AppColors.textPrimary,
  );

  static const TextStyle wordmarkSub = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w600,
    letterSpacing: 4.5,
    color: AppColors.textTertiary,
  );

  static TextTheme get textTheme => const TextTheme(
    displayLarge: displayValue,
    headlineMedium: titleLarge,
    titleLarge: titleMedium,
    titleMedium: labelStrong,
    bodyLarge: body,
    bodyMedium: bodySmall,
    labelLarge: button,
    labelMedium: label,
    labelSmall: label,
  );
}
