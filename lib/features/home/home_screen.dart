import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_config.dart';
import '../../core/layout/breakpoints.dart';
import '../../core/providers/app_providers.dart';
import '../../core/router/app_router.dart';
import '../../core/theme/app_theme.dart';
import '../../models/connection_state.dart';
import '../../widgets/animated_reveal.dart';
import '../../widgets/app_badge.dart';
import '../../widgets/app_bottom_sheet.dart';
import '../../widgets/app_button.dart';
import '../../widgets/connection_badge.dart';
import '../../widgets/section_header.dart';
import '../connection/connection_controller.dart';
import '../demo/demo_mode_sheet.dart';
import '../settings/settings_controller.dart';
import '../telemetry/telemetry_controller.dart';
import 'home_status.dart';
import 'widgets/activity_feed.dart';
import 'widgets/status_banner.dart';
import 'widgets/vehicle_status_card.dart';
import 'widgets/vitals_strip.dart';

/// Dashboard landing screen.
///
/// Ordered by the question it answers: *is anything wrong* (banner), *what do
/// I do next* (one primary action), *how is the vehicle* (vitals, then the
/// detail card), *what has been happening* (activity). Everything above the
/// fold is the first two.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  Timer? _stalenessTicker;

  @override
  void initState() {
    super.initState();
    // Telemetry only pushes an update when a frame arrives, so without a timer
    // a dropout would never visibly go stale — the banner would keep saying
    // "ready" over numbers that stopped moving a minute ago.
    _stalenessTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _stalenessTicker?.cancel();
    super.dispose();
  }

  Future<void> _onRefresh() async {
    // Every card here already watches its provider live, so a refresh has
    // nothing to fetch. Invalidating connectionProvider would tear down and
    // rebuild the controller while leaving the underlying transport connected
    // underneath it — the UI would then show a fresh, wrongly-idle state for a
    // vehicle that never actually disconnected. Instead: attempt a reconnect
    // if one is due, or simply acknowledge the gesture.
    final link = ref.read(connectionProvider);
    if (!link.isConnected && link.hasRememberedDevice) {
      await ref.read(connectionProvider.notifier).reconnectSaved();
    } else {
      await Future<void>.delayed(const Duration(milliseconds: 400));
    }
  }

  void _onPrimaryAction(HomeAction action) {
    switch (action) {
      case HomeAction.drive:
      case HomeAction.driveWithCare:
        context.push(AppRoute.drive);
      case HomeAction.connect:
      case HomeAction.reconnect:
        context.push(AppRoute.connect);
      case HomeAction.resolveFault:
        context.go(AppRoute.telemetry);
      case HomeAction.waitForLink:
        break;
    }
  }

  /// The feed on Home shows the four most recent entries; the sheet carries
  /// the whole log and owns the destructive clear, so wiping history is a
  /// deliberate act rather than a mis-tap on the section header.
  void _showFullActivity(BuildContext context) {
    AppBottomSheet.show<void>(
      context,
      title: 'Activity',
      subtitle: 'Everything the app and vehicle have done this run',
      icon: Icons.history_rounded,
      builder: (sheetContext) => Consumer(
        builder: (context, ref, _) {
          final entries = ref.watch(activityLogProvider);
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Flexible(
                child: SingleChildScrollView(
                  child: ActivityFeed(
                    entries: entries,
                    maxEntries: entries.length,
                  ),
                ),
              ),
              if (entries.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.md),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () {
                      ref.read(activityLogProvider.notifier).clear();
                      Navigator.of(context).pop();
                    },
                    child: Text(
                      'CLEAR HISTORY',
                      style: AppTypography.label.copyWith(
                        color: AppColors.danger,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final link = ref.watch(connectionProvider);
    final telemetry = ref.watch(telemetryProvider);
    final settings = ref.watch(settingsProvider);
    final activity = ref.watch(activityLogProvider);

    final driveMode = telemetry.driveMode ?? settings.defaultDriveMode;
    final status = HomeStatus.evaluate(
      link: link,
      telemetry: telemetry,
      isMockMode: settings.mockMode,
    );

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          color: AppColors.accent,
          backgroundColor: AppColors.surfaceElevated,
          onRefresh: _onRefresh,
          child: PageConstraints(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.lg,
                AppSpacing.lg,
                AppSpacing.xxxl,
              ),
              children: [
                _HomeHeader(
                  link: link,
                  isMockMode: settings.mockMode,
                  onOpenDemo: () => DemoModeSheet.show(context),
                ),
                const SizedBox(height: AppSpacing.xl),
                // Keyed on the state itself so a change in *what is wrong*
                // cross-fades, while a re-render of the same state does not.
                AnimatedReveal(
                  child: StatusBanner(
                    key: ValueKey(status.title),
                    status: status,
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                TwoPane(
                  primaryFlex: 3,
                  secondaryFlex: 2,
                  primary: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _PrimaryAction(
                        status: status,
                        onPressed: () => _onPrimaryAction(status.action),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      VitalsStrip(
                        telemetry: telemetry,
                        settings: settings,
                        driveMode: driveMode,
                        isConnected: link.isConnected,
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      VehicleStatusCard(
                        link: link,
                        telemetry: telemetry,
                        driveMode: driveMode,
                        onConnect: () => context.push(AppRoute.connect),
                      ),
                    ],
                  ),
                  secondary: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SectionHeader(
                        title: 'RECENT ACTIVITY',
                        icon: Icons.history_rounded,
                        trailing: activity.isEmpty
                            ? null
                            : TextButton(
                                onPressed: () => _showFullActivity(context),
                                child: Text(
                                  'VIEW ALL',
                                  style: AppTypography.label.copyWith(
                                    color: AppColors.accent,
                                  ),
                                ),
                              ),
                      ),
                      ActivityFeed(entries: activity),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HomeHeader extends StatelessWidget {
  const _HomeHeader({
    required this.link,
    required this.isMockMode,
    required this.onOpenDemo,
  });

  final LinkState link;
  final bool isMockMode;
  final VoidCallback onOpenDemo;

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
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
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
              // The badge doubles as the way into the simulator controls —
              // the only place they are relevant is where the badge appears.
              Semantics(
                button: true,
                label:
                    'Mock mode is on. No hardware commands are sent. '
                    'Opens the simulator controls.',
                child: ExcludeSemantics(
                  child: GestureDetector(
                    onTap: onOpenDemo,
                    child: const AppBadge(
                      label: 'MOCK MODE',
                      level: StatusLevel.info,
                      icon: Icons.science_rounded,
                      size: AppBadgeSize.small,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

class _PrimaryAction extends StatelessWidget {
  const _PrimaryAction({required this.status, required this.onPressed});

  final HomeStatus status;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final action = status.action;

    return AppButton(
      label: action.label,
      icon: action.icon,
      trailingIcon: action.isWaiting ? null : Icons.arrow_forward_rounded,
      size: AppButtonSize.large,
      fullWidth: true,
      isLoading: action.isWaiting,
      // A blocked vehicle still offers a route forward — to the telemetry that
      // explains the block — rather than a dead grey button.
      variant: action.opensDrive
          ? AppButtonVariant.primary
          : AppButtonVariant.secondary,
      onPressed: action.isWaiting ? null : onPressed,
      semanticLabel: switch (action) {
        HomeAction.drive || HomeAction.driveWithCare =>
          'Start driving. Opens the landscape drive controls',
        HomeAction.connect || HomeAction.reconnect =>
          'Connect vehicle. Opens the Bluetooth connection screen',
        HomeAction.resolveFault =>
          'Review telemetry. Opens the full telemetry dashboard',
        HomeAction.waitForLink => 'Connecting to the vehicle. Please wait',
      },
    );
  }
}
