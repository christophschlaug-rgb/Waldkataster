import 'dart:io';

import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

import '../models/forest_models.dart';
import '../models/marked_point.dart';
import 'secure_storage_service.dart';

/// Verschluesselte lokale Datenbank (SQLCipher) fuer Punkte, Parzellen,
/// Abteilungen, Bestandsaufnahmen, Kulturen und Waldobjekte.
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
      version: 2,
      onCreate: (db, version) async {
        await _createPoints(db);
        await _createForest(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) await _createForest(db);
      },
    );
  }

  Future<void> _createPoints(Database db) async {
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
  }

  Future<void> _createForest(Database db) async {
    await db.execute('''
      CREATE TABLE parcels (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        label TEXT,
        area REAL,
        geometry TEXT NOT NULL,
        attrs TEXT,
        dept_id TEXT,
        updated_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE depts (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        note TEXT,
        updated_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE stands (
        owner_id TEXT PRIMARY KEY,
        hauptbaumart TEXT,
        mischbaumarten TEXT,
        alter_text TEXT,
        struktur TEXT,
        zustand TEXT,
        bemerkungen TEXT,
        updated_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE kulturen (
        id TEXT PRIMARY KEY,
        owner_id TEXT NOT NULL,
        baumarten TEXT,
        flaeche_ha REAL,
        pflanzjahr INTEGER,
        pflegebedarf TEXT,
        notiz TEXT,
        updated_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE objects (
        id TEXT PRIMARY KEY,
        kind TEXT NOT NULL,
        subtype TEXT,
        number TEXT,
        lat REAL NOT NULL,
        lon REAL NOT NULL,
        accuracy REAL,
        zustand TEXT,
        checked_on TEXT,
        note TEXT,
        photos TEXT,
        parcel_id TEXT,
        updated_at TEXT NOT NULL
      )
    ''');
  }

  // ------------------------------------------------------------ Punkte

  Future<List<MarkedPoint>> all() async {
    final db = await database;
    final rows = await db.query('points', orderBy: 'updated_at DESC');
    return rows.map(MarkedPoint.fromMap).toList();
  }

  Future<void> upsert(MarkedPoint p) async {
    final db = await database;
    await db.insert('points', p.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> delete(String id) async {
    final db = await database;
    await db.delete('points', where: 'id = ?', whereArgs: [id]);
  }

  // ---------------------------------------------------------- Parzellen

  Future<List<Parcel>> parcels() async {
    final db = await database;
    final rows = await db.query('parcels', orderBy: 'name COLLATE NOCASE ASC');
    return rows.map(Parcel.fromMap).toList();
  }

  Future<void> upsertParcel(Parcel p) async {
    final db = await database;
    await db.insert('parcels', p.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> deleteParcel(String id) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('parcels', where: 'id = ?', whereArgs: [id]);
      await txn.delete('stands', where: 'owner_id = ?', whereArgs: ['p:$id']);
      await txn.delete('kulturen', where: 'owner_id = ?', whereArgs: ['p:$id']);
      await txn.update('objects', {'parcel_id': null},
          where: 'parcel_id = ?', whereArgs: [id]);
    });
  }

  // -------------------------------------------------------- Abteilungen

  Future<List<Dept>> depts() async {
    final db = await database;
    final rows = await db.query('depts', orderBy: 'name COLLATE NOCASE ASC');
    return rows.map(Dept.fromMap).toList();
  }

  Future<void> upsertDept(Dept d) async {
    final db = await database;
    await db.insert('depts', d.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> deleteDept(String id) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('depts', where: 'id = ?', whereArgs: [id]);
      await txn.delete('stands', where: 'owner_id = ?', whereArgs: ['d:$id']);
      await txn.delete('kulturen', where: 'owner_id = ?', whereArgs: ['d:$id']);
      await txn.update('parcels', {'dept_id': null},
          where: 'dept_id = ?', whereArgs: [id]);
    });
  }

  // ------------------------------------------- Bestand und Kulturen

  Future<Stand?> stand(String ownerId) async {
    final db = await database;
    final rows = await db.query('stands',
        where: 'owner_id = ?', whereArgs: [ownerId], limit: 1);
    return rows.isEmpty ? null : Stand.fromMap(rows.first);
  }

  Future<void> upsertStand(Stand s) async {
    final db = await database;
    await db.insert('stands', s.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Kultur>> kulturen(String ownerId) async {
    final db = await database;
    final rows = await db.query('kulturen',
        where: 'owner_id = ?', whereArgs: [ownerId], orderBy: 'pflanzjahr DESC');
    return rows.map(Kultur.fromMap).toList();
  }

  Future<void> upsertKultur(Kultur k) async {
    final db = await database;
    await db.insert('kulturen', k.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> deleteKultur(String id) async {
    final db = await database;
    await db.delete('kulturen', where: 'id = ?', whereArgs: [id]);
  }

  // ------------------------------------------------------------ Objekte

  Future<List<ForestObject>> objects() async {
    final db = await database;
    final rows = await db.query('objects', orderBy: 'updated_at DESC');
    return rows.map(ForestObject.fromMap).toList();
  }

  Future<void> upsertObject(ForestObject o) async {
    final db = await database;
    await db.insert('objects', o.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> deleteObject(String id) async {
    final db = await database;
    await db.delete('objects', where: 'id = ?', whereArgs: [id]);
  }
}
