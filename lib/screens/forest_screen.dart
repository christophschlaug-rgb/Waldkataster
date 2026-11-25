import 'package:flutter/material.dart';

import '../models/forest_models.dart';
import '../models/shape_models.dart';
import '../services/geo_calc.dart';
import 'shape_screen.dart';
import '../services/db_service.dart';
import '../services/geo_utils.dart';
import '../services/photo_service.dart';
import '../widgets/measure_widgets.dart';
import '../widgets/stand_editor.dart';
import 'dept_screen.dart';
import 'parcel_screen.dart';
import 'point_sheet.dart';

/// Uebersicht: Parzellen, Abteilungen und Objekte. Liefert beim Schliessen
/// ggf. eine Aktion fuer die Karte ('parcel:..', 'dept:..', 'object:..').
class _Repeat {
  final GeoShape earlier;
  final GeoShape later;
  final double fraction;
  const _Repeat(this.earlier, this.later, this.fraction);
}

class ForestScreen extends StatefulWidget {
  const ForestScreen({super.key});

  @override
  State<ForestScreen> createState() => _ForestScreenState();
}

class _ForestScreenState extends State<ForestScreen> {
  List<Parcel> _parcels = [];
  List<Dept> _depts = [];
  List<ForestObject> _objects = [];
  List<Damage> _damages = [];
  List<Measure> _measures = [];
  List<GeoShape> _shapes = [];
  List<_Repeat> _repeats = [];
  String _shpType = '';
  int? _shpYear;
  int? _dmgYear;
  int? _msrYear;
  String _msrStatus = '';
  String _msrOwner = '';
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
      final dm = await DbService.instance.damages();
      final ms = await DbService.instance.measures();
      final sh = await DbService.instance.shapes();
      if (!mounted) return;
      setState(() {
        _parcels = p;
        _depts = d;
        _objects = o;
        _damages = dm;
        _measures = ms;
        _shapes = sh;
        _repeats = _computeRepeats(sh);
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

  String _parcelNameOf(String? id) {
    if (id == null) return '';
    for (final p in _parcels) {
      if (p.id == id) return p.name;
    }
    return '';
  }

  String _ownerName(String ownerId) {
    if (ownerId.startsWith('s:')) {
      for (final s in _shapes) {
        if ('s:${s.id}' == ownerId) return s.title;
      }
      return '';
    }
    if (ownerId.startsWith('p:')) {
      for (final p in _parcels) {
        if ('p:${p.id}' == ownerId) return p.name;
      }
    } else if (ownerId.startsWith('d:')) {
      for (final d in _depts) {
        if ('d:${d.id}' == ownerId) return 'Abteilung ${d.name}';
      }
    }
    return '';
  }

  Future<void> _deleteDamage(Damage d) async {
    if (!await confirmDelete(context, '${d.title} löschen?')) return;
    for (final path in d.photos) {
      await PhotoService.deleteFile(path);
    }
    await DbService.instance.deleteDamage(d.id);
    await _load();
  }

  Future<void> _editMeasure(Measure? existing) async {
    final m = await showMeasureDialog(
      context,
      existing: existing,
      parcels: _parcels,
      depts: _depts,
      shapes: _shapes,
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

  Future<void> _deleteMeasure(Measure m) async {
    if (!await confirmDelete(context, 'Maßnahme "${m.art}" löschen?')) return;
    await DbService.instance.deleteMeasure(m.id);
    await _load();
  }

  /// Flaechen gleichen Typs, die sich mit frueheren Eintraegen ueberschneiden.
  List<_Repeat> _computeRepeats(List<GeoShape> shapes) {
    final out = <_Repeat>[];
    final areas = shapes
        .where((s) => !s.isLine && s.type.trackRepeats && s.points.length >= 3)
        .toList();
    if (areas.length > 80) return out;
    areas.sort((a, b) => (a.dateOn ?? DateTime(1900)).compareTo(b.dateOn ?? DateTime(1900)));
    for (var i = 0; i < areas.length; i++) {
      for (var j = i + 1; j < areas.length; j++) {
        final a = areas[i];
        final b = areas[j];
        if (a.kind != b.kind) continue;
        final f = overlapFraction(b.points, a.points);
        if (f >= 0.1) out.add(_Repeat(a, b, f));
      }
    }
    return out;
  }

  Future<void> _deleteShape(GeoShape s) async {
    if (!await confirmDelete(context, '${s.title} löschen?')) return;
    for (final path in s.photos) {
      await PhotoService.deleteFile(path);
    }
    await DbService.instance.deleteShape(s.id);
    await _load();
  }

  Widget _shapesTab() {
    final years = {
      for (final s in _shapes)
        if (s.dateOn != null) s.dateOn!.year,
    }.toList()
      ..sort((a, b) => b.compareTo(a));

    bool match(GeoShape s) =>
        (_shpType.isEmpty || s.kind == _shpType) &&
        (_shpYear == null || s.dateOn?.year == _shpYear);

    final shown = _shapes.where(match).toList();

    // Auswertung je Parzelle: Flaeche und Anzahl je Typ
    final area = <String, Map<String, double>>{};
    final cnt = <String, Map<String, int>>{};
    for (final s in shown) {
      for (final sh in s.shares) {
        final pn = _parcelNameOf(sh.parcelId);
        final name = sh.parcelId.isEmpty
            ? 'Außerhalb eigener Parzellen'
            : (pn.isEmpty ? 'Unbekannte Parzelle' : pn);
        final a = area.putIfAbsent(name, () => {});
        a[s.kind] = (a[s.kind] ?? 0) + sh.areaM2;
        final c = cnt.putIfAbsent(name, () => {});
        c[s.kind] = (c[s.kind] ?? 0) + 1;
      }
    }
    final repeats = _repeats.where((r) => match(r.later)).toList();

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Wrap(
          spacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            DropdownButton<String>(
              value: _shpType.isEmpty ? 'Alle Typen' : _shpType,
              items: [
                const DropdownMenuItem<String>(
                  value: 'Alle Typen',
                  child: Text('Alle Typen'),
                ),
                for (final t in kShapeTypes)
                  DropdownMenuItem<String>(value: t.key, child: Text(t.label)),
              ],
              onChanged: (v) =>
                  setState(() => _shpType = (v == null || v == 'Alle Typen') ? '' : v),
            ),
            DropdownButton<String>(
              value: _shpYear?.toString() ?? 'Alle Jahre',
              items: [
                const DropdownMenuItem<String>(
                  value: 'Alle Jahre',
                  child: Text('Alle Jahre'),
                ),
                for (final y in years)
                  DropdownMenuItem<String>(value: '$y', child: Text('$y')),
              ],
              onChanged: (v) => setState(
                () => _shpYear = (v == null || v == 'Alle Jahre') ? null : int.tryParse(v),
              ),
            ),
          ],
        ),
        if (area.isNotEmpty)
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: Text(
              'Auswertung je Parzelle (${shown.length} Einträge)',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            children: [
              for (final e in area.entries)
                ListTile(
                  dense: true,
                  title: Text(e.key),
                  subtitle: Text(
                    [
                      for (final k in e.value.entries)
                        '${shapeTypeOf(k.key).label}: ${cnt[e.key]?[k.key] ?? 0}× · ${formatArea(k.value)}',
                    ].join('\n'),
                  ),
                ),
            ],
          ),
        if (repeats.isNotEmpty)
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            leading: const Icon(Icons.history, color: Colors.orange),
            title: Text(
              'Wiederkehrende Schäden (${repeats.length})',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            children: [
              for (final r in repeats)
                ListTile(
                  dense: true,
                  title: Text(
                    '${r.later.type.label}: '
                    '${r.earlier.dateOn != null ? dateText(r.earlier.dateOn!) : 'früher'} '
                    'und ${r.later.dateOn != null ? dateText(r.later.dateOn!) : 'später'}',
                  ),
                  subtitle: Text(
                    '${(r.fraction * 100).round()} % der späteren Fläche war schon betroffen'
                    '${r.later.shares.isNotEmpty && _parcelNameOf(r.later.shares.first.parcelId).isNotEmpty ? '\n${_parcelNameOf(r.later.shares.first.parcelId)}' : ''}',
                  ),
                  isThreeLine: r.later.shares.isNotEmpty &&
                      _parcelNameOf(r.later.shares.first.parcelId).isNotEmpty,
                  onTap: () => Navigator.of(context).pop('shape:${r.later.id}'),
                ),
            ],
          ),
        const SizedBox(height: 8),
        if (shown.isEmpty)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Noch keine Flächen oder Linien.\nLege sie mit dem Knopf '
              '"Punkt anlegen" oder durch langes Drücken auf die Karte an '
              '("Fläche zeichnen", "Linie zeichnen").',
              style: TextStyle(color: Colors.grey),
            ),
          ),
        for (final s in shown)
          ListTile(
            leading: CircleAvatar(
              backgroundColor: s.type.color,
              child: Icon(s.type.icon, color: Colors.white),
            ),
            title: Text(
              '${s.title}${s.dateOn != null ? ' · ${dateText(s.dateOn!)}' : ''}',
            ),
            subtitle: Text(
              '${s.isLine ? '${s.lengthM.round()} m · ' : ''}${formatArea(s.areaM2)}'
              '${s.status.isNotEmpty ? ' · ${s.status}' : ''}',
            ),
            onTap: () => _open(
              ShapeScreen(shape: s, parcels: _parcels, allShapes: _shapes),
            ),
            trailing: IconButton(
              tooltip: 'Löschen',
              icon: const Icon(Icons.delete_outline),
              onPressed: () => _deleteShape(s),
            ),
          ),
      ],
    );
  }

  Widget _damagesTab() {
    final years = {for (final d in _damages) d.foundOn.year}.toList()
      ..sort((a, b) => b.compareTo(a));
    final shown = _damages
        .where((d) => _dmgYear == null || d.foundOn.year == _dmgYear)
        .toList();

    // Auswertung je Parzelle
    final groups = <String, List<Damage>>{};
    for (final d in shown) {
      final name = _parcelNameOf(d.parcelId);
      groups.putIfAbsent(name.isEmpty ? 'Ohne Parzelle' : name, () => []).add(d);
    }

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Row(
          children: [
            const Text('Jahr:'),
            const SizedBox(width: 12),
            DropdownButton<String>(
              value: _dmgYear?.toString() ?? 'Alle',
              items: [
                const DropdownMenuItem<String>(value: 'Alle', child: Text('Alle')),
                for (final y in years)
                  DropdownMenuItem<String>(value: '$y', child: Text('$y')),
              ],
              onChanged: (v) => setState(
                () => _dmgYear = (v == null || v == 'Alle') ? null : int.tryParse(v),
              ),
            ),
          ],
        ),
        if (groups.isNotEmpty)
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: Text(
              'Auswertung ${_dmgYear ?? 'alle Jahre'} (${shown.length} Einträge)',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            children: [
              for (final e in groups.entries)
                Builder(builder: (context) {
                  final kaefer = e.value.where((d) => d.isKaefer).toList();
                  final sturm = e.value.where((d) => !d.isKaefer).toList();
                  double baeume = 0;
                  for (final d in kaefer) {
                    baeume += d.amount ?? 0;
                  }
                  double fm = 0;
                  for (final d in sturm) {
                    fm += d.amount ?? 0;
                  }
                  final parts = <String>[
                    if (kaefer.isNotEmpty)
                      'Käfernester: ${kaefer.length} (${baeume.round()} Bäume)',
                    if (sturm.isNotEmpty)
                      'Sturmschäden: ${sturm.length} (${fm.toStringAsFixed(1).replaceAll('.', ',')} fm)',
                  ];
                  return ListTile(
                    dense: true,
                    title: Text(e.key),
                    subtitle: Text(parts.join('\n')),
                  );
                }),
            ],
          ),
        const SizedBox(height: 8),
        if (shown.isEmpty)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Hier stehen als Punkt erfasste Schäden.\nKäfernester und '
              'Sturmschäden zeichnest du als Fläche (Knopf "Punkt anlegen" '
              'oder langes Drücken auf die Karte, dann "Fläche zeichnen").',
              style: TextStyle(color: Colors.grey),
            ),
          ),
        for (final d in shown)
          ListTile(
            leading: CircleAvatar(
              backgroundColor: d.isKaefer ? const Color(0xFFC62828) : const Color(0xFFEF6C00),
              child: Icon(d.isKaefer ? Icons.bug_report : Icons.storm, color: Colors.white),
            ),
            title: Text('${d.title} · ${dateText(d.foundOn)}'),
            subtitle: Text(
              '${d.status.isEmpty ? '–' : d.status}'
              '${d.amount != null ? ' · ${d.isKaefer ? '${d.amount!.round()} Bäume' : '${d.amount!.toString().replaceAll('.', ',')} fm'}' : ''}'
              '${_parcelNameOf(d.parcelId).isNotEmpty ? '\n${_parcelNameOf(d.parcelId)}' : ''}',
            ),
            isThreeLine: _parcelNameOf(d.parcelId).isNotEmpty,
            onTap: () => Navigator.of(context).pop('damage:${d.id}'),
            trailing: IconButton(
              tooltip: 'Eintrag löschen',
              icon: const Icon(Icons.delete_outline),
              onPressed: () => _deleteDamage(d),
            ),
          ),
      ],
    );
  }

  Widget _measuresTab() {
    final years = {for (final m in _measures) m.start.year}.toList()
      ..sort((a, b) => b.compareTo(a));
    final owners = <String, String>{'Alle': ''};
    for (final d in _depts) {
      owners[uniqueKey(owners, 'Abteilung: ${d.name}')] = 'd:${d.id}';
    }
    for (final p in _parcels) {
      owners[uniqueKey(owners, 'Parzelle: ${p.name}')] = 'p:${p.id}';
    }
    var ownerLabel = 'Alle';
    for (final e in owners.entries) {
      if (e.value == _msrOwner) ownerLabel = e.key;
    }

    final shown = _measures
        .where((m) =>
            (_msrYear == null || m.start.year == _msrYear) &&
            (_msrStatus.isEmpty || m.status == _msrStatus) &&
            (_msrOwner.isEmpty || m.ownerId == _msrOwner))
        .toList();

    final tiles = <Widget>[];
    String? lastKey;
    for (final m in shown) {
      final key = '${kMonatsnamen[m.start.month - 1]} ${m.start.year}';
      if (key != lastKey) {
        tiles.add(
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 12, 4, 4),
            child: Text(
              key,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
        );
        lastKey = key;
      }
      tiles.add(
        measureTile(
          m,
          ownerName: _ownerName(m.ownerId),
          onTap: () => _editMeasure(m),
          onDelete: () => _deleteMeasure(m),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        FilledButton.icon(
          onPressed: () => _editMeasure(null),
          icon: const Icon(Icons.add),
          label: const Text('Maßnahme planen'),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            DropdownButton<String>(
              value: _msrYear?.toString() ?? 'Alle Jahre',
              items: [
                const DropdownMenuItem<String>(
                  value: 'Alle Jahre',
                  child: Text('Alle Jahre'),
                ),
                for (final y in years)
                  DropdownMenuItem<String>(value: '$y', child: Text('$y')),
              ],
              onChanged: (v) => setState(
                () => _msrYear = (v == null || v == 'Alle Jahre') ? null : int.tryParse(v),
              ),
            ),
            DropdownButton<String>(
              value: _msrStatus.isEmpty ? 'Alle Status' : _msrStatus,
              items: [
                const DropdownMenuItem<String>(
                  value: 'Alle Status',
                  child: Text('Alle Status'),
                ),
                for (final s in kMassnahmeStatus)
                  DropdownMenuItem<String>(value: s, child: Text(s)),
              ],
              onChanged: (v) => setState(
                () => _msrStatus = (v == null || v == 'Alle Status') ? '' : v,
              ),
            ),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 230),
              child: DropdownButton<String>(
                isExpanded: true,
                value: ownerLabel,
                items: [
                  for (final k in owners.keys)
                    DropdownMenuItem<String>(
                      value: k,
                      child: Text(k, overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: (v) => setState(() => _msrOwner = owners[v] ?? ''),
              ),
            ),
          ],
        ),
        if (shown.isEmpty)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Keine Maßnahmen für diese Auswahl.',
              style: TextStyle(color: Colors.grey),
            ),
          ),
        ...tiles,
      ],
    );
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
                        child: Icon(objectIconOf(o)),
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
          _damagesTab(),
          _shapesTab(),
          _measuresTab(),
        ],
      );
    }

    return DefaultTabController(
      length: 6,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Mein Wald'),
          bottom: const TabBar(
            isScrollable: true,
            tabs: [
              Tab(text: 'Parzellen'),
              Tab(text: 'Abteilungen'),
              Tab(text: 'Objekte'),
              Tab(text: 'Schäden'),
              Tab(text: 'Flächen'),
              Tab(text: 'Maßnahmen'),
            ],
          ),
        ),
        body: body,
      ),
    );
  }
}
