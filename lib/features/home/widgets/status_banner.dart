import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../home_status.dart';

/// One-line answer to "can I drive right now?", or a full warning panel when
/// the answer is no.
///
/// Deliberately states the reason, not just the state — a driver glancing at
/// the phone should not have to infer why the car will not move.
class StatusBanner extends StatelessWidget {
  const StatusBanner({super.key, required this.status});

  final HomeStatus status;

  @override
  Widget build(BuildContext context) {
    final color = AppColors.forStatus(status.level);
    final isBlocking = status.isBlocking;

    return Semantics(
      liveRegion: true,
      label: '${status.title}. ${status.detail}',
      child: ExcludeSemantics(
        child: AnimatedContainer(
          duration: AppDurations.normal,
          curve: AppDurations.standard,
          width: double.infinity,
          padding: EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: isBlocking ? AppSpacing.lg : AppSpacing.md,
          ),
          decoration: BoxDecoration(
            color: color.withValues(alpha: isBlocking ? 0.14 : 0.10),
            borderRadius: AppRadii.cardRadius,
            border: Border.all(
              color: color.withValues(alpha: isBlocking ? 0.55 : 0.35),
              width: isBlocking ? 1.5 : 1,
            ),
            // The glow is what makes a fault findable in peripheral vision.
            // Calm states get none, so it never becomes background noise.
            boxShadow: isBlocking
                ? AppShadows.glow(color, blur: 22, opacity: 0.18)
                : null,
          ),
          child: Row(
            crossAxisAlignment: isBlocking
                ? CrossAxisAlignment.start
                : CrossAxisAlignment.center,
            children: [
              Container(
                height: isBlocking ? 38 : 24,
                width: isBlocking ? 38 : 24,
                alignment: Alignment.center,
                decoration: isBlocking
                    ? BoxDecoration(
                        color: color.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(AppRadii.sm),
                      )
                    : null,
                child: Icon(status.icon, size: isBlocking ? 22 : 20, color: color),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      status.title,
                      style: isBlocking
                          ? AppTypography.titleMedium.copyWith(
                              fontSize: 16,
                              color: color,
                            )
                          : AppTypography.labelStrong.copyWith(color: color),
                    ),
                    SizedBox(height: isBlocking ? 4 : 2),
                    Text(
                      status.detail,
                      style: AppTypography.bodySmall.copyWith(
                        fontSize: isBlocking ? 13 : 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
