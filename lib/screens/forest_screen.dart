import 'package:flutter/material.dart';

import '../models/forest_models.dart';
import '../services/db_service.dart';
import '../services/geo_utils.dart';
import '../services/photo_service.dart';
import '../widgets/stand_editor.dart';
import 'dept_screen.dart';
import 'parcel_screen.dart';
import 'point_sheet.dart';

/// Uebersicht: Parzellen, Abteilungen und Objekte. Liefert beim Schliessen
/// ggf. eine Aktion fuer die Karte ('parcel:..', 'dept:..', 'object:..').
class ForestScreen extends StatefulWidget {
  const ForestScreen({super.key});

  @override
  State<ForestScreen> createState() => _ForestScreenState();
}

class _ForestScreenState extends State<ForestScreen> {
  List<Parcel> _parcels = [];
  List<Dept> _depts = [];
  List<ForestObject> _objects = [];
  bool _loaded = false;
  String? _error;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final p = await DbService.instance.parcels();
      final d = await DbService.instance.depts();
      final o = await DbService.instance.objects();
      if (!mounted) return;
      setState(() {
        _parcels = p;
        _depts = d;
        _objects = o;
        _loaded = true;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loaded = true;
      });
    }
  }

  Future<void> _open(Widget screen) async {
    final r = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => screen),
    );
    if (!mounted) return;
    if (r != null && r.contains(':')) {
      Navigator.of(context).pop(r);
      return;
    }
    await _load();
  }

  Future<void> _newDept() async {
    final c = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Neue Abteilung'),
        content: TextField(
          controller: c,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Name',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, c.text.trim()),
            child: const Text('Anlegen'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    final d = Dept(id: newId('d'), name: name, updatedAt: DateTime.now());
    await DbService.instance.upsertDept(d);
    await _load();
    if (mounted) _open(DeptScreen(dept: d));
  }

  String _deptName(String? id) {
    for (final d in _depts) {
      if (d.id == id) return d.name;
    }
    return '';
  }

  Future<bool> _confirm(String title, String content, String yes) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(yes),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _deleteParcel(Parcel p) async {
    final ok = await _confirm(
      'Parzelle "${p.name}" entfernen?',
      'Die Parzelle samt Bestandsaufnahme und Kulturen wird gelöscht. '
          'Jagdeinrichtungen und Habitatbäume bleiben erhalten.',
      'Entfernen',
    );
    if (!ok) return;
    await DbService.instance.deleteParcel(p.id);
    await _load();
  }

  Future<void> _deleteDept(Dept d) async {
    final ok = await _confirm(
      'Abteilung "${d.name}" löschen?',
      'Die Parzellen bleiben erhalten, werden aber keiner Abteilung mehr '
          'zugeordnet. Bestandsaufnahme und Kulturen der Abteilung werden gelöscht.',
      'Löschen',
    );
    if (!ok) return;
    await DbService.instance.deleteDept(d.id);
    await _load();
  }

  Future<void> _deleteObject(ForestObject o) async {
    final ok = await _confirm(
      '${o.title} löschen?',
      'Der Eintrag samt Fotos wird von diesem Handy gelöscht.',
      'Löschen',
    );
    if (!ok) return;
    for (final path in o.photos) {
      await PhotoService.deleteFile(path);
    }
    await DbService.instance.deleteObject(o.id);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final q = _query.toLowerCase();
    final parcels = _parcels
        .where((p) =>
            q.isEmpty ||
            p.name.toLowerCase().contains(q) ||
            p.label.toLowerCase().contains(q))
        .toList();

    Widget body;
    if (!_loaded) {
      body = const Center(child: CircularProgressIndicator());
    } else if (_error != null) {
      body = Padding(
        padding: const EdgeInsets.all(16),
        child: Text('Fehler beim Laden: $_error'),
      );
    } else {
      body = TabBarView(
        children: [
          // Parzellen
          Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: TextField(
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Parzellen suchen',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (v) => setState(() => _query = v),
                ),
              ),
              Expanded(
                child: parcels.isEmpty
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: Text(
                            'Noch keine Parzellen.\nTippe auf der Karte den Knopf '
                            '"Parzelle wählen" und dann ein Flurstück an.',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 16, color: Colors.grey),
                          ),
                        ),
                      )
                    : ListView.builder(
                        itemCount: parcels.length,
                        itemBuilder: (context, i) {
                          final p = parcels[i];
                          final dept = _deptName(p.deptId);
                          return ListTile(
                            leading: const CircleAvatar(child: Icon(Icons.crop_square)),
                            title: Text(p.name),
                            subtitle: Text(
                              '${p.label} · ${formatArea(p.area)}'
                              '${dept.isNotEmpty ? ' · $dept' : ''}',
                            ),
                            onTap: () => _open(ParcelScreen(parcel: p)),
                            trailing: IconButton(
                              tooltip: 'Parzelle entfernen',
                              icon: const Icon(Icons.delete_outline),
                              onPressed: () => _deleteParcel(p),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
          // Abteilungen
          ListView(
            padding: const EdgeInsets.all(12),
            children: [
              FilledButton.icon(
                onPressed: _newDept,
                icon: const Icon(Icons.add),
                label: const Text('Abteilung anlegen'),
              ),
              const SizedBox(height: 8),
              if (_depts.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'Noch keine Abteilungen. Eine Abteilung fasst mehrere '
                    'Parzellen zusammen.',
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
              for (final d in _depts)
                Builder(builder: (context) {
                  final members = _parcels.where((p) => p.deptId == d.id).toList();
                  double area = 0;
                  for (final p in members) {
                    area += p.area ?? 0;
                  }
                  return ListTile(
                    leading: const CircleAvatar(child: Icon(Icons.folder_outlined)),
                    title: Text(d.name),
                    subtitle: Text('${members.length} Parzellen · ${formatArea(area)}'),
                    onTap: () => _open(DeptScreen(dept: d)),
                    trailing: IconButton(
                      tooltip: 'Abteilung löschen',
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => _deleteDept(d),
                    ),
                  );
                }),
            ],
          ),
          // Objekte
          _objects.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'Noch keine Jagdeinrichtungen oder Habitatbäume.\n'
                      'Lege sie mit dem Knopf "Punkt anlegen" oder durch langes '
                      'Drücken auf die Karte an.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 16, color: Colors.grey),
                    ),
                  ),
                )
              : ListView.builder(
                  itemCount: _objects.length,
                  itemBuilder: (context, i) {
                    final o = _objects[i];
                    return ListTile(
                      leading: CircleAvatar(
                        child: Icon(o.isJagd ? Icons.cabin : Icons.park),
                      ),
                      title: Text(o.title),
                      subtitle: Text(
                        '${o.zustand.isEmpty ? '–' : o.zustand}'
                        '${o.checkedOn != null ? ' · geprüft ${formatDate(o.checkedOn!).substring(0, 10)}' : ''}',
                      ),
                      onTap: () => Navigator.of(context).pop('object:${o.id}'),
                      trailing: IconButton(
                        tooltip: 'Eintrag löschen',
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => _deleteObject(o),
                      ),
                    );
                  },
                ),
        ],
      );
    }

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Mein Wald'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Parzellen'),
              Tab(text: 'Abteilungen'),
              Tab(text: 'Objekte'),
            ],
          ),
        ),
        body: body,
      ),
    );
  }
}
