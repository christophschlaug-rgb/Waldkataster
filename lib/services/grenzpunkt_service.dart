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
  final int pages;
  final int? matched;

  const GrenzpunktResult({
    this.points = const [],
    this.truncated = false,
    this.error,
    this.pages = 0,
    this.matched,
  });
}

/// Grenzpunkte aus dem Liegenschaftskataster ueber die OGC-API-Features-
/// Schnittstelle des Landesamts (WFS RP ALKIS Punkte, Objektart Grenzpunkt).
/// Koordinaten kommen als Laengen-/Breitengrad (CRS84).
class GrenzpunktService {
  static const String _items =
      'https://www.geoportal.rlp.de/spatial-objects/669/collections/vermkv:Grenzpunkt/items';

  /// Der Dienst liefert grosse Ergebnisse seitenweise; es werden bis zu
  /// [maxPages] Seiten nacheinander geladen.
  static Future<GrenzpunktResult> fetch(
    double west,
    double south,
    double east,
    double north, {
    int limit = 2000,
    int maxPages = 10,
  }) async {
    final bbox = [west, south, east, north]
        .map((v) => v.toStringAsFixed(6))
        .join(',');
    String? url = '$_items?f=json&bbox=$bbox&limit=$limit';
    final points = <CadastralPoint>[];
    final seen = <String>{};
    var pages = 0;
    int? matched;

    try {
      while (url != null && pages < maxPages) {
        final resp = await http.get(
          Uri.parse(url),
          headers: const {'Accept': 'application/geo+json, application/json'},
        ).timeout(const Duration(seconds: 25));
        if (resp.statusCode != 200) {
          return GrenzpunktResult(
            points: points,
            pages: pages,
            error: 'HTTP ${resp.statusCode}',
          );
        }
        final data =
            jsonDecode(utf8.decode(resp.bodyBytes, allowMalformed: true));
        if (data is! Map || data['features'] is! List) {
          return GrenzpunktResult(
            points: points,
            pages: pages,
            error: 'Unerwartete Antwort des Dienstes',
          );
        }
        pages++;
        matched ??= data['numberMatched'] is num
            ? (data['numberMatched'] as num).toInt()
            : null;

        for (final f in data['features'] as List) {
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
              points: points,
              pages: pages,
              error:
                  'Koordinaten nicht als Längen-/Breitengrad geliefert ($lon, $lat)',
            );
          }
          final props = f['properties'] is Map
              ? Map<String, dynamic>.from(f['properties'] as Map)
              : <String, dynamic>{};
          final id = (f['id'] ?? props['gml_id'] ?? '$lat,$lon').toString();
          if (!seen.add(id)) continue;
          points.add(
            CadastralPoint(id: id, lat: lat, lon: lon, properties: props),
          );
        }

        // Verweis auf die naechste Seite (rel = next), falls vorhanden
        String? next;
        final links = data['links'];
        if (links is List) {
          for (final l in links) {
            if (l is Map && l['rel'] == 'next' && l['href'] is String) {
              next = Uri.parse(url).resolve(l['href'] as String).toString();
              break;
            }
          }
        }
        url = next;
      }
      return GrenzpunktResult(
        points: points,
        truncated: url != null,
        pages: pages,
        matched: matched,
      );
    } catch (e) {
      return GrenzpunktResult(points: points, pages: pages, error: e.toString());
    }
  }
}
