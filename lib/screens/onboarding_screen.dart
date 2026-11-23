import 'package:flutter/material.dart';
import '../app_state.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/common.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key, required this.app});
  final AppState app;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _pages = PageController();
  final _name = TextEditingController();
  int _page = 0;
  int _color = 0;

  static const _slides = [
    ('Travel together,\nstay together', 'Create a group and everyone you travel with appears on one live map.'),
    ('No more\n"where are you?"', 'See each other move in real time. No calls, no texts, no data plan for maps.'),
    ('You are in control', 'Share only while the app is open, and pause whenever you like.'),
  ];

  @override
  void dispose() {
    _pages.dispose();
    _name.dispose();
    super.dispose();
  }

  void _next() {
    if (_page < 3) {
      _pages.nextPage(
          duration: const Duration(milliseconds: 500),
          curve: Curves.easeOutCubic);
    } else if (_name.text.trim().isNotEmpty) {
      widget.app.saveProfile(
          Profile(name: _name.text.trim(), colorIndex: _color));
    }
  }

  @override
  Widget build(BuildContext context) {
    final last = _page == 3;
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: Brand.gradient),
        child: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: PageView(
                  controller: _pages,
                  onPageChanged: (i) => setState(() => _page = i),
                  children: [
                    for (final s in _slides) _Slide(title: s.$1, body: s.$2),
                    _NamePage(
                      controller: _name,
                      color: _color,
                      onColor: (i) => setState(() => _color = i),
                      onChanged: () => setState(() {}),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                child: Row(
                  children: [
                    Row(
                      children: [
                        for (var i = 0; i < 4; i++)
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 300),
                            margin: const EdgeInsets.only(right: 6),
                            width: i == _page ? 26 : 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: i == _page
                                  ? Colors.white
                                  : Colors.white38,
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                      ],
                    ),
                    const Spacer(),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 350),
                      curve: Curves.easeOutBack,
                      width: last ? 170 : 64,
                      height: 64,
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: Brand.ink,
                          minimumSize: const Size(64, 64),
                          padding: EdgeInsets.zero,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(32)),
                        ),
                        onPressed: last && _name.text.trim().isEmpty
                            ? null
                            : _next,
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 250),
                          child: last
                              ? const Text("Let's go",
                                  key: ValueKey('go'),
                                  maxLines: 1,
                                  softWrap: false)
                              : const Icon(Icons.arrow_forward_rounded,
                                  key: ValueKey('arrow')),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Slide extends StatelessWidget {
  const _Slide({required this.title, required this.body});
  final String title, body;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Center(child: RadarHero()),
          const SizedBox(height: 36),
          Text(title,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 34,
                  height: 1.1,
                  fontWeight: FontWeight.w800)),
          const SizedBox(height: 14),
          Text(body,
              style: const TextStyle(
                  color: Colors.white70, fontSize: 16, height: 1.4)),
        ],
      ),
    );
  }
}

class _NamePage extends StatelessWidget {
  const _NamePage({
    required this.controller,
    required this.color,
    required this.onColor,
    required this.onChanged,
  });
  final TextEditingController controller;
  final int color;
  final ValueChanged<int> onColor;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 60),
          Center(
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: .6, end: 1),
              duration: const Duration(milliseconds: 600),
              curve: Curves.elasticOut,
              builder: (_, v, child) => Transform.scale(scale: v, child: child),
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: const BoxDecoration(
                    shape: BoxShape.circle, color: Colors.white),
                child: Avatar(
                    name: controller.text.isEmpty ? '?' : controller.text,
                    colorIndex: color,
                    size: 110),
              ),
            ),
          ),
          const SizedBox(height: 36),
          const Text('What should your\nfriends call you?',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 32,
                  height: 1.1,
                  fontWeight: FontWeight.w800)),
          const SizedBox(height: 20),
          TextField(
            controller: controller,
            textCapitalization: TextCapitalization.words,
            onChanged: (_) => onChanged(),
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 18),
            decoration: const InputDecoration(hintText: 'Your name'),
          ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (var i = 0; i < Brand.memberColors.length; i++)
                GestureDetector(
                  onTap: () => onColor(i),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: Brand.memberColors[i],
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: Colors.white, width: i == color ? 4 : 0),
                    ),
                    child: i == color
                        ? const Icon(Icons.check, color: Colors.white, size: 18)
                        : null,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
