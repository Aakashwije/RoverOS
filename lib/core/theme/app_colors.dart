import 'package:flutter/material.dart';

/// Severity of a piece of vehicle state.
///
/// Colour alone never communicates status in ROVEROS: every widget that takes a
/// [StatusLevel] also renders an icon and a text label so the state survives
/// greyscale, colour-blindness and screen readers.
enum StatusLevel {
  neutral,
  good,
  caution,
  danger,
  info;

  bool get isAlarming =>
      this == StatusLevel.caution || this == StatusLevel.danger;
}

/// Centralised palette for the dark automotive dashboard.
abstract final class AppColors {
  // --- Surfaces -------------------------------------------------------------

  /// App scaffold background — near-black with a cool cast.
  static const Color background = Color(0xFF06080B);

  /// Default panel colour.
  static const Color surface = Color(0xFF10141A);

  /// Panel raised above [surface] (nested cards, sheets, pressed states).
  static const Color surfaceElevated = Color(0xFF171C24);

  /// Highest elevation — modals, bottom sheets, menus.
  static const Color surfaceOverlay = Color(0xFF1E242E);

  /// Recessed wells: gauge tracks, slider tracks, inset readouts.
  static const Color surfaceSunken = Color(0xFF0A0D12);

  static const Color border = Color(0xFF242B36);
  static const Color borderStrong = Color(0xFF323B49);

  // --- Text -----------------------------------------------------------------

  static const Color textPrimary = Color(0xFFF2F5F8);
  static const Color textSecondary = Color(0xFF9AA6B4);
  static const Color textTertiary = Color(0xFF6B7787);
  static const Color textOnAccent = Color(0xFF04120F);

  // --- Brand / accents ------------------------------------------------------

  /// Electric cyan — the ROVEROS signature accent.
  static const Color accent = Color(0xFF00E0FF);
  static const Color accentDim = Color(0xFF0092A8);
  static const Color accentGlow = Color(0x3300E0FF);

  // --- Status ---------------------------------------------------------------

  static const Color good = Color(0xFF22D97F);
  static const Color caution = Color(0xFFFFB020);
  static const Color danger = Color(0xFFFF3B47);
  static const Color info = Color(0xFF4D8DFF);
  static const Color neutral = Color(0xFF6B7787);

  /// Emergency-stop red. Deliberately distinct from [danger] so the E-STOP
  /// control never blends into ordinary warning treatments.
  static const Color emergency = Color(0xFFE01B24);
  static const Color emergencyDeep = Color(0xFF8E0F16);

  /// Headlight beam colour used by the lighting UI.
  static const Color headlight = Color(0xFFFFF4D6);

  static Color forStatus(StatusLevel level) => switch (level) {
    StatusLevel.good => good,
    StatusLevel.caution => caution,
    StatusLevel.danger => danger,
    StatusLevel.info => info,
    StatusLevel.neutral => neutral,
  };

  /// Icon paired with each status so meaning survives without colour.
  static IconData iconForStatus(StatusLevel level) => switch (level) {
    StatusLevel.good => Icons.check_circle_rounded,
    StatusLevel.caution => Icons.warning_amber_rounded,
    StatusLevel.danger => Icons.error_rounded,
    StatusLevel.info => Icons.info_rounded,
    StatusLevel.neutral => Icons.remove_circle_outline_rounded,
  };
}
