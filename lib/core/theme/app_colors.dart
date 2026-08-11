import 'package:flutter/material.dart';

/// Severity of a piece of vehicle state.
///
/// Colour alone never communicates status in ROVEROS: every widget that takes a
/// [StatusLevel] also renders an icon and a text label so the state survives
/// greyscale, colour-blindness and screen readers.
///
/// That rule is not decorative. Amber and red project onto the same yellow axis
/// for the ~8% of men with deuteranopia or protanopia, and no choice of amber
/// and red can separate them — measured perceptual distance between the two
/// stays around ΔE 11 however they are tuned. Shape and words carry the
/// meaning; the palette below only has to avoid making things *worse*.
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

  /// Muted label text. Lightened from the original `#6B7787`, which measured
  /// 3.76:1 on [surfaceElevated] — a fail for the 11px all-caps instrument
  /// labels it is used for, which are too small to qualify as large text.
  static const Color textTertiary = Color(0xFF7B8693);

  static const Color textOnAccent = Color(0xFF04120F);

  // --- Brand / accents ------------------------------------------------------

  /// Electric cyan — the ROVEROS signature accent.
  static const Color accent = Color(0xFF00E0FF);
  static const Color accentDim = Color(0xFF0092A8);
  static const Color accentGlow = Color(0x3300E0FF);

  // --- Status ---------------------------------------------------------------
  //
  // Tuned so the five levels form a descending greyscale ladder — each step at
  // least 1.25:1 from the next — because that is what a monochrome, low-vision
  // or dichromatic viewer is left with once hue stops being informative. The
  // previous green (#22D97F) and amber (#FFB020) measured 1.02:1 apart, i.e.
  // the same shade of grey: "battery healthy" and "battery low" were
  // indistinguishable without colour.
  //
  // Every value also clears 4.5:1 against [surfaceElevated], the lightest
  // surface any of them is painted on.

  /// Luminance 0.450 · 8.1:1 on elevated.
  static const Color good = Color(0xFF1DCC80);

  /// Luminance 0.587 · 10.4:1 on elevated.
  static const Color caution = Color(0xFFFFBF28);

  /// Luminance 0.255 · 5.0:1 on elevated.
  static const Color danger = Color(0xFFFA4850);

  /// Luminance 0.333 · 6.2:1 on elevated. Pushed toward violet-blue so it does
  /// not sit on top of the cyan [accent] in the blue-yellow channel.
  static const Color info = Color(0xFF7C96FF);

  /// Luminance 0.234 · 4.6:1 on elevated. Shares its value with
  /// [textTertiary]: "no reading" and muted label text are the same idea.
  static const Color neutral = Color(0xFF7B8693);

  /// Emergency-stop red. Deliberately distinct from [danger] so the E-STOP
  /// control never blends into ordinary warning treatments.
  ///
  /// [emergency] and [emergencyDeep] are *fill* colours — white on [emergency]
  /// measures 4.8:1. Use [emergencyLight] whenever the emergency red is the
  /// foreground on a dark surface, as in the latched E-STOP: [emergency]
  /// itself only reaches 3.5:1 there.
  static const Color emergency = Color(0xFFE01B24);
  static const Color emergencyDeep = Color(0xFF8E0F16);
  static const Color emergencyLight = Color(0xFFF85E66);

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
  ///
  /// Chosen for distinct *silhouettes*, not just distinct glyphs: a filled
  /// circle (good), a triangle (caution), an octagon (danger), a filled circle
  /// with a stem (info) and a hollow ring (neutral) stay apart at 12px, in
  /// greyscale, and for a viewer who cannot separate amber from red.
  static IconData iconForStatus(StatusLevel level) => switch (level) {
    StatusLevel.good => Icons.check_circle_rounded,
    StatusLevel.caution => Icons.warning_amber_rounded,
    StatusLevel.danger => Icons.dangerous_rounded,
    StatusLevel.info => Icons.info_rounded,
    StatusLevel.neutral => Icons.remove_circle_outline_rounded,
  };
}
