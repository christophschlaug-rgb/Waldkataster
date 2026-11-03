import 'dart:convert';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Der Schluessel der lokalen Datenbank liegt verschluesselt im
/// Android Keystore, nie im Klartext in der App.
class SecureStorageService {
  SecureStorageService._();
  static final SecureStorageService instance = SecureStorageService._();

  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );
  static const _dbKeyKey = 'db_encryption_key';

  Future<String>? _dbKeyFuture;

  /// Gleichzeitige Aufrufe teilen sich dasselbe Ergebnis, damit beim ersten
  /// Start nie zwei verschiedene Schluessel entstehen. Existiert schon eine
  /// Datenbank (allowCreate = false), wird nie ein neuer Schluessel erzeugt.
  Future<String> getOrCreateDbKey({required bool allowCreate}) {
    return _dbKeyFuture ??=
        _loadOrCreateDbKey(allowCreate).catchError((Object e) {
      _dbKeyFuture = null;
      throw e;
    });
  }

  Future<String> _loadOrCreateDbKey(bool allowCreate) async {
    final existing = await _storage.read(key: _dbKeyKey);
    if (existing != null) return existing;
    if (!allowCreate) {
      throw StateError(
        'Der Schlüssel der lokalen Datenbank fehlt im Android-Schlüsselspeicher.',
      );
    }
    final random = Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    final key = base64UrlEncode(bytes);
    await _storage.write(key: _dbKeyKey, value: key);
    return key;
  }
}
