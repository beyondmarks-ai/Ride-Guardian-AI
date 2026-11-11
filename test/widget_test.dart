import 'package:bike_safety_ai/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders the safety dashboard and master control', (
    tester,
  ) async {
    await tester.pumpWidget(
      const RideGuardianApp(
        authenticationEnabled: false,
        mapTilesEnabled: false,
      ),
    );
    await tester.pump();

    expect(find.text('RideGuardian AI'), findsNothing);
    expect(find.text('Good evening, Rider'), findsOneWidget);
    expect(find.text('Check helmet to start ride'), findsOneWidget);
    expect(find.text('Safety score'), findsOneWidget);

    await tester.tap(find.text('Family'));
    await tester.pumpAndSettle();

    expect(find.text('Good evening, Rider'), findsNothing);
    expect(find.text('I am a guardian'), findsOneWidget);
    await tester.tap(find.text('I am a guardian'));
    await tester.pumpAndSettle();
    expect(find.text('Guardian dashboard'), findsOneWidget);
    expect(find.text('Connect your first rider'), findsOneWidget);
    // Return to the rider's Family page to verify the project identity.
    await tester.tap(find.byTooltip('Show menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Switch to rider'));
    await tester.pumpAndSettle();
    await tester.drag(find.text('Your guardians'), const Offset(0, -550));
    await tester.pumpAndSettle();
    expect(find.text('Project team'), findsOneWidget);
    expect(find.text('Ayesha'), findsOneWidget);
    expect(find.text('3GN23CS011'), findsOneWidget);
    expect(find.text('Mahvin Ashfaque'), findsOneWidget);
    expect(find.text('3GN23CS035'), findsOneWidget);
    expect(find.text('Iqra Mahveen'), findsOneWidget);
    expect(find.text('3GN23CS029'), findsOneWidget);
    expect(find.text('Prof. Gururaj S.'), findsOneWidget);
  });
}
