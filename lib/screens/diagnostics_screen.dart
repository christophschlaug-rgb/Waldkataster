import 'package:flutter/material.dart';

import '../app_config.dart';
import '../services/wms_service.dart';

/// Zeigt, welche Kartendienste erreichbar sind und was die App daraus liest.
/// Hilfreich, falls eine Ebene auf der Karte fehlt.
class DiagnosticsScreen extends StatelessWidget {
  final Map<String, WmsService> services;
  final Map<String, int> tileErrors;
  final String? lastTileError;
  final List<String> extraLines;

  const DiagnosticsScreen({
    super.key,
    required this.services,
    required this.tileErrors,
    required this.lastTileError,
    this.extraLines = const [],
  });

  String _details(WmsService s) {
    final lines = <String>[];
    if (s.usable) {
      lines.add('Bereit${s.fromCache ? ' (aus dem Zwischenspeicher)' : ''}');
    } else {
      lines.add('Nicht nutzbar: ${s.problem}');
    }
    final caps = s.caps;
    if (caps != null) {
      lines.add('Koordinatensysteme: ${caps.srs.join(', ')}');
      lines.add('Bildformate: ${caps.formats.join(', ')}');
      final names = caps.layers.map((l) => l.name).toList();
      final shown = names.take(12).join(', ');
      lines.add(
        'Ebenen (${names.length}): $shown${names.length > 12 ? ' …' : ''}',
      );
      final minZ = caps.minZoomFor(WmsCatalog.defaultLayers(s));
      lines.add(
        minZ > 0
            ? 'Zeigt Bilder ab Zoomstufe ${minZ.toStringAsFixed(1)}'
            : 'Keine Maßstabsgrenze erkannt',
      );
      lines.add('Kartenadresse: ${caps.getMapUrl}');
    }
    final errors = tileErrors[s.def.id] ?? 0;
    if (errors > 0) lines.add('Fehlerhafte Kartenkacheln: $errors');
    if (s.error != null && s.usable) lines.add('Hinweis: ${s.error}');
    return lines.join('\n');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Dienste prüfen')),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          for (final line in extraLines)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(line, style: const TextStyle(fontSize: 13)),
            ),
          for (final def in kServiceDefs)
            Card(
              child: ListTile(
                leading: Icon(
                  services[def.id]?.usable == true
                      ? Icons.check_circle
                      : Icons.error,
                  color: services[def.id]?.usable == true
                      ? Colors.green
                      : Colors.red,
                ),
                title: Text(def.title),
                subtitle: Text(
                  services[def.id] == null
                      ? 'Noch nicht geladen'
                      : _details(services[def.id]!),
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ),
          if (lastTileError != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'Letzter Kachelfehler: $lastTileError',
                style: const TextStyle(fontSize: 12),
              ),
            ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: () => Navigator.of(context).pop(true),
            icon: const Icon(Icons.refresh),
            label: const Text('Dienste neu laden'),
          ),
        ],
      ),
    );
  }
}
