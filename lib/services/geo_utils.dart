import 'dart:convert';
import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

/// Flaeche einer Parzelle: polygons[i][0] = Aussenring, danach Loecher.
class ParcelGeometry {
  final List<List<List<LatLng>>> polygons;
  const ParcelGeometry(this.polygons);

  static List<LatLng> _ring(Object? raw) {
    final out = <LatLng>[];
    if (raw is List) {
      for (final c in raw) {
        if (c is List && c.length >= 2) {
          out.add(LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()));
        }
      }
    }
    return out;
  }

  static ParcelGeometry? fromGeoJson(Object? geometry) {
    if (geometry is! Map) return null;
    final type = geometry['type'];
    final coords = geometry['coordinates'];
    final polys = <List<List<LatLng>>>[];
    if (type == 'Polygon' && coords is List) {
      polys.add([for (final r in coords) _ring(r)]);
    } else if (type == 'MultiPolygon' && coords is List) {
      for (final p in coords) {
        if (p is List) polys.add([for (final r in p) _ring(r)]);
      }
    } else {
      return null;
    }
    polys.removeWhere((p) => p.isEmpty || p.first.length < 3);
    if (polys.isEmpty) return null;
    return ParcelGeometry(polys);
  }

  static ParcelGeometry? fromJsonString(String s) {
    try {
      return fromGeoJson(jsonDecode(s));
    } catch (_) {
      return null;
    }
  }

  String toJsonString() {
    final multi = [
      for (final p in polygons)
        [
          for (final ring in p)
            [
              for (final pt in ring) [pt.longitude, pt.latitude],
            ],
        ],
    ];
    return jsonEncode({'type': 'MultiPolygon', 'coordinates': multi});
  }

  List<LatLng> get allPoints => [
        for (final p in polygons) ...p.first,
      ];

  /// Naeherung fuer die Beschriftung: Mittelwert der Eckpunkte des
  /// groessten Aussenrings.
  LatLng get centroid {
    var best = polygons.first.first;
    for (final p in polygons) {
      if (p.first.length > best.length) best = p.first;
    }
    double lat = 0, lon = 0;
    for (final pt in best) {
      lat += pt.latitude;
      lon += pt.longitude;
    }
    return LatLng(lat / best.length, lon / best.length);
  }

  static bool _inRing(LatLng p, List<LatLng> ring) {
    var inside = false;
    for (var i = 0, j = ring.length - 1; i < ring.length; j = i++) {
      final a = ring[i];
      final b = ring[j];
      final crosses = (a.latitude > p.latitude) != (b.latitude > p.latitude);
      if (crosses) {
        final x = (b.longitude - a.longitude) *
                (p.latitude - a.latitude) /
                (b.latitude - a.latitude) +
            a.longitude;
        if (p.longitude < x) inside = !inside;
      }
    }
    return inside;
  }

  bool contains(LatLng p) {
    for (final poly in polygons) {
      if (!_inRing(p, poly.first)) continue;
      var inHole = false;
      for (var i = 1; i < poly.length; i++) {
        if (_inRing(p, poly[i])) {
          inHole = true;
          break;
        }
      }
      if (!inHole) return true;
    }
    return false;
  }

  /// Flaeche in Quadratmetern (Naeherung ueber ebene Projektion).
  double areaM2() {
    final c = centroid;
    final cosLat = math.cos(c.latitude * math.pi / 180);
    double ringArea(List<LatLng> ring) {
      double sum = 0;
      for (var i = 0; i < ring.length; i++) {
        final a = ring[i];
        final b = ring[(i + 1) % ring.length];
        final ax = (a.longitude - c.longitude) * 111320 * cosLat;
        final ay = (a.latitude - c.latitude) * 110574;
        final bx = (b.longitude - c.longitude) * 111320 * cosLat;
        final by = (b.latitude - c.latitude) * 110574;
        sum += ax * by - bx * ay;
      }
      return sum.abs() / 2;
    }

    double total = 0;
    for (final poly in polygons) {
      total += ringArea(poly.first);
      for (var i = 1; i < poly.length; i++) {
        total -= ringArea(poly[i]);
      }
    }
    return total;
  }
}

String formatArea(double? m2) {
  if (m2 == null) return '–';
  if (m2 >= 10000) {
    return '${(m2 / 10000).toStringAsFixed(2).replaceAll('.', ',')} ha';
  }
  return '${m2.round()} m²';
}
