import 'package:flutter/material.dart';

import '../models/forest_models.dart';
import '../widgets/measure_widgets.dart';
import '../widgets/photo_strip.dart';
import '../widgets/stand_editor.dart';

/// Kaefernest oder Sturmschaden: Datum, Menge, Status, Foto, Notiz.
class DamageSheet extends StatefulWidget {
  final Damage damage;
  final bool isNew;
  final String? parcelName;
  final Future<void> Function(Damage updated) onSave;
  final Future<void> Function()? onDelete;
  final VoidCallback onTarget;

  const DamageSheet({
    super.key,
    required this.damage,
    required this.isNew,
    required this.parcelName,
    required this.onSave,
    required this.onDelete,
    required this.onTarget,
  });

  @override
  State<DamageSheet> createState() => _DamageSheetState();
}

class _DamageSheetState extends State<DamageSheet> {
  late DateTime _date;
  late String _status;
  late List<String> _photos;
  late final TextEditingController _amount;
  late final TextEditingController _note;

  @override
  void initState() {
    super.initState();
    final d = widget.damage;
    _date = d.foundOn;
    _status = d.status;
    _photos = List<String>.of(d.photos);
    _amount = TextEditingController(
      text: d.amount == null
          ? ''
          : (d.isKaefer
              ? d.amount!.round().toString()
              : d.amount!.toString().replaceAll('.', ',')),
    );
    _note = TextEditingController(text: d.note);
  }

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (d != null) setState(() => _date = DateTime(d.year, d.month, d.day));
  }

  Future<void> _save() async {
    final text = _amount.text.trim().replaceAll(',', '.');
    final amount = text.isEmpty ? null : double.tryParse(text);
    final updated = widget.damage.copyWith(
      foundOn: _date,
      amount: amount,
      clearAmount: amount == null,
      status: _status,
      note: _note.text.trim(),
      photos: _photos,
    );
    await widget.onSave(updated);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    if (!await confirmDelete(context, '${widget.damage.title} löschen?')) return;
    await widget.onDelete!();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.damage;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: [
            Text(
              d.title,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            SelectableText(
              '${d.lat.toStringAsFixed(6)}, ${d.lon.toStringAsFixed(6)}'
              '${d.accuracy != null ? '  (GPS ± ${d.accuracy!.round()} m)' : ''}'
              '${widget.parcelName != null ? '\nParzelle: ${widget.parcelName}' : ''}',
              style: const TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: Text('Festgestellt am ${dateText(_date)}')),
                IconButton(
                  tooltip: 'Datum wählen',
                  icon: const Icon(Icons.calendar_month),
                  onPressed: _pickDate,
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _amount,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: d.isKaefer
                    ? 'Anzahl befallener Bäume'
                    : 'Geschätzte Menge in Festmetern',
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            LabeledDropdown(
              label: 'Status',
              value: _status,
              options: d.isKaefer ? kKaeferStatus : kSturmStatus,
              onChanged: (v) => setState(() => _status = v),
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
            const SizedBox(height: 12),
            PhotoStrip(
              photos: _photos,
              onChanged: (p) => setState(() => _photos = p),
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
