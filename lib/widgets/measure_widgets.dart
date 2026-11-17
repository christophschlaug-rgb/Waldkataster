import 'package:flutter/material.dart';

import '../models/forest_models.dart';
import '../services/db_service.dart';
import 'stand_editor.dart';

String _two(int v) => v.toString().padLeft(2, '0');

String dateText(DateTime d) => '${_two(d.day)}.${_two(d.month)}.${d.year}';

const List<String> kMonatsnamen = [
  'Januar',
  'Februar',
  'März',
  'April',
  'Mai',
  'Juni',
  'Juli',
  'August',
  'September',
  'Oktober',
  'November',
  'Dezember',
];

/// Macht aus [base] einen Schluessel, der in [m] noch nicht vorkommt.
String uniqueKey(Map<String, String> m, String base) {
  if (!m.containsKey(base)) return base;
  var i = 2;
  while (m.containsKey('$base ($i)')) {
    i++;
  }
  return '$base ($i)';
}

String measureRange(Measure m) {
  final e = m.end;
  if (e == null || (e.year == m.start.year && e.month == m.start.month && e.day == m.start.day)) {
    return dateText(m.start);
  }
  return '${dateText(m.start)} – ${dateText(e)}';
}

Color measureStatusColor(String s) {
  switch (s) {
    case 'Erledigt':
      return const Color(0xFF2E7D32);
    case 'In Arbeit':
      return const Color(0xFFEF6C00);
    default:
      return const Color(0xFF607D8B);
  }
}

/// Dialog zum Planen oder Bearbeiten einer Massnahme. Ist [fixedOwner]
/// gesetzt, steht die Zuordnung fest; sonst kann sie gewaehlt werden.
Future<Measure?> showMeasureDialog(
  BuildContext context, {
  Measure? existing,
  List<Parcel> parcels = const [],
  List<Dept> depts = const [],
  String? fixedOwner,
  String fixedOwnerLabel = '',
}) async {
  var art = existing?.art ?? kMassnahmenArten.first;
  var start = existing?.start ?? DateTime.now();
  DateTime? end = existing?.end;
  var status = existing?.status ?? 'Geplant';
  var owner = existing?.ownerId ?? fixedOwner ?? '';
  final note = TextEditingController(text: existing?.note ?? '');

  final ownerOptions = <String, String>{'Keine Zuordnung': ''};
  for (final d in depts) {
    ownerOptions[uniqueKey(ownerOptions, 'Abteilung: ${d.name}')] = 'd:${d.id}';
  }
  for (final p in parcels) {
    ownerOptions[uniqueKey(ownerOptions, 'Parzelle: ${p.name}')] = 'p:${p.id}';
  }

  String ownerLabel() {
    for (final e in ownerOptions.entries) {
      if (e.value == owner) return e.key;
    }
    return 'Keine Zuordnung';
  }

  final saved = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setD) {
        Future<void> pick(bool isStart) async {
          final d = await showDatePicker(
            context: ctx,
            initialDate: isStart ? start : (end ?? start),
            firstDate: DateTime(2000),
            lastDate: DateTime(2100),
          );
          if (d == null) return;
          final day = DateTime(d.year, d.month, d.day);
          setD(() {
            if (isStart) {
              start = day;
              final e = end;
              if (e != null && e.isBefore(day)) end = day;
            } else {
              end = day;
            }
          });
        }

        return AlertDialog(
          title: Text(existing == null ? 'Maßnahme planen' : 'Maßnahme bearbeiten'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LabeledDropdown(
                  label: 'Art der Maßnahme',
                  value: art,
                  options: kMassnahmenArten,
                  onChanged: (v) => setD(() => art = v.isEmpty ? kMassnahmenArten.first : v),
                ),
                const SizedBox(height: 12),
                if (fixedOwner != null)
                  Text('Zuordnung: ${fixedOwnerLabel.isEmpty ? 'Keine' : fixedOwnerLabel}')
                else
                  LabeledDropdown(
                    label: 'Zuordnung',
                    value: ownerLabel(),
                    options: ownerOptions.keys.toList(),
                    onChanged: (v) => setD(() => owner = ownerOptions[v] ?? ''),
                  ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(child: Text('Beginn: ${dateText(start)}')),
                    IconButton(
                      tooltip: 'Beginn wählen',
                      icon: const Icon(Icons.calendar_month),
                      onPressed: () => pick(true),
                    ),
                  ],
                ),
                Row(
                  children: [
                    Expanded(
                      child: Text(end == null ? 'Ende: offen' : 'Ende: ${dateText(end!)}'),
                    ),
                    if (end != null)
                      IconButton(
                        tooltip: 'Ende entfernen',
                        icon: const Icon(Icons.clear),
                        onPressed: () => setD(() => end = null),
                      ),
                    IconButton(
                      tooltip: 'Ende wählen',
                      icon: const Icon(Icons.calendar_month),
                      onPressed: () => pick(false),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                LabeledDropdown(
                  label: 'Status',
                  value: status,
                  options: kMassnahmeStatus,
                  onChanged: (v) => setD(() => status = v.isEmpty ? 'Geplant' : v),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: note,
                  minLines: 1,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Notiz',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Abbrechen'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Speichern'),
            ),
          ],
        );
      },
    ),
  );
  if (saved != true) return null;

  return Measure(
    id: existing?.id ?? newId('m'),
    ownerId: owner,
    art: art,
    start: start,
    end: end,
    status: status,
    note: note.text.trim(),
    updatedAt: DateTime.now(),
  );
}

