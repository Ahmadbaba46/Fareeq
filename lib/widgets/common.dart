import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import '../models.dart';
import '../theme.dart';

/// Fades + slides its child in after [delay]. Used for staggered lists.
class FadeSlide extends StatefulWidget {
  const FadeSlide({super.key, required this.child, this.delay = Duration.zero});
  final Widget child;
  final Duration delay;

  @override
  State<FadeSlide> createState() => _FadeSlideState();
}

class _FadeSlideState extends State<FadeSlide> {
  Timer? _t;
  bool _show = false;

  @override
  void initState() {
    super.initState();
    if (widget.delay == Duration.zero) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _show = true);
      });
    } else {
      _t = Timer(widget.delay, () {
        if (mounted) setState(() => _show = true);
      });
    }
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: _show ? 1 : 0,
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeOut,
      child: AnimatedSlide(
        offset: _show ? Offset.zero : const Offset(0, .15),
        duration: const Duration(milliseconds: 600),
        curve: Curves.easeOutCubic,
        child: widget.child,
      ),
    );
  }
}

class Avatar extends StatelessWidget {
  const Avatar({super.key, required this.name, required this.colorIndex, this.size = 44});
  final String name;
  final int colorIndex;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = Brand.memberColors[colorIndex % Brand.memberColors.length];
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [c, Color.lerp(c, Colors.black, .25)!],
        ),
      ),
      child: Text(
        name.isEmpty ? '?' : String.fromCharCode(name.runes.first).toUpperCase(),
        style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            fontSize: size * .42),
      ),
    );
  }
}

/// Map marker: avatar with a pulsing ring (ring is steady if member is stale).
class PulseMarker extends StatefulWidget {
  const PulseMarker({super.key, required this.member});
  final Member member;

  @override
  State<PulseMarker> createState() => _PulseMarkerState();
}

class _PulseMarkerState extends State<PulseMarker>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1800))
    ..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.member;
    final color = m.sos
        ? Colors.red
        : Brand.memberColors[m.colorIndex % Brand.memberColors.length];
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final t = (m.isLive || m.sos) ? _c.value : 0.0;
        return Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          children: [
            if (m.isLive || m.sos)
              Container(
                width: 40 + (m.sos ? 70 : 50) * t,
                height: 40 + (m.sos ? 70 : 50) * t,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color.withValues(alpha: .35 * (1 - t)),
                ),
              ),
            Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withValues(alpha: .25),
                      blurRadius: 8,
                      offset: const Offset(0, 3))
                ],
              ),
              child: Opacity(
                opacity: m.isLive ? 1 : .55,
                child: Avatar(name: m.name, colorIndex: m.colorIndex, size: 38),
              ),
            ),
            Positioned(
              bottom: 0,
              child: Transform.translate(
                offset: const Offset(0, 4),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: m.sos ? Colors.red : Brand.ink,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(m.sos ? 'SOS' : (m.isMe ? 'You' : m.name),
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w700)),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Animated radar: expanding rings and friends orbiting a centre dot.
class RadarHero extends StatefulWidget {
  const RadarHero({super.key, this.size = 280});
  final double size;

  @override
  State<RadarHero> createState() => _RadarHeroState();
}

class _RadarHeroState extends State<RadarHero>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(seconds: 8))
    ..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, _) => CustomPaint(painter: _RadarPainter(_c.value)),
      ),
    );
  }
}

class _RadarPainter extends CustomPainter {
  _RadarPainter(this.t);
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2;
    // expanding rings
    for (var i = 0; i < 3; i++) {
      final p = (t * 4 + i / 3) % 1.0;
      canvas.drawCircle(
        c,
        r * p,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = Colors.white.withValues(alpha: .35 * (1 - p)),
      );
    }
    // sweep
    final sweep = Paint()
      ..shader = SweepGradient(
        startAngle: 0,
        endAngle: 2 * pi,
        transform: GradientRotation(t * 2 * pi),
        colors: [
          Brand.teal.withValues(alpha: 0),
          Brand.teal.withValues(alpha: .45)
        ],
        stops: const [.6, 1],
      ).createShader(Rect.fromCircle(center: c, radius: r));
    canvas.drawCircle(c, r, sweep);
    // orbiting friends
    for (var i = 0; i < 4; i++) {
      final orbit = r * (.35 + .15 * i);
      final a = t * 2 * pi * (i.isEven ? 1 : -1) * (1 + i * .15) + i * 1.7;
      final o = c + Offset(cos(a), sin(a)) * orbit;
      final col = Brand.memberColors[(i * 2 + 1) % Brand.memberColors.length];
      canvas.drawCircle(o, 14, Paint()..color = col.withValues(alpha: .3));
      canvas.drawCircle(o, 8, Paint()..color = col);
      canvas.drawCircle(
          o,
          8,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.5
            ..color = Colors.white);
    }
    // centre
    canvas.drawCircle(c, 12, Paint()..color = Colors.white);
    canvas.drawCircle(c, 7, Paint()..color = Brand.coral);
  }

  @override
  bool shouldRepaint(_RadarPainter old) => old.t != t;
}
