import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../models/commands.dart';
import '../../../models/telemetry.dart';
import '../auto_behaviour.dart';

/// The vehicle's current decision, at the size it deserves.
///
/// Autonomous mode is the one screen where the interesting information is not
/// a number — it is a sentence the firmware just produced, and it changes every
/// couple of seconds. Buried in a row of cards it was unreadable at a glance;
/// this is the whole point of the screen, so it gets the top of it.
class DecisionReadout extends StatelessWidget {
  const DecisionReadout({
    super.key,
    required this.telemetry,
    required this.behaviour,
    required this.vehicleState,
  });

  final Telemetry telemetry;
  final AutoBehaviour behaviour;
  final VehicleState vehicleState;

  bool get _isActive => behaviour != AutoBehaviour.manual;

  StatusLevel get _level => switch (vehicleState) {
    VehicleState.fault => StatusLevel.danger,
    VehicleState.avoiding || VehicleState.scanning => StatusLevel.info,
    VehicleState.driving => StatusLevel.good,
    _ => StatusLevel.neutral,
  };

  /// Prefers the firmware's own words. Falls back to the vehicle state, then
  /// to an honest "nothing yet" — never to an invented decision.
  String get _headline {
    if (!_isActive) return 'STANDING BY';
    final decision = telemetry.decision;
    if (decision != null && decision.trim().isNotEmpty) {
      return decision.toUpperCase();
    }
    return vehicleState.label;
  }

  String get _detail {
    if (!_isActive) {
      return 'Choose a behaviour above to hand control to the vehicle.';
    }
    if (telemetry.decision == null) {
      return 'Waiting for the vehicle to report its first decision…';
    }
    return 'Reported by the vehicle · ${vehicleState.label}';
  }

  @override
  Widget build(BuildContext context) {
    final color = AppColors.forStatus(_level);

    return Semantics(
      liveRegion: true,
      label: 'Current decision. $_headline. $_detail',
      child: ExcludeSemantics(
        child: AnimatedContainer(
          duration: AppDurations.normal,
          curve: AppDurations.standard,
          width: double.infinity,
          padding: const EdgeInsets.all(AppSpacing.xl),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                color.withValues(alpha: _isActive ? 0.16 : 0.06),
                AppColors.surface,
              ],
            ),
            borderRadius: AppRadii.cardRadius,
            border: Border.all(
              color: color.withValues(alpha: _isActive ? 0.5 : 0.25),
            ),
            boxShadow: _isActive
                ? AppShadows.glow(color, blur: 26, opacity: 0.16)
                : AppShadows.card,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(
                    _isActive ? Icons.psychology_rounded : behaviour.icon,
                    size: 15,
                    color: color,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      _isActive ? 'CURRENT DECISION' : 'AUTONOMOUS MODE',
                      style: AppTypography.label,
                    ),
                  ),
                  _StatePill(label: vehicleState.label, color: color),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              // Keyed on the text so a new decision cross-fades rather than
              // swapping — at a two-second cadence, a hard cut is easy to miss
              // entirely if you happened to blink.
              AnimatedSwitcher(
                duration: AppDurations.normal,
                switchInCurve: AppDurations.emphasized,
                child: Text(
                  _headline,
                  key: ValueKey(_headline),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.titleLarge.copyWith(
                    fontSize: 30,
                    letterSpacing: -0.6,
                    color: _isActive
                        ? AppColors.textPrimary
                        : AppColors.textSecondary,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                _detail,
                style: AppTypography.bodySmall.copyWith(fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatePill extends StatelessWidget {
  const _StatePill({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 3,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: AppRadii.pillRadius,
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        label,
        style: AppTypography.label.copyWith(color: color, fontSize: 10),
      ),
    );
  }
}
