import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/app_router.dart';
import '../../core/theme/app_theme.dart';
import '../../models/connection_state.dart';
import '../../services/bluetooth_permission_service.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_card.dart';
import '../../widgets/connection_badge.dart';
import '../../widgets/section_header.dart';
import '../settings/settings_controller.dart';
import 'bluetooth_permission_controller.dart';
import 'connection_controller.dart';
import 'widgets/bluetooth_permission_card.dart';
import 'widgets/device_tile.dart';

/// Pair with a vehicle: scan, connect, and understand any failure well enough
/// to act on it.
class ConnectionScreen extends ConsumerStatefulWidget {
  const ConnectionScreen({super.key});

  @override
  ConsumerState<ConnectionScreen> createState() => _ConnectionScreenState();
}

class _ConnectionScreenState extends ConsumerState<ConnectionScreen>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
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
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.sm,
            AppSpacing.lg,
            AppSpacing.xxxl,
          ),
          children: [
            _LinkSummary(link: link),
            if (link.errorMessage != null) ...[
              const SizedBox(height: AppSpacing.lg),
              _ErrorPanel(
                link: link,
                onRetry: () => link.hasRememberedDevice
                    ? controller.reconnectSaved()
                    : controller.startScan(),
              ),
            ],
            if (settings.mockMode) ...[
              const SizedBox(height: AppSpacing.lg),
              const _MockNotice(),
            ],
            const SizedBox(height: AppSpacing.xxl),
            if (permissionStatus != null && !permissionStatus.isGranted)
              BluetoothPermissionCard(
                status: permissionStatus,
                onRequest: _requestPermission,
                onOpenSettings: () =>
                    ref.read(bluetoothPermissionServiceProvider).openSettings(),
              )
            else ...[
              SectionHeader(
                title: isScanning ? 'SCANNING…' : 'AVAILABLE VEHICLES',
                icon: Icons.bluetooth_searching_rounded,
                subtitle: isScanning
                    ? 'Keep the vehicle powered on and nearby'
                    : '${devices.length} device${devices.length == 1 ? '' : 's'} found',
                trailing: isScanning
                    ? const SizedBox(
                        height: 16,
                        width: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.accent,
                        ),
                      )
                    : null,
              ),
              if (devices.isEmpty)
                _EmptyScanState(isScanning: isScanning)
              else
                for (final device in devices)
                  DeviceTile(
                    vehicle: device,
                    isRemembered: device.id == link.deviceId,
                    isConnecting:
                        link.status == ConnectionStatus.connecting &&
                        link.deviceId == device.id,
                    isConnected: link.isConnected && link.deviceId == device.id,
                    onConnect: () => controller.connectTo(device),
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
                  icon: isScanning ? Icons.stop_rounded : Icons.refresh_rounded,
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
  const _ErrorPanel({required this.link, required this.onRetry});

  final LinkState link;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final isReconnecting = link.status == ConnectionStatus.reconnecting;
    final color = AppColors.forStatus(link.status.level);

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
            onPressed: isReconnecting ? null : onRetry,
          ),
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

class _EmptyScanState extends StatelessWidget {
  const _EmptyScanState({required this.isScanning});

  final bool isScanning;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.xxl,
      ),
      child: Column(
        children: [
          Icon(
            isScanning ? Icons.radar_rounded : Icons.bluetooth_disabled_rounded,
            size: 32,
            color: AppColors.textTertiary,
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            isScanning ? 'Listening for vehicles…' : 'No vehicles found',
            style: AppTypography.titleMedium.copyWith(fontSize: 16),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            isScanning
                ? 'This usually takes a few seconds.'
                : 'Check that the rover is powered on, within range, and not '
                      'already connected to another device.',
            textAlign: TextAlign.center,
            style: AppTypography.bodySmall,
          ),
        ],
      ),
    );
  }
}
