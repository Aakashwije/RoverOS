import 'package:flutter/material.dart';

import '../../../core/constants/app_config.dart';
import '../../../core/perception/proximity_gate.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/settings.dart';
import '../../../models/telemetry.dart';
import '../../../widgets/app_card.dart';

/// Front ultrasonic readout.
///
/// Proximity is communicated four ways at once — number, status word, icon and
/// a fill bar — so a driver glancing down gets the state without decoding a
/// colour.
///
/// The one state that breaks that pattern is *uncertain*: when the sensor is
/// contradicting itself (soft fabric, an angled wall — the surfaces an HC-SR04
/// cannot see), the number it is producing is not a worse estimate, it is no
/// estimate at all. So that state is structural rather than tonal — the value
/// drops out and the card goes quiet, because a confident-looking distance
/// built on disagreeing readings is the most dangerous thing this widget can
/// show.
class DistanceCard extends StatelessWidget {
  const DistanceCard({
    super.key,
    required this.distanceCm,
    required this.settings,
    this.isStale = false,
    this.compact = false,
    this.proximity,
  });

  final int? distanceCm;
  final AppSettings settings;
  final bool isStale;
  final bool compact;
  final ProximityAssessment? proximity;

  bool get _isUncertain => proximity?.cause == ProximityCause.lowConfidence;

