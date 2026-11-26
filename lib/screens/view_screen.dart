import 'package:flutter/material.dart';

import '../models/shape_models.dart';
import '../services/settings_store.dart';

/// Ansicht: einzelne Arten von Punkten, Flaechen und Linien auf der Karte
/// ein- oder ausblenden.
class ViewScreen extends StatefulWidget {
  final MapSettings settings;

  /// Anzahl vorhandener Eintraege je Schluessel (zur Orientierung).
  final Map<String, int> counts;
  final VoidCallback onChanged;

  const ViewScreen({
    super.key,
    required this.settings,
    required this.counts,
    required this.onChanged,
  });

  @override
  State<ViewScreen> createState() => _ViewScreenState();
}

class _Item {
  final String key;
  final String label;
  final IconData icon;
  final Color color;
  const _Item(this.key, this.label, this.icon, this.color);
}

class _ViewScreenState extends State<ViewScreen> {
  static const List<_Item> _points = [
    _Item('own', 'Eigene Punkte', Icons.adjust, Color(0xFF607D8B)),
    _Item('jagd', 'Jagdeinrichtungen', Icons.cabin, Color(0xFF6A1B9A)),
    _Item('habitat', 'Habitatbäume', Icons.park, Color(0xFF2E7D32)),
    _Item('pflanz', 'Anpflanzungen', Icons.grass, Color(0xFF43A047)),
    _Item('damages', 'Frühere Schäden (Käfernest, Sturmschaden)',
        Icons.bug_report, Color(0xFFC62828)),
  ];

  List<_Item> get _shapes => [
        for (final t in kShapeTypes)
          _Item(
            'shape:${t.key}',
            t.label,
            t.icon,
            t.color,
          ),
      ];

  static const _parcels = [
    _Item('parcels', 'Parzellen', Icons.crop_square, Color(0xFFFFA000)),
  ];

  void _set(String key, bool visible) {
    setState(() {
      if (visible) {
        widget.settings.hidden.remove(key);
      } else {
        widget.settings.hidden.add(key);
      }
    });
    widget.onChanged();
  }

  void _all(bool visible) {
    setState(() {
      if (visible) {
        widget.settings.hidden.clear();
      } else {
        for (final i in [..._points, ..._shapes, ..._parcels]) {
          widget.settings.hidden.add(i.key);
        }
      }
    });
    widget.onChanged();
  }

  Widget _tile(_Item i) {
    final n = widget.counts[i.key] ?? 0;
    return SwitchListTile(
      secondary: Icon(i.icon, color: i.color),
      title: Text(i.label),
      subtitle: Text(n == 0 ? 'keine vorhanden' : '$n vorhanden'),
      value: !widget.settings.hidden.contains(i.key),
      onChanged: (v) => _set(i.key, v),
    );
  }

  Widget _header(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Text(
          text,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Zurück',
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('Ansicht'),
      ),
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Wrap(
              spacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: () => _all(true),
                  icon: const Icon(Icons.visibility),
                  label: const Text('Alle einblenden'),
                ),
                OutlinedButton.icon(
                  onPressed: () => _all(false),
                  icon: const Icon(Icons.visibility_off),
                  label: const Text('Alle ausblenden'),
                ),
              ],
            ),
          ),
          _header('Punkte'),
          for (final i in _points)
            if (i.key != 'damages' || (widget.counts['damages'] ?? 0) > 0) _tile(i),
          _header('Flächen und Linien'),
          for (final i in _shapes) _tile(i),
          _header('Parzellen'),
          for (final i in _parcels) _tile(i),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
