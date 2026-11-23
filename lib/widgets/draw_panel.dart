import 'package:flutter/material.dart';

import '../models/shape_models.dart';
import '../services/geo_utils.dart';
import 'map_widgets.dart';

/// Bedienfeld beim Zeichnen einer Flaeche oder Linie.
class DrawPanel extends StatelessWidget {
  final ShapeType type;
  final int pointCount;
  final double areaM2;
  final double lengthM;
  final bool recording;
  final double? accuracyM;
  final VoidCallback onUndo;
  final VoidCallback onToggleRecord;
  final VoidCallback onAddHere;
  final VoidCallback onFinish;
  final VoidCallback onCancel;

  const DrawPanel({
    super.key,
    required this.type,
    required this.pointCount,
    required this.areaM2,
    required this.lengthM,
    required this.recording,
    required this.accuracyM,
    required this.onUndo,
    required this.onToggleRecord,
    required this.onAddHere,
    required this.onFinish,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final needed = type.isLine ? 2 : 3;
    final info = type.isLine
        ? '$pointCount Punkte · Länge ${formatMeters(lengthM)}'
        : '$pointCount Punkte · Fläche ${pointCount >= 3 ? formatArea(areaM2) : '–'}';

    return Card(
      elevation: 8,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(type.icon, color: type.color),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${type.isLine ? 'Linie' : 'Fläche'} zeichnen: ${type.label}',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
                IconButton(
                  tooltip: 'Abbrechen',
                  icon: const Icon(Icons.close),
                  onPressed: onCancel,
                ),
              ],
            ),
            Text(info, style: const TextStyle(fontSize: 15)),
            const SizedBox(height: 4),
            Text(
              recording
                  ? 'Aufzeichnung läuft: gehe die ${type.isLine ? 'Linie' : 'Grenze'} ab'
                      '${accuracyM != null ? ' (GPS ± ${accuracyM!.round()} m)' : ''}. '
                      'Zusätzlich kannst du Punkte antippen.'
                  : 'Tippe die ${type.isLine ? 'Punkte' : 'Eckpunkte'} auf der Karte an '
                      'oder starte die Aufzeichnung und gehe die Grenze ab.',
              style: const TextStyle(fontSize: 12, color: Colors.black54),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                OutlinedButton.icon(
                  onPressed: pointCount > 0 ? onUndo : null,
                  icon: const Icon(Icons.undo),
                  label: const Text('Zurück'),
                ),
                OutlinedButton.icon(
                  onPressed: onAddHere,
                  icon: const Icon(Icons.add_location_alt),
                  label: const Text('Punkt hier'),
                ),
                FilledButton.tonalIcon(
                  onPressed: onToggleRecord,
                  icon: Icon(recording ? Icons.pause : Icons.fiber_manual_record),
                  label: Text(recording ? 'Pause' : 'Aufzeichnen'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: pointCount >= needed ? onFinish : null,
                icon: const Icon(Icons.check),
                label: Text(
                  pointCount >= needed
                      ? 'Fertig'
                      : 'Fertig (mindestens $needed Punkte)',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