  @override
  Widget build(BuildContext context) {
    final assessment = proximity;

    // Uncertain overrides everything below it: the filtered value exists but
    // is untrustworthy, so the card leads with that rather than with a number.
    if (_isUncertain && assessment != null) {
      return _buildUncertain(context, assessment);
    }

    final status =
        assessment?.status ??
        DistanceStatus.fromDistance(
          distanceCm,
          cautionCm: settings.cautionDistanceCm,
          dangerCm: settings.dangerDistanceCm,
        );
    final color = AppColors.forStatus(status.level);
    final filteredCm = assessment?.distanceCm;
    final display = filteredCm == null
        ? settings.units.format(distanceCm)
        : settings.units.format(filteredCm.round());
    final rawDisplay = settings.units.format(assessment?.rawCm ?? distanceCm);
    final confidence = assessment?.confidence;
    final ttcSeconds = assessment?.contactSeconds;

    return AppCard(
      accent: status.level == StatusLevel.neutral ? null : color,
      borderColor: status == DistanceStatus.danger
          ? AppColors.danger.withValues(alpha: 0.5)
          : null,
      padding: EdgeInsets.all(compact ? AppSpacing.md : AppSpacing.lg),
      semanticLabel:
          'Front distance $display ${settings.units.shortLabel}. '
          '${assessment?.headline ?? status.label}. '
          '${assessment?.detail ?? status.description}.'
          '${confidence == null ? "" : " Confidence ${confidence.label}."}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(Icons.straighten_rounded, size: 13, color: color),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  'FRONT DISTANCE',
                  style: AppTypography.label.copyWith(fontSize: 9.5),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              // A closing obstacle is the one thing that cannot wait for the
              // status line — time-to-contact goes up top, in the colour of the
              // severity it implies, so the glance path is number then TTC.
              if (ttcSeconds != null) ...[
                Icon(Icons.timer_outlined, size: 11, color: color),
                const SizedBox(width: 3),
                Text(
                  '${ttcSeconds}S',
                  style: AppTypography.labelStrong.copyWith(
                    color: color,
                    fontSize: 11,
                  ),
                ),
              ],
            ],
          ),
          SizedBox(height: compact ? AppSpacing.sm : AppSpacing.md),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                display,
                style: AppTypography.metricValue.copyWith(
                  fontSize: compact ? 26 : 32,
                  color: isStale
                      ? AppColors.textTertiary
                      : AppColors.textPrimary,
                ),
              ),
              const SizedBox(width: 4),
              Text(settings.units.shortLabel, style: AppTypography.metricUnit),
            ],
          ),
          if (assessment != null && !compact) ...[
            const SizedBox(height: 3),
            Text(
              'RAW $rawDisplay ${settings.units.shortLabel} · EST',
              style: AppTypography.label.copyWith(
                color: AppColors.textTertiary,
                fontSize: 9,
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          _ProximityBar(
            distanceCm: filteredCm?.round() ?? distanceCm,
            color: color,
            settings: settings,
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Icon(
                AppColors.iconForStatus(status.level),
                size: 12,
                color: color,
              ),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  status.label,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.label.copyWith(color: color),
                ),
              ),
            ],
          ),
          if (assessment != null) ...[
            const SizedBox(height: 4),
            Text(
              _assessmentLabel(assessment),
              maxLines: compact ? 1 : 2,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.textSecondary,
                fontSize: compact ? 10 : 11,
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// The sensor-is-being-defeated state. No number: the filtered value is a
  /// prediction with nothing trustworthy corroborating it, and showing it
  /// anyway is how a driver learns to trust a reading the app itself has
  /// already refused to stand behind.
  Widget _buildUncertain(BuildContext context, ProximityAssessment assessment) {
    const color = AppColors.caution;
    final rawDisplay = settings.units.format(assessment.rawCm ?? distanceCm);

    return AppCard(
      accent: color,
      borderColor: color.withValues(alpha: 0.4),
      padding: EdgeInsets.all(compact ? AppSpacing.md : AppSpacing.lg),
      semanticLabel:
          'Front distance unreliable. The sensor is giving conflicting '
          'readings, possibly off a soft or angled surface. Slow down.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Icon(Icons.blur_on_rounded, size: 13, color: color),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  'FRONT DISTANCE',
                  style: AppTypography.label.copyWith(fontSize: 9.5),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          SizedBox(height: compact ? AppSpacing.sm : AppSpacing.md),
          Text(
            'UNRELIABLE',
            style: AppTypography.metricValue.copyWith(
              fontSize: compact ? 18 : 22,
              color: color,
              letterSpacing: 1.2,
            ),
          ),
          if (!compact) ...[
            const SizedBox(height: 3),
            Text(
              'LAST RAW $rawDisplay ${settings.units.shortLabel}',
              style: AppTypography.label.copyWith(
                color: AppColors.textTertiary,
                fontSize: 9,
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          // The bar collapses to empty: no trustworthy distance, no fill.
          _ProximityBar(distanceCm: null, color: color, settings: settings),
          const SizedBox(height: AppSpacing.sm),
          Text(
            compact
                ? 'Conflicting readings — slow down'
                : 'Sensor is contradicting itself — a soft or angled surface '
                      'may be absorbing the echo. Slow down.',
            maxLines: compact ? 1 : 3,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.textSecondary,
              fontSize: compact ? 10 : 11,
            ),
          ),
        ],
      ),
    );
  }

  String _assessmentLabel(ProximityAssessment assessment) {
    final confidence = assessment.confidence.label;
    // TTC is already up top; the detail line carries the closing rate here.
    if (assessment.isClosing) {
      return 'CLOSING ${assessment.closingSpeedCmPerSecond.round()}cm/s · CONF $confidence';
    }
    return 'CONF $confidence · ${assessment.detail}';
  }
}

/// Fill bar scaled so the caution band occupies a useful part of the track,
/// rather than compressing everything below 60 cm into a sliver.
class _ProximityBar extends StatelessWidget {
  const _ProximityBar({
    required this.distanceCm,
    required this.color,
    required this.settings,
  });

  final int? distanceCm;
  final Color color;
  final AppSettings settings;

  @override
  Widget build(BuildContext context) {
    final fullScale = (settings.cautionDistanceCm * 2)
        .clamp(60, AppConfig.sensorMaxRangeCm)
        .toDouble();
    final fraction = distanceCm == null
        ? 0.0
        : (distanceCm! / fullScale).clamp(0.0, 1.0);

    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadii.xs),
      child: Container(
        height: 6,
        color: AppColors.surfaceSunken,
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: fraction),
          duration: AppDurations.fast,
          builder: (context, value, _) => FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: value,
            child: ColoredBox(color: color),
          ),
        ),
      ),
    );
  }
}
