import 'dart:io';

import 'package:flutter/material.dart';

import '../services/photo_service.dart';

/// Fotos einer Liste: aufnehmen, ansehen (antippen), entfernen (lang druecken).
class PhotoStrip extends StatelessWidget {
  final List<String> photos;
  final ValueChanged<List<String>> onChanged;

  const PhotoStrip({super.key, required this.photos, required this.onChanged});

  Future<void> _add(BuildContext context) async {
    try {
      final path = await PhotoService.takePhoto();
      if (path != null) onChanged([...photos, path]);
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Foto nicht möglich: $e')));
    }
  }

  void _show(BuildContext context, String path) {
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

  Future<void> _remove(BuildContext context, String path) async {
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
    onChanged([for (final p in photos) if (p != path) p]);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Fotos', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final p in photos)
              GestureDetector(
                onTap: () => _show(context, p),
                onLongPress: () => _remove(context, p),
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
              onPressed: () => _add(context),
              icon: const Icon(Icons.photo_camera),
              label: const Text('Foto'),
            ),
          ],
        ),
        if (photos.isNotEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 4),
            child: Text(
              'Foto antippen zum Vergrößern, lang drücken zum Entfernen.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ),
      ],
    );
  }
}
