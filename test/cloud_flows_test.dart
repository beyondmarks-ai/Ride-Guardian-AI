import 'package:bike_safety_ai/controllers/ride_controller.dart';
import 'package:bike_safety_ai/models/ride_models.dart';
import 'package:bike_safety_ai/services/app_backend.dart';
import 'package:bike_safety_ai/services/auth_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class TestUser extends Fake implements User {
  TestUser({this.emailVerified = false, this.phoneNumber});
  @override
  final bool emailVerified;
  @override
  final String? phoneNumber;
  @override
  Future<void> reload() async {}
  @override
  Future<String?> getIdToken([bool forceRefresh = false]) async =>
      'verified-phone-token';
}

class TestAuth extends Fake implements FirebaseAuth {
  TestAuth(this.currentUser);
  @override
  final User? currentUser;
}

void main() {
  test('phone-only user remains signed in and sends an API token', () async {
    final auth = AuthService(
      auth: TestAuth(TestUser(phoneNumber: '+919999999999')),
    );
    expect(await auth.isSignedIn(), isTrue);
    expect(await auth.accessToken(), 'verified-phone-token');
    expect(AuthService.hasVerifiedIdentity(TestUser()), isFalse);
    expect(
      AuthService.hasVerifiedIdentity(TestUser(emailVerified: true)),
      isTrue,
    );
  });

  test('private API errors are not returned as empty family lists', () async {
    final backend = AppBackend(
      client: MockClient(
        (_) async => http.Response('{"message":"Denied"}', 403),
      ),
    );
    await expectLater(
      backend.fetchSharedRiders(),
      throwsA(isA<BackendException>()),
    );
    backend.dispose();
  });

  test(
    'SOS failure stays unconfirmed and retry uses the same request ID',
    () async {
      final ids = <String>[];
      var fail = true;
      final backend = AppBackend(
        client: MockClient((request) async {
          ids.add(request.body);
          return fail
              ? http.Response('{}', 503)
              : http.Response('{"saved":true,"guardians":0}', 202);
        }),
      );
      final controller = RideController(backend: backend);
      controller.route.add(
        RidePoint(
          latitude: 17.91,
          longitude: 77.50,
          speedKph: 0,
          recordedAt: DateTime.now(),
        ),
      );
      await controller.sendSos();
      expect(controller.emergencySent, isFalse);
      expect(controller.emergencyMessage, contains('not confirmed'));
      fail = false;
      await controller.sendSos();
      expect(controller.emergencySent, isTrue);
      expect(controller.emergencyMessage, contains('no guardian'));
      final idPattern = RegExp(r'"requestId":"([^"]+)"');
      expect(
        idPattern.firstMatch(ids[0])!.group(1),
        idPattern.firstMatch(ids[1])!.group(1),
      );
      controller.dispose();
    },
  );

  test('hospital failures surface an actionable error', () async {
    final backend = AppBackend(
      client: MockClient(
        (_) async => http.Response('{"message":"Maps unavailable"}', 503),
      ),
    );
    await expectLater(
      backend.nearbyHospitals(17.91, 77.50),
      throwsA(isA<BackendException>()),
    );
    backend.dispose();
  });
}
