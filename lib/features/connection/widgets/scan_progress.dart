import 'package:flutter/material.dart';

import '../../../core/constants/app_config.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';

/// Determinate progress for a running scan.
///
/// A bare spinner cannot distinguish "still looking" from "wedged". Scans here
/// have a known deadline, so the honest thing is to show it: the user learns
/// how long to keep the rover still, and knows exactly when it is fair to
/// conclude nothing is there.
class ScanProgress extends StatelessWidget {
  const ScanProgress({
    super.key,
    required this.endsAt,
    required this.deviceCount,
  });

  final DateTime? endsAt;
  final int deviceCount;

  @override
  Widget build(BuildContext context) {
    final total = AppConfig.scanTimeout.inSeconds;
    final left = endsAt == null ? total : secondsRemaining(endsAt);
    final elapsed = (total - left).clamp(0, total);
    final progress = total == 0 ? 0.0 : elapsed / total;

    return Semantics(
      liveRegion: true,
      label: deviceCount == 0
          ? 'Scanning. $left seconds remaining. No devices found yet.'
          : 'Scanning. $left seconds remaining. '
                '$deviceCount device${deviceCount == 1 ? '' : 's'} found.',
      child: ExcludeSemantics(
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: AppRadii.cardRadius,
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.radar_rounded,
                    size: 15,
                    color: AppColors.accent,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      deviceCount == 0
                          ? 'Listening for vehicles'
                          : '$deviceCount device'
                                '${deviceCount == 1 ? '' : 's'} so far',
                      style: AppTypography.label.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                  Text(
                    '${left}s',
                    style: AppTypography.labelStrong.copyWith(
                      color: AppColors.accent,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              ClipRRect(
                borderRadius: BorderRadius.circular(AppRadii.pill),
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: progress, end: progress),
                  duration: AppDurations.normal,
                  builder: (context, value, _) => LinearProgressIndicator(
                    value: value.clamp(0.0, 1.0),
                    minHeight: 3,
                    backgroundColor: AppColors.surfaceSunken,
                    valueColor: const AlwaysStoppedAnimation(AppColors.accent),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
