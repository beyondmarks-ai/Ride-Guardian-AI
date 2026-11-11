import 'dart:convert';
import 'package:bike_safety_ai/screens/role_screen.dart';
import 'package:bike_safety_ai/screens/auth_screen.dart';
import 'package:bike_safety_ai/screens/sharing_requests.dart';
import 'package:bike_safety_ai/controllers/auth_controller.dart';
import 'package:bike_safety_ai/controllers/ride_controller.dart';
import 'package:bike_safety_ai/services/app_backend.dart';
import 'package:bike_safety_ai/models/ride_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  testWidgets('first role choice leads to guardian-labelled sign in', (
    tester,
  ) async {
    final auth = AuthController()..initializing = false;
    bool? role;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) => role == null
              ? RoleScreen(
                  onSelect: (value) => setState(() {
                    role = value;
                  }),
                )
              : AuthScreen(
                  controller: auth,
                  guardian: role!,
                  onChangeRole: () => setState(() {
                    role = null;
                  }),
                ),
        ),
      ),
    );
    expect(find.text('I am a rider'), findsOneWidget);
    expect(find.text('I am a guardian'), findsOneWidget);
    expect(find.text('Email address'), findsNothing);
    await tester.tap(find.text('I am a guardian'));
    await tester.pumpAndSettle();
    expect(find.text('GUARDIAN ACCOUNT'), findsOneWidget);
    await tester.ensureVisible(find.text('Change role'));
    await tester.tap(find.text('Change role'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('I am a rider'));
    await tester.pumpAndSettle();
    expect(find.text('RIDER ACCOUNT'), findsOneWidget);
    auth.dispose();
  });

  testWidgets('guardian enters rider number and rider grants sharing', (
    tester,
  ) async {
    final sent = <http.Request>[];
    final controller = RideController(
      backend: AppBackend(
        client: MockClient((request) async {
          if (request.method == 'POST') sent.add(request);
          return http.Response(
            request.method == 'POST' ? '{"requested":true}' : '{"items":[]}',
            200,
          );
        }),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(children: [ConnectRiderCard(controller: controller)]),
        ),
      ),
    );
    await tester.enterText(find.byType(TextFormField), '+91 99999 99999');
    await tester.ensureVisible(find.text('Send connection request'));
    await tester.tap(find.text('Send connection request'));
    await tester.pumpAndSettle();
    expect(sent.single.url.path, endsWith('/riders/request'));
    expect(jsonDecode(sent.single.body)['contact'], '+91 99999 99999');
    controller.guardianRequests.add(
      const SharingRequest(
        guardianId: 'guardian',
        guardianContact: '+918888888888',
        contact: '+919999999999',
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: GuardianRequestInbox(controller: controller)),
      ),
    );
    expect(find.textContaining('ride history'), findsOneWidget);
    await tester.tap(find.text('Allow sharing'));
    await tester.pumpAndSettle();
    expect(sent.last.url.path, endsWith('/guardian-requests/respond'));
    expect(jsonDecode(sent.last.body)['action'], 'accept');
    controller.dispose();
  });
}
