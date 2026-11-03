import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:xml/xml.dart';

import '../app_config.dart';

class WmsLayerInfo {
  final String name;
  final String title;
  final int depth;
  final bool hasNamedAncestor;

  /// Maßstabsgrenzen der Ebene (Nenner), falls der Dienst sie angibt.
  final double? minScaleDenom;
  final double? maxScaleDenom;

  const WmsLayerInfo({
    required this.name,
    required this.title,
    required this.depth,
    required this.hasNamedAncestor,
    this.minScaleDenom,
    this.maxScaleDenom,
  });
}

/// Zoomstufe (Web-Mercator, Breite ca. 50 Grad), bei der der Maßstab dem
/// angegebenen Nenner entspricht (Pixelgröße 0,28 mm).
double zoomForScaleDenominator(double denom) {
  return math.log(100623.4 / (denom * 0.00028)) / math.ln2;
}

/// Was die App aus der Dienstbeschreibung (GetCapabilities) wissen muss.
class WmsCapabilities {
  final String getMapUrl;
  final List<WmsLayerInfo> layers;
  final Set<String> srs;
  final List<String> formats;

  const WmsCapabilities({
    required this.getMapUrl,
    required this.layers,
    required this.srs,
    required this.formats,
  });

  /// Die Karte arbeitet in Web-Mercator (EPSG:3857).
  bool get supportsWebMercator => srs.contains('EPSG:3857');

  /// Ab welcher Zoomstufe die gewaehlten Ebenen Bilder liefern. Darunter
  /// waeren die Kacheln leer bzw. weiss, weil der Dienst dort keine Daten
  /// zeigt. 0 = keine Einschraenkung bekannt.
  double minZoomFor(List<String> names) {
    double? best;
    for (final l in layers) {
      if (!names.contains(l.name)) continue;
      final d = l.maxScaleDenom;
      final z = (d == null || d <= 0) ? 0.0 : zoomForScaleDenominator(d);
      if (best == null || z < best) best = z;
    }
    if (best == null || best <= 0) return 0;
    return best.clamp(8.0, 16.0).toDouble();
  }

  String pickFormat({required bool transparent, bool preferJpeg = false}) {
    final f = formats.map((e) => e.toLowerCase()).toList();
    if (transparent) {
      if (f.contains('image/png')) return 'image/png';
      if (f.contains('image/png8')) return 'image/png8';
      return f.isNotEmpty ? f.first : 'image/png';
    }
    if (preferJpeg && f.contains('image/jpeg')) return 'image/jpeg';
    if (f.contains('image/png')) return 'image/png';
    if (f.contains('image/jpeg')) return 'image/jpeg';
    return f.isNotEmpty ? f.first : 'image/png';
  }
}

/// Ergebnis beim Laden eines Dienstes.
class WmsService {
  final WmsServiceDef def;
  final WmsCapabilities? caps;
  final String? error;
  final bool fromCache;

  const WmsService({
    required this.def,
    this.caps,
    this.error,
    this.fromCache = false,
  });

  bool get usable => caps != null && caps!.supportsWebMercator;

  double minZoomFor(List<String> names) => caps?.minZoomFor(names) ?? 0;

  String get problem {
    if (caps == null) return error ?? 'Dienstbeschreibung nicht lesbar';
    if (!caps!.supportsWebMercator) {
      return 'Der Dienst bietet kein Web-Mercator (EPSG:3857). '
          'Verfügbar: ${caps!.srs.join(', ')}';
    }
    return '';
  }
}

Iterable<XmlElement> _byLocal(XmlNode node, String local) => node.descendants
    .whereType<XmlElement>()
    .where((e) => e.name.local == local);

String? _childText(XmlElement el, String local) {
  for (final c in el.children.whereType<XmlElement>()) {
    if (c.name.local == local) return c.innerText.trim();
  }
  return null;
}

/// Macht aus der GetMap-Adresse eine Basisadresse, an die flutter_map seine
/// Parameter anhaengen kann (https, ohne Sitzungskennung und ohne
/// REQUEST/SERVICE/VERSION).
String normalizeBaseUrl(String raw) {
  var u = raw.trim().replaceAll('&amp;', '&');
  if (u.startsWith('http://')) u = 'https://${u.substring(7)}';
  try {
    final uri = Uri.parse(u);
    if (uri.host.isEmpty) throw const FormatException('kein Host');
    const drop = {'PHPSESSID', 'REQUEST', 'SERVICE', 'VERSION'};
    final params = <String, String>{};
    uri.queryParameters.forEach((k, v) {
      if (!drop.contains(k.toUpperCase())) params[k] = v;
    });
    final base = Uri(
      scheme: 'https',
      host: uri.host,
      path: uri.path,
      queryParameters: params.isEmpty ? null : params,
    ).toString();
    return base.contains('?') ? '$base&' : '$base?';
  } catch (_) {
    if (!u.contains('?')) return '$u?';
    return (u.endsWith('?') || u.endsWith('&')) ? u : '$u&';
  }
}

