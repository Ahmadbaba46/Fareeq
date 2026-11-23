import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../models.dart';
import '../theme.dart';

Future<void> showInviteSheet(BuildContext context, Group group) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _InviteSheet(group: group),
  );
}

class _InviteSheet extends StatelessWidget {
  const _InviteSheet({required this.group});
  final Group group;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
          24, 14, 24, 28 + MediaQuery.of(context).padding.bottom),
      decoration: const BoxDecoration(
        color: Brand.sand,
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 44,
            height: 5,
            decoration: BoxDecoration(
                color: Colors.black12, borderRadius: BorderRadius.circular(4)),
          ),
          const SizedBox(height: 18),
          Text(group.name,
              style:
                  const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          const Text('Ask friends to scan this in Fareeq > Join with code',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.black54)),
          const SizedBox(height: 20),
          TweenAnimationBuilder<double>(
            tween: Tween(begin: .7, end: 1),
            duration: const Duration(milliseconds: 650),
            curve: Curves.elasticOut,
            builder: (_, v, child) => Transform.scale(scale: v, child: child),
            child: Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(28),
                boxShadow: [
                  BoxShadow(
                      color: Brand.ink.withValues(alpha: .1),
                      blurRadius: 24,
                      offset: const Offset(0, 10))
                ],
              ),
              child: QrImageView(
                data: 'fareeq://join/${group.code}',
                size: 220,
                eyeStyle: const QrEyeStyle(
                    eyeShape: QrEyeShape.circle, color: Brand.ink),
                dataModuleStyle: const QrDataModuleStyle(
                    dataModuleShape: QrDataModuleShape.circle,
                    color: Brand.ink),
              ),
            ),
          ),
          const SizedBox(height: 18),
          GestureDetector(
            onTap: () {
              Clipboard.setData(ClipboardData(text: group.code));
              ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Code copied')));
            },
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text(group.code,
                  style: const TextStyle(
                      fontSize: 26,
                      letterSpacing: 6,
                      fontWeight: FontWeight.w800)),
              const SizedBox(width: 10),
              const Icon(Icons.copy_rounded, size: 20, color: Colors.black38),
            ]),
          ),
        ],
      ),
    );
  }
}
