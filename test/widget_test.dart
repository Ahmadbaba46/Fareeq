import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:fareeq/app_state.dart';
import 'package:fareeq/data/demo_repository.dart';
import 'package:fareeq/models.dart';
import 'package:fareeq/theme.dart';
import 'package:fareeq/screens/home_screen.dart';
import 'package:fareeq/screens/onboarding_screen.dart';
import 'package:fareeq/screens/map_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('onboarding renders and advances', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final app = AppState()..repo = DemoRepository();
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

  testWidgets('map: SOS, meeting point, lock, guide line', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final app = AppState();
    await tester.runAsync(app.init);
    await app.saveProfile(Profile(name: 'Ahmad', colorIndex: 1));
    final g = Group(code: 'TESTCODE', name: 'Test trip');
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: MapScreen(app: app, group: g),
      ),
    );
    await tester.pump(const Duration(seconds: 3));
    expect(find.text('Test trip'), findsOneWidget);
    expect(find.text('Amina'), findsWidgets);

    // tap a friend in the list -> direction card appears
    await tester.tap(find.text('Amina').first);
    await tester.pump(const Duration(seconds: 1));
    expect(find.byIcon(Icons.near_me_rounded), findsOneWidget);

    // SOS
    await tester.tap(find.text('SOS'));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Send SOS to your group?'), findsOneWidget);
    await tester.tap(find.text('Send SOS'));
    await tester.pump(const Duration(seconds: 3));
    expect(find.text('Cancel'), findsWidgets);

    // meeting point via repo, shows in sheet
    await app.repo.setMeeting(
      g.code,
      Meeting(
        position: const LatLng(41.01, 28.98),
        label: 'Hotel lobby',
        by: 'Ahmad',
      ),
    );
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('Hotel lobby'), findsWidgets);

    // quick message
    await tester.tap(find.byIcon(Icons.chat_bubble_rounded));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Quick message'), findsOneWidget);
    await tester.tap(find.text('Running late'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 3));
    expect(find.textContaining('Running late'), findsWidgets);

    // owner menu is offered, and locking updates the header
    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Lock group (no new joins)'), findsOneWidget);
    expect(find.text('End trip'), findsOneWidget);
    await tester.tap(find.text('Lock group (no new joins)'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(find.byIcon(Icons.lock_rounded), findsWidgets);
    final menu = tester
        .widget<PopupMenuButton<String>>(find.byType(PopupMenuButton<String>))
        .onSelected!;
    menu('trails');
    menu('straggler');
    await tester.pump(const Duration(seconds: 3));
    expect(app.straggler, isFalse);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('dark mode renders; profile emoji saves', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final app = AppState();
    await tester.runAsync(app.init);
    await app.saveProfile(Profile(name: 'Ahmad', colorIndex: 1));
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: Brand.theme(),
        darkTheme: Brand.darkTheme(),
        themeMode: ThemeMode.dark,
        home: HomeScreen(app: app),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.byIcon(Icons.edit_rounded));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Appearance'), findsOneWidget);
    await tester.tap(find.text('🦁'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Save'));
    await tester.pump();
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pump(const Duration(seconds: 1));
    expect(app.profile!.emoji, '🦁');

    // map screen in dark mode
    final g = Group(code: 'DARKCODE', name: 'Night trip');
    await tester.pumpWidget(
      MaterialApp(
        theme: Brand.theme(),
        darkTheme: Brand.darkTheme(),
        themeMode: ThemeMode.dark,
        home: MapScreen(app: app, group: g),
      ),
    );
    await tester.pump(const Duration(seconds: 3));
    expect(find.text('Night trip'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });
}
