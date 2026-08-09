import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../models/vehicle.dart';
import '../../../widgets/app_card.dart';

/// Recent-activity list for Home.
///
/// Shows a short, readable history so the user can tell what the app and
/// vehicle have been doing — particularly useful after a dropout.
class ActivityFeed extends StatelessWidget {
  const ActivityFeed({super.key, required this.entries, this.maxEntries = 4});

  final List<ActivityEntry> entries;
  final int maxEntries;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return AppCard(
        child: Row(
          children: [
            const Icon(
              Icons.history_rounded,
              size: 18,
              color: AppColors.textTertiary,
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text(
                'No activity yet. Connect a vehicle to start the log.',
                style: AppTypography.bodySmall,
              ),
            ),
          ],
        ),
      );
    }

    final visible = entries.take(maxEntries).toList();

    return AppCard(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Column(
        children: [
          for (var i = 0; i < visible.length; i++) ...[
            _ActivityRow(entry: visible[i]),
            if (i < visible.length - 1)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                child: Divider(),
              ),
          ],
        ],
      ),
    );
  }
}

class _ActivityRow extends StatelessWidget {
  const _ActivityRow({required this.entry});

  final ActivityEntry entry;

  ({IconData icon, StatusLevel level}) get _visuals => switch (entry.severity) {
    ActivitySeverity.success => (
      icon: Icons.check_circle_rounded,
      level: StatusLevel.good,
    ),
    ActivitySeverity.warning => (
      icon: Icons.warning_amber_rounded,
      level: StatusLevel.caution,
    ),
    ActivitySeverity.error => (
      icon: Icons.error_rounded,
      level: StatusLevel.danger,
    ),
    ActivitySeverity.info => (
      icon: Icons.bolt_rounded,
      level: StatusLevel.info,
    ),
  };

  @override
  Widget build(BuildContext context) {
    final visuals = _visuals;
    final color = AppColors.forStatus(visuals.level);

    return Semantics(
      label:
          '${entry.message}. ${entry.detail ?? ''} '
          '${formatRelativeTime(entry.timestamp)}',
      child: ExcludeSemantics(
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.md,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                height: 28,
                width: 28,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.13),
                  borderRadius: BorderRadius.circular(AppRadii.xs),
                ),
                child: Icon(visuals.icon, size: 15, color: color),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.message,
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (entry.detail != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        entry.detail!,
                        style: AppTypography.bodySmall.copyWith(fontSize: 12),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                formatRelativeTime(entry.timestamp),
                style: AppTypography.label.copyWith(fontSize: 10),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
