import 'package:flutter/material.dart';

/// The seven groups the settings list is divided into.
///
/// Named here rather than inline in the screen so the sticky selector, the
/// section headers and the scroll targets cannot drift apart — adding a
/// section without giving it a chip becomes a compile error.
enum SettingsCategory {
  vehicle('VEHICLE', Icons.directions_car_rounded),
  controls('CONTROLS', Icons.gamepad_rounded),
  motors('MOTORS', Icons.settings_input_component_rounded),
  sensors('SENSORS', Icons.sensors_rounded),
  lights('LIGHTS', Icons.lightbulb_rounded),
  connection('CONNECTION', Icons.bluetooth_rounded),
  app('APP', Icons.phone_android_rounded);

  const SettingsCategory(this.label, this.icon);

  final String label;
  final IconData icon;
}
