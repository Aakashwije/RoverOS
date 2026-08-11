import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../models/commands.dart';
import '../../models/connection_state.dart';
import '../../models/telemetry.dart';

/// The single action Home should push the user toward.
enum HomeAction {
  /// Nothing has ever been paired.
  connect('CONNECT VEHICLE', Icons.bluetooth_rounded),

  /// A vehicle is remembered but the link is down.
  reconnect('RECONNECT VEHICLE', Icons.bluetooth_searching_rounded),

  /// The link is being established; the user should wait, not tap.
  waitForLink('CONNECTING…', Icons.hourglass_top_rounded),

  /// Connected and healthy.
  drive('START DRIVING', Icons.sports_esports_rounded),

  /// Connected, but something wants acknowledging first.
  driveWithCare('START DRIVING', Icons.sports_esports_rounded),

  /// Connected and blocked — driving now would be unsafe.
  resolveFault('REVIEW TELEMETRY', Icons.troubleshoot_rounded);

  const HomeAction(this.label, this.icon);

  final String label;
  final IconData icon;

  bool get opensDrive => this == drive || this == driveWithCare;

  bool get opensConnect => this == connect || this == reconnect;

  /// True when tapping would do nothing useful yet.
  bool get isWaiting => this == waitForLink;
}

/// Headline state of the vehicle, in the terms a driver cares about.
///
/// Rendered at two prominences: [isBlocking] states get a full warning banner,
/// everything else gets a single reassuring line. Splitting on severity rather
/// than always shouting is what keeps the banner meaningful — if the screen
/// looks alarmed in the normal case, an actual fault reads as more of the same.
class HomeStatus {
  const HomeStatus({
    required this.title,
    required this.detail,
    required this.level,
    required this.icon,
    required this.action,
  });

  final String title;
  final String detail;
  final StatusLevel level;
  final IconData icon;
  final HomeAction action;

  /// Warrants the loud treatment: a fault, a dead pack, or a link that has
  /// stopped delivering data while claiming to be up.
  bool get isBlocking => level.isAlarming;

  /// Evaluates everything Home knows into one verdict.
  ///
  /// Ordered by severity, most severe first, so a rover that is simultaneously
  /// faulted and low on battery reports the fault — the thing that actually
  /// stops it from being driven.
  static HomeStatus evaluate({
    required LinkState link,
    required Telemetry telemetry,
    required bool isMockMode,
    DateTime? now,
  }) {
    if (link.status.isBusy) {
      return HomeStatus(
        title: link.status.label,
        detail: link.status == ConnectionStatus.reconnecting
            ? _reconnectDetail(link, now ?? DateTime.now())
            : link.status.description,
        level: StatusLevel.info,
        icon: Icons.bluetooth_searching_rounded,
        action: HomeAction.waitForLink,
      );
    }

    if (!link.isConnected) {
      final hasFailure =
          link.errorMessage != null &&
          (link.status == ConnectionStatus.error ||
              link.status == ConnectionStatus.disconnected ||
              link.status == ConnectionStatus.bluetoothOff ||
              link.status == ConnectionStatus.permissionRequired);

      if (hasFailure) {
        return HomeStatus(
          title: link.status.label,
          detail: link.errorMessage!,
          level: link.status.level,
          icon: AppColors.iconForStatus(link.status.level),
          action: link.hasRememberedDevice
              ? HomeAction.reconnect
              : HomeAction.connect,
        );
      }

      return HomeStatus(
        title: 'VEHICLE OFFLINE',
        detail: link.hasRememberedDevice
            ? 'Reconnect to ${link.displayName} to start driving'
            : 'Pair a vehicle to start driving',
        level: StatusLevel.neutral,
        icon: Icons.power_settings_new_rounded,
        action: link.hasRememberedDevice
            ? HomeAction.reconnect
            : HomeAction.connect,
      );
    }

    if (telemetry.vehicleState == VehicleState.fault) {
      return const HomeStatus(
        title: 'VEHICLE FAULT',
        detail: 'The vehicle is reporting a fault. Clear it before driving.',
        level: StatusLevel.danger,
        icon: Icons.report_problem_rounded,
        action: HomeAction.resolveFault,
      );
    }

    if (telemetry.batteryStatus == BatteryStatus.critical) {
      return const HomeStatus(
        title: 'CRITICAL BATTERY',
        detail:
            'Charge the pack before driving. Motors can brown out the board '
            'at this level.',
        level: StatusLevel.danger,
        icon: Icons.battery_alert_rounded,
        action: HomeAction.resolveFault,
      );
    }

    // A connected link that has stopped delivering frames is the most
    // misleading state the app can be in: every number on screen is a memory,
    // and nothing about a still dashboard says so.
    if (telemetry.isStale(now: now)) {
      return const HomeStatus(
        title: 'TELEMETRY STALE',
        detail:
            'The link is up but the vehicle has stopped reporting. Readings '
            'below are the last known values, not live ones.',
        level: StatusLevel.caution,
        icon: Icons.history_toggle_off_rounded,
        action: HomeAction.driveWithCare,
      );
    }

    if (telemetry.batteryStatus == BatteryStatus.low) {
      return const HomeStatus(
        title: 'READY — LOW BATTERY',
        detail: 'The vehicle will drive, but range is limited.',
        level: StatusLevel.caution,
        icon: Icons.battery_2_bar_rounded,
        action: HomeAction.driveWithCare,
      );
    }

    return HomeStatus(
      title: isMockMode ? 'READY — MOCK VEHICLE' : 'VEHICLE READY',
      detail: isMockMode
          ? 'Simulated rover: no hardware commands are sent'
          : 'All systems nominal. Ready to drive.',
      level: isMockMode ? StatusLevel.info : StatusLevel.good,
      icon: isMockMode ? Icons.science_rounded : Icons.check_circle_rounded,
      action: HomeAction.drive,
    );
  }

  /// How the banner describes a reconnect in flight. The countdown matters
  /// more than the attempt number: "retrying in 6s" tells the user whether to
  /// keep waiting or intervene, which "attempt 3" alone does not.
  static String _reconnectDetail(LinkState link, DateTime now) {
    final attempt = link.reconnectAttempt;
    final at = link.nextReconnectAt;
    if (at == null) {
      return 'Attempt $attempt — backing off between tries';
    }
    final seconds = at.difference(now).inSeconds;
    if (seconds <= 0) return 'Attempt $attempt — retrying now';
    return 'Attempt $attempt — next try in ${seconds}s';
  }
}