WmsCapabilities parseCapabilities(String text, String capabilitiesUrl) {
  final doc = XmlDocument.parse(text);

  // Adresse fuer GetMap und angebotene Bildformate
  String? getMapUrl;
  final formats = <String>[];
  for (final getMap in _byLocal(doc, 'GetMap')) {
    for (final f in getMap.children.whereType<XmlElement>()) {
      if (f.name.local == 'Format') formats.add(f.innerText.trim());
    }
    for (final res in _byLocal(getMap, 'OnlineResource')) {
      for (final a in res.attributes) {
        if (a.name.local == 'href') {
          getMapUrl = a.value;
          break;
        }
      }
      if (getMapUrl != null) break;
    }
    if (getMapUrl != null) break;
  }
  getMapUrl ??= capabilitiesUrl;

  // Unterstuetzte Koordinatensysteme
  final srs = <String>{};
  for (final tag in const ['SRS', 'CRS']) {
    for (final e in _byLocal(doc, tag)) {
      for (final part in e.innerText.split(RegExp(r'\s+'))) {
        if (part.isNotEmpty) srs.add(part.toUpperCase());
      }
    }
  }

  // Ebenen (benannte Ebenen, mit Hierarchie)
  final layers = <WmsLayerInfo>[];
  double? parseNum(String? t) =>
      t == null ? null : double.tryParse(t.trim().replaceAll(',', '.'));

  void walk(
    XmlElement el,
    int depth,
    bool namedAncestor,
    double? parentMin,
    double? parentMax,
  ) {
    final name = _childText(el, 'Name');
    final title = _childText(el, 'Title');
    final named = name != null && name.isNotEmpty;

    // Massstabsgrenzen: WMS 1.3.0 (Denominatoren) oder 1.1.1 (ScaleHint)
    var minD = parseNum(_childText(el, 'MinScaleDenominator')) ?? parentMin;
    var maxD = parseNum(_childText(el, 'MaxScaleDenominator')) ?? parentMax;
    for (final c in el.children.whereType<XmlElement>()) {
      if (c.name.local == 'ScaleHint') {
        const k = 0.00028 * 1.4142135623730951;
        final lo = parseNum(c.getAttribute('min'));
        final hi = parseNum(c.getAttribute('max'));
        if (lo != null && lo > 0) minD = lo / k;
        if (hi != null && hi > 0 && hi < 1e6) maxD = hi / k;
      }
    }
    if (maxD != null && maxD > 5e7) maxD = null; // praktisch unbegrenzt

    if (named) {
      layers.add(
        WmsLayerInfo(
          name: name,
          title: (title == null || title.isEmpty) ? name : title,
          depth: depth,
          hasNamedAncestor: namedAncestor,
          minScaleDenom: minD,
          maxScaleDenom: maxD,
        ),
      );
    }
    for (final child in el.children.whereType<XmlElement>()) {
      if (child.name.local == 'Layer') {
        walk(child, depth + 1, namedAncestor || named, minD, maxD);
      }
    }
  }

  for (final capability in _byLocal(doc, 'Capability')) {
    for (final child in capability.children.whereType<XmlElement>()) {
      if (child.name.local == 'Layer') walk(child, 0, false, null, null);
    }
    break;
  }

  return WmsCapabilities(
    getMapUrl: normalizeBaseUrl(getMapUrl),
    layers: layers,
    srs: srs,
    formats: formats,
  );
}

class WmsCatalog {
  static Future<Directory> _capsDir() async {
    final support = await getApplicationSupportDirectory();
    final dir = Directory('${support.path}/wms_caps');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// Laedt die Dienstbeschreibung. Eine frische Kopie (unter 7 Tage) wird
  /// sofort genutzt und im Hintergrund aufgefrischt, damit die App auch
  /// bei schlechtem Netz schnell startet.
  static Future<WmsService> load(
    WmsServiceDef def, {
    bool forceRefresh = false,
  }) async {
    final dir = await _capsDir();
    final file = File('${dir.path}/caps_${def.id}.xml');

    if (!forceRefresh && await file.exists()) {
      final age = DateTime.now().difference((await file.stat()).modified);
      if (age < const Duration(days: 7)) {
        try {
          final caps = parseCapabilities(
            await file.readAsString(),
            def.capabilitiesUrl,
          );
          _refreshInBackground(def, file);
          return WmsService(def: def, caps: caps, fromCache: true);
        } catch (_) {
          // Kopie unbrauchbar: weiter mit frischem Download
        }
      }
    }

    String? netError;
    try {
      final text = await _download(def);
      final caps = parseCapabilities(text, def.capabilitiesUrl);
      await file.writeAsString(text);
      return WmsService(def: def, caps: caps);
    } catch (e) {
      netError = e.toString();
    }

    if (await file.exists()) {
      try {
        final caps = parseCapabilities(
          await file.readAsString(),
          def.capabilitiesUrl,
        );
        return WmsService(
          def: def,
          caps: caps,
          fromCache: true,
          error: netError,
        );
      } catch (_) {}
    }
    return WmsService(def: def, error: netError);
  }

  static Future<String> _download(WmsServiceDef def) async {
    final resp = await http
        .get(Uri.parse(def.capabilitiesUrl))
        .timeout(const Duration(seconds: 20));
    if (resp.statusCode != 200) {
      throw StateError('HTTP ${resp.statusCode}');
    }
    final text = utf8.decode(resp.bodyBytes, allowMalformed: true);
    if (!text.contains('Layer')) {
      throw StateError('Antwort ist keine Dienstbeschreibung');
    }
    return text;
  }

  static Future<void> _refreshInBackground(WmsServiceDef def, File file) async {
    try {
      final text = await _download(def);
      parseCapabilities(text, def.capabilitiesUrl);
      await file.writeAsString(text);
    } catch (_) {}
  }

  /// Standardauswahl der Ebenen je Dienst.
  static List<String> defaultLayers(WmsService svc) {
    final caps = svc.caps;
    if (caps == null) return [];
    final all = caps.layers;

    if (svc.def.id == 'flur') {
      // Nur Flurstuecksgrenzen und -nummern, keine bunten Nutzungsflaechen.
      final picked = all
          .where((l) {
            final t = '${l.name} ${l.title}'.toLowerCase();
            return t.contains('flurst') && !t.contains('nutzung');
          })
          .map((l) => l.name)
          .toList();
      if (picked.isNotEmpty) return picked;
    }
    return all.where((l) => !l.hasNamedAncestor).map((l) => l.name).toList();
  }
}
