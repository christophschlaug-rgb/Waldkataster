import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/marked_point.dart';

Color statusColor(PointStatus s) {
  switch (s) {
    case PointStatus.open:
      return const Color(0xFF607D8B);
    case PointStatus.found:
      return const Color(0xFF2E7D32);
    case PointStatus.notFound:
      return const Color(0xFFC62828);
    case PointStatus.buried:
      return const Color(0xFFEF6C00);
  }
}

String cardinal(double deg) {
  const names = ['N', 'NO', 'O', 'SO', 'S', 'SW', 'W', 'NW'];
  final i = (((deg % 360) + 22.5) / 45).floor() % 8;
  return names[i];
}

/// Durchmesser der Punktmarkierung je Zoomstufe: weit weg klein, nah dran
/// groesser (Zoomstufe 16 = 6 px, ab Zoomstufe 21 = 20 px).
double dotSizeForZoom(double zoom) {
  final v = 6 + (zoom - 16) * 2.8;
  if (v < 6) return 6;
  if (v > 20) return 20;
  return v;
}

String formatMeters(double m) {
  if (m < 10) return '${m.toStringAsFixed(1).replaceAll('.', ',')} m';
  return '${m.round()} m';
}

/// Eigene Position mit Blickrichtung.
class PositionMarker extends StatelessWidget {
  final double? heading;
  const PositionMarker({super.key, required this.heading});

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

/// Grenzpunkt aus dem Kataster (Kreis, Farbe = Status). Nur Anzeige;
/// das Antippen wertet die Karte selbst aus (naechster Punkt).
class CadastralMarker extends StatelessWidget {
  final PointStatus status;
  final bool isTarget;
  final double dot;

  const CadastralMarker({
    super.key,
    required this.status,
    required this.isTarget,
    required this.dot,
  });

  @override
  Widget build(BuildContext context) {
    final size = isTarget ? dot + 6 : dot;
    return IgnorePointer(
      child: Center(
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: statusColor(status),
            shape: BoxShape.circle,
            border: Border.all(
              color: isTarget ? Colors.black : Colors.white,
              width: isTarget ? 2.5 : (dot < 9 ? 1 : 1.5),
            ),
          ),
        ),
      ),
    );
  }
}

/// Selbst gesetzter Punkt (Raute, Farbe = Status).
class OwnPointMarker extends StatelessWidget {
  final PointStatus status;
  final bool isTarget;
  final double dot;

  const OwnPointMarker({
    super.key,
    required this.status,
    required this.isTarget,
    required this.dot,
  });

  @override
  Widget build(BuildContext context) {
    final size = (isTarget ? dot + 6 : dot) * 0.85;
    return IgnorePointer(
      child: Center(
        child: Transform.rotate(
          angle: math.pi / 4,
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: statusColor(status),
              border: Border.all(
                color: isTarget ? Colors.black : Colors.white,
                width: isTarget ? 2.5 : (dot < 9 ? 1 : 1.5),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Zielfuehrung: Entfernung, Richtungspfeil und Messung.
class GuidancePanel extends StatelessWidget {
  final String name;
  final double? distanceM;
  final double? arrowDeg; // Drehung des Pfeils relativ zur Blickrichtung
  final double? bearingDeg; // Himmelsrichtung zum Ziel
  final double? accuracyM;
  final bool measuring;
  final int secondsLeft;
  final int samples;
  final VoidCallback onMeasure;
  final VoidCallback onCancelMeasure;
  final VoidCallback onDetails;
  final VoidCallback onClose;

  const GuidancePanel({
    super.key,
    required this.name,
    required this.distanceM,
    required this.arrowDeg,
    required this.bearingDeg,
    required this.accuracyM,
    required this.measuring,
    required this.secondsLeft,
    required this.samples,
    required this.onMeasure,
    required this.onCancelMeasure,
    required this.onDetails,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final d = distanceM;

    String hint = '';
    if (d == null) {
      hint = 'Warte auf GPS-Signal …';
    } else if (accuracyM != null && accuracyM! >= d) {
      hint = 'Du bist innerhalb der GPS-Genauigkeit (± ${accuracyM!.round()} m). '
          'Gehe langsam in Richtung des Pfeils und miss die Position.';
    } else if (arrowDeg == null) {
      hint = 'Richtung unbekannt: Handy flach halten und leicht bewegen '
          'oder ein paar Schritte gehen.';
    }

    return Card(
      elevation: 8,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 8, 8, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.flag, color: scheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Ziel beenden',
                  icon: const Icon(Icons.close),
                  onPressed: onClose,
                ),
              ],
            ),
            Row(
              children: [
                SizedBox(
                  width: 84,
                  height: 84,
                  child: Center(
                    child: arrowDeg == null
                        ? Icon(Icons.help_outline, size: 56, color: scheme.outline)
                        : Transform.rotate(
                            angle: arrowDeg! * math.pi / 180,
                            child: Icon(
                              Icons.navigation,
                              size: 72,
                              color: scheme.primary,
                            ),
                          ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        d == null ? '– m' : formatMeters(d),
                        style: const TextStyle(
                          fontSize: 40,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (bearingDeg != null)
                        Text(
                          'Richtung ${cardinal(bearingDeg!)} (${bearingDeg!.round()}°)',
                          style: const TextStyle(fontSize: 16),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            if (hint.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4, bottom: 4),
                child: Text(hint, style: const TextStyle(fontSize: 13)),
              ),
            const SizedBox(height: 6),
            if (measuring)
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Messung läuft: noch $secondsLeft s, $samples Werte. '
                      'Bitte stillhalten.',
                      style: const TextStyle(fontSize: 14),
                    ),
                  ),
                  OutlinedButton(
                    onPressed: onCancelMeasure,
                    child: const Text('Abbrechen'),
                  ),
                ],
              )
            else
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: onMeasure,
                      icon: const Icon(Icons.my_location),
                      label: const Text('Position messen (60 s)'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton(
                    onPressed: onDetails,
                    child: const Text('Details'),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
