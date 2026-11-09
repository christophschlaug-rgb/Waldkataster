import 'dart:io';

import 'package:flutter/material.dart';

import '../models/forest_models.dart';
import '../services/photo_service.dart';
import '../widgets/stand_editor.dart';
import 'point_sheet.dart';

/// Jagdeinrichtung oder Habitatbaum: Angaben, Foto, Kommentar.
class ObjectSheet extends StatefulWidget {
  final ForestObject object;
  final bool isNew;
  final String? parcelName;
  final Future<void> Function(ForestObject updated) onSave;
  final Future<void> Function()? onDelete;
  final VoidCallback onTarget;

  const ObjectSheet({
    super.key,
    required this.object,
    required this.isNew,
    required this.parcelName,
    required this.onSave,
    required this.onDelete,
    required this.onTarget,
  });

  @override
  State<ObjectSheet> createState() => _ObjectSheetState();
}

class _ObjectSheetState extends State<ObjectSheet> {
  late String _subtype;
  late String _zustand;
  late DateTime? _checked;
  late List<String> _photos;
  late final TextEditingController _number;
  late final TextEditingController _note;

  @override
  void initState() {
    super.initState();
    final o = widget.object;
    _subtype = o.subtype;
    _zustand = o.zustand;
    _checked = o.checkedOn;
    _photos = List<String>.of(o.photos);
    _number = TextEditingController(text: o.number);
    _note = TextEditingController(text: o.note);
  }

  @override
  void dispose() {
    _number.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _checked ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (d != null) setState(() => _checked = d);
  }

  Future<void> _addPhoto() async {
    try {
      final path = await PhotoService.takePhoto();
      if (path != null && mounted) setState(() => _photos.add(path));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Foto nicht möglich: $e')));
    }
  }

  void _showPhoto(String path) {
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        child: Stack(
          children: [
            InteractiveViewer(
              child: Image.file(
                File(path),
                errorBuilder: (c, e, s) => const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('Foto nicht gefunden'),
                ),
              ),
            ),
            Positioned(
              right: 0,
              top: 0,
              child: IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(ctx),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _removePhoto(String path) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Foto entfernen?'),
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
    await PhotoService.deleteFile(path);
    if (mounted) setState(() => _photos.remove(path));
  }

  Future<void> _save() async {
    final o = widget.object.copyWith(
      subtype: _subtype,
      number: _number.text.trim(),
      zustand: _zustand,
      checkedOn: _checked,
      note: _note.text.trim(),
      photos: _photos,
    );
    await widget.onSave(o);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eintrag löschen?'),
        content: const Text('Eintrag samt Fotos wird von diesem Handy gelöscht.'),
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
    for (final p in widget.object.photos) {
      await PhotoService.deleteFile(p);
    }
    await widget.onDelete!();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final o = widget.object;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: [
            Text(
              o.isJagd ? 'Jagdeinrichtung' : 'Habitatbaum',
              style: const TextStyle(fontSize: 13, color: Colors.grey),
            ),
            SelectableText(
              '${o.lat.toStringAsFixed(6)}, ${o.lon.toStringAsFixed(6)}'
              '${o.accuracy != null ? '  (GPS ± ${o.accuracy!.round()} m)' : ''}'
              '${widget.parcelName != null ? '\nParzelle: ${widget.parcelName}' : ''}',
              style: const TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 12),
            if (o.isJagd) ...[
              InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Typ',
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    isExpanded: true,
                    value: kJagdTypen.containsKey(_subtype) ? _subtype : null,
                    hint: const Text('Bitte wählen'),
                    items: [
                      for (final e in kJagdTypen.entries)
                        DropdownMenuItem<String>(
                          value: e.key,
                          child: Text(e.value),
                        ),
                    ],
                    onChanged: (v) => setState(() => _subtype = v ?? ''),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _number,
                decoration: const InputDecoration(
                  labelText: 'Bezeichnung oder Nummer',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              LabeledDropdown(
                label: 'Zustand',
                value: _zustand,
                options: kJagdZustand,
                onChanged: (v) => setState(() => _zustand = v),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _checked == null
                          ? 'Noch nicht geprüft'
                          : 'Geprüft am ${formatDate(_checked!).substring(0, 10)}',
                    ),
                  ),
                  TextButton(
                    onPressed: () => setState(() => _checked = DateTime.now()),
                    child: const Text('Heute geprüft'),
                  ),
                  IconButton(
                    tooltip: 'Datum wählen',
                    icon: const Icon(Icons.calendar_month),
                    onPressed: _pickDate,
                  ),
                ],
              ),
            ] else ...[
              LabeledDropdown(
                label: 'Baumart',
                value: _subtype,
                options: kBaumarten,
                onChanged: (v) => setState(() => _subtype = v),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _number,
                decoration: const InputDecoration(
                  labelText: 'Nummer (laut Plakette am Baum)',
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
                labelText: 'Kommentar',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            const Text('Fotos', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final p in _photos)
                  GestureDetector(
                    onTap: () => _showPhoto(p),
                    onLongPress: () => _removePhoto(p),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.file(
                        File(p),
                        width: 96,
                        height: 96,
                        fit: BoxFit.cover,
                        errorBuilder: (c, e, s) => const SizedBox(
                          width: 96,
                          height: 96,
                          child: Icon(Icons.broken_image),
                        ),
                      ),
                    ),
                  ),
                OutlinedButton.icon(
                  onPressed: _addPhoto,
                  icon: const Icon(Icons.photo_camera),
                  label: const Text('Foto'),
                ),
              ],
            ),
            if (_photos.isNotEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text(
                  'Foto antippen zum Vergrößern, lang drücken zum Entfernen.',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ),
            const SizedBox(height: 12),
            Row(
              children: [
                if (!widget.isNew)
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        widget.onTarget();
                      },
                      icon: const Icon(Icons.flag),
                      label: const Text('Als Ziel'),
                    ),
                  ),
                if (!widget.isNew) const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _save,
                    icon: const Icon(Icons.save_outlined),
                    label: const Text('Speichern'),
                  ),
                ),
              ],
            ),
            if (widget.onDelete != null && !widget.isNew)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: _delete,
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Eintrag löschen'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
