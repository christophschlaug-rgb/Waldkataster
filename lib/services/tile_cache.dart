import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

/// HTTP-Client, der Kartenkacheln auf dem Geraet zwischenspeichert.
/// Bereits angesehene Kartenteile bleiben so auch bei Funkloch sichtbar
/// und laden schneller.
class TileCachingClient extends http.BaseClient {
  TileCachingClient(this._inner, this._dir,
      {this.maxAge = const Duration(days: 30)});

  final http.Client _inner;
  final Directory _dir;
  final Duration maxAge;

  /// Luftbild-Kacheln (JPEG) unter ca. 3,5 KB sind praktisch einfarbig
  /// (weiss): der Dienst liefert dort kein Bild (ausserhalb des Massstabs,
  /// kein Datenbestand). Solche Kacheln gelten als Fehler, damit die
  /// darunterliegende Karte sichtbar bleibt.
  static const int _blankJpegLimit = 3500;

  bool _isBlankJpeg(Uri url, int length) {
    final t = url.toString().toLowerCase();
    final jpeg = t.contains('image%2fjpeg') || t.contains('image/jpeg');
    return jpeg && length < _blankJpegLimit;
  }

  http.StreamedResponse _notFound(http.BaseRequest request) {
    return http.StreamedResponse(
      Stream<List<int>>.value(const <int>[]),
      404,
      contentLength: 0,
      request: request,
      reasonPhrase: 'Kachel ohne Bild',
    );
  }

  File _fileFor(Uri url) {
    final key = md5.convert(utf8.encode(url.toString())).toString();
    return File('${_dir.path}/$key.tile');
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request.method != 'GET') return _inner.send(request);

    final file = _fileFor(request.url);
    try {
      if (await file.exists()) {
        final stat = await file.stat();
        if (DateTime.now().difference(stat.modified) < maxAge) {
          final bytes = await file.readAsBytes();
          if (_isBlankJpeg(request.url, bytes.length)) {
            // alte, leere Kachel aus dem Zwischenspeicher verwerfen
            try {
              await file.delete();
            } catch (_) {}
          } else {
            return http.StreamedResponse(
              Stream.value(bytes),
              200,
              contentLength: bytes.length,
              request: request,
              headers: const {'content-type': 'image/png'},
            );
          }
        }
      }
    } catch (_) {
      // Zwischenspeicher defekt: einfach neu laden
    }

    final response = await _inner.send(request);
    final bytes = await response.stream.toBytes();
    final type = (response.headers['content-type'] ?? '').toLowerCase();
    if (response.statusCode == 200 &&
        type.startsWith('image/') &&
        _isBlankJpeg(request.url, bytes.length)) {
      return _notFound(request);
    }
    if (response.statusCode == 200 && type.startsWith('image/')) {
      try {
        await file.writeAsBytes(bytes);
      } catch (_) {}
    }
    return http.StreamedResponse(
      Stream.value(bytes),
      response.statusCode,
      contentLength: bytes.length,
      request: request,
      headers: response.headers,
      isRedirect: response.isRedirect,
      persistentConnection: response.persistentConnection,
      reasonPhrase: response.reasonPhrase,
    );
  }

  @override
  void close() {
    _inner.close();
    super.close();
  }
}

/// Raeumt den Zwischenspeicher auf: Kacheln aelter als 30 Tage werden
/// geloescht, die Gesamtgroesse bleibt unter ca. 500 MB.
Future<void> cleanTileCache(
  Directory dir, {
  Duration maxAge = const Duration(days: 30),
  int maxBytes = 500 * 1024 * 1024,
}) async {
  try {
    final entries = <MapEntry<File, FileStat>>[];
    var total = 0;
    await for (final e in dir.list()) {
      if (e is File) {
        final s = await e.stat();
        entries.add(MapEntry(e, s));
        total += s.size;
      }
    }

    final now = DateTime.now();
    for (final e in entries.toList()) {
      if (now.difference(e.value.modified) > maxAge) {
        await e.key.delete();
        total -= e.value.size;
        entries.remove(e);
      }
    }

    if (total > maxBytes) {
      entries.sort((a, b) => a.value.modified.compareTo(b.value.modified));
      for (final e in entries) {
        if (total <= maxBytes * 0.8) break;
        await e.key.delete();
        total -= e.value.size;
      }
    }
  } catch (_) {}
}
