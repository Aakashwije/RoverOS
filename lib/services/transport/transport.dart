import '../../models/vehicle.dart';

enum TransportKind {
  bluetooth('Bluetooth'),
  mock('Mock vehicle'),
  wifi('Wi-Fi');

  const TransportKind(this.label);

  final String label;
}

/// Link lifecycle as reported by a transport, independent of any UI state.
enum TransportStatus {
  idle,
  scanning,
  connecting,
  connected,
  disconnected,
  failed,
}

/// Why a transport operation failed, in terms the UI can turn into an action.
enum TransportFailure {
  permissionDenied(
    'Bluetooth permission required',
    'ROVEROS needs Bluetooth permission to find and connect to your vehicle.',
  ),
  adapterOff(
    'Bluetooth is off',
    'Turn on Bluetooth to connect to the vehicle.',
  ),
  unsupported(
    'Bluetooth unavailable',
    'This device does not support Bluetooth Low Energy.',
  ),
  deviceNotFound(
    'Vehicle not found',
    'The saved vehicle did not respond. Make sure it is powered on and in range.',
  ),
  connectionFailed(
    'Could not connect',
    'The vehicle refused the connection. Power-cycle it and try again.',
  ),
  serviceNotFound(
    'Incompatible vehicle',
    'This device does not expose the ROVEROS serial service.',
  ),
  writeFailed(
    'Command not delivered',
    'The vehicle did not accept the last command.',
  ),
  disconnected(
    'Link lost',
    'The vehicle disconnected. Its safety timeout will stop the motors.',
  );

  const TransportFailure(this.title, this.message);

  /// Short headline, e.g. for a banner title.
  final String title;

  /// Full sentence including what the user should do about it.
  final String message;
}

/// Thrown by transports instead of raw platform errors, so the UI never has to
/// interpret a plugin-specific exception.
class TransportException implements Exception {
  const TransportException(this.failure, {this.cause});

  final TransportFailure failure;
  final Object? cause;

  String get title => failure.title;
  String get message => failure.message;

  @override
  String toString() => 'TransportException(${failure.name}: $message)';
}

/// The single interface every link speaks.
///
/// The UI and the command layer depend only on this, which is what lets mock
/// mode, Bluetooth and a future Wi-Fi link be swapped without touching a
/// widget. Frames in and out are plain strings; framing and parsing belong to
/// `car_protocol.dart`.
abstract class Transport {
  TransportKind get kind;

  /// Current lifecycle state, replayed to new listeners.
  Stream<TransportStatus> get status;

  TransportStatus get currentStatus;

  /// Identifier of the connected device, when connected.
  String? get connectedDeviceId;

  /// Emits the accumulating device list while a scan runs.
  ///
  /// Implementations must stop scanning when the returned stream is cancelled.
  Stream<List<DiscoveredVehicle>> scan({Duration? timeout});

  Future<void> stopScan();

  /// Connects to [deviceId], or to the last known device when omitted.
  ///
  /// Throws [TransportException] on failure.
  Future<void> connect({String? deviceId});

  Future<void> disconnect();

  /// Sends one complete frame, terminator included.
  Future<void> send(String command);

  /// Complete inbound frames, already split on the protocol terminator.
  Stream<String> subscribe();

  /// Current link RSSI in dBm, or `null` when the transport cannot measure it.
  Future<int?> readRssi();

  Future<void> dispose();
}
