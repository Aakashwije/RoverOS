import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/bluetooth_permission_service.dart';

final bluetoothPermissionServiceProvider = Provider<BluetoothPermissionService>(
  (ref) => const BluetoothPermissionService(),
);

/// The current, last-checked Bluetooth permission state.
///
/// Kept separate from [LinkState][../../models/connection_state.dart]: this is
/// a pre-flight gate the Connection screen checks before it ever tries to
/// touch the radio, whereas `ConnectionStatus.permissionRequired` is a
/// reactive state raised when the transport itself hits an OS-level denial
/// mid-operation.
final bluetoothPermissionProvider =
    AsyncNotifierProvider<BluetoothPermissionController, RoverPermissionStatus>(
      BluetoothPermissionController.new,
    );

class BluetoothPermissionController
    extends AsyncNotifier<RoverPermissionStatus> {
  BluetoothPermissionService get _service =>
      ref.read(bluetoothPermissionServiceProvider);

  @override
  Future<RoverPermissionStatus> build() => _service.status();

  /// Re-reads status without prompting — used on screen entry and when the
  /// app resumes, in case the user changed it from Settings.
  Future<RoverPermissionStatus> refresh() async {
    final status = await _service.status();
    state = AsyncData(status);
    return status;
  }

  /// Shows the OS permission prompt.
  Future<RoverPermissionStatus> request() async {
    final status = await _service.request();
    state = AsyncData(status);
    return status;
  }
}
