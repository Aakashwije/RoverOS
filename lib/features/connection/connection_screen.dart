import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/layout/breakpoints.dart';
import '../../core/router/app_router.dart';
import '../../core/theme/app_theme.dart';
import '../../models/connection_state.dart';
import '../../models/vehicle.dart';
import '../../services/bluetooth_permission_service.dart';
import '../../services/haptics.dart';
import '../../widgets/animated_reveal.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_card.dart';
import '../../widgets/connection_badge.dart';
import '../../widgets/section_header.dart';
import '../settings/settings_controller.dart';
import 'bluetooth_permission_controller.dart';
import 'connection_controller.dart';
import 'widgets/bluetooth_permission_card.dart';
import 'widgets/device_tile.dart';
import 'widgets/scan_progress.dart';

/// Pair with a vehicle: scan, connect, and understand any failure well enough
/// to act on it.
class ConnectionScreen extends ConsumerStatefulWidget {
  const ConnectionScreen({super.key});

  @override
  ConsumerState<ConnectionScreen> createState() => _ConnectionScreenState();
}

class _ConnectionScreenState extends ConsumerState<ConnectionScreen>
    with WidgetsBindingObserver {
  Timer? _countdownTicker;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // The scan countdown and every "seen Ns ago" label are derived from
    // wall-clock time, which no provider emits changes for. One shared tick
    // re-renders them all.
    _countdownTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });

    // Start looking immediately; arriving here always means "find my vehicle".
    // Mock mode never touches the radio, so it skips the permission gate
    // entirely; real hardware waits for a granted check before scanning.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      if (ref.read(settingsProvider).mockMode) {
        _startScanIfIdle();
        return;
      }
      final status = await ref
          .read(bluetoothPermissionProvider.notifier)
          .refresh();
      if (mounted && status == RoverPermissionStatus.granted) {
        _startScanIfIdle();
      }
    });
  }

  @override
  void dispose() {
    _countdownTicker?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    // The controller outlives this screen, so leave the transport tidy.
    ref.read(connectionProvider.notifier).stopScan();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Coming back from the OS Settings app is the only way permission can
    // change while this screen is open — pick that up so the user does not
    // have to back out and re-enter to continue.
    if (state != AppLifecycleState.resumed) return;
    if (ref.read(settingsProvider).mockMode) return;
    unawaited(_recheckPermissionAfterResume());
  }

  Future<void> _recheckPermissionAfterResume() async {
    final wasGranted =
        ref.read(bluetoothPermissionProvider).value?.isGranted ?? false;
    final status = await ref
        .read(bluetoothPermissionProvider.notifier)
        .refresh();
    if (mounted && !wasGranted && status == RoverPermissionStatus.granted) {
      _startScanIfIdle();
    }
  }

  void _startScanIfIdle() {
    if (!mounted) return;
    final link = ref.read(connectionProvider);
    if (!link.isConnected) ref.read(connectionProvider.notifier).startScan();
  }

  Future<void> _requestPermission() async {
    final status = await ref
        .read(bluetoothPermissionProvider.notifier)
        .request();
    if (status == RoverPermissionStatus.granted) _startScanIfIdle();
  }

  void _enableMockMode() {
    ref
        .read(settingsProvider.notifier)
        .update((s) => s.copyWith(mockMode: true));
    // Flipping mock mode rebuilds the transport, so the scan has to be
    // restarted against the new one rather than resumed.
    WidgetsBinding.instance.addPostFrameCallback((_) => _startScanIfIdle());
  }

  @override
  Widget build(BuildContext context) {
    final link = ref.watch(connectionProvider);
    final devices = ref.watch(scanResultsProvider);
    final settings = ref.watch(settingsProvider);
    final controller = ref.read(connectionProvider.notifier);
    final isScanning = link.status == ConnectionStatus.scanning;

    final permissionStatus = settings.mockMode
        ? RoverPermissionStatus.granted
        : ref.watch(bluetoothPermissionProvider).value;

    // The vehicle the user already trusts goes first, always — it is what they
    // came here for in every case except the first ever pairing.
    final remembered = <DiscoveredVehicle>[];
    final others = <DiscoveredVehicle>[];
    for (final device in devices) {
      (device.id == link.deviceId ? remembered : others).add(device);
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          tooltip: 'Back',
          onPressed: () =>
              context.canPop() ? context.pop() : context.go(AppRoute.home),
        ),
        title: const Text('CONNECT VEHICLE', style: AppTypography.labelStrong),
      ),
      body: SafeArea(
        top: false,
        child: PageConstraints(
          maxWidth: 760,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.sm,
              AppSpacing.lg,
              AppSpacing.xxxl,
            ),
            children: [
              _LinkSummary(link: link),
              AnimatedReveal(
                child: link.errorMessage == null
                    ? null
                    : Padding(
                        key: ValueKey(link.errorMessage),
                        padding: const EdgeInsets.only(top: AppSpacing.lg),
                        child: _ErrorPanel(
                          link: link,
                          onRetry: () => link.hasRememberedDevice
                              ? controller.reconnectSaved()
                              : controller.startScan(),
                          // A device seen seconds ago does not need to be
                          // rediscovered — dial it directly. Scanning again
                          // just adds the radio's discovery latency to a
                          // connection attempt that already knows its target.
                          onRetryDirect: link.hasRememberedDevice
                              ? () => controller.connectTo(
                                  DiscoveredVehicle(
                                    id: link.deviceId!,
                                    name: link.deviceName ?? '',
                                  ),
                                )
                              : null,
                        ),
                      ),
              ),
              if (settings.mockMode) ...[
                const SizedBox(height: AppSpacing.lg),
                const _MockNotice(),
              ],
              const SizedBox(height: AppSpacing.xxl),
              if (permissionStatus != null && !permissionStatus.isGranted)
                BluetoothPermissionCard(
                  status: permissionStatus,
                  onRequest: _requestPermission,
                  onOpenSettings: () => ref
                      .read(bluetoothPermissionServiceProvider)
                      .openSettings(),
                )
              else ...[
                AnimatedReveal(
                  child: isScanning
                      ? Padding(
                          key: const ValueKey('scan-progress'),
                          padding: const EdgeInsets.only(bottom: AppSpacing.lg),
                          child: ScanProgress(
                            endsAt: link.scanEndsAt,
                            deviceCount: devices.length,
                          ),
                        )
                      : null,
                ),
                if (remembered.isNotEmpty) ...[
                  const SectionHeader(
                    title: 'YOUR VEHICLE',
                    icon: Icons.star_rounded,
                    subtitle: 'Paired with this phone before',
                  ),
                  for (final device in remembered)
                    DeviceTile(
                      vehicle: device,
                      kind: settings.vehicleKind,
                      isRemembered: true,
                      isConnecting:
                          link.status == ConnectionStatus.connecting &&
                          link.deviceId == device.id,
                      isConnected:
                          link.isConnected && link.deviceId == device.id,
                      onConnect: () {
                        Haptics.selection(enabled: settings.hapticsEnabled);
                        controller.connectTo(device);
                      },
                    ),
                  const SizedBox(height: AppSpacing.lg),
                ],
                SectionHeader(
                  title: remembered.isEmpty
                      ? 'AVAILABLE VEHICLES'
                      : 'OTHER DEVICES',
                  icon: Icons.bluetooth_searching_rounded,
                  subtitle: isScanning
                      ? 'Keep the vehicle powered on and nearby'
                      : '${others.length} device'
                            '${others.length == 1 ? '' : 's'} found',
                ),
                if (others.isEmpty)
                  _EmptyScanState(
                    isScanning: isScanning,
                    isMockMode: settings.mockMode,
                    hasRemembered: remembered.isNotEmpty,
                    onEnableMockMode: _enableMockMode,
                  )
                else
                  for (final device in others)
                    DeviceTile(
                      vehicle: device,
                      kind: settings.vehicleKind,
                      isRemembered: false,
                      isConnecting:
                          link.status == ConnectionStatus.connecting &&
                          link.deviceId == device.id,
                      isConnected:
                          link.isConnected && link.deviceId == device.id,
                      onConnect: () {
                        Haptics.selection(enabled: settings.hapticsEnabled);
                        controller.connectTo(device);
                      },
                    ),
                const SizedBox(height: AppSpacing.xxl),
                if (link.isConnected)
                  AppButton(
                    label: 'CONTINUE',
                    icon: Icons.check_rounded,
                    size: AppButtonSize.large,
                    fullWidth: true,
                    onPressed: () => context.canPop()
                        ? context.pop()
                        : context.go(AppRoute.home),
                  )
                else
                  AppButton(
                    label: isScanning ? 'STOP SCAN' : 'SCAN AGAIN',
                    icon: isScanning
                        ? Icons.stop_rounded
                        : Icons.refresh_rounded,
                    variant: AppButtonVariant.secondary,
                    size: AppButtonSize.large,
                    fullWidth: true,
                    onPressed: () => isScanning
                        ? controller.stopScan()
                        : controller.startScan(),
                  ),
              ],
              if (link.hasRememberedDevice) ...[
                const SizedBox(height: AppSpacing.md),
                Center(
                  child: TextButton(
                    onPressed: controller.forgetDevice,
                    child: Text(
                      'FORGET ${link.displayName.toUpperCase()}',
                      style: AppTypography.label.copyWith(
                        color: AppColors.danger,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _LinkSummary extends StatelessWidget {
  const _LinkSummary({required this.link});

  final LinkState link;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      elevated: true,
      accent: AppColors.forStatus(link.status.level),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  link.isConnected ? link.displayName : 'No active link',
                  style: AppTypography.titleMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(link.status.description, style: AppTypography.bodySmall),
                const SizedBox(height: AppSpacing.md),
                ConnectionBadge(link: link),
              ],
            ),
          ),
          if (link.isConnected)
            Column(
              children: [
                SignalBars(quality: link.signal, height: 26, showLabel: false),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  link.signal.label,
                  style: AppTypography.label.copyWith(
                    color: AppColors.forStatus(link.signal.level),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

/// Failure panel. Always states what happened and what to do about it — never
/// a bare "something went wrong".
class _ErrorPanel extends StatelessWidget {
  const _ErrorPanel({
    required this.link,
    required this.onRetry,
    this.onRetryDirect,
  });

  final LinkState link;
  final VoidCallback onRetry;

  /// Connects straight to the remembered vehicle, skipping the scan. Null
  /// when no vehicle is remembered, in which case [onRetry] (a scan) is the
  /// only way forward.
  final VoidCallback? onRetryDirect;

  @override
  Widget build(BuildContext context) {
    final isReconnecting = link.status == ConnectionStatus.reconnecting;
    final color = AppColors.forStatus(link.status.level);
    // Prefer the direct dial: the target is already known, so the full scan
    // is strictly slower.
    final retry = onRetryDirect ?? onRetry;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: AppRadii.cardRadius,
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                AppColors.iconForStatus(link.status.level),
                size: 18,
                color: color,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  link.status.label,
                  style: AppTypography.labelStrong.copyWith(color: color),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(link.errorMessage!, style: AppTypography.bodySmall),
          if (isReconnecting) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Attempt ${link.reconnectAttempt} — backing off between tries.',
              style: AppTypography.bodySmall.copyWith(fontSize: 12),
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          AppButton(
            label: isReconnecting ? 'RECONNECTING…' : 'RETRY',
            icon: Icons.refresh_rounded,
            size: AppButtonSize.small,
            variant: AppButtonVariant.secondary,
            isLoading: isReconnecting,
            onPressed: isReconnecting ? null : retry,
          ),
          if (onRetryDirect != null && !isReconnecting) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Retries the last link directly — no rescan.',
              style: AppTypography.bodySmall.copyWith(fontSize: 11),
            ),
          ],
        ],
      ),
    );
  }
}

class _MockNotice extends StatelessWidget {
  const _MockNotice();

  @override
  Widget build(BuildContext context) {
    return AppCard(
      accent: AppColors.info,
      child: Row(
        children: [
          const Icon(Icons.science_rounded, size: 18, color: AppColors.info),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'MOCK MODE IS ON',
                  style: AppTypography.labelStrong.copyWith(
                    color: AppColors.info,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'Devices listed here are simulated. Turn off mock mode in '
                  'Settings to scan for real hardware.',
                  style: AppTypography.bodySmall.copyWith(fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// What to do when nothing turned up.
///
/// A scan that finds nothing is the most common failure on this screen and the
/// least self-explanatory, so this names every cause in the order they are
/// worth checking — rather than leaving the user to guess which of power,
/// range, pairing or app mode is the one that is wrong.
class _EmptyScanState extends StatelessWidget {
  const _EmptyScanState({
    required this.isScanning,
    required this.isMockMode,
    required this.hasRemembered,
    required this.onEnableMockMode,
  });

  final bool isScanning;
  final bool isMockMode;
  final bool hasRemembered;
  final VoidCallback onEnableMockMode;

  @override
  Widget build(BuildContext context) {
    if (isScanning) {
      return AppCard(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.xxl,
        ),
        child: Column(
          children: [
            const Icon(
              Icons.radar_rounded,
              size: 32,
              color: AppColors.textTertiary,
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              hasRemembered
                  ? 'Looking for other devices…'
                  : 'Listening for vehicles…',
              style: AppTypography.titleMedium.copyWith(fontSize: 16),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'This usually takes a few seconds.',
              textAlign: TextAlign.center,
              style: AppTypography.bodySmall,
            ),
          ],
        ),
      );
    }

    return AppCard(
      accent: AppColors.caution,
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.search_off_rounded,
                size: 22,
                color: AppColors.caution,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  'No rover found',
                  style: AppTypography.titleMedium.copyWith(fontSize: 17),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          const _Check(
            icon: Icons.power_settings_new_rounded,
            title: 'Is the rover powered on?',
            detail:
                'The ESP32 only advertises once its board has booted — give it '
                'a few seconds after switching on.',
          ),
          const _Check(
            icon: Icons.bluetooth_rounded,
            title: 'Is Bluetooth on, and the rover in range?',
            detail:
                'BLE range drops sharply through walls. Get within a couple of '
                'metres for the first pairing.',
          ),
          const _Check(
            icon: Icons.phonelink_off_rounded,
            title: 'Is something else already connected to it?',
            detail:
                'The rover accepts one link at a time. Close the app on any '
                'other phone, or power-cycle the board.',
          ),
          if (!isMockMode) ...[
            const _Check(
              icon: Icons.science_rounded,
              title: 'No hardware to hand?',
              detail:
                  'Mock mode drives a simulated rover so you can explore every '
                  'screen without a board.',
            ),
            const SizedBox(height: AppSpacing.md),
            AppButton(
              label: 'TURN ON MOCK MODE',
              icon: Icons.science_rounded,
              size: AppButtonSize.small,
              variant: AppButtonVariant.secondary,
              fullWidth: true,
              onPressed: onEnableMockMode,
            ),
          ],
        ],
      ),
    );
  }
}

class _Check extends StatelessWidget {
  const _Check({required this.icon, required this.title, required this.detail});

  final IconData icon;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: AppColors.textTertiary),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  detail,
                  style: AppTypography.bodySmall.copyWith(fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
