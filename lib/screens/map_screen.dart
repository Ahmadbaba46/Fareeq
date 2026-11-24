import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_state.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/invite_sheet.dart';

const _meetingId = '#meeting';

String formatDistance(double m) =>
    m < 1000 ? '${m.round()} m' : '${(m / 1000).toStringAsFixed(1)} km';

String walkTime(double m) {
  final min = (m / 83).round(); // ~5 km/h
  if (min < 1) return '1 min walk';
  if (min < 90) return '$min min walk';
  return '${(min / 60).toStringAsFixed(1)} h walk';
}

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
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );
  late final AnimationController _fly = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  StreamSubscription<List<Member>>? _membersSub;
  StreamSubscription<GroupInfo>? _infoSub;
  List<Member> _members = [];
  GroupInfo _info = const GroupInfo();
  final Map<String, LatLng> _from = {};
  final Map<String, LatLng> _to = {};
  final Set<String> _sosSeen = {};
  LatLng? _me;
  bool _fitted = false;
  bool _mapReady = false;
  bool _endedHandled = false;
  String? _target; // member id or _meetingId
  static const _osmUrl = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
  static const _userAgent = 'com.fuyoudhat.fareeq';

  /// Every tile you look at is cached on disk (up to 1 GB) and kept for 30
  /// days, so places you have already seen on the map still work offline.
  final NetworkTileProvider _tiles = NetworkTileProvider(
    cachingProvider: BuiltInMapCachingProvider.getOrCreateInstance(
      overrideFreshAge: const Duration(days: 30),
    ),
  );
  bool _saving = false;
  bool _showTrails = false;
  final Map<String, List<LatLng>> _trails = {};
  final Set<String> _stragDismissed = {};

  String get _code => widget.group.code;
  Profile get _profile => widget.app.profile!;
  bool get _isOwner =>
      _info.ownerId != null && _info.ownerId == widget.app.repo.userId;
  Member? get _meMember => _members.where((m) => m.isMe).firstOrNull;

  @override
  void initState() {
    super.initState();
    _onMe();
    widget.app.myPosition.addListener(_onMe);
    widget.app.addListener(_onApp);
    _membersSub = widget.app.repo.members(_code).listen(_onMembers);
    _infoSub = widget.app.repo.groupInfo(_code).listen(_onInfo);
  }

  void _onApp() {
    if (mounted) setState(() {});
  }

  void _onMe() {
    final p = widget.app.myPosition.value;
    if (p != null) _me = p;
  }

  void _onInfo(GroupInfo info) {
    if (!mounted) return;
    setState(() => _info = info);
    if (info.ended && !_endedHandled) {
      _endedHandled = true;
      if (!_isOwnerEnding) _showEnded();
    }
    if (_target == _meetingId && info.meeting == null) _target = null;
  }

  bool _isOwnerEnding = false;

  Future<void> _showEnded() async {
    await widget.app.forget(widget.group);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text('Trip ended'),
        content: const Text('The group creator ended this trip.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
    if (mounted) Navigator.pop(context);
  }

  void _onMembers(List<Member> list) {
    if (!mounted) return;
    for (final m in list) {
      final pos = m.position;
      if (pos == null) continue;
      _from[m.id] = _shown(m.id) ?? pos;
      _to[m.id] = pos;
    }
    // alert once when somebody else sends an SOS
    for (final m in list) {
      if (m.sos && !m.isMe && _sosSeen.add(m.id)) {
        HapticFeedback.heavyImpact();
      }
      if (!m.sos) _sosSeen.remove(m.id);
    }
    // keep a short local trail of each person's movement
    for (final m in list) {
      final p = m.position;
      if (p == null) continue;
      final t = _trails.putIfAbsent(m.id, () => []);
      if (t.isEmpty || const Distance().as(LengthUnit.Meter, t.last, p) > 8) {
        t.add(p);
        if (t.length > 120) t.removeAt(0);
      }
    }
    _members = list;
    _stragDismissed.removeWhere((id) => !_stragglers().any((s) => s.id == id));
    _move.value = 0;
    _move.animateTo(1, curve: Curves.easeInOut);
    setState(() {});
    if (!_fitted && _mapReady && list.any((m) => m.position != null)) {
      _fitted = true;
      _fitAll();
    }
  }

  // ---------- offline map ----------
  static int _tx(double lon, int z) =>
      (((lon + 180) / 360) * (1 << z)).floor().clamp(0, (1 << z) - 1);
  static int _ty(double lat, int z) {
    final r = lat.clamp(-85.0, 85.0) * math.pi / 180;
    final y = (1 - math.log(math.tan(r) + 1 / math.cos(r)) / math.pi) / 2;
    return (y * (1 << z)).floor().clamp(0, (1 << z) - 1);
  }

  Future<void> _warmTile(TileCoordinates c, TileLayer layer) {
    final done = Completer<void>();
    final stream = _tiles.getImage(c, layer).resolve(ImageConfiguration.empty);
    late ImageStreamListener l;
    void finish() {
      stream.removeListener(l);
      if (!done.isCompleted) done.complete();
    }

    l = ImageStreamListener((_, _) => finish(), onError: (_, _) => finish());
    stream.addListener(l);
    return done.future.timeout(const Duration(seconds: 15), onTimeout: finish);
  }

  /// Politely pre-loads the tiles of the area on screen. Deliberately small
  /// (max 150 tiles, 3 at a time): OpenStreetMap's free servers forbid bulk
  /// downloading.
  Future<void> _saveOffline() async {
    if (_saving) return;
    const cap = 150;
    final cam = _map.camera;
    final b = cam.visibleBounds;
    final zoom = cam.zoom.round();
    final coords = <TileCoordinates>[];
    for (var z = (zoom - 1).clamp(3, 17); z <= (zoom + 1).clamp(3, 17); z++) {
      final x0 = _tx(b.west, z), x1 = _tx(b.east, z);
      final y0 = _ty(b.north, z), y1 = _ty(b.south, z);
      final level = <TileCoordinates>[
        for (var x = x0; x <= x1; x++)
          for (var y = y0; y <= y1; y++) TileCoordinates(x, y, z),
      ];
      if (coords.length + level.length > cap) break;
      coords.addAll(level);
    }
    if (coords.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Zoom in a little first: this area is too large.'),
        ),
      );
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _saving = true);
    messenger.showSnackBar(
      SnackBar(content: Text('Saving ${coords.length} map tiles for offline…')),
    );
    final layer = TileLayer(
      urlTemplate: _osmUrl,
      userAgentPackageName: _userAgent,
      tileProvider: _tiles,
    );
    for (var i = 0; i < coords.length; i += 3) {
      await Future.wait([
        for (final c in coords.skip(i).take(3)) _warmTile(c, layer),
      ]);
      if (!mounted) return;
    }
    setState(() => _saving = false);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text('Done. This area now works offline for 30 days.'),
        ),
      );
  }

  /// Live people (not me) who are far from every other live person.
  List<Member> _stragglers() {
    final live = _members.where((m) => m.isLive && m.position != null).toList();
    if (live.length < 3) return [];
    const far = 1500.0; // metres
    return [
      for (final m in live)
        if (!m.isMe &&
            live
                .where((o) => o.id != m.id)
                .every(
                  (o) =>
                      const Distance().as(
                        LengthUnit.Meter,
                        m.position!,
                        o.position!,
                      ) >
                      far,
                ))
          m,
    ];
  }

  Future<void> _showStatus() async {
    const options = [
      'On my way',
      'Running late',
      'Found the place',
      'Need a break',
      'I am lost',
      'All good here',
    ];
    final current = _meMember?.activeStatus;
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        padding: EdgeInsets.fromLTRB(
          20,
          14,
          20,
          24 + MediaQuery.of(context).padding.bottom,
        ),
        decoration: BoxDecoration(
          color: context.bg,
          borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 44,
              height: 5,
              decoration: BoxDecoration(
                color: context.line,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Quick message',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
            Text(
              'Shown above your marker for 30 minutes',
              style: TextStyle(color: context.muted, fontSize: 12.5),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final o in options)
                  ChoiceChip(
                    label: Text(o),
                    selected: current == o,
                    onSelected: (_) => Navigator.pop(context, o),
                  ),
              ],
            ),
            if (current != null) ...[
              const SizedBox(height: 14),
              TextButton(
                onPressed: () => Navigator.pop(context, ''),
                child: const Text('Clear my message'),
              ),
            ],
          ],
        ),
      ),
    );
    if (choice == null) return;
    await widget.app.repo.setStatus(
      _code,
      _profile,
      choice.isEmpty ? null : choice,
    );
  }

  LatLng? _shown(String id) {
    final a = _from[id], b = _to[id];
    if (b == null) return null;
    if (a == null) return b;
    final t = Curves.easeInOut.transform(_move.value);
    return LatLng(
      a.latitude + (b.latitude - a.latitude) * t,
      a.longitude + (b.longitude - a.longitude) * t,
    );
  }

  LatLng? get _myShown {
    final id = _meMember?.id;
    return (id == null ? null : _shown(id)) ?? _me;
  }

  LatLng? _targetPos() {
    final t = _target;
    if (t == null) return null;
    if (t == _meetingId) return _info.meeting?.position;
    return _shown(t);
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
      final arc = (1 - (2 * t - 1) * (2 * t - 1)) * 0.8;
      _map.move(
        LatLng(
          startC.latitude + (dest.latitude - startC.latitude) * t,
          startC.longitude + (dest.longitude - startC.longitude) * t,
        ),
        startZ + (endZ - startZ) * t - arc,
      );
    }

    _fly.addListener(tick);
    _fly.forward().whenComplete(() => _fly.removeListener(tick));
  }

  void _fitPoints(List<LatLng> pts) {
    if (pts.isEmpty) return;
    if (pts.length == 1) return _flyTo(pts.first);
    _map.fitCamera(
      CameraFit.coordinates(
        coordinates: pts,
        padding: const EdgeInsets.fromLTRB(60, 160, 60, 340),
        maxZoom: 17,
      ),
    );
  }

  void _fitAll() => _fitPoints([
    ..._members.map((m) => m.position).whereType<LatLng>(),
    ?_info.meeting?.position,
  ]);

  /// Selecting a target draws a free straight guide line from you to it.
  void _selectTarget(String id) {
    if (_target == id) {
      setState(() => _target = null);
      return;
    }
    setState(() => _target = id);
    final tp = _targetPos();
    final me = _myShown;
    if (tp != null) _fitPoints([if (me != null) me, tp]);
  }

  Future<void> _openMapsTo(LatLng p) async {
    // Opens the phone's maps app for turn-by-turn; no API key needed.
    final uri = Uri.parse(
      'https://www.google.com/maps/dir/?api=1&travelmode=walking&destination=${p.latitude},${p.longitude}',
    );
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  // ---------- SOS ----------
  Future<void> _toggleSos() async {
    final active = _meMember?.sos ?? false;
    if (active) {
      await widget.app.repo.setSos(_code, _profile, false);
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        icon: const Icon(Icons.sos_rounded, color: Colors.red, size: 40),
        title: const Text('Send SOS to your group?'),
        content: const Text(
          'Everyone sees a red alert with your exact location and can navigate to you.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red,
              minimumSize: const Size(110, 46),
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Send SOS'),
          ),
        ],
      ),
    );
    if (ok == true) {
      HapticFeedback.heavyImpact();
      await widget.app.repo.setSos(_code, _profile, true);
    }
  }

  // ---------- meeting point ----------
  Future<void> _askMeeting(LatLng p) async {
    final c = TextEditingController(text: 'Meet here');
    final label = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text('Set meeting point'),
        content: TextField(
          controller: c,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'e.g. Hotel lobby, 6pm'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(100, 46)),
            onPressed: () => Navigator.pop(context, c.text.trim()),
            child: const Text('Set'),
          ),
        ],
      ),
    );
    if (label == null) return;
    await widget.app.repo.setMeeting(
      _code,
      Meeting(
        position: p,
        label: label.isEmpty ? 'Meeting point' : label,
        by: _profile.name,
      ),
    );
    HapticFeedback.mediumImpact();
  }

  // ---------- group menu ----------
  Future<void> _menu(String v) async {
    switch (v) {
      case 'invite':
        await showInviteSheet(context, widget.group);
      case 'sharing':
        await widget.app.setSharing(!widget.app.sharing);
      case 'offline':
        await _saveOffline();
      case 'trails':
        setState(() => _showTrails = !_showTrails);
      case 'straggler':
        await widget.app.setStraggler(!widget.app.straggler);
      case 'lock':
        await widget.app.repo.setLocked(_code, !_info.locked);
      case 'end':
        final ok = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
            title: const Text('End this trip?'),
            content: const Text(
              'All locations are deleted and the group closes for everyone.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: Brand.coral,
                  minimumSize: const Size(110, 46),
                ),
                onPressed: () => Navigator.pop(context, true),
                child: const Text('End trip'),
              ),
            ],
          ),
        );
        if (ok == true) {
          _isOwnerEnding = true;
          await widget.app.repo.endTrip(_code);
          await widget.app.forget(widget.group);
          if (mounted) Navigator.pop(context);
        }
      case 'leave':
        await widget.app.leave(widget.group);
        if (mounted) Navigator.pop(context);
    }
  }

  @override
  void dispose() {
    _membersSub?.cancel();
    _infoSub?.cancel();
    widget.app.myPosition.removeListener(_onMe);
    widget.app.removeListener(_onApp);
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
    final sheetTop = MediaQuery.of(context).size.height * .30 + 12;
    final sosAlerts = _members.where((m) => m.sos && !m.isMe).toList();
    final iSos = _meMember?.sos ?? false;

    return Scaffold(
      body: Stack(
        children: [
          FlutterMap(
            mapController: _map,
            options: MapOptions(
              initialCenter: start,
              initialZoom: 14,
              onLongPress: (_, p) => _askMeeting(p),
              onMapReady: () {
                _mapReady = true;
                if (!_fitted && withPos.isNotEmpty) {
                  _fitted = true;
                  _fitAll();
                }
              },
            ),
            children: [
              TileLayer(
                urlTemplate: _osmUrl,
                userAgentPackageName: _userAgent,
                tileProvider: _tiles,
                // Dark mode: invert + dim the (light) OSM tiles.
                tileBuilder: context.isDark
                    ? (ctx, tile, _) => ColorFiltered(
                        colorFilter: const ColorFilter.matrix(<double>[
                          -.78, 0, 0, 0, 215, //
                          0, -.78, 0, 0, 220,
                          0, 0, -.78, 0, 235,
                          0, 0, 0, 1, 0,
                        ]),
                        child: tile,
                      )
                    : null,
              ),
              if (_showTrails)
                PolylineLayer(
                  polylines: [
                    for (final e in _trails.entries)
                      if (e.value.length > 1)
                        Polyline(
                          points: e.value,
                          strokeWidth: 4,
                          color: Brand
                              .memberColors[(_members
                                          .where((m) => m.id == e.key)
                                          .firstOrNull
                                          ?.colorIndex ??
                                      0) %
                                  Brand.memberColors.length]
                              .withValues(alpha: .75),
                        ),
                  ],
                ),
              AnimatedBuilder(
                animation: _move,
                builder: (context, _) {
                  final a = _myShown;
                  final b = _targetPos();
                  final isSos = _members.any((m) => m.id == _target && m.sos);
                  final color = isSos ? Colors.red : Brand.indigo;
                  return Stack(
                    children: [
                      if (a != null && b != null)
                        PolylineLayer(
                          polylines: [
                            Polyline(
                              points: [a, b],
                              strokeWidth: 5,
                              color: color,
                              borderStrokeWidth: 2,
                              borderColor: Colors.white,
                              pattern: StrokePattern.dashed(
                                segments: const [14, 9],
                              ),
                            ),
                          ],
                        ),
                      MarkerLayer(
                        markers: [
                          if (a != null && b != null)
                            Marker(
                              point: LatLng(
                                (a.latitude + b.latitude) / 2,
                                (a.longitude + b.longitude) / 2,
                              ),
                              width: 150,
                              height: 40,
                              child: _LineChip(
                                meters: const Distance().as(
                                  LengthUnit.Meter,
                                  a,
                                  b,
                                ),
                                color: color,
                              ),
                            ),
                          if (_info.meeting != null)
                            Marker(
                              point: _info.meeting!.position,
                              width: 140,
                              height: 96,
                              child: GestureDetector(
                                onTap: () => _selectTarget(_meetingId),
                                child: _MeetingMarker(meeting: _info.meeting!),
                              ),
                            ),
                          for (final m in _members)
                            if (_shown(m.id) != null)
                              Marker(
                                point: _shown(m.id)!,
                                width: 110,
                                height: 110,
                                child: GestureDetector(
                                  onTap: () {
                                    if (m.isMe) {
                                      setState(() => _target = null);
                                      _flyTo(_myShown!);
                                    } else {
                                      _selectTarget(m.id);
                                    }
                                  },
                                  child: PulseMarker(member: m),
                                ),
                              ),
                        ],
                      ),
                    ],
                  );
                },
              ),
              const RichAttributionWidget(
                alignment: AttributionAlignment.bottomLeft,
                attributions: [
                  TextSourceAttribution('© OpenStreetMap contributors'),
                ],
              ),
            ],
          ),
          _TopBar(
            group: widget.group,
            info: _info,
            isOwner: _isOwner,
            liveCount: _members.where((m) => m.isLive).length,
            total: _members.length,
            sharing: widget.app.sharing,
            showTrails: _showTrails,
            straggler: widget.app.straggler,
            onInvite: () => showInviteSheet(context, widget.group),
            onMenu: _menu,
          ),
          // SOS banners from other people
          Positioned(
            top: MediaQuery.of(context).padding.top + 84,
            left: 12,
            right: 12,
            child: Column(
              children: [
                ValueListenableBuilder<bool>(
                  valueListenable: widget.app.repo.offline,
                  builder: (_, off, _) => off
                      ? const _InfoBanner(
                          icon: Icons.cloud_off_rounded,
                          color: Colors.blueGrey,
                          text: 'No connection. Showing last known locations; your updates send when you are back online.',
                        )
                      : const SizedBox.shrink(),
                ),
                if (widget.app.straggler)
                  for (final s in _stragglers())
                    if (!_stragDismissed.contains(s.id))
                      _InfoBanner(
                        key: ValueKey('far${s.id}'),
                        icon: Icons.social_distance_rounded,
                        color: Colors.orange.shade800,
                        text: '${s.name} is far from the group',
                        actionLabel: 'Find',
                        onAction: () => _selectTarget(s.id),
                        onClose: () =>
                            setState(() => _stragDismissed.add(s.id)),
                      ),
                for (final m in sosAlerts)
                  _SosBanner(
                    key: ValueKey(m.id),
                    member: m,
                    meters: _myShown == null || m.position == null
                        ? null
                        : const Distance().as(
                            LengthUnit.Meter,
                            _myShown!,
                            m.position!,
                          ),
                    onGo: () {
                      setState(() => _target = null);
                      _selectTarget(m.id);
                    },
                  ),
              ],
            ),
          ),
          // right-hand buttons
          Positioned(
            right: 16,
            bottom: sheetTop,
            child: Column(
              children: [
                _SosButton(active: iSos, onTap: _toggleSos),
                const SizedBox(height: 10),
                _RoundButton(
                  icon: Icons.chat_bubble_rounded,
                  onTap: _showStatus,
                ),
                const SizedBox(height: 10),
                _RoundButton(icon: Icons.zoom_out_map_rounded, onTap: _fitAll),
                const SizedBox(height: 10),
                _RoundButton(
                  icon: Icons.my_location_rounded,
                  onTap: () {
                    final p = _myShown;
                    if (p != null) _flyTo(p);
                  },
                ),
              ],
            ),
          ),
          // active direction card
          Positioned(
            left: 16,
            right: 84,
            bottom: sheetTop,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              transitionBuilder: (c, a) => FadeTransition(
                opacity: a,
                child: SlideTransition(
                  position: Tween(
                    begin: const Offset(0, .3),
                    end: Offset.zero,
                  ).animate(a),
                  child: c,
                ),
              ),
              child: _target == null
                  ? const SizedBox.shrink(key: ValueKey('none'))
                  : _DirectionCard(
                      key: ValueKey(_target),
                      title: _target == _meetingId
                          ? (_info.meeting?.label ?? 'Meeting point')
                          : (_members
                                    .where((m) => m.id == _target)
                                    .firstOrNull
                                    ?.name ??
                                ''),
                      sos: _members.any((m) => m.id == _target && m.sos),
                      meters: (_myShown == null || _targetPos() == null)
                          ? null
                          : const Distance().as(
                              LengthUnit.Meter,
                              _myShown!,
                              _targetPos()!,
                            ),
                      onClose: () => setState(() => _target = null),
                      onMaps: () {
                        final p = _targetPos();
                        if (p != null) _openMapsTo(p);
                      },
                    ),
            ),
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
              meeting: _info.meeting,
              me: _myShown,
              target: _target,
              onTap: (m) {
                if (m.isMe) {
                  setState(() => _target = null);
                  if (_myShown != null) _flyTo(_myShown!);
                } else {
                  _selectTarget(m.id);
                }
              },
              onTapMeeting: () => _selectTarget(_meetingId),
              onClearMeeting: () async {
                await widget.app.repo.setMeeting(_code, null);
              },
              onNavigate: (m) {
                if (m.position != null) _openMapsTo(m.position!);
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ======================= widgets =======================

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.group,
    required this.info,
    required this.isOwner,
    required this.liveCount,
    required this.total,
    required this.sharing,
    required this.showTrails,
    required this.straggler,
    required this.onInvite,
    required this.onMenu,
  });
  final Group group;
  final GroupInfo info;
  final bool isOwner, sharing, showTrails, straggler;
  final int liveCount, total;
  final VoidCallback onInvite;
  final ValueChanged<String> onMenu;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 10,
      left: 12,
      right: 12,
      child: FadeSlide(
        child: Container(
          padding: const EdgeInsets.fromLTRB(4, 4, 4, 4),
          decoration: BoxDecoration(
            color: context.surface.withValues(alpha: .95),
            borderRadius: BorderRadius.circular(26),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: .15),
                blurRadius: 20,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            children: [
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.arrow_back_rounded),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            group.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 16,
                            ),
                          ),
                        ),
                        if (info.locked) ...[
                          const SizedBox(width: 6),
                          Icon(
                            Icons.lock_rounded,
                            size: 14,
                            color: context.muted,
                          ),
                        ],
                      ],
                    ),
                    Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          margin: const EdgeInsets.only(right: 6),
                          decoration: BoxDecoration(
                            color: sharing ? Brand.teal : Colors.orange,
                            shape: BoxShape.circle,
                          ),
                        ),
                        Flexible(
                          child: Text(
                            sharing
                                ? '$liveCount of $total live'
                                : 'Sharing paused',
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              color: context.muted,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              IconButton.filledTonal(
                tooltip: 'Invite (QR)',
                onPressed: onInvite,
                icon: const Icon(Icons.qr_code_2_rounded),
              ),
              PopupMenuButton<String>(
                onSelected: onMenu,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
                itemBuilder: (_) => [
                  const PopupMenuItem(
                    value: 'invite',
                    child: _MenuRow(
                      Icon(Icons.qr_code_2_rounded),
                      Text('Invite with QR'),
                    ),
                  ),
                  PopupMenuItem(
                    value: 'sharing',
                    child: _MenuRow(
                      Icon(
                        sharing
                            ? Icons.pause_circle_rounded
                            : Icons.play_circle_rounded,
                      ),
                      Text(sharing ? 'Pause my sharing' : 'Resume sharing'),
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'offline',
                    child: _MenuRow(
                      Icon(Icons.download_for_offline_rounded),
                      Text('Save this area offline'),
                    ),
                  ),
                  PopupMenuItem(
                    value: 'trails',
                    child: _MenuRow(
                      const Icon(Icons.timeline_rounded),
                      Text(showTrails ? 'Hide trails' : 'Show trails'),
                    ),
                  ),
                  PopupMenuItem(
                    value: 'straggler',
                    child: _MenuRow(
                      const Icon(Icons.social_distance_rounded),
                      Text(
                        straggler
                            ? 'Turn off far-away alerts'
                            : 'Alert me if someone is far',
                      ),
                    ),
                  ),
                  if (isOwner)
                    PopupMenuItem(
                      value: 'lock',
                      child: _MenuRow(
                        Icon(
                          info.locked
                              ? Icons.lock_open_rounded
                              : Icons.lock_rounded,
                        ),
                        Text(
                          info.locked
                              ? 'Unlock group'
                              : 'Lock group (no new joins)',
                        ),
                      ),
                    ),
                  if (isOwner)
                    const PopupMenuItem(
                      value: 'end',
                      child: _MenuRow(
                        Icon(Icons.flag_rounded, color: Brand.coral),
                        Text('End trip'),
                      ),
                    ),
                  if (!isOwner)
                    const PopupMenuItem(
                      value: 'leave',
                      child: _MenuRow(
                        Icon(Icons.logout_rounded),
                        Text('Leave group'),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoBanner extends StatelessWidget {
  const _InfoBanner({
    super.key,
    required this.icon,
    required this.color,
    required this.text,
    this.actionLabel,
    this.onAction,
    this.onClose,
  });
  final IconData icon;
  final Color color;
  final String text;
  final String? actionLabel;
  final VoidCallback? onAction, onClose;

  @override
  Widget build(BuildContext context) {
    return FadeSlide(
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.fromLTRB(14, 8, 6, 8),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(18),
          boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 10)],
        ),
        child: Row(
          children: [
            Icon(icon, color: Colors.white, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                text,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (actionLabel != null)
              TextButton(
                onPressed: onAction,
                style: TextButton.styleFrom(foregroundColor: Colors.white),
                child: Text(
                  actionLabel!,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            if (onClose != null)
              IconButton(
                onPressed: onClose,
                icon: const Icon(
                  Icons.close_rounded,
                  color: Colors.white70,
                  size: 20,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _MenuRow extends StatelessWidget {
  const _MenuRow(this.icon, this.label);
  final Icon icon;
  final Text label;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      icon,
      const SizedBox(width: 14),
      Flexible(child: label),
    ],
  );
}

class _LineChip extends StatelessWidget {
  const _LineChip({required this.meters, required this.color});
  final double meters;
  final Color color;

  @override
  Widget build(BuildContext context) => Center(
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 6)],
      ),
      child: Text(
        '${formatDistance(meters)} · ${walkTime(meters)}',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
  );
}

class _MeetingMarker extends StatelessWidget {
  const _MeetingMarker({required this.meeting});
  final Meeting meeting;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 700),
      curve: Curves.elasticOut,
      builder: (_, v, child) => Transform.scale(
        scale: v,
        alignment: Alignment.bottomCenter,
        child: child,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            constraints: const BoxConstraints(maxWidth: 130),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: Brand.ink,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              meeting.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: Brand.teal,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 3),
              boxShadow: const [
                BoxShadow(color: Colors.black26, blurRadius: 8),
              ],
            ),
            child: const Icon(Icons.flag_rounded, color: Colors.white),
          ),
        ],
      ),
    );
  }
}

class _SosBanner extends StatefulWidget {
  const _SosBanner({
    super.key,
    required this.member,
    required this.meters,
    required this.onGo,
  });
  final Member member;
  final double? meters;
  final VoidCallback onGo;

  @override
  State<_SosBanner> createState() => _SosBannerState();
}

class _SosBannerState extends State<_SosBanner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeSlide(
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, child) => Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
          decoration: BoxDecoration(
            color: Color.lerp(
              Colors.red.shade700,
              Colors.red.shade500,
              _c.value,
            ),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.red.withValues(alpha: .3 + .3 * _c.value),
                blurRadius: 16 + 10 * _c.value,
              ),
            ],
          ),
          child: child,
        ),
        child: Row(
          children: [
            const Icon(Icons.sos_rounded, color: Colors.white, size: 28),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${widget.member.name} needs help',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                    ),
                  ),
                  if (widget.meters != null)
                    Text(
                      '${formatDistance(widget.meters!)} away · ${walkTime(widget.meters!)}',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                      ),
                    ),
                ],
              ),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: Colors.red.shade700,
                minimumSize: const Size(72, 40),
                padding: const EdgeInsets.symmetric(horizontal: 16),
              ),
              onPressed: widget.onGo,
              child: const Text('Go'),
            ),
          ],
        ),
      ),
    );
  }
}