/// Eine Zeile der Massnahmenliste.
Widget measureTile(
  Measure m, {
  required String ownerName,
  required VoidCallback onTap,
  required VoidCallback onDelete,
}) {
  return Card(
    child: ListTile(
      leading: Icon(
        m.status == 'Erledigt' ? Icons.check_circle : Icons.event,
        color: measureStatusColor(m.status),
      ),
      title: Text(m.art),
      subtitle: Text(
        '${ownerName.isEmpty ? '' : '$ownerName · '}${measureRange(m)} · ${m.status}'
        '${m.note.isNotEmpty ? '\n${m.note}' : ''}',
      ),
      isThreeLine: m.note.isNotEmpty,
      onTap: onTap,
      trailing: IconButton(
        tooltip: 'Maßnahme löschen',
        icon: const Icon(Icons.delete_outline),
        onPressed: onDelete,
      ),
    ),
  );
}

Future<bool> confirmDelete(BuildContext context, String title) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
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
  return ok == true;
}

/// Massnahmen einer Parzelle oder Abteilung (im Steckbrief).
class MeasureEditor extends StatefulWidget {
  final String ownerId;
  final String ownerLabel;
  const MeasureEditor({super.key, required this.ownerId, required this.ownerLabel});

  @override
  State<MeasureEditor> createState() => _MeasureEditorState();
}

class _MeasureEditorState extends State<MeasureEditor> {
  List<Measure> _items = [];
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final list = await DbService.instance.measures(ownerId: widget.ownerId);
      if (!mounted) return;
      setState(() {
        _items = list;
        _loaded = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loaded = true);
    }
  }

  Future<void> _edit(Measure? existing) async {
    final m = await showMeasureDialog(
      context,
      existing: existing,
      fixedOwner: widget.ownerId,
      fixedOwnerLabel: widget.ownerLabel,
    );
    if (m == null) return;
    try {
      await DbService.instance.upsertMeasure(m);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Speichern nicht möglich: $e')));
      }
    }
    await _load();
  }

  Future<void> _delete(Measure m) async {
    if (!await confirmDelete(context, 'Maßnahme "${m.art}" löschen?')) return;
    await DbService.instance.deleteMeasure(m.id);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_items.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text('Noch keine Maßnahmen geplant.',
                style: TextStyle(color: Colors.grey)),
          ),
        for (final m in _items)
          measureTile(
            m,
            ownerName: '',
            onTap: () => _edit(m),
            onDelete: () => _delete(m),
          ),
        Align(
          alignment: Alignment.centerRight,
          child: OutlinedButton.icon(
            onPressed: () => _edit(null),
            icon: const Icon(Icons.add),
            label: const Text('Maßnahme planen'),
          ),
        ),
      ],
    );
  }
}
