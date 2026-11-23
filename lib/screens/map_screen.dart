import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import '../app_state.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/common.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key, required this.app, required this.group});
  final AppState app;
  final Group group;

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> with TickerProviderStateMixin {
  final _map = MapController();
  late final AnimationController _move = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1600));
  late final AnimationController _fly = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 900));

  StreamSubscription<List<Member>>? _membersSub;
  List<Member> _members = [];
  final Map<String, LatLng> _from = {};
  final Map<String, LatLng> _to = {};
  LatLng? _me;
  bool _fitted = false;
  bool _mapReady = false;
  String? _following;

  String get _code => widget.group.code;

  @override
  void initState() {
    super.initState();
    _membersSub = widget.app.repo.members(_code).listen(_onMembers);
    _onMe();
    widget.app.myPosition.addListener(_onMe);
  }

  void _onMe() {
    final p = widget.app.myPosition.value;
    if (p != null) _me = p;
  }

  void _onMembers(List<Member> list) {
    if (!mounted) return;
    // current displayed position becomes the animation start
    final t = _move.value;
    for (final m in list) {
      final pos = m.position;
      if (pos == null) continue;
      final shown = _shown(m.id);
      _from[m.id] = shown ?? pos;
      _to[m.id] = pos;
    }
    _members = list;
    _move.value = 0;
    _move.animateTo(1, curve: Curves.easeInOut);
    if (t >= 0 && _following != null) _followTick();
    setState(() {});
    if (!_fitted && _mapReady && list.any((m) => m.position != null)) {
      _fitted = true;
      _fitAll();
    }
  }

  LatLng? _shown(String id) {
    final a = _from[id], b = _to[id];
    if (b == null) return null;
    if (a == null) return b;
    final t = Curves.easeInOut.transform(_move.value);
    return LatLng(a.latitude + (b.latitude - a.latitude) * t,
        a.longitude + (b.longitude - a.longitude) * t);
  }

  void _followTick() {
    final p = _to[_following];
    if (p != null) _flyTo(p, zoom: _map.camera.zoom);
  }

  void _flyTo(LatLng dest, {double? zoom}) {
    final cam = _map.camera;
    final startC = cam.center;
    final startZ = cam.zoom;
    final endZ = zoom ?? 15.5;
    _fly
      ..stop()
      ..reset();
    void tick() {
      final t = Curves.easeInOutCubic.transform(_fly.value);
      // little "zoom out then in" arc for a flight feel
      final arc = (1 - (2 * t - 1) * (2 * t - 1)) * 0.8;
      _map.move(
        LatLng(startC.latitude + (dest.latitude - startC.latitude) * t,
            startC.longitude + (dest.longitude - startC.longitude) * t),
        startZ + (endZ - startZ) * t - arc,
      );
    }

    _fly.addListener(tick);
    _fly.forward().whenComplete(() => _fly.removeListener(tick));
  }

  void _fitAll() {
    final pts = _members.map((m) => m.position).whereType<LatLng>().toList();
    if (pts.isEmpty) return;
    if (pts.length == 1) return _flyTo(pts.first);
    _map.fitCamera(CameraFit.coordinates(
      coordinates: pts,
      padding: const EdgeInsets.fromLTRB(60, 140, 60, 340),
      maxZoom: 16,
    ));
  }

  Future<void> _navigate(Member m) async {
    final p = m.position;
    if (p == null) return;
    // Works without any API key: opens Google/Apple/any maps handler.
    final uri = Uri.parse(
        'https://www.google.com/maps/dir/?api=1&destination=${p.latitude},${p.longitude}');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  void dispose() {
    _membersSub?.cancel();
    widget.app.myPosition.removeListener(_onMe);
    _move.dispose();
    _fly.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final withPos = _members.where((m) => m.position != null);
    final start = withPos.isNotEmpty
        ? withPos.first.position!
        : const LatLng(41.0082, 28.9784);
    return Scaffold(
      body: Stack(
        children: [
          FlutterMap(
            mapController: _map,
            options: MapOptions(
              initialCenter: start,
              initialZoom: 14,
              onMapReady: () {
                _mapReady = true;
                if (!_fitted && withPos.isNotEmpty) {
                  _fitted = true;
                  _fitAll();
                }
              },
              onPositionChanged: (_, byGesture) {
                if (byGesture && _following != null) {
                  setState(() => _following = null);
                }
              },
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.fuyoudhat.fareeq',
              ),
              AnimatedBuilder(
                animation: _move,
                builder: (context, _) => MarkerLayer(
                  markers: [
                    for (final m in _members)
                      if (_shown(m.id) != null)
                        Marker(
                          point: _shown(m.id)!,
                          width: 110,
                          height: 110,
                          child: GestureDetector(
                            onTap: () => _flyTo(_to[m.id]!),
                            child: PulseMarker(member: m),
                          ),
                        ),
                  ],
                ),
              ),
              const RichAttributionWidget(
                alignment: AttributionAlignment.bottomLeft,
                attributions: [TextSourceAttribution('© OpenStreetMap contributors')],
              ),
            ],
          ),
          _TopBar(
            group: widget.group,
            liveCount: _members.where((m) => m.isLive).length,
            total: _members.length,
            app: widget.app,
          ),
          Positioned(
            right: 16,
            bottom: MediaQuery.of(context).size.height * .32 + 12,
            child: Column(children: [
              _RoundButton(icon: Icons.zoom_out_map_rounded, onTap: _fitAll),
              const SizedBox(height: 10),
              _RoundButton(
                icon: Icons.my_location_rounded,
                onTap: () {
                  final p = _to['me'] ?? _me;
                  if (p != null) _flyTo(p);
                },
              ),
            ]),
          ),
          DraggableScrollableSheet(
            initialChildSize: .30,
            minChildSize: .14,
            maxChildSize: .75,
            snap: true,
            snapSizes: const [.14, .30, .75],
            builder: (context, scroll) => _MemberSheet(
              controller: scroll,
              members: _members,
              me: _to['me'] ?? _me,
              following: _following,
              onTap: (m) {
                final p = _to[m.id];
                if (p == null) return;
                setState(() => _following = m.isMe ? null : m.id);
                _flyTo(p);
              },
              onNavigate: _navigate,
            ),
          ),
        ],
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.group,
    required this.liveCount,
    required this.total,
    required this.app,
  });
  final AppState app;
  final Group group;
  final int liveCount, total;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 10,
      left: 12,
      right: 12,
      child: FadeSlide(
        child: Container(
          padding: const EdgeInsets.fromLTRB(6, 6, 14, 6),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: .94),
            borderRadius: BorderRadius.circular(26),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withValues(alpha: .15),
                  blurRadius: 20,
                  offset: const Offset(0, 6))
            ],
          ),
          child: Row(children: [
            IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.arrow_back_rounded)),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(group.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontWeight: FontWeight.w800, fontSize: 16)),
                  GestureDetector(
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: group.code));
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          content: Text('Code ${group.code} copied. Send it to your friends.')));
                    },
                    child: Row(children: [
                      Container(
                        width: 8,
                        height: 8,
                        margin: const EdgeInsets.only(right: 6),
                        decoration: const BoxDecoration(
                            color: Brand.teal, shape: BoxShape.circle),
                      ),
                      Text('$liveCount of $total live · ${group.code}',
                          style: const TextStyle(
                              fontSize: 12, color: Colors.black54)),
                      const SizedBox(width: 4),
                      const Icon(Icons.copy_rounded,
                          size: 12, color: Colors.black38),
                    ]),
                  ),
                ],
              ),
            ),
            ListenableBuilder(
              listenable: app,
              builder: (context, _) => Column(mainAxisSize: MainAxisSize.min, children: [
                Switch(
                  value: app.sharing,
                  onChanged: app.setSharing,
                  activeThumbColor: Brand.teal,
                ),
                Text(app.sharing ? 'Sharing' : 'Paused',
                    style: const TextStyle(fontSize: 10, color: Colors.black54)),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.white,
        elevation: 6,
        shadowColor: Colors.black38,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Padding(
              padding: const EdgeInsets.all(13),
              child: Icon(icon, color: Brand.ink)),
        ),
      );
}