class _SosButton extends StatelessWidget {
  const _SosButton({required this.active, required this.onTap});
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => AnimatedContainer(
    duration: const Duration(milliseconds: 300),
    decoration: BoxDecoration(
      color: active ? Colors.white : Colors.red,
      borderRadius: BorderRadius.circular(28),
      border: Border.all(color: Colors.red, width: 2),
      boxShadow: [
        BoxShadow(
          color: Colors.red.withValues(alpha: .35),
          blurRadius: 14,
          offset: const Offset(0, 5),
        ),
      ],
    ),
    child: Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(28),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                active ? Icons.close_rounded : Icons.sos_rounded,
                color: active ? Colors.red : Colors.white,
              ),
              const SizedBox(width: 6),
              Text(
                active ? 'Cancel' : 'SOS',
                style: TextStyle(
                  color: active ? Colors.red : Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _DirectionCard extends StatelessWidget {
  const _DirectionCard({
    super.key,
    required this.title,
    required this.sos,
    required this.meters,
    required this.onClose,
    required this.onMaps,
  });
  final String title;
  final bool sos;
  final double? meters;
  final VoidCallback onClose, onMaps;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 6, 10),
      decoration: BoxDecoration(
        color: context.surface,
        borderRadius: BorderRadius.circular(22),
        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 16)],
      ),
      child: Row(
        children: [
          Icon(Icons.near_me_rounded, color: sos ? Colors.red : Brand.indigo),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                Text(
                  meters == null
                      ? 'Waiting for location…'
                      : '${formatDistance(meters!)} · ${walkTime(meters!)}',
                  style: TextStyle(fontSize: 12, color: context.muted),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Open walking directions',
            onPressed: onMaps,
            icon: const Icon(Icons.directions_walk_rounded),
          ),
          IconButton(onPressed: onClose, icon: const Icon(Icons.close_rounded)),
        ],
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
    color: context.surface,
    elevation: 6,
    shadowColor: Colors.black38,
    shape: const CircleBorder(),
    child: InkWell(
      customBorder: const CircleBorder(),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(13),
        child: Icon(icon, color: context.text),
      ),
    ),
  );
}

