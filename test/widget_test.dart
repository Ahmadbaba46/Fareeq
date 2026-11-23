import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:fareeq/app_state.dart';
import 'package:fareeq/data/demo_repository.dart';
import 'package:fareeq/models.dart';
import 'package:fareeq/screens/home_screen.dart';
import 'package:fareeq/screens/onboarding_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('onboarding renders and advances', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final app = AppState()
      ..repo = DemoRepository();
    await tester.pumpWidget(MaterialApp(home: OnboardingScreen(app: app)));
    expect(find.textContaining('Travel together'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.arrow_forward_rounded));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(find.textContaining('where are you'), findsOneWidget);
  });

  testWidgets('home shows demo banner and creates a group', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final app = AppState();
    await tester.runAsync(app.init);
    await app.saveProfile(Profile(name: 'Ahmad', colorIndex: 1));
    await tester.pumpWidget(MaterialApp(home: HomeScreen(app: app)));
    await tester.pump(const Duration(seconds: 1));
    expect(find.textContaining('Demo mode'), findsOneWidget);
    expect(find.text('Ahmad'), findsOneWidget);
    await tester.tap(find.text('New group'));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Name your trip'), findsOneWidget);
    await tester.tapAt(const Offset(10, 10));
    await tester.pump(const Duration(seconds: 1));
    await tester.runAsync(() => app.create('Istanbul'));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Istanbul'), findsOneWidget);
  });
}
