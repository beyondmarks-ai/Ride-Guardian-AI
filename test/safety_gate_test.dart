import 'dart:convert';
import 'dart:typed_data';
import 'package:bike_safety_ai/controllers/ride_controller.dart';
import 'package:bike_safety_ai/services/app_backend.dart';
import 'package:bike_safety_ai/services/accident_detector.dart';
import 'package:bike_safety_ai/services/ride_monitor.dart';
import 'package:bike_safety_ai/models/ride_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image_picker/image_picker.dart';

class FakeMonitor extends RideMonitor {
  int starts = 0;
  void Function(MotionSample)? motion;
  @override
  Future<void> start({
    required void Function(Position) onPosition,
    required void Function(MotionSample) onMotion,
  }) async {
    starts++;
    motion = onMotion;
  }

  @override
  Future<void> stop() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'ride gate rejects absent, negative, cancelled and expired checks',
    () async {
      final monitor = FakeMonitor();
      var detected = false;
      var cancelled = false;
      final controller = RideController(
        monitor: monitor,
        captureHelmet: () async =>
            cancelled ? null : XFile.fromData(Uint8List.fromList([1, 2])),
        backend: AppBackend(
          client: MockClient(
            (_) async => http.Response(
              jsonEncode({
                'detected': detected,
                'confidence': 99,
                'reason': 'Camera verdict',
                'strapStatus': 'not_visible',
              }),
              200,
            ),
          ),
        ),
      );
      await controller.startRide();
      expect(monitor.starts, 0);
      await controller.runHelmetCheck();
      controller.confirmHelmetStrap(true);
      await controller.startRide();
      expect(monitor.starts, 0); // high confidence in absence must not pass
      detected = true;
      await controller.runHelmetCheck();
      await controller.startRide();
      expect(monitor.starts, 0); // strap confirmation still required
      controller.confirmHelmetStrap(true);
      controller.helmetVerifiedAt = DateTime.now().subtract(
        const Duration(minutes: 6),
      );
      await controller.startRide();
      expect(monitor.starts, 0);
      await controller.runHelmetCheck();
      controller.confirmHelmetStrap(true);
      cancelled = true;
      await controller.runHelmetCheck();
      await controller.startRide();
      expect(monitor.starts, 0);
      cancelled = false;
      await controller.runHelmetCheck();
      controller.confirmHelmetStrap(true);
      await controller.startRide();
      expect(monitor.starts, 1);
      expect(controller.isRiding, isTrue);
      await controller.stopRide();
      expect(controller.canStartRide, isFalse);
      controller.dispose();
    },
  );

  test('service failure leaves helmet unavailable and ride blocked', () async {
    final controller = RideController(
      monitor: FakeMonitor(),
      captureHelmet: () async => XFile.fromData(Uint8List(1)),
      backend: AppBackend(
        client: MockClient((_) async => http.Response('{}', 503)),
      ),
    );
    await controller.runHelmetCheck();
    expect(controller.helmetState, HelmetCheckState.unavailable);
    expect(controller.helmetMessage, contains('503'));
    expect(controller.canStartRide, isFalse);
    controller.dispose();
  });

  test(
    'vibration window rejects road noise and isolated bump; detects repeated peaks with cooldown',
    () {
      final detector = AccidentDetector();
      final now = DateTime(2026);
      String? sample(int ms, double a, [double r = 0]) => detector.add(
        MotionSample(
          acceleration: a,
          rotation: r,
          recordedAt: now.add(Duration(milliseconds: ms)),
        ),
        speedKph: 20,
      );
      for (int i = 0; i < 100; i++) {
        expect(sample(i * 20, 4), isNull);
      }
      expect(sample(2100, 20), isNull);
      for (int i = 0; i < 7; i++) {
        expect(sample(6000 + i * 220, 16), isNull);
      }
      expect(sample(7540, 16), contains('vibrations'));
      expect(sample(7800, 50, 4), isNull);
      expect(sample(70000, 50, 4), contains('impact'));
    },
  );

  testWidgets(
    'suspected accident countdown can cancel and sends SOS only on expiry',
    (tester) async {
      final monitor = FakeMonitor();
      int alerts = 0;
      final controller = RideController(
        monitor: monitor,
        backend: AppBackend(
          client: MockClient((request) async {
            if (request.url.path.endsWith('/emergency')) alerts++;
            return http.Response('{"saved":true,"guardians":1}', 202);
          }),
        ),
      );
      controller.helmetState = HelmetCheckState.detected;
      controller.helmetVerifiedAt = DateTime.now();
      controller.confirmHelmetStrap(true);
      await controller.startRide();
      final now = DateTime.now();
      monitor.motion!(
        MotionSample(acceleration: 50, rotation: 4, recordedAt: now),
      );
      expect(controller.emergencyCountdown, 20);
      controller.cancelEmergency();
      await tester.pump(const Duration(seconds: 21));
      expect(alerts, 0);
      controller.route.add(
        RidePoint(
          latitude: 17.91,
          longitude: 77.50,
          speedKph: 0,
          recordedAt: now,
        ),
      );
      // The second trigger is beyond the detector's cooldown.
      monitor.motion!(
        MotionSample(
          acceleration: 50,
          rotation: 4,
          recordedAt: now.add(const Duration(seconds: 65)),
        ),
      );
      expect(controller.emergencyCountdown, 20);
      await tester.pump(const Duration(seconds: 21));
      await tester.pump();
      expect(alerts, 1);
      controller.dispose();
    },
  );
}
