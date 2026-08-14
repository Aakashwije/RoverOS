import '../core/constants/app_config.dart';

/// BLE identity of a vehicle: the GATT service and characteristic(s) its
/// firmware exposes for the wire protocol.
///
/// [writeCharUuid] and [notifyCharUuid] may be equal — some BLE-serial modules
/// (the HM-10/AT-09 family commonly wired to non-BLE MCUs) expose a single
/// characteristic that both accepts writes and emits notifications, unlike
/// the car's split Nordic UART RX/TX pair. `BluetoothTransport` handles that
/// case automatically: both lookups simply resolve to the same characteristic.
class BleProfile {
  const BleProfile({
    required this.serviceUuid,
    required this.writeCharUuid,
    required this.notifyCharUuid,
  });

  final String serviceUuid;
  final String writeCharUuid;
  final String notifyCharUuid;
}

/// Which physical vehicle ROVEROS is currently driving.
///
/// Everything vehicle-shaped — the BLE profile to scan/connect with, which
/// device names look like "mine", what name a freshly-paired device gets —
/// is attached here so the rest of the app only ever asks "what kind is
/// active" once, in [lib/models/settings.dart]'s `AppSettings.vehicleKind`.
enum VehicleKind {
  /// The Optimus OP0148 ESP32 4WD car — the original, unmodified target.
  /// Speaks the Nordic UART Service, the de-facto BLE serial profile ESP32
  /// Arduino sketches expose.
  car(
    label: 'Car',
    defaultVehicleName: 'ESP32-CAR',
    nameHints: ['ESP32', 'ROVER', 'OPTIMUS', 'CAR', 'BT'],
    bleProfile: BleProfile(
      serviceUuid: AppConfig.nordicUartService,
      writeCharUuid: AppConfig.nordicUartRx,
      notifyCharUuid: AppConfig.nordicUartTx,
    ),
  ),

  /// The Optimus Spiderbot — an Arduino Nano quadruped with an add-on
  /// BLE-serial module (the Nano has no radio of its own).
  ///
  /// The UUIDs below are the common defaults for the HM-10/AT-09 family of
  /// modules, not a confirmed value for this specific kit — verify against
  /// the actual module once it's wired up (e.g. with a generic BLE scanner
  /// app) and update these if it advertises something different.
  spider(
    label: 'Spider',
    defaultVehicleName: 'NANO-SPIDER',
    nameHints: ['SPIDER', 'HM-10', 'HMSOFT', 'AT-09', 'MLT-BT'],
    bleProfile: BleProfile(
      serviceUuid: '0000ffe0-0000-1000-8000-00805f9b34fb',
      writeCharUuid: '0000ffe1-0000-1000-8000-00805f9b34fb',
      notifyCharUuid: '0000ffe1-0000-1000-8000-00805f9b34fb',
    ),
  );

  const VehicleKind({
    required this.label,
    required this.defaultVehicleName,
    required this.nameHints,
    required this.bleProfile,
  });

  final String label;
  final String defaultVehicleName;

  /// Advertised-name prefixes that sort a scan result to the top as "likely
  /// this vehicle" — a soft heuristic, not a scan filter.
  final List<String> nameHints;

  final BleProfile bleProfile;

  static VehicleKind fromName(String? name) =>
      values.firstWhere((k) => k.name == name, orElse: () => car);
}
