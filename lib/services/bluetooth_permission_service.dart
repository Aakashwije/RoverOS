import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

/// App-level view of whether ROVEROS may use Bluetooth, collapsed from
/// however many OS permissions actually back it on this platform.
enum RoverPermissionStatus {
  /// Not yet asked, or asked and soft-denied — the OS prompt can still be
  /// shown again.
  denied,

  /// The user granted everything this platform requires.
  granted,

  /// Denied permanently ("don't ask again" / repeated denial). The OS will
  /// no longer show its own prompt; only the Settings app can change this.
  permanentlyDenied,

  /// Blocked by a device policy (e.g. parental controls, MDM) rather than by
  /// the user. Settings will not help.
  restricted;

  bool get isGranted => this == RoverPermissionStatus.granted;
  bool get canPromptDirectly => this == RoverPermissionStatus.denied;
}

/// Wraps `permission_handler` behind ROVEROS's own vocabulary, so the rest of
/// the app never has to know which OS permissions Bluetooth happens to map to
/// on a given platform and SDK version.
///
/// Android's Bluetooth permissions changed shape at API 31 (BLUETOOTH_SCAN /
/// BLUETOOTH_CONNECT replacing ACCESS_FINE_LOCATION); this asks for all of
/// them and lets the platform ignore whichever don't apply to the running
/// device, rather than branching on SDK version here.
class BluetoothPermissionService {
  const BluetoothPermissionService();

  bool get _isRuntimeGated => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  List<Permission> get _permissions {
    if (kIsWeb) return const [];
    if (Platform.isAndroid) {
      return const [
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
        Permission.locationWhenInUse,
      ];
    }
    if (Platform.isIOS) return const [Permission.bluetooth];
    return const [];
  }

  /// Current status without prompting.
  Future<RoverPermissionStatus> status() async {
    if (!_isRuntimeGated) return RoverPermissionStatus.granted;
    final statuses = await Future.wait(_permissions.map((p) => p.status));
    return _combine(statuses);
  }

  /// Shows the OS permission prompt for whichever permissions are still
  /// undetermined. A no-op, status-only call when already decided.
  Future<RoverPermissionStatus> request() async {
    if (!_isRuntimeGated) return RoverPermissionStatus.granted;
    final result = await _permissions.request();
    return _combine(result.values.toList());
  }

  /// Opens the app's OS settings page, the only way out of
  /// [RoverPermissionStatus.permanentlyDenied].
  Future<bool> openSettings() => openAppSettings();

  RoverPermissionStatus _combine(List<PermissionStatus> statuses) {
    if (statuses.every((s) => s.isGranted || s.isLimited)) {
      return RoverPermissionStatus.granted;
    }
    // A single permanently-denied or restricted permission blocks the whole
    // feature, so it takes priority over a merely "denied" sibling.
    if (statuses.any((s) => s.isPermanentlyDenied)) {
      return RoverPermissionStatus.permanentlyDenied;
    }
    if (statuses.any((s) => s.isRestricted)) {
      return RoverPermissionStatus.restricted;
    }
    return RoverPermissionStatus.denied;
  }
}
