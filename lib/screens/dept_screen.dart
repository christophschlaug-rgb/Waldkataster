import 'package:flutter/material.dart';

import '../models/forest_models.dart';
import '../services/db_service.dart';
import '../services/geo_utils.dart';
import '../widgets/stand_editor.dart';

/// Abteilung: fasst mehrere Parzellen zusammen und hat eigene Bestandsaufnahme
/// und Kulturen. Liefert ggf. eine Aktion fuer die Karte ('dept:<id>').
class DeptScreen extends StatefulWidget {
  final Dept dept;
  const DeptScreen({super.key, required this.dept});

  @override
  State<DeptScreen> createState() => _DeptScreenState();
}

class _DeptScreenState extends State<DeptScreen> {
  late Dept _dept;
  late final TextEditingController _name;
  late final TextEditingController _note;
  List<Parcel> _parcels = [];
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _dept = widget.dept;
    _name = TextEditingController(text: _dept.name);
    _note = TextEditingController(text: _dept.note);
    _load();
  }

  @override
  void dispose() {
    _name.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final p = await DbService.instance.parcels();
      if (!mounted) return;
      setState(() {
        _parcels = p;
        _loaded = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loaded = true);
    }
  }

  Future<void> _saveBasics() async {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    final d = _dept.copyWith(name: name, note: _note.text.trim());
    await DbService.instance.upsertDept(d);
    setState(() => _dept = d);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Gespeichert')));
  }

  Future<void> _toggle(Parcel p, bool member) async {
    final updated = member ? p.copyWith(deptId: _dept.id) : p.copyWith(clearDept: true);
    await DbService.instance.upsertParcel(updated);
    await _load();
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Abteilung "${_dept.name}" löschen?'),
        content: const Text(
          'Die Parzellen bleiben erhalten, werden aber keiner Abteilung mehr '
          'zugeordnet. Bestandsaufnahme und Kulturen der Abteilung werden gelöscht.',
        ),
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
    await DbService.instance.deleteDept(_dept.id);
    if (mounted) Navigator.of(context).pop('deleted');
  }

  @override
  Widget build(BuildContext context) {
    final members = _parcels.where((p) => p.deptId == _dept.id).toList();
    double area = 0;
    for (final p in members) {
      area += p.area ?? 0;
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(_dept.name),
        actions: [
          IconButton(
            tooltip: 'Abteilung löschen',
            icon: const Icon(Icons.delete_outline),
            onPressed: _delete,
          ),
        ],
      ),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                TextField(
                  controller: _name,
                  decoration: const InputDecoration(
                    labelText: 'Name der Abteilung',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _note,
                  minLines: 1,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Notiz',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.tonal(
                    onPressed: _saveBasics,
                    child: const Text('Speichern'),
                  ),
                ),
                const Divider(height: 32),
                Text(
                  'Parzellen dieser Abteilung (${members.length}, ${formatArea(area)})',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                if (_parcels.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      'Wähle zuerst auf der Karte Parzellen aus.',
                      style: TextStyle(color: Colors.grey),
                    ),
                  ),
                for (final p in _parcels)
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(p.name),
                    subtitle: Text(
                      '${p.label} · ${formatArea(p.area)}'
                      '${p.deptId != null && p.deptId != _dept.id ? ' · in anderer Abteilung' : ''}',
                    ),
                    value: p.deptId == _dept.id,
                    onChanged: (v) => _toggle(p, v == true),
                  ),
                const Divider(height: 32),
                const Text(
                  'Bestandsaufnahme',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                StandEditor(ownerId: 'd:${_dept.id}'),
                const Divider(height: 32),
                const Text(
                  'Kulturen',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                KulturEditor(ownerId: 'd:${_dept.id}'),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: members.isEmpty
                      ? null
                      : () => Navigator.of(context).pop('dept:${_dept.id}'),
                  icon: const Icon(Icons.map_outlined),
                  label: const Text('Auf der Karte zeigen'),
                ),
              ],
            ),
    );
  }
}
