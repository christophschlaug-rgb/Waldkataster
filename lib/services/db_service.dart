import 'dart:io';

import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

import '../models/marked_point.dart';
import 'secure_storage_service.dart';

/// Verschluesselte lokale Datenbank (SQLCipher) fuer eigene Punkte sowie
/// Status, Notizen und Messungen zu Grenzpunkten.
class DbService {
  DbService._();
  static final DbService instance = DbService._();

  Future<Database>? _opening;

  Future<Database> get database {
    return _opening ??= _open().catchError((Object e) {
      _opening = null;
      throw e;
    });
  }

  Future<Database> _open() async {
    final dir = await getApplicationDocumentsDirectory();
    final path = join(dir.path, 'waldkataster.db');
    final dbExists = await File(path).exists();
    final password = await SecureStorageService.instance
        .getOrCreateDbKey(allowCreate: !dbExists);

    return openDatabase(
      path,
      password: password,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE points (
            id TEXT PRIMARY KEY,
            kind TEXT NOT NULL,
            name TEXT NOT NULL,
            lat REAL NOT NULL,
            lon REAL NOT NULL,
            status TEXT NOT NULL,
            note TEXT,
            m_lat REAL,
            m_lon REAL,
            m_acc REAL,
            m_samples INTEGER,
            m_at TEXT,
            attrs TEXT,
            updated_at TEXT NOT NULL
          )
        ''');
      },
    );
  }

  Future<List<MarkedPoint>> all() async {
    final db = await database;
    final rows = await db.query('points', orderBy: 'updated_at DESC');
    return rows.map(MarkedPoint.fromMap).toList();
  }

  Future<void> upsert(MarkedPoint p) async {
    final db = await database;
    await db.insert(
      'points',
      p.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> delete(String id) async {
    final db = await database;
    await db.delete('points', where: 'id = ?', whereArgs: [id]);
  }
}
