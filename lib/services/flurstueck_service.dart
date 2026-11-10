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
/// OGC-API-Features-Schnittstelle des Landesamts). Die Kennung des
/// Datensatzes wird aus der Datensatzliste ermittelt; als Rueckfall dienen
/// bekannte Schreibweisen.
class FlurstueckService {
  static const String _base = 'https://www.geoportal.rlp.de/spatial-objects/519';
  static const Map<String, String> _headers = {
    'Accept': 'application/geo+json, application/json',
  };
  static const List<String> _fallbackIds = [
    'ave:Flurstueck',
    'ave:Flurstück',
    'Flurstueck',
  ];
  static String? _collectionId;
  static String _collectionsInfo = '';

  static String _norm(String s) => s
      .toLowerCase()
      .replaceAll('ü', 'ue')
      .replaceAll('ö', 'oe')
      .replaceAll('ä', 'ae')
      .replaceAll('ß', 'ss');

  static String _snippet(String body, {int max = 280}) {
    final t = body.replaceAll(RegExp(r'\s+'), ' ').trim();
    return t.length > max ? '${t.substring(0, max)} …' : t;
  }

  /// Kennung eines Eintrags der Datensatzliste: je nach Dienst unter
  /// unterschiedlichen Namen oder nur im Verweis auf die Objekte.
  static String? _idOf(Map c) {
    for (final key in const [
      'id',
      'name',
      'collectionId',
      'collection_id',
      'featuretype',
      'featureType',
      'typename',
      'typeName',
    ]) {
      final v = c[key];
      if (v != null && '$v'.trim().isNotEmpty) return '$v'.trim();
    }
    final links = c['links'];
    if (links is List) {
      for (final l in links) {
        if (l is Map && l['href'] is String) {
          final m = RegExp(r'collections/([^/?]+)').firstMatch(l['href'] as String);
          if (m != null) return Uri.decodeComponent(m.group(1)!);
        }
      }
    }
    return null;
  }

  /// Moegliche Kennungen des Flurstueck-Datensatzes, beste zuerst.
  static Future<List<String>> _candidates() async {
    final out = <String>[];
    final cached = _collectionId;
    if (cached != null) out.add(cached);
    try {
      final resp = await http
          .get(Uri.parse('$_base/collections?f=json'), headers: _headers)
          .timeout(const Duration(seconds: 20));
      final body = utf8.decode(resp.bodyBytes, allowMalformed: true);
      _collectionsInfo = _snippet(body, max: 400);
      if (resp.statusCode == 200) {
        final data = jsonDecode(body);
        final list = data is Map ? data['collections'] : (data is List ? data : null);
        if (list is List) {
          final exact = <String>[];
          final loose = <String>[];
          for (final c in list) {
            if (c is! Map) continue;
            final id = _idOf(c);
            if (id == null) continue;
            final text = _norm('$id ${c['title'] ?? ''}');
            if (!text.contains('flurstueck')) continue;
            if (_norm(id).endsWith('flurstueck')) {
              exact.add(id);
            } else {
              loose.add(id);
            }
          }
          out.addAll(exact);
          out.addAll(loose);
        }
      }
    } catch (_) {}
    for (final id in _fallbackIds) {
      if (!out.contains(id)) out.add(id);
    }
    return out;
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
      const d = 0.00004; // ca. 4 m
      final bbox = [
        p.longitude - d,
        p.latitude - d,
        p.longitude + d,
        p.latitude + d,
      ].map((v) => v.toStringAsFixed(7)).join(',');

      final tried = <String>[];
      var problem = '';

      for (final id in await _candidates()) {
        tried.add(id);
        final url = '$_base/collections/${Uri.encodeComponent(id)}/items'
            '?f=json&limit=50&bbox=$bbox';
        final resp = await http
            .get(Uri.parse(url), headers: _headers)
            .timeout(const Duration(seconds: 25));
        final body = utf8.decode(resp.bodyBytes, allowMalformed: true);

        if (resp.statusCode != 200) {
          problem = 'HTTP ${resp.statusCode}: ${_snippet(body)}';
          continue;
        }
        Object? data;
        try {
          data = jsonDecode(body);
        } catch (_) {
          problem = 'Keine JSON-Antwort: ${_snippet(body)}';
          continue;
        }
        final feats = data is Map ? data['features'] : null;
        if (feats is! List) {
          // z. B. "Datensatz nicht vorhanden": naechste Schreibweise probieren
          problem = 'Unerwartete Antwort: ${_snippet(body)}';
          continue;
        }
        _collectionId = id;
        if (feats.isEmpty) {
          return const FlurstueckResult(
            error: 'An dieser Stelle wurde kein Flurstück gefunden.',
          );
        }

        var parsed = 0;
        for (final f in feats) {
          if (f is! Map) continue;
          final geom = ParcelGeometry.fromGeoJson(f['geometry']);
          if (geom == null) continue;
          parsed++;
          if (!geom.contains(p)) continue;
          final props = f['properties'] is Map
              ? Map<String, dynamic>.from(f['properties'] as Map)
              : <String, dynamic>{};
          final fid =
              (f['id'] ?? props['gml_id'] ?? '${p.latitude},${p.longitude}')
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
        return FlurstueckResult(
          error: parsed == 0
              ? 'Flurstücke ohne lesbare Fläche: ${_snippet(body)}'
              : 'Die angetippte Stelle liegt in keinem der gelieferten Flurstücke.',
        );
      }

      return FlurstueckResult(
        error: '$problem\n\nGeprüfte Datensatz-Kennungen: ${tried.join(', ')}'
            '\n\nDatensatzliste des Dienstes: $_collectionsInfo',
      );
    } catch (e) {
      return FlurstueckResult(error: e.toString());
    }
  }
}
