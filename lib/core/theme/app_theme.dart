import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_colors.dart';
import 'app_spacing.dart';
import 'app_typography.dart';

export 'app_colors.dart';
export 'app_spacing.dart';
export 'app_typography.dart';

/// Material 3 theme wired to the ROVEROS palette.
///
/// ROVEROS is dark-only by design: the dashboard is built for a phone mounted
/// in front of a moving vehicle, where a light theme would be a glare hazard.
abstract final class AppTheme {
  static ThemeData get dark {
    final colorScheme =
        ColorScheme.fromSeed(
          seedColor: AppColors.accent,
          brightness: Brightness.dark,
        ).copyWith(
          surface: AppColors.background,
          onSurface: AppColors.textPrimary,
          primary: AppColors.accent,
          onPrimary: AppColors.textOnAccent,
          secondary: AppColors.accentDim,
          error: AppColors.danger,
          onError: Colors.white,
          outline: AppColors.border,
          outlineVariant: AppColors.borderStrong,
        );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: AppColors.background,
      canvasColor: AppColors.background,
      textTheme: AppTypography.textTheme,
      splashFactory: InkSparkle.splashFactory,
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: AppTypography.titleMedium,
        iconTheme: IconThemeData(color: AppColors.textPrimary),
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.light,
          statusBarBrightness: Brightness.dark,
        ),
      ),
      cardTheme: const CardThemeData(
        color: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: AppRadii.cardRadius),
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.border,
        thickness: 1,
        space: 1,
      ),
      iconTheme: const IconThemeData(color: AppColors.textSecondary, size: 22),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.surfaceOverlay,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: AppRadii.sheetRadius),
        showDragHandle: false,
      ),
      dialogTheme: const DialogThemeData(
        backgroundColor: AppColors.surfaceOverlay,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(AppRadii.lg)),
        ),
        titleTextStyle: AppTypography.titleMedium,
        contentTextStyle: AppTypography.body,
      ),
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: AppColors.surfaceOverlay,
        contentTextStyle: TextStyle(color: AppColors.textPrimary, fontSize: 14),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: AppRadii.cardRadius),
      ),
      sliderTheme: const SliderThemeData(
        activeTrackColor: AppColors.accent,
        inactiveTrackColor: AppColors.surfaceSunken,
        thumbColor: AppColors.accent,
        overlayColor: AppColors.accentGlow,
        trackHeight: 6,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? AppColors.textOnAccent
              : AppColors.textTertiary,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? AppColors.accent
              : AppColors.surfaceSunken,
        ),
        trackOutlineColor: const WidgetStatePropertyAll(AppColors.border),
      ),
      tooltipTheme: const TooltipThemeData(
        decoration: BoxDecoration(
          color: AppColors.surfaceOverlay,
          borderRadius: BorderRadius.all(Radius.circular(AppRadii.sm)),
        ),
        textStyle: TextStyle(color: AppColors.textPrimary, fontSize: 12),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        },
      ),
    );
  }
}
