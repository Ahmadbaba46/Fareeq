import 'package:flutter/material.dart';

import '../app_state.dart';
import '../data/repository.dart' show parseCode;
import '../models.dart';
import '../services/location_service.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'map_screen.dart';
import 'scan_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, required this.app});
  final AppState app;

  void _open(BuildContext context, Group g) {
    Navigator.of(context).push(
      PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 500),
        pageBuilder: (_, _, _) => MapScreen(app: app, group: g),
        transitionsBuilder: (_, a, _, child) => FadeTransition(
          opacity: CurvedAnimation(parent: a, curve: Curves.easeOut),
          child: ScaleTransition(
            scale: Tween(
              begin: .96,
              end: 1.0,
            ).animate(CurvedAnimation(parent: a, curve: Curves.easeOutCubic)),
            child: child,
          ),
        ),
      ),
    );
  }

  Future<void> _sheet(BuildContext context, {required bool create}) async {
    final g = await showModalBottomSheet<Group>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _GroupSheet(app: app, create: create),
    );
    if (g != null && context.mounted) _open(context, g);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ListenableBuilder(
        listenable: app,
        builder: (context, _) {
          final p = app.profile!;
          return CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Container(
                  padding: EdgeInsets.fromLTRB(
                    24,
                    MediaQuery.of(context).padding.top + 20,
                    24,
                    28,
                  ),
                  decoration: const BoxDecoration(
                    gradient: Brand.gradient,
                    borderRadius: BorderRadius.vertical(
                      bottom: Radius.circular(36),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Avatar(
                            name: p.name,
                            colorIndex: p.colorIndex,
                            size: 48,
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Welcome back',
                                  style: TextStyle(color: Colors.white70),
                                ),
                                Text(
                                  p.name,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 22,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(
                            width: 70,
                            height: 70,
                            child: RadarHero(size: 70),
                          ),
                        ],
                      ),
                      const SizedBox(height: 22),
                      Row(
                        children: [
                          Expanded(
                            child: _ActionButton(
                              icon: Icons.add_rounded,
                              label: 'New group',
                              filled: true,
                              onTap: () => _sheet(context, create: true),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _ActionButton(
                              icon: Icons.vpn_key_rounded,
                              label: 'Join with code',
                              onTap: () => _sheet(context, create: false),
                            ),
                          ),
                        ],
                      ),
                      if (app.locationStatus != null &&
                          app.locationStatus != LocationStatus.ok) ...[
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Brand.coral.withValues(alpha: .3),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Row(
                            children: [
                              Icon(
                                Icons.location_off_rounded,
                                color: Colors.white,
                                size: 20,
                              ),
                              SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'Location is off or blocked, so friends cannot see you. Allow it in Settings > Apps > Fareeq > Permissions.',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 12.5,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      if (app.repo.isDemo) ...[
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: .12),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Row(
                            children: [
                              Icon(
                                Icons.science_rounded,
                                color: Colors.amber,
                                size: 20,
                              ),
                              SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'Demo mode: friends are simulated. Connect Firebase (free) to go live. See README.',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 12.5,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              if (app.groups.isEmpty)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Padding(
                      padding: EdgeInsets.all(40),
                      child: Text(
                        'No groups yet.\nCreate one and share the code with your travel crew.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.black54, height: 1.5),
                      ),
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.all(20),
                  sliver: SliverList.builder(
                    itemCount: app.groups.length,
                    itemBuilder: (context, i) {
                      final g = app.groups[i];
                      return FadeSlide(
                        key: ValueKey(g.code),
                        delay: Duration(milliseconds: 80 * i),
                        child: Dismissible(
                          key: ValueKey('d${g.code}'),
                          direction: DismissDirection.endToStart,
                          background: Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            alignment: Alignment.centerRight,
                            padding: const EdgeInsets.only(right: 24),
                            decoration: BoxDecoration(
                              color: Brand.coral,
                              borderRadius: BorderRadius.circular(22),
                            ),
                            child: const Icon(
                              Icons.logout_rounded,
                              color: Colors.white,
                            ),
                          ),
                          onDismissed: (_) => app.leave(g),
                          child: _GroupCard(
                            group: g,
                            onTap: () => _open(context, g),
                          ),
                        ),
                      );
                    },
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.filled = false,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: filled ? Colors.white : Colors.white.withValues(alpha: .15),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: filled ? Brand.ink : Colors.white),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: filled ? Brand.ink : Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GroupCard extends StatelessWidget {
  const _GroupCard({required this.group, required this.onTap});
  final Group group;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final idx = group.code.codeUnits.fold<int>(0, (a, b) => a + b);
    final c = Brand.memberColors[idx % Brand.memberColors.length];
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: Brand.ink.withValues(alpha: .06),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: c.withValues(alpha: .15),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(Icons.public_rounded, color: c),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        group.name,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Code  ${group.code}',
                        style: const TextStyle(
                          color: Colors.black45,
                          letterSpacing: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded, color: Colors.black26),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GroupSheet extends StatefulWidget {
  const _GroupSheet({required this.app, required this.create});
  final AppState app;
  final bool create;

  @override
  State<_GroupSheet> createState() => _GroupSheetState();
}

class _GroupSheetState extends State<_GroupSheet> {
  final _c = TextEditingController();
  bool _busy = false;
  String? _error;

  Future<void> _submit() async {
    final text = _c.text.trim();
    if (text.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final g = widget.create
          ? await widget.app.create(text)
          : await widget.app.join(text);
      if (mounted) Navigator.pop(context, g);
    } on JoinException catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.message;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = 'Something went wrong. Check your connection.';
        });
      }
    }
  }

  Future<void> _scan() async {
    final v = await Navigator.of(context)
        .push<String>(MaterialPageRoute(builder: (_) => const ScanScreen()));
    if (v == null || !mounted) return;
    _c.text = parseCode(v);
    _submit();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        padding: const EdgeInsets.fromLTRB(24, 14, 24, 28),
        decoration: const BoxDecoration(
          color: Brand.sand,
          borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 44,
                height: 5,
                decoration: BoxDecoration(
                  color: Colors.black12,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              widget.create ? 'Name your trip' : 'Enter group code',
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _c,
              autofocus: true,
              textCapitalization: widget.create
                  ? TextCapitalization.words
                  : TextCapitalization.characters,
              onSubmitted: (_) => _submit(),
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 18,
                letterSpacing: widget.create ? 0 : 4,
              ),
              decoration: InputDecoration(
                hintText: widget.create ? 'e.g. Istanbul 2026' : 'ABCD2345',
                errorText: _error,
              ),
            ),
            const SizedBox(height: 18),
            FilledButton(
              onPressed: _busy ? null : _submit,
              child: _busy
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Colors.white,
                      ),
                    )
                  : Text(widget.create ? 'Create group' : 'Join group'),
            ),
            if (!widget.create) ...[
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: _busy ? null : _scan,
                icon: const Icon(Icons.qr_code_scanner_rounded),
                label: const Text('Scan QR code'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(56),
                  foregroundColor: Brand.ink,
                  side: const BorderSide(color: Colors.black12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
