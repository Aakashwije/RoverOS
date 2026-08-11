import 'package:flutter_test/flutter_test.dart';
import 'package:roveros/core/perception/distance_filter.dart';
import 'package:roveros/core/perception/proximity_gate.dart';
import 'package:roveros/core/perception/radar_field.dart';
import 'package:roveros/models/telemetry.dart';

void main() {
  group('ProximityGate', () {
    test('escalates a safe absolute distance when time-to-contact is critical', () {
      final gate = ProximityGate();
      final now = DateTime(2026, 1, 1);

      final assessment = gate.assess(
        estimate: DistanceEstimate(
          bearingDegrees: 90,
          distanceCm: 80,
          velocityCmPerSecond: -80,
          standardDeviationCm: 2,
          confidenceScore: 0.9,
          sampleCount: 8,
          rawCm: 80,
          wasRejected: false,
          echoRate: 1,
          updatedAt: now,
        ),
        cautionCm: 60,
        dangerCm: 30,
        now: now,
      );

      expect(assessment.status, DistanceStatus.danger);
      expect(assessment.cause, ProximityCause.closingRate);
      expect(assessment.contactSeconds, '1.0');
    });

    test('requires extra clearance before relaxing from danger', () {
      final gate = ProximityGate();
      final now = DateTime(2026, 1, 1);

      ProximityAssessment assess(double distanceCm) => gate.assess(
        estimate: DistanceEstimate(
          bearingDegrees: 90,
          distanceCm: distanceCm,
          velocityCmPerSecond: 0,
          standardDeviationCm: 2,
          confidenceScore: 0.9,
          sampleCount: 8,
          rawCm: distanceCm.round(),
          wasRejected: false,
          echoRate: 1,
          updatedAt: now,
        ),
        cautionCm: 60,
        dangerCm: 30,
        now: now,
      );

      expect(assess(29).status, DistanceStatus.danger);
      expect(assess(34).status, DistanceStatus.danger);
      expect(assess(40).status, DistanceStatus.caution);
    });
  });

  group('RadarField', () {
    test('recommends the centre gap between two close side returns', () {
      final now = DateTime(2026, 1, 1);
      final analysis = RadarField.analyse(
        samples: {
          45: RadarSample(angle: 45, distanceCm: 25, takenAt: now),
          90: RadarSample(angle: 90, distanceCm: 120, takenAt: now),
          135: RadarSample(angle: 135, distanceCm: 25, takenAt: now),
        },
        clearanceCm: 60,
        referenceBearing: 90,
        now: now,
      );

      expect(analysis.hasData, isTrue);
      expect(analysis.recommended, isNotNull);
      expect(analysis.recommended!.headingDegrees, 90);
      expect(analysis.recommended!.startDegrees, lessThan(90));
      expect(analysis.recommended!.endDegrees, greaterThan(90));
    });
  });
}
