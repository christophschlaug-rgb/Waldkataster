import 'package:flutter/material.dart';

import '../models/forest_models.dart';
import '../services/db_service.dart';
import '../services/geo_utils.dart';
import '../widgets/stand_editor.dart';

/// Steckbrief einer Parzelle: Name, Abteilung, Bestand, Kulturen, Objekte.
/// Liefert beim Schliessen ggf. eine Aktion fuer die Karte ('parcel:<id>').
class ParcelScreen extends StatefulWidget {
  final Parcel parcel;
  const ParcelScreen({super.key, required this.parcel});

  @override
  State<ParcelScreen> createState() => _ParcelScreenState();
}

class _ParcelScreenState extends State<ParcelScreen> {
  late Parcel _parcel;
  late final TextEditingController _name;
  List<Dept> _depts = [];
  List<ForestObject> _objects = [];
  bool _loaded = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _parcel = widget.parcel;
    _name = TextEditingController(text: _parcel.name);
    _load();
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final depts = await DbService.instance.depts();
      final all = await DbService.instance.objects();
      if (!mounted) return;
      setState(() {
        _depts = depts;
        _objects = all.where((o) => o.parcelId == _parcel.id).toList();
        _loaded = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loaded = true;
      });
    }
  }

  String get _deptName {
    for (final d in _depts) {
      if (d.id == _parcel.deptId) return d.name;
    }
    return '';
  }

  Future<void> _saveBasics() async {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    try {
      await DbService.instance.upsertParcel(_parcel.copyWith(name: name));
      setState(() => _parcel = _parcel.copyWith(name: name));
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Gespeichert')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Speichern nicht möglich: $e')));
    }
  }

  Future<void> _setDept(String name) async {
    Parcel updated;
    if (name.isEmpty) {
      updated = _parcel.copyWith(clearDept: true);
    } else {
      final d = _depts.firstWhere((d) => d.name == name);
      updated = _parcel.copyWith(deptId: d.id);
    }
    await DbService.instance.upsertParcel(updated);
    setState(() => _parcel = updated);
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Parzelle "${_parcel.name}" entfernen?'),
        content: const Text(
          'Die Parzelle samt Bestandsaufnahme und Kulturen wird von diesem '
          'Handy gelöscht. Jagdeinrichtungen und Habitatbäume bleiben erhalten.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Entfernen'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await DbService.instance.deleteParcel(_parcel.id);
    if (mounted) Navigator.of(context).pop('deleted');
  }

  @override
  Widget build(BuildContext context) {
    final id = _parcel.id;
    return Scaffold(
      appBar: AppBar(
        title: Text(_parcel.name),
        actions: [
          IconButton(
            tooltip: 'Parzelle entfernen',
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
                if (_error != null) Text('Fehler: $_error'),
                TextField(
                  controller: _name,
                  decoration: const InputDecoration(
                    labelText: 'Name',
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => _saveBasics(),
                ),
                const SizedBox(height: 8),
                Text('Flurstück: ${_parcel.label.isEmpty ? '–' : _parcel.label}'),
                Text('Fläche: ${formatArea(_parcel.area)}'),
                const SizedBox(height: 12),
                LabeledDropdown(
                  label: 'Abteilung',
                  value: _deptName,
                  options: [for (final d in _depts) d.name],
                  onChanged: _setDept,
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.tonal(
                    onPressed: _saveBasics,
                    child: const Text('Namen speichern'),
                  ),
                ),
                const Divider(height: 32),
                const Text(
                  'Bestandsaufnahme',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                StandEditor(ownerId: 'p:$id'),
                const Divider(height: 32),
                const Text(
                  'Kulturen',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                KulturEditor(ownerId: 'p:$id'),
                const Divider(height: 32),
                const Text(
                  'Objekte in dieser Parzelle',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                if (_objects.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      'Noch keine Jagdeinrichtungen oder Habitatbäume.',
                      style: TextStyle(color: Colors.grey),
                    ),
                  ),
                for (final o in _objects)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(o.isJagd ? Icons.cabin : Icons.park),
                    title: Text(o.title),
                    subtitle: Text(o.zustand.isEmpty ? '–' : o.zustand),
                    onTap: () => Navigator.of(context).pop('object:${o.id}'),
                  ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: () => Navigator.of(context).pop('parcel:$id'),
                  icon: const Icon(Icons.map_outlined),
                  label: const Text('Auf der Karte zeigen'),
                ),
              ],
            ),
    );
  }
}
