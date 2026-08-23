import 'package:bike_safety_ai/controllers/auth_controller.dart';
import 'package:bike_safety_ai/controllers/ride_controller.dart';
import 'package:bike_safety_ai/models/ride_models.dart';
import 'package:bike_safety_ai/screens/app_shell.dart';
import 'package:bike_safety_ai/screens/auth_screen.dart';
import 'package:bike_safety_ai/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';

void main() {
  testWidgets('generate client walkthrough screenshots', (tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 932));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final controller = RideController();
    _seedClientPreview(controller);
    final frameKey = GlobalKey();

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        home: RepaintBoundary(
          key: frameKey,
          child: AuthScreen(controller: AuthController()),
        ),
      ),
    );
    await tester.pump();
    await _capture(tester, frameKey, '00-secure-sign-in.png');

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        home: RepaintBoundary(
          key: frameKey,
          child: AppShell(
            controller: controller,
            username: 'rakesh@example.com',
          ),
        ),
      ),
    );
    await tester.pump();

    await _capture(tester, frameKey, '01-home-dashboard.png');
    await _openAndCapture(tester, frameKey, 'Live', '02-live-tracking.png');
    await _openAndCapture(tester, frameKey, 'Safety', '03-safety-center.png');
    await _openAndCapture(tester, frameKey, 'Rides', '04-ride-history.png');
    await _openAndCapture(tester, frameKey, 'Family', '05-family-guardian.png');

    final emergencyController = RideController();
    _seedClientPreview(emergencyController);
    emergencyController.emergencyCountdown = 20;
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        home: RepaintBoundary(
          key: frameKey,
          child: AppShell(
            controller: emergencyController,
            username: 'rakesh@example.com',
          ),
        ),
      ),
    );
    await tester.pump();
    await _capture(tester, frameKey, '06-accident-countdown.png');
  });
}

Future<void> _openAndCapture(
  WidgetTester tester,
  GlobalKey frameKey,
  String tab,
  String fileName,
) async {
  await tester.tap(find.text(tab).last);
  await tester.pump();
  await _capture(tester, frameKey, fileName);
}

Future<void> _capture(
  WidgetTester tester,
  GlobalKey frameKey,
  String fileName,
) async {
  await expectLater(
    find.byKey(frameKey),
    matchesGoldenFile('../docs/images/$fileName'),
  );
}

void _seedClientPreview(RideController controller) {
  final now = DateTime(2026, 8, 23, 18, 42);
  controller
    ..backendOnline = true
    ..isRiding = true
    ..startedAt = now.subtract(const Duration(minutes: 28, seconds: 14))
    ..elapsed = const Duration(minutes: 28, seconds: 14)
    ..speedKph = 42
    ..maxSpeedKph = 61
    ..distanceKm = 12.7
    ..safetyScore = 94
    ..helmetState = HelmetCheckState.detected
    ..helmetConfidence = 96.8
    ..currentPosition = Position(
      latitude: 19.07609,
      longitude: 72.87743,
      timestamp: now,
      accuracy: 4.2,
      altitude: 12,
      altitudeAccuracy: 2.1,
      heading: 82,
      headingAccuracy: 3,
      speed: 11.67,
      speedAccuracy: .5,
    )
    ..nearbyHospitals = const [
      NearbyPlace(
        name: 'City Care Hospital',
        distanceKm: 1.4,
        latitude: 19.0821,
        longitude: 72.8812,
      ),
      NearbyPlace(
        name: 'LifeLine Medical Centre',
        distanceKm: 2.3,
        latitude: 19.0712,
        longitude: 72.8661,
      ),
    ]
    ..activeRoute = const RoutePlan(
      destination: NearbyPlace(
        name: 'City Care Hospital',
        distanceKm: 1.4,
        latitude: 19.0821,
        longitude: 72.8812,
      ),
      distanceKm: 1.8,
      durationMinutes: 6,
    );

  controller.events.add(
    RideEvent(
      type: RideEventType.sharpTurn,
      timestamp: now.subtract(const Duration(minutes: 9)),
      value: 2.4,
    ),
  );
  controller.history.addAll([
    RideSummary(
      id: 'preview-1',
      startedAt: now.subtract(const Duration(days: 1)),
      duration: const Duration(minutes: 41, seconds: 18),
      distanceKm: 24.6,
      maxSpeedKph: 67,
      safetyScore: 96,
      eventCount: 1,
    ),
    RideSummary(
      id: 'preview-2',
      startedAt: now.subtract(const Duration(days: 3)),
      duration: const Duration(minutes: 32, seconds: 5),
      distanceKm: 17.2,
      maxSpeedKph: 58,
      safetyScore: 91,
      eventCount: 2,
    ),
    RideSummary(
      id: 'preview-3',
      startedAt: now.subtract(const Duration(days: 6)),
      duration: const Duration(minutes: 53, seconds: 44),
      distanceKm: 31.8,
      maxSpeedKph: 72,
      safetyScore: 88,
      eventCount: 3,
    ),
  ]);
  controller.family.addAll(const [
    FamilyMember(
      name: 'Anita Sharma',
      relationship: 'Guardian',
      initials: 'AS',
      email: 'anita@example.com',
      isOnline: true,
    ),
    FamilyMember(
      name: 'Rahul Sharma',
      relationship: 'Guardian',
      initials: 'RS',
      email: 'rahul@example.com',
    ),
  ]);
  controller.sharedRiders.add(
    const FamilyMember(
      name: 'Aman Sharma',
      relationship: 'Rider sharing with you',
      initials: 'AM',
      userId: 'preview-rider',
      email: 'aman@example.com',
      isOnline: true,
    ),
  );
}