class _MemberSheet extends StatelessWidget {
  const _MemberSheet({
    required this.controller,
    required this.members,
    required this.meeting,
    required this.me,
    required this.target,
    required this.onTap,
    required this.onTapMeeting,
    required this.onClearMeeting,
    required this.onNavigate,
  });
  final ScrollController controller;
  final List<Member> members;
  final Meeting? meeting;
  final LatLng? me;
  final String? target;
  final ValueChanged<Member> onTap;
  final VoidCallback onTapMeeting, onClearMeeting;
  final ValueChanged<Member> onNavigate;

  String _distance(LatLng? p) {
    if (me == null || p == null) return '';
    return '${formatDistance(const Distance().as(LengthUnit.Meter, me!, p))} away';
  }

  @override
  Widget build(BuildContext context) {
    final extra = meeting != null ? 1 : 0;
    return Container(
      decoration: BoxDecoration(
        color: context.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .18),
            blurRadius: 24,
            offset: const Offset(0, -6),
          ),
        ],
      ),
      child: ListView.builder(
        controller: controller,
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
        itemCount: members.length + 1 + extra,
        itemBuilder: (context, i) {
          if (i == 0) {
            return Column(
              children: [
                Container(
                  width: 44,
                  height: 5,
                  decoration: BoxDecoration(
                    color: context.line,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(height: 14),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Your crew',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                  ),
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Tap a person for a guide line. Long-press the map to set a meeting point.',
                    style: TextStyle(fontSize: 12, color: context.muted),
                  ),
                ),
                const SizedBox(height: 8),
              ],
            );
          }
          if (meeting != null && i == 1) {
            final active = target == _meetingId;
            return _tile(
              active: active,
              onTap: onTapMeeting,
              leading: Container(
                width: 44,
                height: 44,
                decoration: const BoxDecoration(
                  color: Brand.teal,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.flag_rounded, color: Colors.white),
              ),
              title: meeting!.label,
              subtitle: [
                if (meeting!.by.isNotEmpty) 'Set by ${meeting!.by}',
                _distance(meeting!.position),
              ].where((s) => s.isNotEmpty).join(' · '),
              trailing: IconButton(
                tooltip: 'Remove meeting point',
                onPressed: onClearMeeting,
                icon: const Icon(Icons.close_rounded),
              ),
            );
          }
          final m = members[i - 1 - extra];
          return _tile(
            active: target == m.id,
            onTap: () => onTap(m),
            leading: Avatar(
              name: m.name,
              colorIndex: m.colorIndex,
              emoji: m.emoji,
            ),
            title: m.isMe ? 'You' : m.name,
            titleColor: m.sos ? Colors.red : null,
            dot: m.sos ? Colors.red : (m.isLive ? Brand.teal : context.subtle),
            subtitle: [
              if (m.sos) 'SOS - needs help',
              if (m.activeStatus != null) '"${m.activeStatus}"',
              m.lastSeen,
              if (!m.isMe) _distance(m.position),
            ].where((s) => s.isNotEmpty).join(' · '),
            trailing: m.isMe || m.position == null
                ? null
                : IconButton.filledTonal(
                    tooltip: 'Walking directions',
                    onPressed: () => onNavigate(m),
                    icon: const Icon(Icons.directions_walk_rounded),
                  ),
          );
        },
      ),
    );
  }

  Widget _tile({
    required bool active,
    required VoidCallback onTap,
    required Widget leading,
    required String title,
    required String subtitle,
    Widget? trailing,
    Color? dot,
    Color? titleColor,
  }) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      margin: const EdgeInsets.symmetric(vertical: 3),
      decoration: BoxDecoration(
        color: active ? Brand.indigo.withValues(alpha: .1) : Colors.transparent,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: ListTile(
          onTap: onTap,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          leading: leading,
          title: Text(
            title,
            style: TextStyle(fontWeight: FontWeight.w700, color: titleColor),
          ),
          subtitle: Row(
            children: [
              if (dot != null)
                Container(
                  width: 8,
                  height: 8,
                  margin: const EdgeInsets.only(right: 6),
                  decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
                ),
              Flexible(child: Text(subtitle, overflow: TextOverflow.ellipsis)),
            ],
          ),
          trailing: trailing,
        ),
      ),
    );
  }
}
