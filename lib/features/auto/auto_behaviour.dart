import 'package:flutter/material.dart';

import '../../models/commands.dart';

/// The three mutually exclusive things the Auto screen can put the vehicle in.
///
/// The firmware tracks two separate knobs — drive mode and scan mode — but the
/// user is making one choice, and offering both as independent toggles invites
/// the nonsense combination (avoiding *and* sweeping) that the firmware would
/// have to arbitrate anyway. Collapsing them here means the UI can only ever
/// ask for something coherent.
enum AutoBehaviour {
  manual(
    'MANUAL',
    'You are driving',
    Icons.sports_esports_rounded,
    'Autonomous behaviours are off. Drive from the DRIVE tab.',
  ),
  avoid(
    'AVOID',
    'Vehicle avoids obstacles',
    Icons.auto_mode_rounded,
    'The vehicle drives and steers around obstacles on its own.',
  ),
  scan(
    'SCAN',
    'Sweeping the servo',
    Icons.radar_rounded,
    'Sweeps the servo and maps distances. The chassis stays still.',
  );

  const AutoBehaviour(this.label, this.summary, this.icon, this.description);

  final String label;
  final String summary;
  final IconData icon;
  final String description;

  /// Entering this behaviour hands control to the firmware, so it asks first.
  bool get requiresConfirmation => this == avoid;

  static AutoBehaviour of(DriveMode driveMode, ScanMode scanMode) {
    if (driveMode == DriveMode.obstacleAvoidance) return avoid;
    if (scanMode != ScanMode.off) return scan;
    return manual;
  }
}
