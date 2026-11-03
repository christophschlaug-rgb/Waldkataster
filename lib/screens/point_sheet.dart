import 'package:flutter/material.dart';

import '../models/marked_point.dart';
import '../widgets/map_widgets.dart';

String formatDate(DateTime d) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(d.day)}.${two(d.month)}.${d.year} ${two(d.hour)}:${two(d.minute)}';
}

/// Details eines Punktes: Status, Notiz, Messung, Katastereigenschaften.
class PointSheet extends StatefulWidget {
  final MarkedPoint point;
  final Map<String, dynamic>? attributes;
  final bool isTarget;
  final Future<void> Function(MarkedPoint updated) onSave;
  final VoidCallback onToggleTarget;
  final Future<void> Function()? onDelete;

  const PointSheet({
    super.key,
    required this.point,
    required this.attributes,
    required this.isTarget,
    required this.onSave,
    required this.onToggleTarget,
    required this.onDelete,
  });

  @override
  State<PointSheet> createState() => _PointSheetState();
}

class _PointSheetState extends State<PointSheet> {
  late PointStatus _status;
  late final TextEditingController _note;
  late final TextEditingController _name;

  @override
  void initState() {
    super.initState();
    _status = widget.point.status;
    _note = TextEditingController(text: widget.point.note);
    _name = TextEditingController(text: widget.point.name);
  }

  @override
  void dispose() {
    _note.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    final updated = widget.point.copyWith(
      name: widget.point.isOwn && name.isNotEmpty ? name : null,
      status: _status,
      note: _note.text.trim(),
    );
    await widget.onSave(updated);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Punkt löschen?'),
        content: const Text('Der Punkt wird von diesem Handy gelöscht.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Löschen'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await widget.onDelete!();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.point;
    final attrs = widget.attributes;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: [
            Text(
              p.isOwn ? 'Eigener Punkt' : 'Grenzpunkt (Kataster)',
              style: const TextStyle(fontSize: 13, color: Colors.grey),
            ),
            if (p.isOwn)
              TextField(
                controller: _name,
                decoration: const InputDecoration(labelText: 'Name'),
              )
            else
              Text(
                p.name,
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
            const SizedBox(height: 4),
            SelectableText(
              'Koordinaten: ${p.lat.toStringAsFixed(6)}, ${p.lon.toStringAsFixed(6)}',
              style: const TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 12),
            const Text('Status', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final s in PointStatus.values)
                  ChoiceChip(
                    avatar: CircleAvatar(backgroundColor: statusColor(s), radius: 6),
                    label: Text(statusLabel(s)),
                    selected: _status == s,
                    onSelected: (_) => setState(() => _status = s),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _note,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Notiz',
                border: OutlineInputBorder(),
              ),
            ),
            if (p.hasMeasurement) ...[
              const SizedBox(height: 12),
              Text(
                'Messung: ${p.measuredLat!.toStringAsFixed(6)}, '
                '${p.measuredLon!.toStringAsFixed(6)}'
                '${p.measuredAccuracy != null ? '  (± ${p.measuredAccuracy!.toStringAsFixed(1)} m' : ''}'
                '${p.measuredSamples != null ? ', ${p.measuredSamples} Werte' : ''}'
                '${p.measuredAccuracy != null ? ')' : ''}'
                '${p.measuredAt != null ? '\n${formatDate(p.measuredAt!)}' : ''}',
                style: const TextStyle(fontSize: 13),
              ),
            ],
            if (attrs != null && attrs.isNotEmpty)
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: const Text('Angaben aus dem Kataster'),
                children: [
                  for (final e in attrs.entries)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                          '${e.key}: ${e.value}',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                    ),
                ],
              ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: widget.onToggleTarget,
                    icon: Icon(widget.isTarget ? Icons.flag_outlined : Icons.flag),
                    label: Text(widget.isTarget ? 'Ziel beenden' : 'Als Ziel wählen'),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.tonal(onPressed: _save, child: const Text('Speichern')),
              ],
            ),
            if (widget.onDelete != null)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: _delete,
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Punkt löschen'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
