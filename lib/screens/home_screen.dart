import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart' hide Path;

import '../app_state.dart';
import '../data/repository.dart' show parseCode;
import '../models.dart';
import '../services/location_service.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/profile_sheet.dart';
import 'map_screen.dart';
import 'scan_screen.dart';

String _greeting() {
  final h = DateTime.now().hour;
  if (h < 12) return 'Good morning';
  if (h < 18) return 'Good afternoon';
  return 'Good evening';
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.app});
  final AppState app;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _mapOpen = false;
  AppState get app => widget.app;

  Future<void> _open(Group g) async {
    await app.touch(g);
    if (!mounted) return;
    setState(() => _mapOpen = true); // pause the home live listener
    await Navigator.of(context).push(
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
    if (!mounted) return;
    setState(() => _mapOpen = false);
    app.refreshSummaries();
  }

  Future<void> _sheet({required bool create}) async {
    final g = await showModalBottomSheet<Group>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _GroupSheet(app: app, create: create),
    );
    if (g != null && mounted) {
      app.refreshSummaries();
      _open(g);
    }
  }

  Future<void> _scan() async {
    final v = await Navigator.of(context)
        .push<String>(MaterialPageRoute(builder: (_) => const ScanScreen()));
    if (v == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final g = await app.join(parseCode(v));
      if (mounted) {
        app.refreshSummaries();
        _open(g);
      }
    } on JoinException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not join. Check your connection.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ListenableBuilder(
        listenable: app,
        builder: (context, _) {
          final p = app.profile!;
          final top = MediaQuery.of(context).padding.top;
          final header = _Header(
            profile: p,
            onProfile: () => showProfileSheet(context, app),
          );
          final banners = _Banners(app: app);

          if (app.groups.isEmpty) {
            return _FirstRun(
              top: top,
              header: header,
              banners: banners,
              onCreate: () => _sheet(create: true),
              onJoin: () => _sheet(create: false),
              onScan: _scan,
            );
          }

          final active = app.groups.first;
          return RefreshIndicator(
            onRefresh: app.refreshSummaries,
            edgeOffset: top,
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(20, top + 20, 20, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        header,
                        banners,
                        const SizedBox(height: 18),
                        FadeSlide(
                          child: _LiveTripCard(
                            key: ValueKey(active.code),
                            app: app,
                            group: active,
                            paused: _mapOpen,
                            onOpen: () => _open(active),
                          ),
                        ),
                        const SizedBox(height: 16),
                        FadeSlide(
                          delay: const Duration(milliseconds: 120),
                          child: Row(
                            children: [
                              Expanded(
                                child: _QuickAction(
                                  icon: Icons.add_rounded,
                                  label: 'New group',
                                  color: Brand.teal,
                                  onTap: () => _sheet(create: true),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: _QuickAction(
                                  icon: Icons.vpn_key_rounded,
                                  label: 'Join with code',
                                  color: Brand.indigo,
                                  onTap: () => _sheet(create: false),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: _QuickAction(
                                  icon: Icons.qr_code_scanner_rounded,
                                  label: 'Scan QR',
                                  color: Brand.coral,
                                  onTap: _scan,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            const Padding(
                              padding: EdgeInsets.only(left: 2),
                              child: Text(
                                'Your trips',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            Text(
                              app.groups.length == 1
                                  ? '1 trip'
                                  : '${app.groups.length} trips',
                              style: TextStyle(
                                fontSize: 12.5,
                                color: context.muted,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                      ],
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                  sliver: SliverList.builder(
                    itemCount: app.groups.length,
                    itemBuilder: (context, i) {
                      final g = app.groups[i];
                      return FadeSlide(
                        key: ValueKey(g.code),
                        delay: Duration(milliseconds: 200 + 70 * i),
                        child: Dismissible(
                          key: ValueKey('d${g.code}'),
                          direction: DismissDirection.endToStart,
                          background: Container(
                            margin: const EdgeInsets.only(bottom: 10),
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
                          child: _TripTile(
                            group: g,
                            summary: app.summaries[g.code],
                            onTap: () => _open(g),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      20,
                      4,
                      20,
                      24 + MediaQuery.of(context).padding.bottom,
                    ),
                    child: Text(
                      'Swipe a trip left to leave it',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12, color: context.muted),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ======================= header & banners =======================

class _Header extends StatelessWidget {
  const _Header({required this.profile, required this.onProfile});
  final Profile profile;
  final VoidCallback onProfile;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _greeting(),
                style: TextStyle(
                  fontSize: 13,
                  color: context.muted,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                profile.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -.5,
                ),
              ),
            ],
          ),
        ),
        Semantics(
          button: true,
          label: 'Edit profile',
          child: GestureDetector(
            onTap: onProfile,
            child: SizedBox(
              width: 52,
              height: 52,
              child: Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.center,
                children: [
                  Avatar(
                    name: profile.name,
                    colorIndex: profile.colorIndex,
                    size: 48,
                    emoji: profile.emoji,
                  ),
                  Positioned(
                    right: -1,
                    bottom: -1,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: context.surface,
                        shape: BoxShape.circle,
                        boxShadow: const [
                          BoxShadow(color: Colors.black26, blurRadius: 4),
                        ],
                      ),
                      child: Icon(
                        Icons.edit_rounded,
                        size: 11,
                        color: context.text,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Banners extends StatelessWidget {
  const _Banners({required this.app});
  final AppState app;

  Widget _banner(
    BuildContext context,
    IconData icon,
    Color color,
    String text,
  ) {
    return Container(
      margin: const EdgeInsets.only(top: 14),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: context.isDark ? .22 : .14),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 12.5))),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final off =
        app.locationStatus != null && app.locationStatus != LocationStatus.ok;
    return Column(
      children: [
        if (off)
          _banner(
            context,
            Icons.location_off_rounded,
            Brand.coral,
            'Location is off or blocked, so friends cannot see you. Allow it in Settings > Apps > Fareeq > Permissions.',
          ),
        if (app.repo.isDemo)
          _banner(
            context,
            Icons.science_rounded,
            Colors.amber.shade700,
            'Demo mode: friends are simulated. Connect Firebase (free) to go live. See README.',
          ),
      ],
    );
  }
}

// ======================= live trip hero =======================

class _LiveTripCard extends StatefulWidget {
  const _LiveTripCard({
    super.key,
    required this.app,
    required this.group,
    required this.paused,
    required this.onOpen,
  });
  final AppState app;
  final Group group;
  final bool paused;
  final VoidCallback onOpen;

  @override
  State<_LiveTripCard> createState() => _LiveTripCardState();
}

class _LiveTripCardState extends State<_LiveTripCard>
    with SingleTickerProviderStateMixin {
  StreamSubscription<List<Member>>? _sub;
  List<Member> _members = [];
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  )..repeat();

  @override
  void initState() {
    super.initState();
    _subscribe();
  }

  void _subscribe() {
    _sub?.cancel();
    _sub = widget.app.repo.members(widget.group.code).listen((m) {
      if (mounted) setState(() => _members = m);
    }, onError: (_) {});
  }

  @override
  void didUpdateWidget(_LiveTripCard old) {
    super.didUpdateWidget(old);
    if (widget.paused && !old.paused) {
      _sub?.cancel(); // map screen has its own listener: don't double the reads
      _sub = null;
    } else if (!widget.paused && old.paused) {
      _subscribe();
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final summary = widget.app.summaries[widget.group.code];
    final live = _members.isNotEmpty
        ? _members.where((m) => m.isLive).length
        : (summary?.live ?? 0);
    final total = _members.isNotEmpty
        ? _members.length
        : (summary?.people ?? 0);
    final me = _members.where((m) => m.isMe).firstOrNull;
    // nearest other person with a position
    Member? nearest;
    double? nearestM;
    if (me?.position != null) {
      for (final m in _members) {
        if (m.isMe || m.position == null) continue;
        final d = const Distance().as(
          LengthUnit.Meter,
          me!.position!,
          m.position!,
        );
        if (nearestM == null || d < nearestM) {
          nearest = m;
          nearestM = d;
        }
      }
    }
    final others = _members.where((m) => !m.isMe).toList();
    final anySos = _members.any((m) => m.sos && !m.isMe);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: context.isDark
              ? const [Color(0xFF102640), Color(0xFF17406A), Color(0xFF0F9C8D)]
              : const [Color(0xFF0F1B2D), Color(0xFF1E3A5F), Color(0xFF14B8A6)],
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: context.isDark ? .45 : .22),
            blurRadius: 30,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: Column(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: SizedBox(
              height: 124,
              width: double.infinity,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: AnimatedBuilder(
                      animation: _pulse,
                      builder: (_, _) => CustomPaint(
                        painter: _MiniMapPainter(
                          _members,
                          context.isDark,
                          _pulse.value,
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 10,
                    top: 10,
                    child: _Chip(
                      dot: anySos ? Colors.redAccent : const Color(0xFF34D399),
                      text: anySos ? 'SOS' : 'LIVE',
                      dark: true,
                    ),
                  ),
                  if (nearest != null && nearestM != null)
                    Positioned(
                      right: 10,
                      bottom: 10,
                      child: _Chip(
                        text: '${nearest.name} · ${formatDistance(nearestM)}',
                        dark: false,
                      ),
                    ),
                  if (_members.every((m) => m.position == null))
                    const Center(
                      child: Text(
                        'Waiting for locations…',
                        style: TextStyle(color: Colors.white70, fontSize: 12.5),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.group.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -.3,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '$live of $total live · Code ${widget.group.code}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFFBCD0E6),
                          fontSize: 12.5,
                        ),
                      ),
                      const SizedBox(height: 10),
                      _AvatarStack(members: others),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                FilledButton(
                  onPressed: widget.onOpen,
                  style: FilledButton.styleFrom(
                    backgroundColor: context.isDark ? Brand.teal : Colors.white,
                    foregroundColor: context.isDark
                        ? const Color(0xFF06201C)
                        : Brand.ink,
                    minimumSize: const Size(0, 46),
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                    textStyle: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Open map'),
                      SizedBox(width: 8),
                      Icon(Icons.arrow_forward_rounded, size: 18),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.text, required this.dark, this.dot});
  final String text;
  final bool dark;
  final Color? dot;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: dark ? Colors.black.withValues(alpha: .55) : Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (dot != null) ...[
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
          ],
          Text(
            text,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              letterSpacing: dark ? .4 : 0,
              color: dark ? Colors.white : Brand.ink,
            ),
          ),
        ],
      ),
    );
  }
}

class _AvatarStack extends StatelessWidget {
  const _AvatarStack({required this.members});
  final List<Member> members;

  @override
  Widget build(BuildContext context) {
    if (members.isEmpty) {
      return const Text(
        'Invite friends with the QR on the map',
        style: TextStyle(color: Color(0xFFBCD0E6), fontSize: 12),
      );
    }
    final shown = members.take(4).toList();
    final extra = members.length - shown.length;
    Widget ring(Widget child) => Container(
      width: 30,
      height: 30,
      margin: const EdgeInsets.only(right: 0),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: const Color(0xFF1E3A5F), width: 2),
      ),
      child: ClipOval(child: child),
    );
    return SizedBox(
      height: 30,
      child: Stack(
        children: [
          for (var i = 0; i < shown.length; i++)
            Positioned(
              left: i * 22.0,
              child: ring(
                Avatar(
                  name: shown[i].name,
                  colorIndex: shown[i].colorIndex,
                  emoji: shown[i].emoji,
                  size: 26,
                ),
              ),
            ),
          if (extra > 0)
            Positioned(
              left: shown.length * 22.0,
              child: ring(
                Container(
                  alignment: Alignment.center,
                  color: const Color(0xFF475A73),
                  child: Text(
                    '+$extra',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Schematic mini-map: decorative streets, with members placed by their real
/// relative positions (no map tiles, so it costs nothing and works offline).
class _MiniMapPainter extends CustomPainter {
  _MiniMapPainter(this.members, this.dark, this.t);
  final List<Member> members;
  final bool dark;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = dark ? const Color(0xFF0E1C30) : const Color(0xFF1A3354),
    );
    // river
    final river = Path()
      ..moveTo(-10, h * .74)
      ..cubicTo(w * .18, h * .56, w * .34, h * .9, w * .58, h * .62)
      ..cubicTo(w * .78, h * .4, w * .92, h * .34, w + 10, h * .4);
    canvas.drawPath(
      river,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 16
        ..color = const Color(0xFF2A5A7A).withValues(alpha: dark ? .7 : .55),
    );
    final road = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..color = Colors.white.withValues(alpha: .11);
    road.strokeWidth = 3;
    canvas.drawLine(Offset(w * .06, -5), Offset(w * .2, h + 5), road);
    canvas.drawLine(Offset(-5, h * .24), Offset(w + 5, h * .56), road);
    canvas.drawLine(Offset(w * .46, -5), Offset(w * .64, h + 5), road);
    road.strokeWidth = 2;
    canvas.drawLine(Offset(w * .78, -5), Offset(w * .7, h + 5), road);
    canvas.drawLine(Offset(-5, h * .9), Offset(w + 5, h * .15), road);

    final pts = members.where((m) => m.position != null).toList();
    if (pts.isEmpty) return;

    // project real lat/lng into the card, keeping the true aspect ratio
    final lat0 =
        pts.map((m) => m.position!.latitude).reduce((a, b) => a + b) /
        pts.length;
    final k = math.cos(lat0 * math.pi / 180);
    Offset raw(Member m) =>
        Offset(m.position!.longitude * k, -m.position!.latitude);
    final raws = pts.map(raw).toList();
    final minX = raws.map((o) => o.dx).reduce(math.min);
    final maxX = raws.map((o) => o.dx).reduce(math.max);
    final minY = raws.map((o) => o.dy).reduce(math.min);
    final maxY = raws.map((o) => o.dy).reduce(math.max);
    final span = math.max(math.max(maxX - minX, maxY - minY), 0.0008);
    const pad = 30.0;
    final scale = (math.min(w, h) - pad * 2) / span;
    final cx = (minX + maxX) / 2, cy = (minY + maxY) / 2;
    Offset toPx(Offset r) =>
        Offset(w / 2 + (r.dx - cx) * scale * 1.4, h / 2 + (r.dy - cy) * scale);
    final px = [for (final r in raws) toPx(r)];

    // guide line from me to the nearest other person
    final meIdx = pts.indexWhere((m) => m.isMe);
    if (meIdx >= 0 && pts.length > 1) {
      var best = -1;
      var bestD = double.infinity;
      for (var i = 0; i < pts.length; i++) {
        if (i == meIdx) continue;
        final d = (px[i] - px[meIdx]).distance;
        if (d < bestD) {
          bestD = d;
          best = i;
        }
      }
      if (best >= 0) {
        final a = px[meIdx], b = px[best];
        final len = (b - a).distance;
        if (len > 1) {
          final dir = (b - a) / len;
          for (var d = 0.0; d < len; d += 13) {
            canvas.drawLine(
              a + dir * d,
              a + dir * math.min(d + 7, len),
              Paint()
                ..color = Colors.white
                ..strokeWidth = 2.4
                ..strokeCap = StrokeCap.round,
            );
          }
        }
      }
    }

    for (var i = 0; i < pts.length; i++) {
      final m = pts[i];
      final c = m.sos
          ? Colors.red
          : Brand.memberColors[m.colorIndex % Brand.memberColors.length];
      final p = px[i];
      final live = m.isLive || m.sos;
      if (live) {
        canvas.drawCircle(
          p,
          9 + 12 * t,
          Paint()..color = c.withValues(alpha: .35 * (1 - t)),
        );
      }
      final o = live ? 1.0 : .5;
      canvas.drawCircle(p, 8, Paint()..color = c.withValues(alpha: o));
      canvas.drawCircle(
        p,
        8,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..color = Colors.white.withValues(alpha: o),
      );
    }
  }

  @override
  bool shouldRepaint(_MiniMapPainter old) => true;
}

// ======================= actions & list =======================

class _QuickAction extends StatelessWidget {
  const _QuickAction({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.surface,
      borderRadius: BorderRadius.circular(20),
      elevation: context.isDark ? 0 : 2,
      shadowColor: Brand.ink.withValues(alpha: .1),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(6, 14, 6, 12),
          child: Column(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color.withValues(alpha: context.isDark ? .22 : .14),
                ),
                child: Icon(icon, size: 20, color: color),
              ),
              const SizedBox(height: 8),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TripTile extends StatelessWidget {
  const _TripTile({
    required this.group,
    required this.summary,
    required this.onTap,
  });
  final Group group;
  final GroupSummary? summary;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final idx = group.code.codeUnits.fold<int>(0, (a, b) => a + b);
    final c = Brand.memberColors[idx % Brand.memberColors.length];
    final s = summary;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: context.surface,
        borderRadius: BorderRadius.circular(22),
        boxShadow: context.isDark
            ? null
            : [
                BoxShadow(
                  color: Brand.ink.withValues(alpha: .06),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color: c.withValues(alpha: context.isDark ? .2 : .14),
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
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          if (s != null && s.live > 0) ...[
                            Container(
                              width: 7,
                              height: 7,
                              margin: const EdgeInsets.only(right: 6),
                              decoration: const BoxDecoration(
                                color: Brand.teal,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ],
                          Flexible(
                            child: Text(
                              s == null
                                  ? 'Code ${group.code}'
                                  : '${s.people} ${s.people == 1 ? 'person' : 'people'} · ${s.live == 0 ? 'nobody live' : '${s.live} live'}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12.5,
                                color: context.muted,
                              ),
                            ),
                          ),
                          if (s != null && s.locked) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: context.line,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.lock_rounded,
                                    size: 10,
                                    color: context.muted,
                                  ),
                                  const SizedBox(width: 3),
                                  Text(
                                    'Locked',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: context.muted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: context.subtle),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ======================= first run =======================

class _FirstRun extends StatelessWidget {
  const _FirstRun({
    required this.top,
    required this.header,
    required this.banners,
    required this.onCreate,
    required this.onJoin,
    required this.onScan,
  });
  final double top;
  final Widget header, banners;
  final VoidCallback onCreate, onJoin, onScan;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        20,
        top + 20,
        20,
        24 + MediaQuery.of(context).padding.bottom,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          header,
          banners,
          const SizedBox(height: 26),
          FadeSlide(
            child: Container(
              height: 280,
              width: double.infinity,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(32),
                gradient: Brand.gradient,
              ),
              child: const Center(child: RadarHero(size: 260)),
            ),
          ),
          const SizedBox(height: 24),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              'Your travel crew,\non one map',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w800,
                height: 1.1,
                letterSpacing: -.6,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              'Create a group for your next trip, or join one with a code or QR. Everyone shows up live, no calls needed.',
              style: TextStyle(
                fontSize: 14.5,
                height: 1.5,
                color: context.muted,
              ),
            ),
          ),
          const SizedBox(height: 26),
          FilledButton.icon(
            onPressed: onCreate,
            icon: const Icon(Icons.add_rounded),
            label: const Text('Create a group'),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _OutlineAction(
                  icon: Icons.vpn_key_rounded,
                  label: 'Join with code',
                  color: Brand.indigo,
                  onTap: onJoin,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _OutlineAction(
                  icon: Icons.qr_code_scanner_rounded,
                  label: 'Scan QR',
                  color: Brand.coral,
                  onTap: onScan,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _OutlineAction extends StatelessWidget {
  const _OutlineAction({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 18, color: color),
      label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(52),
        foregroundColor: context.text,
        backgroundColor: context.surface,
        side: BorderSide(color: context.line, width: 1.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        textStyle: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700),
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
        decoration: BoxDecoration(
          color: context.bg,
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
                  color: context.line,
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
                  foregroundColor: context.text,
                  side: BorderSide(color: context.line),
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
