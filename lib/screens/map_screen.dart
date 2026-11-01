import 'dart:async';
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
import '../services/heading_tracker.dart';
import '../services/settings_store.dart';
import '../services/tile_cache.dart';
import '../services/wms_service.dart';
import 'diagnostics_screen.dart';

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

  MapSettings _settings = MapSettings();
  Map<String, WmsService> _services = {};
  TileCachingClient? _client;
  NetworkTileProvider? _provider;

  bool _loading = true;
  String? _fatal;

  Position? _pos;
  StreamSubscription<Position>? _posSub;
  String? _locationMessage;
  bool _follow = true;
  bool _mapReady = false;
  bool _firstFixDone = false;
  DateTime _lastRotate = DateTime.fromMillisecondsSinceEpoch(0);

  final Map<String, int> _tileErrors = {};
  String? _lastTileError;

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
    _heading.heading.removeListener(_onHeading);
    _heading.dispose();
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

      final client = TileCachingClient(http.Client(), tileDir);
      final services = await _loadServices();
      if (!mounted) {
        client.close();
        return;
      }
      setState(() {
        _settings = settings;
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
  }

  Future<void> _applyKeepAwake() async {
    try {
      await _screenChannel
          .invokeMethod<void>('keepOn', {'on': _settings.keepAwake});
    } catch (_) {}
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
  }) {
    if (svc == null || !svc.usable || _provider == null) return null;
    final caps = svc.caps!;
    final names = layerNames ?? WmsCatalog.defaultLayers(svc);
    if (names.isEmpty) return null;

    return TileLayer(
      key: ValueKey('${svc.def.id}:${names.join('|')}'),
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
      maxNativeZoom: 20,
      maxZoom: 22,
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

    final baseId = s.base == BaseMap.topo ? 'topo' : 'dop';
    final base = _wmsLayer(_services[baseId], transparent: false, opacity: 1);
    if (base != null) layers.add(base);

    if (s.flurOn) {
      final flur = _wmsLayer(
        _services['flur'],
        transparent: true,
        opacity: s.flurOpacity,
        layerNames: s.flurLayers,
      );
      if (flur != null) layers.add(flur);
    }
    if (s.gstOn) {
      final gst =
          _wmsLayer(_services['gst'], transparent: true, opacity: 0.6);
      if (gst != null) layers.add(gst);
    }

    final pos = _pos;
    final here = pos == null ? null : LatLng(pos.latitude, pos.longitude);

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
        onPositionChanged: (camera, hasGesture) {
          if (hasGesture && _follow) setState(() => _follow = false);
        },
      ),
      children: [
        ...layers,
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
        if (here != null)
          ValueListenableBuilder<double?>(
            valueListenable: _heading.heading,
            builder: (context, h, _) => MarkerLayer(
              markers: [
                Marker(
                  point: here,
                  width: 56,
                  height: 56,
                  child: _PositionMarker(heading: h),
                ),
              ],
            ),
          ),
      ],
    );
  }

  // ------------------------------------------------------- Oberfläche

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

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Align(
          alignment: Alignment.topLeft,
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
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: MediaQuery.of(context).size.width - 100,
                    ),
                    child: Row(
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
                  ),
                ),
              ),
              if (missing.isNotEmpty) ...[
                const SizedBox(height: 8),
                GestureDetector(
                  onTap: _openDiagnostics,
                  child: Material(
                    elevation: 3,
                    borderRadius: BorderRadius.circular(12),
                    color: Colors.red.shade50,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      child: Text(
                        'Nicht verfügbar: ${missing.join(', ')}\nTippen für Details',
                        style: TextStyle(
                          color: Colors.red.shade900,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ],
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
            'Kartendaten: ${attributionText()}\n\n'
            'Die Flurkarte ist eine Orientierungshilfe und keine '
            'rechtsverbindliche Grenzfeststellung. Die Lage der '
            'Katasterpunkte ist unterschiedlich genau; eine Übertragung in '
            'die Örtlichkeit erfordert fachkundige Bewertung. Die Genauigkeit '
            'des Handy-GPS liegt unter Baumkronen oft bei mehreren Metern.',
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
        ],
      ),
    );
  }
}

class _PositionMarker extends StatelessWidget {
  final double? heading;
  const _PositionMarker({required this.heading});

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        if (heading != null)
          Transform.rotate(
            angle: heading! * math.pi / 180,
            child: const Icon(
              Icons.navigation,
              size: 52,
              color: Color.fromARGB(170, 21, 101, 192),
            ),
          ),
        Container(
          width: 18,
          height: 18,
          decoration: BoxDecoration(
            color: const Color(0xFF1565C0),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 3),
          ),
        ),
      ],
    );
  }
}