class _MemberSheet extends StatelessWidget {
  const _MemberSheet({
    required this.controller,
    required this.members,
    required this.me,
    required this.following,
    required this.onTap,
    required this.onNavigate,
  });
  final ScrollController controller;
  final List<Member> members;
  final LatLng? me;
  final String? following;
  final ValueChanged<Member> onTap;
  final ValueChanged<Member> onNavigate;

  String _distance(Member m) {
    final p = m.position;
    if (m.isMe || me == null || p == null) return '';
    final d = const Distance().as(LengthUnit.Meter, me!, p);
    return d < 1000 ? '${d.round()} m away' : '${(d / 1000).toStringAsFixed(1)} km away';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: .18),
              blurRadius: 24,
              offset: const Offset(0, -6))
        ],
      ),
      child: ListView.builder(
        controller: controller,
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
        itemCount: members.length + 1,
        itemBuilder: (context, i) {
          if (i == 0) {
            return Column(children: [
              Container(
                width: 44,
                height: 5,
                decoration: BoxDecoration(
                    color: Colors.black12,
                    borderRadius: BorderRadius.circular(4)),
              ),
              const SizedBox(height: 14),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text('Your crew',
                    style:
                        TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
              ),
              const SizedBox(height: 8),
            ]);
          }
          final m = members[i - 1];
          final active = following == m.id;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            margin: const EdgeInsets.symmetric(vertical: 3),
            decoration: BoxDecoration(
              color: active ? Brand.teal.withValues(alpha: .12) : Colors.transparent,
              borderRadius: BorderRadius.circular(18),
            ),
            child: ListTile(
              onTap: () => onTap(m),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
              leading: Avatar(name: m.name, colorIndex: m.colorIndex),
              title: Text(m.isMe ? 'You' : m.name,
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Row(children: [
                Container(
                  width: 8,
                  height: 8,
                  margin: const EdgeInsets.only(right: 6),
                  decoration: BoxDecoration(
                      color: m.isLive ? Brand.teal : Colors.black26,
                      shape: BoxShape.circle),
                ),
                Flexible(
                  child: Text(
                      [m.lastSeen, _distance(m)].where((s) => s.isNotEmpty).join(' · '),
                      overflow: TextOverflow.ellipsis),
                ),
              ]),
              trailing: m.isMe || m.position == null
                  ? null
                  : IconButton.filledTonal(
                      tooltip: 'Directions',
                      onPressed: () => onNavigate(m),
                      icon: const Icon(Icons.directions_rounded),
                    ),
            ),
          );
        },
      ),
    );
  }
}
