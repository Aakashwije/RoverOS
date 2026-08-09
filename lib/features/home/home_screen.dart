import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_config.dart';
import '../../core/providers/app_providers.dart';
import '../../core/router/app_router.dart';
import '../../core/theme/app_theme.dart';
import '../../models/connection_state.dart';
import '../../widgets/app_badge.dart';
import '../../widgets/app_button.dart';
import '../../widgets/connection_badge.dart';
import '../../widgets/section_header.dart';
import '../connection/connection_controller.dart';
import '../settings/settings_controller.dart';
import '../telemetry/telemetry_controller.dart';
import 'widgets/activity_feed.dart';
import 'widgets/readiness_banner.dart';
import 'widgets/vehicle_status_card.dart';

/// Dashboard landing screen: vehicle state at a glance, plus the single action
/// that matters most from here — start driving.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final link = ref.watch(connectionProvider);
    final telemetry = ref.watch(telemetryProvider);
    final settings = ref.watch(settingsProvider);
    final activity = ref.watch(activityLogProvider);

    final driveMode = telemetry.driveMode ?? settings.defaultDriveMode;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          color: AppColors.accent,
          backgroundColor: AppColors.surfaceElevated,
          // Every card here already watches its provider live, so a refresh
          // has nothing to fetch. Invalidating connectionProvider would tear
          // down and rebuild the controller while leaving the underlying
          // transport connected underneath it — the UI would then show a
          // fresh, wrongly-idle state for a vehicle that never actually
          // disconnected. Instead: attempt a reconnect if one is due, or
          // simply acknowledge the gesture.
          onRefresh: () async {
            final link = ref.read(connectionProvider);
            if (!link.isConnected && link.hasRememberedDevice) {
              await ref.read(connectionProvider.notifier).reconnectSaved();
            } else {
              await Future<void>.delayed(const Duration(milliseconds: 400));
            }
          },
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.lg,
              AppSpacing.lg,
              AppSpacing.xxxl,
            ),
            children: [
              _HomeHeader(link: link, isMockMode: settings.mockMode),
              const SizedBox(height: AppSpacing.xl),
              ReadinessBanner(
                link: link,
                telemetry: telemetry,
                isMockMode: settings.mockMode,
              ),
              const SizedBox(height: AppSpacing.lg),
              VehicleStatusCard(
                link: link,
                telemetry: telemetry,
                driveMode: driveMode,
                onConnect: () => context.push(AppRoute.connect),
              ),
              const SizedBox(height: AppSpacing.xxl),
              SectionHeader(
                title: 'RECENT ACTIVITY',
                icon: Icons.history_rounded,
                trailing: activity.isEmpty
                    ? null
                    : TextButton(
                        onPressed: () =>
                            ref.read(activityLogProvider.notifier).clear(),
                        child: Text(
                          'CLEAR',
                          style: AppTypography.label.copyWith(
                            color: AppColors.accent,
                          ),
                        ),
                      ),
              ),
              ActivityFeed(entries: activity),
              const SizedBox(height: AppSpacing.xxl),
              _PrimaryAction(isConnected: link.isConnected),
              const SizedBox(height: AppSpacing.md),
              Center(
                child: TextButton.icon(
                  onPressed: () => context.push(AppRoute.telemetry),
                  icon: const Icon(Icons.insights_rounded, size: 16),
                  label: Text(
                    'VIEW TELEMETRY',
                    style: AppTypography.label.copyWith(
                      color: AppColors.textSecondary,
                    ),
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

class _HomeHeader extends StatelessWidget {
  const _HomeHeader({required this.link, required this.isMockMode});

  final LinkState link;
  final bool isMockMode;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                AppConfig.appName,
                style: AppTypography.wordmark.copyWith(
                  fontSize: 28,
                  letterSpacing: 4.5,
                ),
              ),
              const SizedBox(height: 5),
              const Text(AppConfig.tagline, style: AppTypography.wordmarkSub),
            ],
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            ConnectionBadge(link: link),
            if (isMockMode) ...[
              const SizedBox(height: AppSpacing.sm),
              const AppBadge(
                label: 'MOCK MODE',
                level: StatusLevel.info,
                icon: Icons.science_rounded,
                size: AppBadgeSize.small,
                semanticLabel:
                    'Mock mode is on. No hardware commands are sent.',
              ),
            ],
          ],
        ),
      ],
    );
  }
}

class _PrimaryAction extends StatelessWidget {
  const _PrimaryAction({required this.isConnected});

  final bool isConnected;

  @override
  Widget build(BuildContext context) {
    return AppButton(
      label: isConnected ? 'START DRIVING' : 'CONNECT VEHICLE',
      icon: isConnected
          ? Icons.sports_esports_rounded
          : Icons.bluetooth_rounded,
      trailingIcon: Icons.arrow_forward_rounded,
      size: AppButtonSize.large,
      fullWidth: true,
      onPressed: () =>
          context.push(isConnected ? AppRoute.drive : AppRoute.connect),
      semanticLabel: isConnected
          ? 'Start driving. Opens the landscape drive controls'
          : 'Connect vehicle. Opens the Bluetooth connection screen',
    );
  }
}
