import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

import '../models/shape_models.dart';
import 'geo_utils.dart';

const Distance _dist = Distance();

double distM(LatLng a, LatLng b) => _dist.as(LengthUnit.Meter, a, b);

double lineLengthM(List<LatLng> pts, {bool closed = false}) {
  var sum = 0.0;
  for (var i = 0; i + 1 < pts.length; i++) {
    sum += distM(pts[i], pts[i + 1]);
  }
  if (closed && pts.length > 2) sum += distM(pts.last, pts.first);
  return sum;
}

/// Flaeche eines Rings in Quadratmetern (ebene Naeherung um den Schwerpunkt).
double ringAreaM2(List<LatLng> ring) {
  if (ring.length < 3) return 0;
  final c = centroidOf(ring);
  final cosLat = math.cos(c.latitude * math.pi / 180);
  var sum = 0.0;
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

LatLng centroidOf(List<LatLng> pts) {
  var lat = 0.0, lon = 0.0;
  for (final p in pts) {
    lat += p.latitude;
    lon += p.longitude;
  }
  return LatLng(lat / pts.length, lon / pts.length);
}

bool pointInRing(LatLng p, List<LatLng> ring) {
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

/// Abstand eines Punktes zu einer Strecke in Metern.
double distanceToSegmentM(LatLng p, LatLng a, LatLng b) {
  final cosLat = math.cos(p.latitude * math.pi / 180);
  double x(LatLng q) => (q.longitude - p.longitude) * 111320 * cosLat;
  double y(LatLng q) => (q.latitude - p.latitude) * 110574;
  final ax = x(a), ay = y(a), bx = x(b), by = y(b);
  final dx = bx - ax, dy = by - ay;
  final len2 = dx * dx + dy * dy;
  var t = len2 == 0 ? 0.0 : -(ax * dx + ay * dy) / len2;
  if (t < 0) t = 0;
  if (t > 1) t = 1;
  final px = ax + t * dx, py = ay + t * dy;
  return math.sqrt(px * px + py * py);
}

double distanceToLineM(LatLng p, List<LatLng> pts) {
  if (pts.isEmpty) return double.infinity;
  if (pts.length == 1) return distM(p, pts.first);
  var best = double.infinity;
  for (var i = 0; i + 1 < pts.length; i++) {
    final d = distanceToSegmentM(p, pts[i], pts[i + 1]);
    if (d < best) best = d;
  }
  return best;
}

/// Douglas-Peucker: entfernt Punkte, die weniger als [toleranceM] von der
/// Verbindungslinie abweichen (glaettet aufgezeichnete Routen).
List<LatLng> simplifyPoints(List<LatLng> pts, double toleranceM) {
  if (pts.length < 3) return List<LatLng>.of(pts);
  final keep = List<bool>.filled(pts.length, false);
  keep[0] = true;
  keep[pts.length - 1] = true;

  void rec(int from, int to) {
    var maxD = 0.0;
    var idx = -1;
    for (var i = from + 1; i < to; i++) {
      final d = distanceToSegmentM(pts[i], pts[from], pts[to]);
      if (d > maxD) {
        maxD = d;
        idx = i;
      }
    }
    if (idx != -1 && maxD > toleranceM) {
      keep[idx] = true;
      rec(from, idx);
      rec(idx, to);
    }
  }

  rec(0, pts.length - 1);
  return [
    for (var i = 0; i < pts.length; i++)
      if (keep[i]) pts[i],
  ];
}

class ParcelRef {
  final String id;
  final ParcelGeometry geometry;
  const ParcelRef(this.id, this.geometry);
}

class ShapeStats {
  final double areaM2;
  final double lengthM;
  final List<ParcelShare> shares;
  const ShapeStats(this.areaM2, this.lengthM, this.shares);
}

String _parcelAt(LatLng p, List<ParcelRef> parcels) {
  for (final r in parcels) {
    if (r.geometry.contains(p)) return r.id;
  }
  return '';
}

/// Berechnet Flaeche, Laenge und die Anteile je Parzelle. Die Anteile werden
/// durch Raster-Stichproben ermittelt (Genauigkeit im Prozentbereich).
ShapeStats computeShapeStats({
  required bool isLine,
  required List<LatLng> points,
  required double width,
  required List<ParcelRef> parcels,
}) {
  final counts = <String, int>{};
  var total = 0;

  if (!isLine) {
    final area = ringAreaM2(points);
    final length = lineLengthM(points, closed: true);
    if (points.length >= 3 && area > 0) {
      var minLat = 90.0, maxLat = -90.0, minLon = 180.0, maxLon = -180.0;
      for (final p in points) {
        minLat = math.min(minLat, p.latitude);
        maxLat = math.max(maxLat, p.latitude);
        minLon = math.min(minLon, p.longitude);
        maxLon = math.max(maxLon, p.longitude);
      }
      const n = 40;
      final dLat = (maxLat - minLat) / n;
      final dLon = (maxLon - minLon) / n;
      for (var i = 0; i < n; i++) {
        for (var j = 0; j < n; j++) {
          final p = LatLng(minLat + (i + 0.5) * dLat, minLon + (j + 0.5) * dLon);
          if (!pointInRing(p, points)) continue;
          final id = _parcelAt(p, parcels);
          counts[id] = (counts[id] ?? 0) + 1;
          total++;
        }
      }
      if (total == 0) {
        final id = _parcelAt(centroidOf(points), parcels);
        counts[id] = 1;
        total = 1;
      }
    }
    return ShapeStats(area, length, [
      for (final e in counts.entries)
        ParcelShare(
          parcelId: e.key,
          areaM2: area * e.value / total,
          lengthM: 0,
        ),
    ]);
  }

  final length = lineLengthM(points);
  final area = length * width;
  if (points.length >= 2 && length > 0) {
    final step = math.max(1.5, length / 200);
    for (var i = 0; i + 1 < points.length; i++) {
      final a = points[i];
      final b = points[i + 1];
      final segLen = distM(a, b);
      final steps = math.max(1, (segLen / step).ceil());
      for (var k = 0; k < steps; k++) {
        final t = (k + 0.5) / steps;
        final p = LatLng(
          a.latitude + (b.latitude - a.latitude) * t,
          a.longitude + (b.longitude - a.longitude) * t,
        );
        final id = _parcelAt(p, parcels);
        counts[id] = (counts[id] ?? 0) + 1;
        total++;
      }
    }
  }
  return ShapeStats(area, length, [
    for (final e in counts.entries)
      ParcelShare(
        parcelId: e.key,
        areaM2: total == 0 ? 0 : area * e.value / total,
        lengthM: total == 0 ? 0 : length * e.value / total,
      ),
  ]);
}

/// Welcher Anteil der Flaeche A von der Flaeche B ueberdeckt wird (0 bis 1).
double overlapFraction(List<LatLng> a, List<LatLng> b) {
  if (a.length < 3 || b.length < 3) return 0;
  double minLat(List<LatLng> l) => l.map((p) => p.latitude).reduce(math.min);
  double maxLat(List<LatLng> l) => l.map((p) => p.latitude).reduce(math.max);
  double minLon(List<LatLng> l) => l.map((p) => p.longitude).reduce(math.min);
  double maxLon(List<LatLng> l) => l.map((p) => p.longitude).reduce(math.max);

  final aMinLat = minLat(a), aMaxLat = maxLat(a);
  final aMinLon = minLon(a), aMaxLon = maxLon(a);
  if (aMaxLat < minLat(b) ||
      aMinLat > maxLat(b) ||
      aMaxLon < minLon(b) ||
      aMinLon > maxLon(b)) {
    return 0;
  }
  const n = 30;
  final dLat = (aMaxLat - aMinLat) / n;
  final dLon = (aMaxLon - aMinLon) / n;
  var inside = 0, both = 0;
  for (var i = 0; i < n; i++) {
    for (var j = 0; j < n; j++) {
      final p = LatLng(aMinLat + (i + 0.5) * dLat, aMinLon + (j + 0.5) * dLon);
      if (!pointInRing(p, a)) continue;
      inside++;
      if (pointInRing(p, b)) both++;
    }
  }
  return inside == 0 ? 0 : both / inside;
}
