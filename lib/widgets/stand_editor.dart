import 'package:flutter/material.dart';

import '../models/forest_models.dart';
import '../services/db_service.dart';

String newId(String prefix) =>
    '$prefix${DateTime.now().microsecondsSinceEpoch}';

/// Auswahlfeld (Dropdown) mit Beschriftung.
class LabeledDropdown extends StatelessWidget {
  final String label;
  final String value;
  final List<String> options;
  final ValueChanged<String> onChanged;

  const LabeledDropdown({
    super.key,
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final items = <String>{'', ...options};
    if (value.isNotEmpty) items.add(value);
    return InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          isExpanded: true,
          value: value,
          items: [
            for (final o in items)
              DropdownMenuItem<String>(
                value: o,
                child: Text(o.isEmpty ? '–' : o),
              ),
          ],
          onChanged: (v) => onChanged(v ?? ''),
        ),
      ),
    );
  }
}

/// Bestandsaufnahme (Steckbrief) einer Parzelle oder Abteilung.
class StandEditor extends StatefulWidget {
  final String ownerId;
  const StandEditor({super.key, required this.ownerId});

  @override
  State<StandEditor> createState() => _StandEditorState();
}

class _StandEditorState extends State<StandEditor> {
  bool _loaded = false;
  String _haupt = '';
  String _struktur = '';
  String _zustand = '';
  final _misch = TextEditingController();
  final _alter = TextEditingController();
  final _bemerkung = TextEditingController();
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _misch.dispose();
    _alter.dispose();
    _bemerkung.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final s = await DbService.instance.stand(widget.ownerId);
      if (!mounted) return;
      setState(() {
        if (s != null) {
          _haupt = s.hauptbaumart;
          _struktur = s.struktur;
          _zustand = s.zustand;
          _misch.text = s.mischbaumarten;
          _alter.text = s.alter;
          _bemerkung.text = s.bemerkungen;
        }
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

  Future<void> _save() async {
    try {
      await DbService.instance.upsertStand(
        Stand(
          ownerId: widget.ownerId,
          hauptbaumart: _haupt,
          mischbaumarten: _misch.text.trim(),
          alter: _alter.text.trim(),
          struktur: _struktur,
          zustand: _zustand,
          bemerkungen: _bemerkung.text.trim(),
          updatedAt: DateTime.now(),
        ),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Bestandsaufnahme gespeichert')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Speichern nicht möglich: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null) return Text('Fehler: $_error');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LabeledDropdown(
          label: 'Hauptbaumart',
          value: _haupt,
          options: kBaumarten,
          onChanged: (v) => setState(() => _haupt = v),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _misch,
          decoration: const InputDecoration(
            labelText: 'Mischbaumarten',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _alter,
          decoration: const InputDecoration(
            labelText: 'Alter (z. B. 40 bis 60 Jahre)',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        LabeledDropdown(
          label: 'Bestandsstruktur',
          value: _struktur,
          options: kStruktur,
          onChanged: (v) => setState(() => _struktur = v),
        ),
        const SizedBox(height: 12),
        LabeledDropdown(
          label: 'Zustand',
          value: _zustand,
          options: kBestandZustand,
          onChanged: (v) => setState(() => _zustand = v),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _bemerkung,
          minLines: 2,
          maxLines: 5,
          decoration: const InputDecoration(
            labelText: 'Bemerkungen',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.save_outlined),
            label: const Text('Bestandsaufnahme speichern'),
          ),
        ),
      ],
    );
  }
}

/// Kulturen einer Parzelle oder Abteilung.
class KulturEditor extends StatefulWidget {
  final String ownerId;
  const KulturEditor({super.key, required this.ownerId});

  @override
  State<KulturEditor> createState() => _KulturEditorState();
}

class _KulturEditorState extends State<KulturEditor> {
  List<Kultur> _items = [];
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final list = await DbService.instance.kulturen(widget.ownerId);
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

  Future<void> _edit(Kultur? existing) async {
    final arten = TextEditingController(text: existing?.baumarten ?? '');
    final flaeche = TextEditingController(
      text: existing?.flaecheHa == null
          ? ''
          : existing!.flaecheHa!.toString().replaceAll('.', ','),
    );
    final jahr = TextEditingController(
      text: existing?.pflanzjahr?.toString() ?? '${DateTime.now().year}',
    );
    final notiz = TextEditingController(text: existing?.notiz ?? '');
    var pflege = existing?.pflegebedarf ?? 'Keiner';

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text(existing == null ? 'Kultur hinzufügen' : 'Kultur bearbeiten'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: arten,
                  decoration: const InputDecoration(
                    labelText: 'Baumarten',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: flaeche,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Fläche in ha',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: jahr,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Pflanzjahr',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                LabeledDropdown(
                  label: 'Pflegebedarf',
                  value: pflege,
                  options: kPflegebedarf,
                  onChanged: (v) => setD(() => pflege = v.isEmpty ? 'Keiner' : v),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: notiz,
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
        ),
      ),
    );
    if (saved != true) return;

    final k = Kultur(
      id: existing?.id ?? newId('k'),
      ownerId: widget.ownerId,
      baumarten: arten.text.trim(),
      flaecheHa: double.tryParse(flaeche.text.trim().replaceAll(',', '.')),
      pflanzjahr: int.tryParse(jahr.text.trim()),
      pflegebedarf: pflege,
      notiz: notiz.text.trim(),
      updatedAt: DateTime.now(),
    );
    try {
      await DbService.instance.upsertKultur(k);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Speichern nicht möglich: $e')));
    }
    await _load();
  }

  Future<void> _delete(Kultur k) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Kultur löschen?'),
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
    await DbService.instance.deleteKultur(k.id);
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
            child: Text('Noch keine Kulturen erfasst.',
                style: TextStyle(color: Colors.grey)),
          ),
        for (final k in _items)
          Card(
            child: ListTile(
              title: Text(
                '${k.baumarten.isEmpty ? 'Kultur' : k.baumarten}'
                '${k.pflanzjahr != null ? ' (${k.pflanzjahr})' : ''}',
              ),
              subtitle: Text(
                '${k.flaecheHa != null ? '${k.flaecheHa!.toString().replaceAll('.', ',')} ha · ' : ''}'
                'Pflege: ${k.pflegebedarf}'
                '${k.notiz.isNotEmpty ? '\n${k.notiz}' : ''}',
              ),
              isThreeLine: k.notiz.isNotEmpty,
              onTap: () => _edit(k),
              trailing: IconButton(
                icon: const Icon(Icons.delete_outline),
                onPressed: () => _delete(k),
              ),
            ),
          ),
        Align(
          alignment: Alignment.centerRight,
          child: OutlinedButton.icon(
            onPressed: () => _edit(null),
            icon: const Icon(Icons.add),
            label: const Text('Kultur hinzufügen'),
          ),
        ),
      ],
    );
  }
}
