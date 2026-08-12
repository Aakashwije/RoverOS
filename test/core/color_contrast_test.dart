import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:roveros/core/theme/app_colors.dart';
import 'package:roveros/core/theme/color_contrast.dart';

/// Accessibility guarantees for the palette.
///
/// These are regression tests, not aspirations: every threshold below was
/// failing at some point. `good` and `caution` once measured 1.02:1 apart in
/// luminance — the same shade of grey — so "battery healthy" and "battery low"
/// were indistinguishable to a monochrome or severely colour-blind viewer.
/// `textTertiary` sat at 3.76:1 on elevated surfaces, under the AA floor for
/// the 11px labels it is used for throughout the dashboard.
void main() {
  /// Every surface a foreground colour is painted on. Elevated is the
  /// lightest and therefore the worst case for a light-on-dark palette.
  const surfaces = <String, Color>{
    'background': AppColors.background,
    'surface': AppColors.surface,
    'surfaceElevated': AppColors.surfaceElevated,
    'surfaceSunken': AppColors.surfaceSunken,
  };

  const statusColours = <String, Color>{
    'good': AppColors.good,
    'caution': AppColors.caution,
    'danger': AppColors.danger,
    'info': AppColors.info,
    'neutral': AppColors.neutral,
  };

  group('contrast against every surface', () {
    for (final entry in statusColours.entries) {
      test('${entry.key} clears AA on all surfaces', () {
        for (final surface in surfaces.entries) {
          final ratio = ColorContrast.ratio(entry.value, surface.value);
          expect(
            ratio,
            greaterThanOrEqualTo(ColorContrast.aaText),
            reason:
                '${entry.key} on ${surface.key} is ${ratio.toStringAsFixed(2)}:1, '
                'below the ${ColorContrast.aaText}:1 floor for the status '
                'labels this colour is used for',
          );
        }
      });
    }

    for (final entry in <String, Color>{
      'textPrimary': AppColors.textPrimary,
      'textSecondary': AppColors.textSecondary,
      'textTertiary': AppColors.textTertiary,
      'accent': AppColors.accent,
    }.entries) {
      test('${entry.key} clears AA on all surfaces', () {
        for (final surface in surfaces.entries) {
          final ratio = ColorContrast.ratio(entry.value, surface.value);
          expect(
            ratio,
            greaterThanOrEqualTo(ColorContrast.aaText),
            reason:
                '${entry.key} on ${surface.key} is '
                '${ratio.toStringAsFixed(2)}:1',
          );
        }
      });
    }

    test('emergency red is legible in both of its roles', () {
      // As a fill, with white text on it.
      expect(
        ColorContrast.ratio(Colors.white, AppColors.emergency),
        greaterThanOrEqualTo(ColorContrast.aaLarge),
      );
      // As a foreground, which is what the latched E-STOP uses. The fill red
      // only manages 3.5:1 here, which is why emergencyLight exists.
      expect(
        ColorContrast.ratio(
          AppColors.emergencyLight,
          AppColors.surfaceElevated,
        ),
        greaterThanOrEqualTo(ColorContrast.aaText),
      );
    });
  });

  group('greyscale separation', () {
    /// Luminance-only contrast is what survives when hue stops being
    /// informative — monochrome displays, severe colour vision deficiency, and
    /// a phone screen washed out by direct sun on a driveway.
    const ladder = [
      ('caution', AppColors.caution),
      ('good', AppColors.good),
      ('info', AppColors.info),
      ('danger', AppColors.danger),
    ];

    test('the four signalling colours form a descending ladder', () {
      for (var i = 0; i < ladder.length - 1; i++) {
        final (upperName, upper) = ladder[i];
        final (lowerName, lower) = ladder[i + 1];
        expect(
          ColorContrast.relativeLuminance(upper),
          greaterThan(ColorContrast.relativeLuminance(lower)),
          reason: '$upperName should be lighter than $lowerName',
        );
      }
    });

    test('adjacent rungs are at least 1.2:1 apart', () {
      for (var i = 0; i < ladder.length - 1; i++) {
        final (upperName, upper) = ladder[i];
        final (lowerName, lower) = ladder[i + 1];
        final ratio = ColorContrast.ratio(upper, lower);
        expect(
          ratio,
          greaterThanOrEqualTo(1.2),
          reason:
              '$upperName and $lowerName are only '
              '${ratio.toStringAsFixed(2)}:1 apart in luminance — they read as '
              'the same shade without colour',
        );
      }
    });

    test(
      'caution and danger are far apart, being the safety-critical pair',
      () {
        // Amber and red collapse onto one another for red-green dichromats no
        // matter how they are chosen, so luminance is the only channel left to
        // separate them in. Shape and wording carry the rest.
        final ratio = ColorContrast.ratio(AppColors.caution, AppColors.danger);
        expect(ratio, greaterThanOrEqualTo(1.9));
      },
    );
  });

  group('shape carries meaning where colour cannot', () {
    test('every status level has a distinct icon', () {
      final icons = StatusLevel.values
          .map(AppColors.iconForStatus)
          .toList(growable: false);
      expect(icons.toSet().length, StatusLevel.values.length);
    });

    test('every status level has a distinct colour', () {
      final colours = StatusLevel.values
          .map(AppColors.forStatus)
          .toList(growable: false);
      expect(colours.toSet().length, StatusLevel.values.length);
    });
  });

  group('ColorContrast maths', () {
    test('matches the WCAG reference values', () {
      expect(
        ColorContrast.ratio(Colors.white, Colors.black),
        closeTo(21, 0.01),
      );
      expect(
        ColorContrast.ratio(Colors.white, Colors.white),
        closeTo(1, 0.001),
      );
      expect(ColorContrast.relativeLuminance(Colors.white), closeTo(1, 0.001));
      expect(ColorContrast.relativeLuminance(Colors.black), closeTo(0, 0.001));
    });

    test('is symmetric', () {
      expect(
        ColorContrast.ratio(AppColors.accent, AppColors.surface),
        closeTo(ColorContrast.ratio(AppColors.surface, AppColors.accent), 1e-9),
      );
    });
  });
}
