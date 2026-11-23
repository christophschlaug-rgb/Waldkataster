import 'package:flutter/material.dart';

import '../models/forest_models.dart';
import '../models/shape_models.dart';
import '../services/db_service.dart';
import '../services/geo_calc.dart';
import '../services/geo_utils.dart';
import '../services/photo_service.dart';
import '../widgets/map_widgets.dart';
import '../widgets/measure_widgets.dart';
import '../widgets/photo_strip.dart';
import '../widgets/stand_editor.dart';

class _Overlap {
  final GeoShape other;
  final double fraction;
  const _Overlap(this.other, this.fraction);
}

/// Steckbrief einer Flaeche oder Linie. Liefert ggf. eine Aktion fuer die
/// Karte ('shape:<id>', 'shapetarget:<id>', 'redraw:<id>').
class ShapeScreen extends StatefulWidget {
  final GeoShape shape;
  final List<Parcel> parcels;
  final List<GeoShape> allShapes;

  const ShapeScreen({
    super.key,
    required this.shape,
    required this.parcels,
    required this.allShapes,
  });

  @override
  State<ShapeScreen> createState() => _ShapeScreenState();
}

class _ShapeScreenState extends State<ShapeScreen> {
  late GeoShape _shape;
  late final TextEditingController _name;
  late final TextEditingController _amount;
  late final TextEditingController _width;
  late final TextEditingController _note;
  DateTime? _date;
  late String _status;
  late List<String> _photos;
  List<_Overlap> _overlaps = [];

  @override
  void initState() {
    super.initState();
    _shape = widget.shape;
    _name = TextEditingController(text: _shape.name);
    _amount = TextEditingController(
      text: _shape.amount == null ? '' : _shape.amount!.toString().replaceAll('.', ','),
    );
    _width = TextEditingController(
      text: _shape.width == 0 ? '' : _shape.width.toString().replaceAll('.', ','),
    );
    _note = TextEditingController(text: _shape.note);
    _date = _shape.dateOn;
    _status = _shape.status;
    _photos = List<String>.of(_shape.photos);
    _computeOverlaps();
  }

  @override
  void dispose() {
    _name.dispose();
    _amount.dispose();
    _width.dispose();
    _note.dispose();
    super.dispose();
  }

  void _computeOverlaps() {
    final list = <_Overlap>[];
    if (_shape.type.hasDate && !_shape.isLine) {
      for (final o in widget.allShapes) {
        if (o.id == _shape.id || o.kind != _shape.kind || o.isLine) continue;
        final f = overlapFraction(_shape.points, o.points);
        if (f >= 0.03) list.add(_Overlap(o, f));
      }
      list.sort((a, b) {
        final da = a.other.dateOn ?? DateTime(1900);
        final db = b.other.dateOn ?? DateTime(1900);
        return da.compareTo(db);
      });
    }
    _overlaps = list;
  }

  List<ParcelRef> _refs() {
    final out = <ParcelRef>[];
    for (final p in widget.parcels) {
      final g = ParcelGeometry.fromJsonString(p.geometryJson);
      if (g != null) out.add(ParcelRef(p.id, g));
    }
    return out;
  }

  String _parcelName(String id) {
    if (id.isEmpty) return 'Außerhalb eigener Parzellen';
    for (final p in widget.parcels) {
      if (p.id == id) return p.name;
    }
    return 'Unbekannte Parzelle';
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _date ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (d != null) setState(() => _date = DateTime(d.year, d.month, d.day));
  }

