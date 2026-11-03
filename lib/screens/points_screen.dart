import 'package:flutter/material.dart';

import '../models/marked_point.dart';
import '../widgets/map_widgets.dart';
import 'point_sheet.dart';

/// Liste aller gemerkten Punkte (eigene Punkte und bearbeitete Grenzpunkte).
class PointsScreen extends StatelessWidget {
  final List<MarkedPoint> points;
  const PointsScreen({super.key, required this.points});

  @override
  Widget build(BuildContext context) {
    final sorted = [...points]
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return Scaffold(
      appBar: AppBar(title: const Text('Meine Punkte')),
      body: sorted.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Noch keine Punkte.\nTippe auf der Karte einen Grenzpunkt an oder '
                  'setze mit langem Drücken einen eigenen Punkt.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16, color: Colors.grey),
                ),
              ),
            )
          : ListView.builder(
              itemCount: sorted.length,
              itemBuilder: (context, i) {
                final p = sorted[i];
                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: statusColor(p.status),
                    child: Icon(
                      p.isOwn ? Icons.place : Icons.adjust,
                      color: Colors.white,
                    ),
                  ),
                  title: Text(p.name),
                  subtitle: Text(
                    '${statusLabel(p.status)} · ${formatDate(p.updatedAt)}'
                    '${p.note.isNotEmpty ? '\n${p.note}' : ''}',
                  ),
                  isThreeLine: p.note.isNotEmpty,
                  onTap: () => Navigator.of(context).pop(p.id),
                );
              },
            ),
    );
  }
}
