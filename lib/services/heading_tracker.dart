import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:sensors_plus/sensors_plus.dart';

/// Kompass aus Beschleunigungs- und Magnetfeldsensor (Handy flach halten).
/// Der Wert ist die Blickrichtung in Grad (0 = Norden, 90 = Osten).
class HeadingTracker {
  /// Ungefaehre Missweisung (Ablenkung der Kompassnadel nach Osten)
  /// fuer Rheinland-Pfalz. Ein Fehler von ca. 1 Grad ist hier unerheblich.
  static const double declinationDeg = 4.0;

  final ValueNotifier<double?> heading = ValueNotifier<double?>(null);

  StreamSubscription<AccelerometerEvent>? _accSub;
  StreamSubscription<MagnetometerEvent>? _magSub;
  List<double>? _g;
  List<double>? _m;
  double _sinF = 0;
  double _cosF = 0;
  bool _hasAngle = false;
  double? _lastPublished;

  bool get running => _accSub != null;

  void start() {
    if (running) return;
    _accSub = accelerometerEventStream(
      samplingPeriod: SensorInterval.uiInterval,
    ).listen(
      (e) {
        _g = _lowPass(_g, [e.x, e.y, e.z], 0.12);
        _update();
      },
      onError: (_) {},
    );
    _magSub = magnetometerEventStream(
      samplingPeriod: SensorInterval.uiInterval,
    ).listen(
      (e) {
        _m = _lowPass(_m, [e.x, e.y, e.z], 0.12);
        _update();
      },
      onError: (_) {},
    );
  }

  void stop() {
    _accSub?.cancel();
    _magSub?.cancel();
    _accSub = null;
    _magSub = null;
  }

  void dispose() {
    stop();
    heading.dispose();
  }

  List<double> _lowPass(List<double>? prev, List<double> next, double alpha) {
    if (prev == null) return next;
    return [
      prev[0] + alpha * (next[0] - prev[0]),
      prev[1] + alpha * (next[1] - prev[1]),
      prev[2] + alpha * (next[2] - prev[2]),
    ];
  }

  void _update() {
    final g = _g;
    final m = _m;
    if (g == null || m == null) return;

    final ax = g[0], ay = g[1], az = g[2];
    final ex = m[0], ey = m[1], ez = m[2];

    // Gestoertes Magnetfeld (Metall, Auto, Stromleitung) ignorieren.
    final field = math.sqrt(ex * ex + ey * ey + ez * ez);
    if (field < 15 || field > 90) return;

    var hx = ey * az - ez * ay;
    var hy = ez * ax - ex * az;
    var hz = ex * ay - ey * ax;
    final normH = math.sqrt(hx * hx + hy * hy + hz * hz);
    if (normH < 0.1) return;
    hx /= normH;
    hy /= normH;
    hz /= normH;

    final normA = math.sqrt(ax * ax + ay * ay + az * az);
    if (normA == 0) return;
    final nax = ax / normA;
    final naz = az / normA;

    final my = naz * hx - nax * hz;
    final azimuth = math.atan2(hy, my); // Bogenmass, bezogen auf Magnetisch-Nord

    // Winkel mit Kreis-Tiefpass glaetten (kein Sprung bei 359 -> 0 Grad).
    const alpha = 0.2;
    if (!_hasAngle) {
      _sinF = math.sin(azimuth);
      _cosF = math.cos(azimuth);
      _hasAngle = true;
    } else {
      _sinF += alpha * (math.sin(azimuth) - _sinF);
      _cosF += alpha * (math.cos(azimuth) - _cosF);
    }

    var deg = math.atan2(_sinF, _cosF) * 180 / math.pi + declinationDeg;
    deg = (deg % 360 + 360) % 360;

    final last = _lastPublished;
    if (last != null) {
      var diff = (deg - last).abs();
      if (diff > 180) diff = 360 - diff;
      if (diff < 1.5) return;
    }
    _lastPublished = deg;
    heading.value = deg;
  }
}
