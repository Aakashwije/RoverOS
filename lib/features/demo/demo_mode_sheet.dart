import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../services/transport/mock_transport.dart';
import '../../widgets/app_bottom_sheet.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_slider.dart';
import '../../widgets/section_header.dart';
import '../connection/connection_controller.dart';
import '../settings/settings_controller.dart';

/// Controls for the simulated rover.
///
/// The mock transport already models battery sag, obstacles and error frames;
/// what it lacked was a way to *reach* those states on purpose. Waiting eleven
/// minutes for a pack to drain to the critical warning is not a demo, and a
/// sensor failure that only happens by accident is not a test.
class DemoModeSheet extends ConsumerStatefulWidget {
  const DemoModeSheet({super.key});

  static Future<void> show(BuildContext context) {
    return AppBottomSheet.show<void>(
      context,
      title: 'Simulator controls',
      subtitle: 'Drive the mock rover into states worth looking at',
      icon: Icons.science_rounded,
      builder: (context) => const DemoModeSheet(),
    );
  }

  @override
  ConsumerState<DemoModeSheet> createState() => _DemoModeSheetState();
}

class _DemoModeSheetState extends ConsumerState<DemoModeSheet> {
  /// Slider positions are held locally so dragging stays smooth; the transport
  /// is only told on release. Null means "follow the simulator".
  int? _pendingBattery;
  int? _pendingDistance;

  MockTransport? get _mock {
    final transport = ref.read(transportProvider);
    return transport is MockTransport ? transport : null;
  }

  void _apply(void Function(MockTransport mock) action) {
    final mock = _mock;
    if (mock == null) return;
    setState(() => action(mock));
  }

  @override
  Widget build(BuildContext context) {
    final isMockMode = ref.watch(settingsProvider.select((s) => s.mockMode));
    final link = ref.watch(connectionProvider);
    final mock = _mock;

    if (!isMockMode || mock == null) {
      return const _UnavailableNotice();
    }

    final battery = _pendingBattery ?? mock.batteryPercent;
    final distance = _pendingDistance ?? mock.distanceCm;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!link.isConnected) ...[
          AppCard(
            accent: AppColors.caution,
            child: Row(
              children: [
                const Icon(
                  Icons.info_rounded,
                  size: 18,
                  color: AppColors.caution,
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Text(
                    'Connect to the mock vehicle first — these controls change '
                    'what it reports, and nothing is reporting yet.',
                    style: AppTypography.bodySmall.copyWith(fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
        ],
        const SectionHeader(
          title: 'VEHICLE STATE',
          icon: Icons.tune_rounded,
          subtitle: 'Applied on release',
        ),
        AppSlider(
          label: 'BATTERY',
          leadingIcon: Icons.battery_5_bar_rounded,
          value: battery.toDouble(),
          min: 0,
          max: 100,
          divisions: 100,
          unit: '%',
          color: AppColors.good,
          helperText:
              'Drop below 30% for the low warning, below 15% for critical.',
          onChanged: (value) => setState(() => _pendingBattery = value.round()),
          onChangeEnd: (value) {
            _apply((mock) => mock.setBattery(value.round()));
            setState(() => _pendingBattery = null);
          },
        ),
        const SizedBox(height: AppSpacing.lg),
        AppSlider(
          label: 'OBSTACLE DISTANCE',
          leadingIcon: Icons.straighten_rounded,
          value: distance.toDouble(),
          min: 6,
          max: 320,
          divisions: 157,
          unit: 'cm',
          color: AppColors.caution,
          helperText:
              'The simulation keeps moving this as the rover drives — set it '
              'to stage an obstacle right now.',
          onChanged: (value) =>
              setState(() => _pendingDistance = value.round()),
          onChangeEnd: (value) {
            _apply((mock) => mock.setDistance(value.round()));
            setState(() => _pendingDistance = null);
          },
        ),
        const SizedBox(height: AppSpacing.xxl),
        SectionHeader(
          title: 'INJECT A FAULT',
          icon: Icons.bug_report_rounded,
          subtitle: 'Currently: ${mock.activeFault.label}',
        ),
        for (final fault in MockFault.values.where((f) => f != MockFault.none))
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: _FaultRow(
              fault: fault,
              isActive: mock.activeFault == fault,
              onTrigger: () => _apply((mock) => mock.injectFault(fault)),
            ),
          ),
        const SizedBox(height: AppSpacing.lg),
        AppButton(
          label: 'CLEAR FAULTS',
          icon: Icons.healing_rounded,
          variant: AppButtonVariant.secondary,
          fullWidth: true,
          onPressed: mock.activeFault == MockFault.none
              ? null
              : () => _apply((mock) => mock.clearFaults()),
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          'Faults are simulator-only. Nothing here is ever sent to real '
          'hardware.',
          textAlign: TextAlign.center,
          style: AppTypography.bodySmall.copyWith(fontSize: 11),
        ),
      ],
    );
  }
}

IconData _iconFor(MockFault fault) => switch (fault) {
  MockFault.none => Icons.check_circle_rounded,
  MockFault.sensorFailure => Icons.sensors_off_rounded,
  MockFault.motorFault => Icons.electrical_services_rounded,
  MockFault.lowBattery => Icons.battery_alert_rounded,
  MockFault.dropout => Icons.link_off_rounded,
};

class _FaultRow extends StatelessWidget {
  const _FaultRow({
    required this.fault,
    required this.isActive,
    required this.onTrigger,
  });

  final MockFault fault;
  final bool isActive;
  final VoidCallback onTrigger;

  @override
  Widget build(BuildContext context) {
    final color = isActive ? AppColors.danger : AppColors.textTertiary;

    return AppCard(
      onTap: onTrigger,
      accent: isActive ? AppColors.danger : null,
      padding: const EdgeInsets.all(AppSpacing.md),
      semanticLabel:
          '${fault.label}. ${fault.description}. '
          '${isActive ? 'Currently active.' : 'Activate to inject.'}',
      child: Row(
        children: [
          Container(
            height: 34,
            width: 34,
            decoration: BoxDecoration(
              color: isActive
                  ? AppColors.danger.withValues(alpha: 0.16)
                  : AppColors.surfaceSunken,
              borderRadius: BorderRadius.circular(AppRadii.sm),
            ),
            child: Icon(_iconFor(fault), size: 17, color: color),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  fault.label,
                  style: AppTypography.labelStrong.copyWith(fontSize: 11),
                ),
                const SizedBox(height: 2),
                Text(
                  fault.description,
                  style: AppTypography.bodySmall.copyWith(fontSize: 11.5),
                ),
              ],
            ),
          ),
          if (isActive)
            const Icon(
              Icons.check_circle_rounded,
              size: 17,
              color: AppColors.danger,
            )
          else
            const Icon(
              Icons.play_arrow_rounded,
              size: 18,
              color: AppColors.textTertiary,
            ),
        ],
      ),
    );
  }
}

class _UnavailableNotice extends StatelessWidget {
  const _UnavailableNotice();

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Row(
        children: [
          const Icon(
            Icons.info_rounded,
            size: 18,
            color: AppColors.textTertiary,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              'The simulator controls are only available while mock car mode '
              'is on.',
              style: AppTypography.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}