  Future<void> _save() async {
    final width = double.tryParse(_width.text.trim().replaceAll(',', '.')) ?? _shape.width;
    final amountText = _amount.text.trim().replaceAll(',', '.');
    final amount = amountText.isEmpty ? null : double.tryParse(amountText);

    var s = _shape.copyWith(
      name: _name.text.trim(),
      dateOn: _date,
      clearDate: _date == null,
      status: _status,
      amount: amount,
      clearAmount: amount == null,
      note: _note.text.trim(),
      photos: _photos,
      width: _shape.isLine ? width : 0,
    );
    if (_shape.isLine && width != _shape.width) {
      final stats = computeShapeStats(
        isLine: true,
        points: s.points,
        width: width,
        parcels: _refs(),
      );
      s = s.copyWith(areaM2: stats.areaM2, lengthM: stats.lengthM, shares: stats.shares);
    }
    try {
      await DbService.instance.upsertShape(s);
      if (!mounted) return;
      setState(() => _shape = s);
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Gespeichert')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Speichern nicht möglich: $e')));
    }
  }

  Future<void> _delete() async {
    if (!await confirmDelete(context, '${_shape.title} löschen?')) return;
    for (final p in _shape.photos) {
      await PhotoService.deleteFile(p);
    }
    await DbService.instance.deleteShape(_shape.id);
    if (mounted) Navigator.of(context).pop('deleted');
  }

  @override
  Widget build(BuildContext context) {
    final t = _shape.type;
    final shares = [..._shape.shares]..sort((a, b) => b.areaM2.compareTo(a.areaM2));
    final totalArea = _shape.areaM2 == 0 ? 1.0 : _shape.areaM2;

    return Scaffold(
      appBar: AppBar(
        title: Text(_shape.title),
        actions: [
          IconButton(
            tooltip: 'Löschen',
            icon: const Icon(Icons.delete_outline),
            onPressed: _delete,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            color: t.color.withAlpha(30),
            child: ListTile(
              leading: Icon(t.icon, color: t.color, size: 32),
              title: Text(
                _shape.isLine
                    ? 'Länge ${formatMeters(_shape.lengthM)}'
                    : 'Fläche ${formatArea(_shape.areaM2)}',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              subtitle: Text(
                _shape.isLine
                    ? 'Breite ${_shape.width.toString().replaceAll('.', ',')} m · '
                        'Fläche ${formatArea(_shape.areaM2)}'
                    : 'Umfang ${formatMeters(_shape.lengthM)} · ${_shape.points.length} Eckpunkte',
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _name,
            decoration: const InputDecoration(
              labelText: 'Name (optional)',
              border: OutlineInputBorder(),
            ),
          ),
          if (t.hasDate) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text(_date == null ? 'Datum: offen' : 'Datum: ${dateText(_date!)}'),
                ),
                if (_date != null)
                  IconButton(
                    tooltip: 'Datum entfernen',
                    icon: const Icon(Icons.clear),
                    onPressed: () => setState(() => _date = null),
                  ),
                IconButton(
                  tooltip: 'Datum wählen',
                  icon: const Icon(Icons.calendar_month),
                  onPressed: _pickDate,
                ),
              ],
            ),
          ],
          if (t.statusOptions.isNotEmpty) ...[
            const SizedBox(height: 8),
            LabeledDropdown(
              label: 'Status',
              value: _status,
              options: t.statusOptions,
              onChanged: (v) => setState(() => _status = v),
            ),
          ],
          if (t.amountLabel != null) ...[
            const SizedBox(height: 12),
            TextField(
              controller: _amount,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: t.amountLabel,
                border: const OutlineInputBorder(),
              ),
            ),
          ],
          if (t.isLine) ...[
            const SizedBox(height: 12),
            TextField(
              controller: _width,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Breite in Metern',
                border: OutlineInputBorder(),
              ),
            ),
          ],
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
          const SizedBox(height: 12),
          PhotoStrip(photos: _photos, onChanged: (p) => setState(() => _photos = p)),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.save_outlined),
              label: const Text('Speichern'),
            ),
          ),
          const Divider(height: 32),
          const Text(
            'Anteile je Parzelle',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          if (shares.isEmpty)
            const Text('Keine Zuordnung berechnet.', style: TextStyle(color: Colors.grey)),
          for (final s in shares)
            ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: Text(_parcelName(s.parcelId)),
              subtitle: Text(
                '${formatArea(s.areaM2)}'
                '${_shape.isLine ? ' · ${formatMeters(s.lengthM)}' : ''}'
                ' · ${(s.areaM2 / totalArea * 100).round()} %',
              ),
            ),
          if (_overlaps.isNotEmpty) ...[
            const Divider(height: 32),
            Card(
              color: Colors.amber.shade50,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.history, color: Colors.orange),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Diese Stelle war schon betroffen (${t.label})',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    for (final o in _overlaps)
                      Text(
                        '${o.other.dateOn != null ? dateText(o.other.dateOn!) : 'ohne Datum'}: '
                        '${(o.fraction * 100).round()} % dieser Fläche'
                        '${o.other.name.isNotEmpty ? ' (${o.other.name})' : ''}',
                      ),
                  ],
                ),
              ),
            ),
          ],
          if (_shape.kind == 'teil') ...[
            const Divider(height: 32),
            const Text(
              'Bestandsaufnahme',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            StandEditor(ownerId: 's:${_shape.id}'),
            const Divider(height: 32),
            const Text(
              'Kulturen',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            KulturEditor(ownerId: 's:${_shape.id}'),
          ],
          const Divider(height: 32),
          const Text(
            'Maßnahmen',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          MeasureEditor(ownerId: 's:${_shape.id}', ownerLabel: _shape.title),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () => Navigator.of(context).pop('shape:${_shape.id}'),
            icon: const Icon(Icons.map_outlined),
            label: const Text('Auf der Karte zeigen'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => Navigator.of(context).pop('shapetarget:${_shape.id}'),
            icon: const Icon(Icons.flag),
            label: const Text('Als Ziel wählen'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => Navigator.of(context).pop('redraw:${_shape.id}'),
            icon: const Icon(Icons.edit),
            label: Text(_shape.isLine ? 'Linie neu zeichnen' : 'Fläche neu zeichnen'),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: _delete,
            style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
            icon: const Icon(Icons.delete_outline),
            label: Text('${_shape.isLine ? 'Linie' : 'Fläche'} löschen'),
          ),
        ],
      ),
    );
  }
}
