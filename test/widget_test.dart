import 'package:bike_safety_ai/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders the safety dashboard and master control', (
    tester,
  ) async {
    await tester.pumpWidget(
      const RideGuardianApp(authenticationEnabled: false),
    );
    await tester.pump();

    expect(find.text('RideGuardian AI'), findsNothing);
    expect(find.text('Good evening, Rider'), findsOneWidget);
    expect(find.text('Start ride safety systems'), findsOneWidget);
    expect(find.text('Safety score'), findsOneWidget);
  });
}
