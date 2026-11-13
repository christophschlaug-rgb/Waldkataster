import 'package:flutter/material.dart';

import '../models/marked_point.dart';
import '../widgets/map_widgets.dart';
import 'point_sheet.dart';

/// Liste aller gemerkten Punkte (eigene Punkte und bearbeitete Grenzpunkte).
class PointsScreen extends StatefulWidget {
  final List<MarkedPoint> points;
  final Future<void> Function(MarkedPoint point) onDelete;

  const PointsScreen({super.key, required this.points, required this.onDelete});

  @override
  State<PointsScreen> createState() => _PointsScreenState();
}

class _PointsScreenState extends State<PointsScreen> {
  late List<MarkedPoint> _points;

  @override
  void initState() {
    super.initState();
    _points = [...widget.points]
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  }

  Future<void> _delete(MarkedPoint p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(p.isOwn ? 'Punkt löschen?' : 'Eintrag zurücksetzen?'),
        content: Text(
          p.isOwn
              ? '"${p.name}" wird von diesem Handy gelöscht.'
              : 'Status, Notiz und Messung von "${p.name}" werden gelöscht. '
                  'Der Katasterpunkt selbst bleibt erhalten.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(p.isOwn ? 'Löschen' : 'Zurücksetzen'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await widget.onDelete(p);
    if (mounted) setState(() => _points.removeWhere((x) => x.id == p.id));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Meine Punkte')),
      body: _points.isEmpty
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
              itemCount: _points.length,
              itemBuilder: (context, i) {
                final p = _points[i];
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
                  trailing: IconButton(
                    tooltip: p.isOwn ? 'Punkt löschen' : 'Eintrag zurücksetzen',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => _delete(p),
                  ),
                );
              },
            ),
    );
  }
}
