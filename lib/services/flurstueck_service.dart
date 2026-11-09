import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import 'geo_utils.dart';

class FlurstueckHit {
  final String id;
  final ParcelGeometry geometry;
  final Map<String, dynamic> props;
  final String label;
  final double? area;

  const FlurstueckHit({
    required this.id,
    required this.geometry,
    required this.props,
    required this.label,
    required this.area,
  });
}

class FlurstueckResult {
  final FlurstueckHit? hit;
  final String? error;
  const FlurstueckResult({this.hit, this.error});
}

/// Flurstuecke aus dem Liegenschaftskataster (WFS RP ALKIS Vereinfacht,
/// OGC-API-Features-Schnittstelle des Landesamts). Die Objektart wird beim
/// ersten Aufruf aus der Liste der Datensaetze ermittelt.
class FlurstueckService {
  static const String _base = 'https://www.geoportal.rlp.de/spatial-objects/519';
  static const Map<String, String> _headers = {
    'Accept': 'application/geo+json, application/json',
  };
  static String? _collectionId;

  static String _norm(String s) => s
      .toLowerCase()
      .replaceAll('ü', 'ue')
      .replaceAll('ö', 'oe')
      .replaceAll('ä', 'ae')
      .replaceAll('ß', 'ss');

  static Future<String> _collection() async {
    final cached = _collectionId;
    if (cached != null) return cached;
    final resp = await http
        .get(Uri.parse('$_base/collections?f=json'), headers: _headers)
        .timeout(const Duration(seconds: 20));
    if (resp.statusCode != 200) {
      throw StateError('Datensatzliste: HTTP ${resp.statusCode}');
    }
    final data = jsonDecode(utf8.decode(resp.bodyBytes, allowMalformed: true));
    final list = data is Map ? data['collections'] : null;
    if (list is List) {
      for (final c in list) {
        if (c is Map) {
          final id = '${c['id']}';
          final text = _norm('$id ${c['title'] ?? ''}');
          if (text.contains('flurstueck')) {
            _collectionId = id;
            return id;
          }
        }
      }
    }
    throw StateError('Datensatz "Flurstück" nicht gefunden');
  }

  static String? _find(Map<String, dynamic> props, List<String> keys) {
    for (final key in keys) {
      for (final e in props.entries) {
        if (_norm(e.key).contains(key) &&
            e.value != null &&
            '${e.value}'.trim().isNotEmpty) {
          return '${e.value}'.trim();
        }
      }
    }
    return null;
  }

  static String _label(Map<String, dynamic> props, String id) {
    final kz = _find(props, ['kennzeichen']);
    if (kz != null) return kz;
    final parts = <String>[];
    final gem = _find(props, ['gemarkung']);
    final flur = _find(props, ['flurnummer', 'flur']);
    final zaehler = _find(props, ['zaehler']);
    final nenner = _find(props, ['nenner']);
    if (gem != null) parts.add(gem);
    if (flur != null) parts.add('Flur $flur');
    if (zaehler != null) {
      parts.add('Flurstück $zaehler${nenner != null ? '/$nenner' : ''}');
    }
    return parts.isEmpty ? id : parts.join(', ');
  }

  static double? _area(Map<String, dynamic> props) {
    final v = _find(props, ['flaeche']);
    if (v == null) return null;
    return double.tryParse(v.replaceAll(',', '.'));
  }

  /// Flurstueck an einer Stelle der Karte (Punkt-in-Flaeche).
  static Future<FlurstueckResult> at(LatLng p) async {
    try {
      final id = await _collection();
      const d = 0.00004; // ca. 4 m
      final bbox = [
        p.longitude - d,
        p.latitude - d,
        p.longitude + d,
        p.latitude + d,
      ].map((v) => v.toStringAsFixed(7)).join(',');
      final url = '$_base/collections/$id/items?f=json&bbox=$bbox&limit=50';
      final resp = await http
          .get(Uri.parse(url), headers: _headers)
          .timeout(const Duration(seconds: 25));
      if (resp.statusCode != 200) {
        return FlurstueckResult(error: 'HTTP ${resp.statusCode}');
      }
      final data = jsonDecode(utf8.decode(resp.bodyBytes, allowMalformed: true));
      final feats = data is Map ? data['features'] : null;
      if (feats is! List) {
        return const FlurstueckResult(error: 'Unerwartete Antwort des Dienstes');
      }
      for (final f in feats) {
        if (f is! Map) continue;
        final geom = ParcelGeometry.fromGeoJson(f['geometry']);
        if (geom == null || !geom.contains(p)) continue;
        final props = f['properties'] is Map
            ? Map<String, dynamic>.from(f['properties'] as Map)
            : <String, dynamic>{};
        final fid = (f['id'] ?? props['gml_id'] ?? '${p.latitude},${p.longitude}')
            .toString();
        return FlurstueckResult(
          hit: FlurstueckHit(
            id: fid,
            geometry: geom,
            props: props,
            label: _label(props, fid),
            area: _area(props) ?? geom.areaM2(),
          ),
        );
      }
      return const FlurstueckResult(error: 'Hier wurde kein Flurstück gefunden');
    } catch (e) {
      return FlurstueckResult(error: e.toString());
    }
  }
}
