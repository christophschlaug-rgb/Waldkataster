import 'dart:convert';

import 'package:http/http.dart' as http;

class CadastralPoint {
  final String id;
  final double lat;
  final double lon;
  final Map<String, dynamic> properties;

  const CadastralPoint({
    required this.id,
    required this.lat,
    required this.lon,
    required this.properties,
  });

  /// Lesbarer Name: bevorzugt eine Punktkennung aus den Eigenschaften.
  String get title {
    for (final key in const ['punktkennung', 'kennung', 'name', 'bezeichnung']) {
      for (final e in properties.entries) {
        if (e.key.toLowerCase() == key &&
            e.value != null &&
            '${e.value}'.isNotEmpty) {
          return '${e.value}';
        }
      }
    }
    return id.length > 24 ? id.substring(id.length - 24) : id;
  }
}

class GrenzpunktResult {
  final List<CadastralPoint> points;
  final bool truncated;
  final String? error;

  const GrenzpunktResult({
    this.points = const [],
    this.truncated = false,
    this.error,
  });
}

/// Grenzpunkte aus dem Liegenschaftskataster ueber die OGC-API-Features-
/// Schnittstelle des Landesamts (WFS RP ALKIS Punkte, Objektart Grenzpunkt).
/// Koordinaten kommen als Laengen-/Breitengrad (CRS84).
class GrenzpunktService {
  static const String _items =
      'https://www.geoportal.rlp.de/spatial-objects/669/collections/vermkv:Grenzpunkt/items';

  static Future<GrenzpunktResult> fetch(
    double west,
    double south,
    double east,
    double north, {
    int limit = 2000,
  }) async {
    final bbox = [west, south, east, north]
        .map((v) => v.toStringAsFixed(6))
        .join(',');
    final url = '$_items?f=json&bbox=$bbox&limit=$limit';
    try {
      final resp = await http.get(
        Uri.parse(url),
        headers: const {'Accept': 'application/geo+json, application/json'},
      ).timeout(const Duration(seconds: 25));
      if (resp.statusCode != 200) {
        return GrenzpunktResult(error: 'HTTP ${resp.statusCode}');
      }
      final data = jsonDecode(utf8.decode(resp.bodyBytes, allowMalformed: true));
      if (data is! Map || data['features'] is! List) {
        return const GrenzpunktResult(error: 'Unerwartete Antwort des Dienstes');
      }
      final feats = data['features'] as List;
      final points = <CadastralPoint>[];
      for (final f in feats) {
        if (f is! Map) continue;
        final g = f['geometry'];
        if (g is! Map || g['type'] != 'Point') continue;
        final c = g['coordinates'];
        if (c is! List || c.length < 2) continue;
        final lon = (c[0] as num).toDouble();
        final lat = (c[1] as num).toDouble();
        // Plausibilitaet: es muessen Grad-Werte sein
        if (lon.abs() > 180 || lat.abs() > 90) {
          return GrenzpunktResult(
            error: 'Koordinaten nicht als Längen-/Breitengrad geliefert ($lon, $lat)',
          );
        }
        final props = f['properties'] is Map
            ? Map<String, dynamic>.from(f['properties'] as Map)
            : <String, dynamic>{};
        final id = (f['id'] ?? props['gml_id'] ?? '$lat,$lon').toString();
        points.add(
          CadastralPoint(id: id, lat: lat, lon: lon, properties: props),
        );
      }
      return GrenzpunktResult(points: points, truncated: feats.length >= limit);
    } catch (e) {
      return GrenzpunktResult(error: e.toString());
    }
  }
}
