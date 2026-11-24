import 'package:flutter/material.dart';

import 'app_state.dart';
import 'screens/home_screen.dart';
import 'screens/onboarding_screen.dart';
import 'theme.dart';
import 'widgets/common.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const FareeqApp());
}

class FareeqApp extends StatefulWidget {
  const FareeqApp({super.key});

  @override
  State<FareeqApp> createState() => _FareeqAppState();
}

class _FareeqAppState extends State<FareeqApp> {
  final _app = AppState();
  late final Future<void> _ready = _app.init();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Fareeq',
      debugShowCheckedModeBanner: false,
      theme: Brand.theme(),
      home: FutureBuilder<void>(
        future: _ready,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const _Splash();
          }
          return ListenableBuilder(
            listenable: _app,
            builder: (context, _) => AnimatedSwitcher(
              duration: const Duration(milliseconds: 600),
              child: _app.profile == null
                  ? OnboardingScreen(key: const ValueKey('onb'), app: _app)
                  : HomeScreen(key: const ValueKey('home'), app: _app),
            ),
          );
        },
      ),
    );
  }
}

class _Splash extends StatelessWidget {
  const _Splash();

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Container(
      decoration: const BoxDecoration(gradient: Brand.gradient),
      child: const Center(child: RadarHero(size: 200)),
    ),
  );
}
