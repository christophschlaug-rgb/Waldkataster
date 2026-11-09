import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:path_provider/path_provider.dart';

import '../app_config.dart';
import '../models/forest_models.dart';
import '../models/marked_point.dart';
import '../services/flurstueck_service.dart';
import '../services/geo_utils.dart';
import '../widgets/stand_editor.dart';
import 'forest_screen.dart';
import 'object_sheet.dart';
import 'parcel_screen.dart';
import '../services/db_service.dart';
import '../services/grenzpunkt_service.dart';
import '../services/heading_tracker.dart';
import '../services/settings_store.dart';
import '../services/tile_cache.dart';
import '../services/wms_service.dart';
import '../widgets/map_widgets.dart';
import 'diagnostics_screen.dart';
import 'point_sheet.dart';
import 'points_screen.dart';

/// Grenzpunkte werden erst ab dieser Zoomstufe geladen und angezeigt.
const double kPointsMinZoom = 16;

class _Sample {
  final double lat;
  final double lon;
  final double acc;
  const _Sample(this.lat, this.lon, this.acc);
}

class _ParcelView {
  final Parcel parcel;
  final ParcelGeometry geometry;
  final LatLng centroid;
  _ParcelView(this.parcel, this.geometry) : centroid = geometry.centroid;
}

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> with WidgetsBindingObserver {
  static const MethodChannel _screenChannel =
      MethodChannel('de.waldkataster.app/screen');

  final MapController _map = MapController();
  final HeadingTracker _heading = HeadingTracker();
  final Distance _distance = const Distance();
  final ValueNotifier<double> _zoom = ValueNotifier<double>(9);
  // Nur in halben Zoomstufen aktualisiert, damit die Marker beim Zoomen
  // nicht dauernd neu gezeichnet werden.
  final ValueNotifier<double> _dotZoom = ValueNotifier<double>(9);

  MapSettings _settings = MapSettings();
  Map<String, WmsService> _services = {};
  TileCachingClient? _client;
  NetworkTileProvider? _provider;

  bool _loading = true;
  String? _fatal;
  String? _dbError;

  Position? _pos;
  StreamSubscription<Position>? _posSub;
  String? _locationMessage;
  bool _follow = true;
  bool _mapReady = false;
  bool _firstFixDone = false;
  DateTime _lastRotate = DateTime.fromMillisecondsSinceEpoch(0);

  final Map<String, int> _tileErrors = {};
  String? _lastTileError;

  // Punkte
  Map<String, MarkedPoint> _saved = {};
  List<CadastralPoint> _cad = [];
  LatLngBounds? _loadedBounds;
  Timer? _loadTimer;
  bool _loadingPoints = false;
  String? _pointsMessage;
  String? _pointsDiag;

  // Ziel und Messung
  String? _targetId;
  String _targetName = '';
  LatLng? _targetPos;
  int? _lastBand;
  bool _measuring = false;
  DateTime? _measureEnd;
  Timer? _measureTimer;
  final List<_Sample> _samples = [];

  // Mein Wald
  List<_ParcelView> _parcels = [];
  List<Dept> _depts = [];
  List<ForestObject> _objects = [];
  bool _pickMode = false;
  bool _pickBusy = false;
  FlurstueckHit? _pending;

  static const List<Color> _deptPalette = [
    Color(0xFF8E24AA),
    Color(0xFF00897B),
    Color(0xFFD81B60),
    Color(0xFF3949AB),
    Color(0xFF7CB342),
    Color(0xFF6D4C41),
    Color(0xFF00ACC1),
    Color(0xFFF4511E),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _heading.heading.addListener(_onHeading);
    _bootstrap();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _posSub?.cancel();
    _loadTimer?.cancel();
    _measureTimer?.cancel();
    _heading.heading.removeListener(_onHeading);
    _heading.dispose();
    _zoom.dispose();
    _dotZoom.dispose();
    _client?.close();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _stopSensors();
    } else if (state == AppLifecycleState.resumed && !_loading) {
      _startSensors();
    }
  }

  // ------------------------------------------------------------- Start

  Future<Map<String, WmsService>> _loadServices({bool force = false}) async {
    final list = await Future.wait(
      kServiceDefs.map((d) => WmsCatalog.load(d, forceRefresh: force)),
    );
    return {for (final s in list) s.def.id: s};
  }

  Future<void> _bootstrap() async {
    try {
      final settings = await MapSettings.load();
      final support = await getApplicationSupportDirectory();
      final tileDir = Directory('${support.path}/tiles');
      if (!await tileDir.exists()) await tileDir.create(recursive: true);
      unawaited(cleanTileCache(tileDir));

      Map<String, MarkedPoint> saved = {};
      String? dbError;
      List<Parcel> parcels = [];
      List<Dept> depts = [];
      List<ForestObject> objects = [];
      try {
        final list = await DbService.instance.all();
        saved = {for (final p in list) p.id: p};
        parcels = await DbService.instance.parcels();
        depts = await DbService.instance.depts();
        objects = await DbService.instance.objects();
      } catch (e) {
        dbError = e.toString();
      }

      final client = TileCachingClient(http.Client(), tileDir);
      final services = await _loadServices();
      if (!mounted) {
        client.close();
        return;
      }
      setState(() {
        _settings = settings;
        _saved = saved;
        _depts = depts;
        _setParcels(parcels);
        _objects = objects;
        _dbError = dbError;
        _client = client;
        _provider = NetworkTileProvider(httpClient: client);
        _services = services;
        _loading = false;
      });
      _startSensors();
      _applyKeepAwake();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _fatal = e.toString();
        _loading = false;
      });
    }
  }

  // ---------------------------------------------------------- Sensoren

  void _startSensors() {
    _startLocation();
    _heading.start();
  }

  void _stopSensors() {
    _posSub?.cancel();
    _posSub = null;
    _heading.stop();
  }

  Future<void> _startLocation() async {
    if (_posSub != null) return;
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        if (mounted) {
          setState(() => _locationMessage =
              'Die Standortdienste des Handys sind ausgeschaltet.');
        }
        return;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (mounted) {
          setState(() => _locationMessage =
              'Ohne Standortfreigabe kann die Position nicht angezeigt '
              'werden. Bitte in den Android-Einstellungen erlauben.');
        }
        return;
      }
      _posSub = Geolocator.getPositionStream(
        locationSettings: AndroidSettings(
          accuracy: LocationAccuracy.best,
          distanceFilter: 0,
          intervalDuration: const Duration(seconds: 1),
        ),
      ).listen(
        _onPosition,
        onError: (Object e) {
          if (mounted) setState(() => _locationMessage = 'GPS-Fehler: $e');
        },
      );
    } catch (e) {
      if (mounted) setState(() => _locationMessage = 'GPS nicht verfügbar: $e');
    }
  }

  void _onPosition(Position p) {
    if (!mounted) return;
    setState(() {
      _pos = p;
      _locationMessage = null;
    });

    if (_measuring && p.accuracy <= 40) {
      _samples.add(_Sample(p.latitude, p.longitude, p.accuracy));
    }
    _updateHaptics(p);

    if (!_mapReady) return;
    final ll = LatLng(p.latitude, p.longitude);
    if (!_firstFixDone) {
      _firstFixDone = true;
      _follow = true;
      _map.move(ll, 17);
    } else if (_follow) {
      _map.move(ll, _map.camera.zoom);
    }
  }

  /// Kurze Vibration, wenn man dem Ziel naeher kommt (10 m, 5 m, 2 m).
  void _updateHaptics(Position p) {
    final target = _targetPos;
    if (target == null) return;
    final d = _distance.as(
      LengthUnit.Meter,
      LatLng(p.latitude, p.longitude),
      target,
    );
    final band = d > 10 ? 3 : (d > 5 ? 2 : (d > 2 ? 1 : 0));
    final last = _lastBand;
    if (last != null && band != last) {
      if (band < last) {
        HapticFeedback.heavyImpact();
      } else {
        HapticFeedback.lightImpact();
      }
    }
    _lastBand = band;
  }

  void _onHeading() {
    final h = _heading.heading.value;
    if (h == null || !_settings.headingUp || !_mapReady) return;
    final now = DateTime.now();
    if (now.difference(_lastRotate).inMilliseconds < 120) return;
    _lastRotate = now;
    _map.rotate(-h); // Blickrichtung nach oben
  }

  void _onMapReady() {
    _mapReady = true;
    final p = _pos;
    if (p != null) {
      _firstFixDone = true;
      _map.move(LatLng(p.latitude, p.longitude), 17);
    }
    if (_settings.headingUp) {
      final h = _heading.heading.value;
      if (h != null) _map.rotate(-h);
    }
    _zoom.value = _map.camera.zoom;
    _dotZoom.value = (_map.camera.zoom * 2).floor() / 2;
    _scheduleLoadPoints(_map.camera);
  }

  void _onCameraChanged(MapCamera camera, bool hasGesture) {
    _zoom.value = camera.zoom;
    final q = (camera.zoom * 2).floor() / 2;
    if (q != _dotZoom.value) _dotZoom.value = q;
    if (hasGesture && _follow) setState(() => _follow = false);
    _scheduleLoadPoints(camera);
  }

  Future<void> _applyKeepAwake() async {
    try {
      await _screenChannel
          .invokeMethod<void>('keepOn', {'on': _settings.keepAwake});
    } catch (_) {}
  }

  // ------------------------------------------------------ Grenzpunkte

  void _scheduleLoadPoints(MapCamera camera) {
    _loadTimer?.cancel();
    if (!_settings.pointsOn) return;
    _loadTimer = Timer(
      const Duration(milliseconds: 700),
      () => _loadPoints(camera),
    );
  }

  Future<void> _loadPoints(MapCamera camera) async {
    if (!mounted || !_settings.pointsOn) return;

    if (camera.zoom < kPointsMinZoom) {
      if (_cad.isNotEmpty || _pointsMessage == null) {
        setState(() {
          _cad = [];
          _loadedBounds = null;
          _pointsMessage = 'Für Grenzpunkte näher heranzoomen';
        });
      }
      return;
    }

    final b = camera.visibleBounds;
    final lb = _loadedBounds;
    if (lb != null && lb.contains(b.northWest) && lb.contains(b.southEast)) {
      return;
    }

    final dLat = (b.north - b.south) * 0.3;
    final dLon = (b.east - b.west) * 0.3;
    final west = b.west - dLon;
    final south = b.south - dLat;
    final east = b.east + dLon;
    final north = b.north + dLat;

    setState(() => _loadingPoints = true);
    final res = await GrenzpunktService.fetch(west, south, east, north);
    if (!mounted) return;
    setState(() {
      _loadingPoints = false;
      if (res.error != null) {
        _loadedBounds = null;
        _pointsMessage = 'Grenzpunkte nicht geladen: ${res.error}';
        _pointsDiag = 'Fehler: ${res.error}';
      } else {
        _cad = res.points;
        _loadedBounds = LatLngBounds(LatLng(south, west), LatLng(north, east));
        _pointsMessage = null;
        _pointsDiag = '${res.points.length} Grenzpunkte geladen '
            '(${res.pages} Seite(n)'
            '${res.matched != null ? ', laut Dienst ${res.matched} im Ausschnitt' : ''})';
      }
    });
  }

  // ------------------------------------------------------------ Punkte

  Future<void> _savePoint(MarkedPoint p) async {
    try {
      await DbService.instance.upsert(p);
      if (!mounted) return;
      setState(() {
        _saved[p.id] = p;
        if (_targetId == p.id) _targetName = p.name;
      });
    } catch (e) {
      _snack('Speichern nicht möglich: $e');
    }
  }

  Future<void> _deletePoint(MarkedPoint p) async {
    try {
      await DbService.instance.delete(p.id);
      if (!mounted) return;
      setState(() {
        _saved.remove(p.id);
        if (_targetId == p.id) _clearTarget();
      });
    } catch (e) {
      _snack('Löschen nicht möglich: $e');
    }
  }

  Future<void> _openPointSheet(
    MarkedPoint p, {
    Map<String, dynamic>? attrs,
  }) async {
    Map<String, dynamic>? attributes = attrs;
    if (attributes == null && p.attributesJson != null) {
      try {
        attributes =
            (jsonDecode(p.attributesJson!) as Map).cast<String, dynamic>();
      } catch (_) {}
    }
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => PointSheet(
        point: p,
        attributes: attributes,
        isTarget: _targetId == p.id,
        onSave: _savePoint,
        onToggleTarget: () {
          Navigator.pop(ctx);
          if (_targetId == p.id) {
            setState(_clearTarget);
          } else {
            _setTarget(p);
          }
        },
        onDelete: p.isOwn ? () => _deletePoint(p) : null,
      ),
    );
  }

  void _onCadastralTap(CadastralPoint c) {
    final id = 'k:${c.id}';
    final p = _saved[id] ??
        MarkedPoint(
          id: id,
          kind: 'kataster',
          name: 'Grenzpunkt ${c.title}',
          lat: c.lat,
          lon: c.lon,
          attributesJson: jsonEncode(c.properties),
          updatedAt: DateTime.now(),
        );
    _openPointSheet(p, attrs: c.properties);
  }

  int get _ownCount => _saved.values.where((p) => p.isOwn).length;

  double _meters(LatLng from, double lat, double lon) {
    final dy = (lat - from.latitude) * 110574.0;
    final dx = (lon - from.longitude) *
        111320.0 *
        math.cos(from.latitude * math.pi / 180);
    return math.sqrt(dx * dx + dy * dy);
  }

  /// Antippen der Karte: der naechste Punkt bzw. das naechste Objekt in ca.
  /// 26 Bildpunkten Umkreis wird geoeffnet. Sonst gilt: im Auswahlmodus wird
  /// das Flurstueck geladen, sonst die angetippte eigene Parzelle gezeigt.
  void _onMapTap(LatLng tap) {
    final zoom = _map.camera.zoom;
    final metersPerPixel =
        156543.034 * math.cos(tap.latitude * math.pi / 180) / math.pow(2, zoom);
    double best = 26 * metersPerPixel;
    CadastralPoint? cad;
    MarkedPoint? own;
    ForestObject? obj;

    if (_settings.pointsOn) {
      for (final c in _cad) {
        final d = _meters(tap, c.lat, c.lon);
        if (d < best) {
          best = d;
          cad = c;
          own = null;
          obj = null;
        }
      }
    }
    for (final p in _saved.values) {
      if (!p.isOwn) continue;
      final d = _meters(tap, p.lat, p.lon);
      if (d < best) {
        best = d;
        own = p;
        cad = null;
        obj = null;
      }
    }
    for (final o in _objects) {
      final d = _meters(tap, o.lat, o.lon);
      if (d < best) {
        best = d;
        obj = o;
        own = null;
        cad = null;
      }
    }

    if (obj != null) {
      _openObjectSheet(obj);
      return;
    }
    if (own != null) {
      _openPointSheet(own);
      return;
    }
    if (cad != null) {
      _onCadastralTap(cad);
      return;
    }

    for (final v in _parcels) {
      if (v.geometry.contains(tap)) {
        _showParcelQuick(v.parcel);
        return;
      }
    }
    if (_pickMode) _pickParcelAt(tap);
  }

  // ------------------------------------------------------ Mein Wald

  Color _deptColor(String? deptId) {
    if (deptId == null) return const Color(0xFFFFA000);
    final i = _depts.indexWhere((d) => d.id == deptId);
    if (i < 0) return const Color(0xFFFFA000);
    return _deptPalette[i % _deptPalette.length];
  }

  void _setParcels(List<Parcel> list) {
    final views = <_ParcelView>[];
    for (final p in list) {
      final g = ParcelGeometry.fromJsonString(p.geometryJson);
      if (g != null) views.add(_ParcelView(p, g));
    }
    _parcels = views;
  }

  Future<void> _reloadForest() async {
    try {
      final parcels = await DbService.instance.parcels();
      final depts = await DbService.instance.depts();
      final objects = await DbService.instance.objects();
      if (!mounted) return;
      setState(() {
        _depts = depts;
        _setParcels(parcels);
        _objects = objects;
      });
    } catch (e) {
      _snack('Daten konnten nicht geladen werden: $e');
    }
  }

  String? _parcelIdAt(LatLng p) {
    for (final v in _parcels) {
      if (v.geometry.contains(p)) return v.parcel.id;
    }
    return null;
  }

  String? _parcelName(String? id) {
    if (id == null) return null;
    for (final v in _parcels) {
      if (v.parcel.id == id) return v.parcel.name;
    }
    return null;
  }

  void _fitPoints(List<LatLng> pts) {
    if (pts.isEmpty) {
      _snack('Noch keine Parzellen vorhanden.');
      return;
    }
    if (!_mapReady) return;
    setState(() => _follow = false);
    _map.fitCamera(
      CameraFit.bounds(
        bounds: LatLngBounds.fromPoints(pts),
        padding: const EdgeInsets.all(48),
      ),
    );
  }

  Future<void> _handleAction(String? r) async {
    if (r == null) return;
    final i = r.indexOf(':');
    if (i < 0) return;
    final kind = r.substring(0, i);
    final id = r.substring(i + 1);
    if (kind == 'parcel') {
      for (final v in _parcels) {
        if (v.parcel.id == id) {
          _fitPoints(v.geometry.allPoints);
          return;
        }
      }
    } else if (kind == 'dept') {
      _fitPoints([
        for (final v in _parcels)
          if (v.parcel.deptId == id) ...v.geometry.allPoints,
      ]);
    } else if (kind == 'object') {
      for (final o in _objects) {
        if (o.id == id) {
          if (_mapReady) {
            setState(() => _follow = false);
            _map.move(LatLng(o.lat, o.lon), 19);
          }
          await _openObjectSheet(o);
          return;
        }
      }
    }
  }

  Future<void> _openForest() async {
    final r = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const ForestScreen()),
    );
    await _reloadForest();
    await _handleAction(r);
  }

  Future<void> _openParcel(Parcel p) async {
    final r = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => ParcelScreen(parcel: p)),
    );
    await _reloadForest();
    await _handleAction(r);
  }

  void _showParcelQuick(Parcel p) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                p.name,
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Text('Flurstück: ${p.label.isEmpty ? '–' : p.label}'),
              Text('Fläche: ${formatArea(p.area)}'),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: () {
                  Navigator.pop(ctx);
                  _openParcel(p);
                },
                icon: const Icon(Icons.description_outlined),
                label: const Text('Steckbrief öffnen'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Auswahlmodus: Flurstueck an der angetippten Stelle laden und als
  /// eigene Parzelle speichern.
  Future<void> _pickParcelAt(LatLng at) async {
    if (_pickBusy) return;
    setState(() => _pickBusy = true);
    final res = await FlurstueckService.at(at);
    if (!mounted) return;
    setState(() => _pickBusy = false);

    final hit = res.hit;
    if (hit == null) {
      _snack(res.error ?? 'Kein Flurstück gefunden.');
      return;
    }

    setState(() => _pending = hit);
    final controller = TextEditingController(text: hit.label);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Parzelle speichern'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Flurstück: ${hit.label}\nFläche: ${formatArea(hit.area)}'),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Name der Parzelle',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Speichern'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    setState(() => _pending = null);
    if (name == null || name.isEmpty) return;

    try {
      await DbService.instance.upsertParcel(
        Parcel(
          id: 'f:${hit.id}',
          name: name,
          label: hit.label,
          area: hit.area,
          geometryJson: hit.geometry.toJsonString(),
          attrsJson: jsonEncode(hit.props),
          updatedAt: DateTime.now(),
        ),
      );
      await _reloadForest();
      _snack('Parzelle "$name" gespeichert');
    } catch (e) {
      _snack('Speichern nicht möglich: $e');
    }
  }

  // -------------------------------------------- Jagdeinrichtung, Habitatbaum

  Future<void> _showCreateMenu(LatLng at, {double? accuracy}) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.adjust),
              title: const Text('Eigener Punkt'),
              subtitle: const Text('Markierung mit Status und Notiz'),
              onTap: () => Navigator.pop(ctx, 'point'),
            ),
            ListTile(
              leading: const Icon(Icons.cabin),
              title: const Text('Jagdeinrichtung'),
              subtitle: const Text('Leiter, Bock, Kanzel'),
              onTap: () => Navigator.pop(ctx, 'jagd'),
            ),
            ListTile(
              leading: const Icon(Icons.park),
              title: const Text('Habitatbaum'),
              onTap: () => Navigator.pop(ctx, 'habitat'),
            ),
          ],
        ),
      ),
    );
    if (choice == 'point') {
      await _createOwnPoint(at);
    } else if (choice == 'jagd' || choice == 'habitat') {
      await _createObject(choice!, at, accuracy);
    }
  }

  void _showCreateMenuHere() {
    final p = _pos;
    if (p == null) {
      _snack(_locationMessage ?? 'Noch kein GPS-Signal.');
      return;
    }
    _showCreateMenu(LatLng(p.latitude, p.longitude), accuracy: p.accuracy);
  }

  Future<void> _createObject(String kind, LatLng at, double? accuracy) async {
    final o = ForestObject(
      id: newId('o'),
      kind: kind,
      lat: at.latitude,
      lon: at.longitude,
      accuracy: accuracy,
      parcelId: _parcelIdAt(at),
      updatedAt: DateTime.now(),
    );
    await _openObjectSheet(o, isNew: true);
  }

  Future<void> _openObjectSheet(ForestObject o, {bool isNew = false}) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => ObjectSheet(
        object: o,
        isNew: isNew,
        parcelName: _parcelName(o.parcelId),
        onSave: _saveObject,
        onDelete: () => _deleteObject(o),
        onTarget: () => _setTargetRaw(
          id: o.id,
          name: o.title,
          lat: o.lat,
          lon: o.lon,
        ),
      ),
    );
  }

  Future<void> _saveObject(ForestObject o) async {
    try {
      final saved = o.parcelId == null
          ? o.copyWith(parcelId: _parcelIdAt(LatLng(o.lat, o.lon)))
          : o;
      await DbService.instance.upsertObject(saved);
      if (!mounted) return;
      setState(() {
        final i = _objects.indexWhere((x) => x.id == saved.id);
        if (i >= 0) {
          _objects[i] = saved;
        } else {
          _objects.insert(0, saved);
        }
        if (_targetId == saved.id) _targetName = saved.title;
      });
    } catch (e) {
      _snack('Speichern nicht möglich: $e');
    }
  }

  Future<void> _deleteObject(ForestObject o) async {
    try {
      await DbService.instance.deleteObject(o.id);
      if (!mounted) return;
      setState(() {
        _objects.removeWhere((x) => x.id == o.id);
        if (_targetId == o.id) _clearTarget();
      });
    } catch (e) {
      _snack('Löschen nicht möglich: $e');
    }
  }

  Future<void> _createOwnPoint(LatLng at) async {
    final controller = TextEditingController(text: 'Punkt ${_ownCount + 1}');
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eigenen Punkt anlegen'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'Name',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Anlegen'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    final p = MarkedPoint(
      id: 'e:${DateTime.now().microsecondsSinceEpoch}',
      kind: 'eigen',
      name: name,
      lat: at.latitude,
      lon: at.longitude,
      updatedAt: DateTime.now(),
    );
    await _savePoint(p);
    _snack('Punkt "$name" angelegt');
  }

  void _createOwnPointHere() {
    final p = _pos;
    if (p == null) {
      _snack(_locationMessage ?? 'Noch kein GPS-Signal.');
      return;
    }
    _createOwnPoint(LatLng(p.latitude, p.longitude));
  }

  Future<void> _openPoints() async {
    final id = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => PointsScreen(points: _saved.values.toList()),
      ),
    );
    if (id == null) return;
    final p = _saved[id];
    if (p == null) return;
    if (_mapReady) {
      setState(() => _follow = false);
      _map.move(LatLng(p.lat, p.lon), 18);
    }
    _openPointSheet(p);
  }

  // ------------------------------------------------- Ziel und Messung

  Future<void> _setTarget(MarkedPoint p) =>
      _setTargetRaw(id: p.id, name: p.name, lat: p.lat, lon: p.lon);

  Future<void> _setTargetRaw({
    required String id,
    required String name,
    required double lat,
    required double lon,
  }) async {
    setState(() {
      _targetId = id;
      _targetName = name;
      _targetPos = LatLng(lat, lon);
      _lastBand = null;
    });
    if (!_settings.hintSeen) {
      _settings.hintSeen = true;
      _settings.save();
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Wichtiger Hinweis'),
          content: const Text(
            'Die Zielführung ist eine Orientierungshilfe. Die Lage der '
            'Katasterpunkte ist unterschiedlich genau, und das Handy-GPS '
            'ist unter Baumkronen oft nur auf mehrere Meter genau. Den '
            'Grenzstein findest du damit nur ungefähr, die verbindliche '
            'Grenze klärt die Vermessung.',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Verstanden'),
            ),
          ],
        ),
      );
    }
  }

  void _clearTarget() {
    _targetId = null;
    _targetName = '';
    _targetPos = null;
    _lastBand = null;
    _cancelMeasure();
  }

  void _cancelMeasure() {
    _measureTimer?.cancel();
    _measureTimer = null;
    _measuring = false;
    _measureEnd = null;
    _samples.clear();
  }

  void _startMeasure() {
    if (_pos == null) {
      _snack(_locationMessage ?? 'Noch kein GPS-Signal.');
      return;
    }
    setState(() {
      _samples.clear();
      _measuring = true;
      _measureEnd = DateTime.now().add(const Duration(seconds: 60));
    });
    _measureTimer?.cancel();
    _measureTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (!mounted) return;
      final end = _measureEnd;
      if (end != null && DateTime.now().isAfter(end)) {
        _finishMeasure();
      } else {
        setState(() {});
      }
    });
  }

  Future<void> _finishMeasure() async {
    _measureTimer?.cancel();
    _measureTimer = null;
    final samples = List<_Sample>.of(_samples);
    setState(() {
      _measuring = false;
      _measureEnd = null;
      _samples.clear();
    });

    if (samples.length < 5) {
      _snack('Zu wenige GPS-Werte für eine Messung. Bitte erneut versuchen.');
      return;
    }

    // Gewichteter Mittelwert (genauere Werte zaehlen mehr)
    double sw = 0, slat = 0, slon = 0;
    for (final s in samples) {
      final w = 1 / (s.acc * s.acc);
      sw += w;
      slat += w * s.lat;
      slon += w * s.lon;
    }
    final mean = LatLng(slat / sw, slon / sw);

    double sumSq = 0, accSum = 0;
    for (final s in samples) {
      final d = _distance.as(LengthUnit.Meter, mean, LatLng(s.lat, s.lon));
      sumSq += d * d;
      accSum += s.acc;
    }
    final spread = math.sqrt(sumSq / samples.length);
    final meanAcc = accSum / samples.length;

    final target = _targetPos;
    String versatz = '';
    if (target != null) {
      final d = _distance.as(LengthUnit.Meter, mean, target);
      final b = (_distance.bearing(mean, target) + 360) % 360;
      versatz = '\n\nAbstand zum Zielpunkt: ${formatMeters(d)} '
          'in Richtung ${cardinal(b)}';
    }

    if (!mounted) return;
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Messung abgeschlossen'),
        content: Text(
          'Mittlere Position aus ${samples.length} GPS-Werten:\n'
          '${mean.latitude.toStringAsFixed(6)}, ${mean.longitude.toStringAsFixed(6)}\n\n'
          'Streuung ± ${spread.toStringAsFixed(1)} m, '
          'mittlere GPS-Genauigkeit ± ${meanAcc.toStringAsFixed(1)} m'
          '$versatz',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'discard'),
            child: const Text('Verwerfen'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'save'),
            child: const Text('Messung speichern'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, 'found'),
            child: const Text('Gefunden'),
          ),
        ],
      ),
    );
    if (choice == null || choice == 'discard') return;

    final id = _targetId;
    if (id == null) return;
    if (!(id.startsWith('k:') || id.startsWith('e:'))) {
      _snack('Für Waldobjekte wird die Messung nicht gespeichert.');
      return;
    }
    MarkedPoint? base = _saved[id];
    if (base == null) {
      // Katasterpunkt ohne bisherigen Eintrag: aus Ziel neu anlegen
      final t = _targetPos;
      if (t == null) return;
      base = MarkedPoint(
        id: id,
        kind: id.startsWith('e:') ? 'eigen' : 'kataster',
        name: _targetName,
        lat: t.latitude,
        lon: t.longitude,
        updatedAt: DateTime.now(),
      );
      for (final c in _cad) {
        if ('k:${c.id}' == id) {
          base = MarkedPoint(
            id: id,
            kind: 'kataster',
            name: _targetName,
            lat: c.lat,
            lon: c.lon,
            attributesJson: jsonEncode(c.properties),
            updatedAt: DateTime.now(),
          );
        }
      }
    }
    await _savePoint(
      base!.copyWith(
        status: choice == 'found' ? PointStatus.found : null,
        measuredLat: mean.latitude,
        measuredLon: mean.longitude,
        measuredAccuracy: meanAcc,
        measuredSamples: samples.length,
        measuredAt: DateTime.now(),
      ),
    );
    _snack(choice == 'found' ? 'Als gefunden gespeichert' : 'Messung gespeichert');
  }

  // ------------------------------------------------------------- Aktionen

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  void _centerOnMe() {
    final p = _pos;
    if (p == null) {
      _snack(_locationMessage ?? 'Noch kein GPS-Signal.');
      return;
    }
    setState(() => _follow = true);
    if (_mapReady) {
      _map.move(
        LatLng(p.latitude, p.longitude),
        math.max(_map.camera.zoom, 16),
      );
    }
  }

  void _toggleHeadingUp() {
    final on = !_settings.headingUp;
    if (on && _heading.heading.value == null) {
      _snack('Kompass wird gestartet. Handy flach halten und leicht bewegen.');
    }
    setState(() => _settings.headingUp = on);
    _settings.save();
    if (!_mapReady) return;
    if (on) {
      final h = _heading.heading.value;
      if (h != null) _map.rotate(-h);
    } else {
      _map.rotate(0);
    }
  }

  void _change(StateSetter setSheet, VoidCallback change) {
    setState(change);
    setSheet(() {});
    _settings.save();
  }

  // ------------------------------------------------------------- Karte

  TileLayer? _wmsLayer(
    WmsService? svc, {
    required bool transparent,
    required double opacity,
    List<String>? layerNames,
    double minZoom = 0,
    double maxZoom = 22,
  }) {
    if (svc == null || !svc.usable || _provider == null) return null;
    final caps = svc.caps!;
    final names = layerNames ?? WmsCatalog.defaultLayers(svc);
    if (names.isEmpty) return null;

    return TileLayer(
      key: ValueKey('${svc.def.id}:${names.join('|')}:$minZoom:$maxZoom'),
      wmsOptions: WMSTileLayerOptions(
        baseUrl: caps.getMapUrl,
        layers: names,
        format: caps.pickFormat(
          transparent: transparent,
          preferJpeg: svc.def.preferJpeg,
        ),
        transparent: transparent,
        version: '1.1.1',
      ),
      tileProvider: _provider,
      userAgentPackageName: kAppPackage,
      minZoom: minZoom,
      maxZoom: maxZoom,
      maxNativeZoom: 20,
      panBuffer: 2,
      keepBuffer: 4,
      tileDisplay: TileDisplay.instantaneous(opacity: opacity),
      errorTileCallback: (tile, error, stackTrace) {
        _tileErrors.update(svc.def.id, (v) => v + 1, ifAbsent: () => 1);
        final text = error.toString();
        _lastTileError = '${svc.def.title}: '
            '${text.length > 160 ? text.substring(0, 160) : text}';
      },
    );
  }

  Widget _buildMap() {
    final s = _settings;
    final layers = <Widget>[];

    // Luftbild nur ab der Zoomstufe, in der der Dienst Bilder liefert;
    // darunter zeigt die Karte RP (sonst waere das Bild weiss).
    final aerialSvc = _services['dop'];
    double aerialMin = 0;
    final aerialWanted = s.base == BaseMap.aerial && aerialSvc?.usable == true;
    if (aerialWanted) {
      aerialMin = aerialSvc!.minZoomFor(WmsCatalog.defaultLayers(aerialSvc));
    }

    final topo = _wmsLayer(
      _services['topo'],
      transparent: false,
      opacity: 1,
      maxZoom: (aerialWanted && aerialMin > 0) ? aerialMin - 0.01 : 22,
    );
    if (topo != null && !(aerialWanted && aerialMin == 0)) layers.add(topo);

    if (aerialWanted) {
      final aerial = _wmsLayer(
        aerialSvc,
        transparent: false,
        opacity: 1,
        minZoom: aerialMin,
      );
      if (aerial != null) layers.add(aerial);
    }

    if (s.flurOn) {
      final flurSvc = _services['flur'];
      final names = s.flurLayers ??
          (flurSvc == null ? <String>[] : WmsCatalog.defaultLayers(flurSvc));
      final flur = _wmsLayer(
        flurSvc,
        transparent: true,
        opacity: s.flurOpacity,
        layerNames: s.flurLayers,
        minZoom: flurSvc == null ? 0 : flurSvc.minZoomFor(names),
      );
      if (flur != null) layers.add(flur);
    }
    if (s.gstOn) {
      final gstSvc = _services['gst'];
      final gst = _wmsLayer(
        gstSvc,
        transparent: true,
        opacity: 0.6,
        minZoom: gstSvc == null
            ? 0
            : gstSvc.minZoomFor(WmsCatalog.defaultLayers(gstSvc)),
      );
      if (gst != null) layers.add(gst);
    }

    final pos = _pos;
    final here = pos == null ? null : LatLng(pos.latitude, pos.longitude);
    final target = _targetPos;

    return FlutterMap(
      mapController: _map,
      options: MapOptions(
        initialCenter: const LatLng(50.0, 7.4),
        initialZoom: 9,
        minZoom: 6,
        maxZoom: 21,
        interactionOptions: InteractionOptions(
          flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
        ),
        onMapReady: _onMapReady,
        onPositionChanged: _onCameraChanged,
        onTap: (tapPosition, point) => _onMapTap(point),
        onLongPress: (tapPosition, point) => _showCreateMenu(point),
      ),
      children: [
        ...layers,
        PolygonLayer(
          polygons: [
            for (final v in _parcels)
              for (final poly in v.geometry.polygons)
                Polygon(
                  points: poly.first,
                  holePointsList: poly.length > 1 ? poly.sublist(1) : null,
                  color: _deptColor(v.parcel.deptId).withAlpha(45),
                  borderColor: _deptColor(v.parcel.deptId).withAlpha(235),
                  borderStrokeWidth: 2.5,
                ),
            if (_pending != null)
              for (final poly in _pending!.geometry.polygons)
                Polygon(
                  points: poly.first,
                  holePointsList: poly.length > 1 ? poly.sublist(1) : null,
                  color: const Color(0xFF00B8D4).withAlpha(70),
                  borderColor: const Color(0xFF00B8D4),
                  borderStrokeWidth: 4,
                ),
          ],
        ),
        ValueListenableBuilder<double>(
          valueListenable: _dotZoom,
          builder: (context, z, _) {
            if (z < 13 || _parcels.isEmpty) return const SizedBox.shrink();
            return MarkerLayer(
              markers: [
                for (final v in _parcels)
                  Marker(
                    point: v.centroid,
                    width: 150,
                    height: 28,
                    child: IgnorePointer(
                      child: Center(
                        child: Text(
                          v.parcel.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            shadows: [
                              Shadow(color: Colors.black, blurRadius: 4),
                              Shadow(color: Colors.black, blurRadius: 2),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
        if (here != null && target != null)
          PolylineLayer(
            polylines: [
              Polyline(
                points: [here, target],
                strokeWidth: 3,
                color: const Color.fromARGB(200, 183, 28, 28),
              ),
            ],
          ),
        if (target != null)
          CircleLayer(
            circles: [
              CircleMarker(
                point: target,
                radius: 5,
                useRadiusInMeter: true,
                color: const Color.fromARGB(25, 183, 28, 28),
                borderColor: const Color.fromARGB(180, 183, 28, 28),
                borderStrokeWidth: 1.5,
              ),
              CircleMarker(
                point: target,
                radius: 2,
                useRadiusInMeter: true,
                color: const Color.fromARGB(40, 183, 28, 28),
                borderColor: const Color.fromARGB(200, 183, 28, 28),
                borderStrokeWidth: 1.5,
              ),
            ],
          ),
        if (pos != null && here != null)
          CircleLayer(
            circles: [
              CircleMarker(
                point: here,
                radius: pos.accuracy,
                useRadiusInMeter: true,
                color: const Color.fromARGB(45, 33, 150, 243),
                borderColor: const Color.fromARGB(200, 33, 150, 243),
                borderStrokeWidth: 1.5,
              ),
            ],
          ),
        if (s.pointsOn && _cad.isNotEmpty)
          ValueListenableBuilder<double>(
            valueListenable: _dotZoom,
            builder: (context, z, _) {
              final dot = dotSizeForZoom(z);
              return MarkerLayer(
                markers: [
                  for (final c in _cad)
                    Marker(
                      point: LatLng(c.lat, c.lon),
                      width: dot + 12,
                      height: dot + 12,
                      child: CadastralMarker(
                        status: _saved['k:${c.id}']?.status ?? PointStatus.open,
                        isTarget: _targetId == 'k:${c.id}',
                        dot: dot,
                      ),
                    ),
                ],
              );
            },
          ),
        ValueListenableBuilder<double>(
          valueListenable: _dotZoom,
          builder: (context, z, _) {
            final dot = dotSizeForZoom(z);
            return MarkerLayer(
              markers: [
                for (final p in _saved.values.where((p) => p.isOwn))
                  Marker(
                    point: LatLng(p.lat, p.lon),
                    width: dot + 14,
                    height: dot + 14,
                    child: OwnPointMarker(
                      status: p.status,
                      isTarget: _targetId == p.id,
                      dot: dot,
                    ),
                  ),
              ],
            );
          },
        ),
        if (_objects.isNotEmpty)
          ValueListenableBuilder<double>(
            valueListenable: _dotZoom,
            builder: (context, z, _) {
              final size = (14 + (z - 14) * 2.5).clamp(14.0, 30.0).toDouble();
              return MarkerLayer(
                markers: [
                  for (final o in _objects)
                    Marker(
                      point: LatLng(o.lat, o.lon),
                      width: size + 8,
                      height: size + 8,
                      child: ObjectMarker(
                        isJagd: o.isJagd,
                        isTarget: _targetId == o.id,
                        size: size,
                      ),
                    ),
                ],
              );
            },
          ),
        if (here != null)
          ValueListenableBuilder<double?>(
            valueListenable: _heading.heading,
            builder: (context, h, _) => MarkerLayer(
              markers: [
                Marker(
                  point: here,
                  width: 56,
                  height: 56,
                  child: PositionMarker(heading: h),
                ),
              ],
            ),
          ),
      ],
    );
  }

  // ------------------------------------------------------- Oberfläche

  Widget _chip(String text, {required Color bg, required Color fg, VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Material(
        elevation: 3,
        borderRadius: BorderRadius.circular(12),
        color: bg,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Text(text, style: TextStyle(color: fg, fontSize: 13)),
        ),
      ),
    );
  }

  Widget _buildStatus() {
    final p = _pos;
    String text;
    Color color;
    IconData icon;
    if (_locationMessage != null) {
      text = _locationMessage!;
      color = Colors.red.shade700;
      icon = Icons.location_off;
    } else if (p == null) {
      text = 'GPS-Signal wird gesucht …';
      color = Colors.orange.shade800;
      icon = Icons.gps_not_fixed;
    } else {
      text = 'GPS ± ${p.accuracy.round()} m';
      color = p.accuracy <= 5
          ? Colors.green.shade700
          : (p.accuracy <= 15 ? Colors.orange.shade800 : Colors.red.shade700);
      icon = Icons.gps_fixed;
    }

    final needed = <WmsServiceDef>[
      _settings.base == BaseMap.topo ? kTopoService : kAerialService,
      if (_settings.flurOn) kFlurService,
      if (_settings.gstOn) kAccuracyService,
    ];
    final missing = needed
        .where((d) => _services[d.id]?.usable != true)
        .map((d) => d.title)
        .toList();

    final notes = <String>[
      if (_settings.pointsOn && _loadingPoints) 'Grenzpunkte werden geladen …',
      if (_settings.pointsOn && !_loadingPoints && _pointsMessage != null)
        _pointsMessage!,
      if (_dbError != null) 'Punktspeicher nicht verfügbar: $_dbError',
    ];

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Align(
          alignment: Alignment.topLeft,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width - 100,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Material(
                  elevation: 3,
                  borderRadius: BorderRadius.circular(12),
                  color: Colors.white,
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(icon, color: color),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                text,
                                style: TextStyle(
                                  color: color,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                            ),
                          ],
                        ),
                        ValueListenableBuilder<double>(
                          valueListenable: _zoom,
                          builder: (context, z, _) => Text(
                            'Zoomstufe ${z.toStringAsFixed(1).replaceAll('.', ',')}',
                            style: const TextStyle(
                              fontSize: 11,
                              color: Colors.black54,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                for (final n in notes) ...[
                  const SizedBox(height: 6),
                  _chip(n, bg: Colors.white, fg: Colors.black87),
                ],
                if (_pickMode || _pickBusy) ...[
                  const SizedBox(height: 6),
                  _chip(
                    _pickBusy
                        ? 'Flurstück wird geladen …'
                        : 'Parzellenauswahl: Tippe ein Flurstück an. '
                            'Zum Beenden den Auswahl-Knopf erneut tippen.',
                    bg: Colors.teal.shade50,
                    fg: Colors.teal.shade900,
                  ),
                ],
                if (missing.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  _chip(
                    'Nicht verfügbar: ${missing.join(', ')}\nTippen für Details',
                    bg: Colors.red.shade50,
                    fg: Colors.red.shade900,
                    onTap: _openDiagnostics,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildButtons() {
    final primary = Theme.of(context).colorScheme.primaryContainer;
    return SafeArea(
      child: Align(
        alignment: Alignment.centerRight,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              FloatingActionButton(
                heroTag: 'layers',
                tooltip: 'Karten und Ebenen',
                onPressed: _openLayers,
                child: const Icon(Icons.layers),
              ),
              const SizedBox(height: 12),
              FloatingActionButton(
                heroTag: 'compass',
                tooltip: _settings.headingUp
                    ? 'Norden nach oben'
                    : 'Karte nach Blickrichtung drehen',
                backgroundColor: _settings.headingUp ? primary : null,
                onPressed: _toggleHeadingUp,
                child: Icon(
                  _settings.headingUp ? Icons.explore : Icons.explore_outlined,
                ),
              ),
              const SizedBox(height: 12),
              FloatingActionButton.small(
                heroTag: 'pick',
                tooltip: _pickMode ? 'Parzellenauswahl beenden' : 'Parzelle wählen',
                backgroundColor: _pickMode ? primary : null,
                onPressed: () => setState(() {
                  _pickMode = !_pickMode;
                  _pending = null;
                }),
                child: Icon(_pickMode ? Icons.check_box : Icons.crop_square),
              ),
              const SizedBox(height: 12),
              FloatingActionButton.small(
                heroTag: 'point',
                tooltip: 'Punkt anlegen (Eigener Punkt, Jagdeinrichtung, Habitatbaum)',
                onPressed: _showCreateMenuHere,
                child: const Icon(Icons.add_location_alt),
              ),
              const SizedBox(height: 12),
              FloatingActionButton(
                heroTag: 'me',
                tooltip: 'Auf meine Position zentrieren',
                backgroundColor: _follow ? primary : null,
                onPressed: _centerOnMe,
                child: Icon(
                  _follow ? Icons.my_location : Icons.location_searching,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAttribution() {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: SafeArea(
        top: false,
        child: GestureDetector(
          onTap: _showInfo,
          child: Container(
            color: const Color.fromARGB(210, 255, 255, 255),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            child: Text(
              attributionText(),
              style: const TextStyle(fontSize: 10, color: Colors.black87),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGuidance() {
    final target = _targetPos;
    if (target == null) return const SizedBox.shrink();
    return Positioned(
      left: 8,
      right: 8,
      bottom: 30,
      child: SafeArea(
        top: false,
        child: ValueListenableBuilder<double?>(
          valueListenable: _heading.heading,
          builder: (context, h, _) {
            final pos = _pos;
            double? dist;
            double? bearing;
            double? arrow;
            if (pos != null) {
              final here = LatLng(pos.latitude, pos.longitude);
              dist = _distance.as(LengthUnit.Meter, here, target);
              bearing = (_distance.bearing(here, target) + 360) % 360;
              double? facing = h;
              if (facing == null && pos.speed > 0.8 && pos.heading >= 0) {
                facing = pos.heading;
              }
              if (facing != null) arrow = (bearing - facing + 360) % 360;
            }
            final end = _measureEnd;
            final left = end == null
                ? 0
                : math.max(0, end.difference(DateTime.now()).inSeconds);
            return GuidancePanel(
              name: _targetName,
              distanceM: dist,
              arrowDeg: arrow,
              bearingDeg: bearing,
              accuracyM: pos?.accuracy,
              measuring: _measuring,
              secondsLeft: left,
              samples: _samples.length,
              onMeasure: _startMeasure,
              onCancelMeasure: () => setState(_cancelMeasure),
              onDetails: () {
                final id = _targetId;
                final p = id == null ? null : _saved[id];
                if (p != null) {
                  _openPointSheet(p);
                } else {
                  for (final c in _cad) {
                    if ('k:${c.id}' == id) {
                      _onCadastralTap(c);
                      return;
                    }
                  }
                }
              },
              onClose: () => setState(_clearTarget),
            );
          },
        ),
      ),
    );
  }

  Future<void> _openLayers() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => _buildSheet(ctx, setSheet),
      ),
    );
  }

  List<Widget> _flurLayerTiles(StateSetter setSheet) {
    final svc = _services['flur'];
    if (svc == null || !svc.usable) {
      return [const ListTile(title: Text('Flurkarte derzeit nicht verfügbar'))];
    }
    final current =
        (_settings.flurLayers ?? WmsCatalog.defaultLayers(svc)).toSet();
    return [
      for (final l in svc.caps!.layers)
        CheckboxListTile(
          dense: true,
          contentPadding: EdgeInsets.only(left: 16.0 + 12 * l.depth, right: 8),
          title: Text(l.title),
          value: current.contains(l.name),
          onChanged: (v) {
            final next =
                (_settings.flurLayers ?? WmsCatalog.defaultLayers(svc)).toSet();
            if (v == true) {
              next.add(l.name);
            } else {
              next.remove(l.name);
            }
            _change(setSheet, () => _settings.flurLayers = next.toList());
          },
        ),
      TextButton(
        onPressed: () => _change(setSheet, () => _settings.flurLayers = null),
        child: const Text('Standardauswahl wiederherstellen'),
      ),
    ];
  }

  Widget _buildSheet(BuildContext ctx, StateSetter setSheet) {
    final s = _settings;
    return SafeArea(
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          const Text(
            'Hintergrund',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          SegmentedButton<BaseMap>(
            segments: const [
              ButtonSegment(
                value: BaseMap.topo,
                label: Text('Karte'),
                icon: Icon(Icons.map_outlined),
              ),
              ButtonSegment(
                value: BaseMap.aerial,
                label: Text('Luftbild'),
                icon: Icon(Icons.satellite_alt),
              ),
            ],
            selected: {s.base},
            onSelectionChanged: (v) =>
                _change(setSheet, () => _settings.base = v.first),
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Flurkarte anzeigen'),
            subtitle: const Text('Flurstücksgrenzen und -nummern'),
            value: s.flurOn,
            onChanged: (v) => _change(setSheet, () => _settings.flurOn = v),
          ),
          if (s.flurOn) ...[
            Row(
              children: [
                const Text('Deckkraft'),
                Expanded(
                  child: Slider(
                    value: s.flurOpacity,
                    min: 0.2,
                    max: 1.0,
                    divisions: 8,
                    label: '${(s.flurOpacity * 100).round()} %',
                    onChanged: (v) =>
                        _change(setSheet, () => _settings.flurOpacity = v),
                  ),
                ),
              ],
            ),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const Text('Ebenen der Flurkarte'),
              children: _flurLayerTiles(setSheet),
            ),
          ],
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Grenzpunkte anzeigen'),
            subtitle: Text(
              'Ab Zoomstufe ${kPointsMinZoom.round()}, antippen für Details und Ziel',
            ),
            value: s.pointsOn,
            onChanged: (v) {
              _change(setSheet, () {
                _settings.pointsOn = v;
                if (!v) {
                  _cad = [];
                  _loadedBounds = null;
                  _pointsMessage = null;
                }
              });
              if (v && _mapReady) _scheduleLoadPoints(_map.camera);
            },
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Genauigkeit des Katasters'),
            subtitle: const Text('Farbflächen der Lagegenauigkeit'),
            value: s.gstOn,
            onChanged: (v) => _change(setSheet, () => _settings.gstOn = v),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Display wach halten'),
            subtitle: const Text('Verbraucht mehr Akku'),
            value: s.keepAwake,
            onChanged: (v) {
              _change(setSheet, () => _settings.keepAwake = v);
              _applyKeepAwake();
            },
          ),
          const Divider(),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.forest),
            title: Text('Mein Wald (${_parcels.length} Parzellen)'),
            onTap: () {
              Navigator.of(ctx).pop();
              _openForest();
            },
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.zoom_out_map),
            title: const Text('Alle Parzellen anzeigen'),
            onTap: () {
              Navigator.of(ctx).pop();
              _fitPoints([for (final v in _parcels) ...v.geometry.allPoints]);
            },
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.place_outlined),
            title: Text('Meine Punkte (${_saved.length})'),
            onTap: () {
              Navigator.of(ctx).pop();
              _openPoints();
            },
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.fact_check_outlined),
            title: const Text('Dienste prüfen'),
            onTap: () {
              Navigator.of(ctx).pop();
              _openDiagnostics();
            },
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.info_outline),
            title: const Text('Info und Quellen'),
            onTap: () {
              Navigator.of(ctx).pop();
              _showInfo();
            },
          ),
        ],
      ),
    );
  }

  Future<void> _openDiagnostics() async {
    final reload = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => DiagnosticsScreen(
          services: _services,
          tileErrors: Map<String, int>.of(_tileErrors),
          lastTileError: _lastTileError,
          extraLines: [
            'Grenzpunkte (OGC API): ${_pointsDiag ?? 'noch nicht abgefragt (ab Zoomstufe ${kPointsMinZoom.round()})'}',
            if (_dbError != null) 'Punktspeicher: $_dbError',
          ],
        ),
      ),
    );
    if (reload == true) {
      setState(() {
        _loading = true;
        _mapReady = false;
      });
      final services = await _loadServices(force: true);
      if (!mounted) return;
      setState(() {
        _services = services;
        _tileErrors.clear();
        _lastTileError = null;
        _loading = false;
      });
    }
  }

  void _showInfo() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Info und Quellen'),
        content: SingleChildScrollView(
          child: Text(
            'Kartendaten und Grenzpunkte: ${attributionText()}\n\n'
            'Die Flurkarte ist eine Orientierungshilfe und keine '
            'rechtsverbindliche Grenzfeststellung. Die Lage der '
            'Katasterpunkte ist unterschiedlich genau; eine Übertragung in '
            'die Örtlichkeit erfordert fachkundige Bewertung. Die Genauigkeit '
            'des Handy-GPS liegt unter Baumkronen oft bei mehreren Metern. '
            'Zusätzlich weicht das amtliche Koordinatensystem (ETRS89) '
            'systematisch um etwa einen Meter vom GPS-System ab; das ist hier '
            'nicht herausgerechnet.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Schließen'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Karten werden vorbereitet …'),
            ],
          ),
        ),
      );
    }
    if (_fatal != null) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('Start fehlgeschlagen:\n$_fatal'),
          ),
        ),
      );
    }
    return Scaffold(
      body: Stack(
        children: [
          _buildMap(),
          _buildStatus(),
          _buildButtons(),
          _buildAttribution(),
          _buildGuidance(),
        ],
      ),
    );
  }
}
