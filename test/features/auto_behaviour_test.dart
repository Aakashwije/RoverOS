import 'package:flutter_test/flutter_test.dart';
import 'package:roveros/features/auto/auto_behaviour.dart';
import 'package:roveros/models/commands.dart';

/// The Auto screen collapses two firmware knobs into one choice. This checks
/// the collapse is total — every combination the controller can produce maps
/// to exactly one segment, including the ones that should not happen.
void main() {
  test('avoiding wins over any scan state', () {
    for (final scan in ScanMode.values) {
      expect(
        AutoBehaviour.of(DriveMode.obstacleAvoidance, scan),
        AutoBehaviour.avoid,
        reason: 'obstacle avoidance with scan ${scan.name}',
      );
    }
  });

  test('a running scan in manual mode reads as scanning', () {
    expect(
      AutoBehaviour.of(DriveMode.manual, ScanMode.auto),
      AutoBehaviour.scan,
    );
    expect(
      AutoBehaviour.of(DriveMode.manual, ScanMode.once),
      AutoBehaviour.scan,
    );
  });

  test('manual with no scan is manual', () {
    expect(
      AutoBehaviour.of(DriveMode.manual, ScanMode.off),
      AutoBehaviour.manual,
    );
  });

  test('every drive/scan combination resolves to a segment', () {
    for (final mode in DriveMode.values) {
      for (final scan in ScanMode.values) {
        expect(AutoBehaviour.of(mode, scan), isA<AutoBehaviour>());
      }
    }
  });

  test('only obstacle avoidance asks before it starts', () {
    expect(
      AutoBehaviour.values.where((b) => b.requiresConfirmation),
      [AutoBehaviour.avoid],
    );
  });

  test('every behaviour has copy for the segment and the caption', () {
    for (final behaviour in AutoBehaviour.values) {
      expect(behaviour.label, isNotEmpty);
      expect(behaviour.description, isNotEmpty);
      expect(behaviour.summary, isNotEmpty);
    }
  });
}
