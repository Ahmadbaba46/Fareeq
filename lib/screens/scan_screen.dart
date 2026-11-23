import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../theme.dart';

/// Pops with the first scanned QR payload.
class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen>
    with SingleTickerProviderStateMixin {
  final _scanner = MobileScannerController(
      detectionSpeed: DetectionSpeed.noDuplicates,
      formats: const [BarcodeFormat.qrCode]);
  late final AnimationController _line = AnimationController(
      vsync: this, duration: const Duration(seconds: 2))
    ..repeat(reverse: true);
  bool _done = false;

  @override
  void dispose() {
    _line.dispose();
    _scanner.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const box = 260.0;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(children: [
        MobileScanner(
          controller: _scanner,
          onDetect: (capture) {
            final v = capture.barcodes
                .map((b) => b.rawValue)
                .whereType<String>()
                .firstOrNull;
            if (v != null && !_done) {
              _done = true;
              Navigator.pop(context, v);
            }
          },
          errorBuilder: (context, error) => const Center(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: Text(
                'Camera permission is needed to scan. Allow it in Settings, or type the code instead.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white),
              ),
            ),
          ),
        ),
        Center(
          child: SizedBox(
            width: box,
            height: box,
            child: AnimatedBuilder(
              animation: _line,
              builder: (_, _) => CustomPaint(painter: _FramePainter(_line.value)),
            ),
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Row(children: [
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close_rounded, color: Colors.white),
              ),
              const Spacer(),
              IconButton(
                onPressed: _scanner.toggleTorch,
                icon: const Icon(Icons.flashlight_on_rounded,
                    color: Colors.white),
              ),
            ]),
          ),
        ),
        const Positioned(
          left: 0,
          right: 0,
          bottom: 90,
          child: Text('Point at the group QR code',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600)),
        ),
      ]),
    );
  }
}

class _FramePainter extends CustomPainter {
  _FramePainter(this.t);
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = Brand.teal
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;
    const l = 36.0;
    final w = size.width, h = size.height;
    for (final c in [
      [Offset(0, l), Offset.zero, Offset(l, 0)],
      [Offset(w - l, 0), Offset(w, 0), Offset(w, l)],
      [Offset(w, h - l), Offset(w, h), Offset(w - l, h)],
      [Offset(l, h), Offset(0, h), Offset(0, h - l)],
    ]) {
      canvas.drawPath(
          Path()
            ..moveTo(c[0].dx, c[0].dy)
            ..lineTo(c[1].dx, c[1].dy)
            ..lineTo(c[2].dx, c[2].dy),
          p);
    }
    final y = 12 + (h - 24) * Curves.easeInOut.transform(t);
    canvas.drawLine(
        Offset(14, y),
        Offset(w - 14, y),
        Paint()
          ..strokeWidth = 3
          ..shader = LinearGradient(colors: [
            Brand.teal.withValues(alpha: 0),
            Brand.teal,
            Brand.teal.withValues(alpha: 0),
          ]).createShader(Rect.fromLTWH(0, 0, w, 1)));
  }

  @override
  bool shouldRepaint(_FramePainter o) => o.t != t;
}
