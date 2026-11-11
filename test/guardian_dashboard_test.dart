import 'dart:async';
import 'package:bike_safety_ai/controllers/ride_controller.dart';
import 'package:bike_safety_ai/models/ride_models.dart';
import 'package:bike_safety_ai/screens/guardian_dashboard.dart';
import 'package:bike_safety_ai/screens/hospital_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('guardian shows shared speed and hides it when stale', (
    tester,
  ) async {
    final controller = RideController();
    controller.backendOnline = true;
    controller.sharedRiders.add(
      const FamilyMember(
        name: 'Test Rider',
        initials: 'TR',
        relationship: 'Rider',
        userId: 'rider',
      ),
    );
    controller.watchedRider = SharedRiderStatus(
      riderId: 'rider',
      name: 'Test Rider',
      status: 'RIDING',
      updatedAt: DateTime.now(),
      speedKph: 42,
      latitude: 17.91,
      longitude: 77.50,
    );
    Widget page() => MaterialApp(
      home: GuardianDashboard(controller: controller, mapTilesEnabled: false),
    );
    await tester.pumpWidget(page());
    await tester.pumpAndSettle();
    expect(find.text('42'), findsOneWidget);
    expect(find.text('Ride in progress'), findsOneWidget);
    controller.watchedRider = SharedRiderStatus(
      riderId: 'rider',
      name: 'Test Rider',
      status: 'RIDING',
      updatedAt: DateTime.now().subtract(const Duration(minutes: 2)),
      speedKph: 42,
    );
    await tester.pumpWidget(page());
    await tester.pumpAndSettle();
    expect(find.text('42'), findsNothing);
    expect(find.text('Updates unavailable'), findsOneWidget);
    controller.dispose();
  });

  testWidgets(
    'hospitals open immediately, show results, and recover after error',
    (tester) async {
      var result = Completer<List<NearbyPlace>>();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showHospitalSearch(
                  context,
                  title: 'Hospitals near you',
                  search: () => result.future,
                ),
                child: const Text('Hospitals'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Hospitals'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Hospitals near you'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      result.completeError(StateError('Location unavailable'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Location unavailable'), findsOneWidget);
      result = Completer<List<NearbyPlace>>();
      await tester.tap(find.text('Try again'));
      await tester.pump();
      result.complete([
        const NearbyPlace(
          name: 'Test Hospital',
          distanceKm: 2,
          latitude: 17.91,
          longitude: 77.50,
        ),
      ]);
      await tester.pumpAndSettle();
      expect(find.text('Test Hospital'), findsOneWidget);
    },
  );
}
