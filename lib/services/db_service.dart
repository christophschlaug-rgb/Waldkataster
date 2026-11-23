import 'dart:io';

import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

import '../models/forest_models.dart';
import '../models/marked_point.dart';
import '../models/shape_models.dart';
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
      version: 4,
      onCreate: (db, version) async {
        await _createPoints(db);
        await _createForest(db);
        await _createDamagesAndMeasures(db);
        await _createShapes(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) await _createForest(db);
        if (oldVersion < 3) await _createDamagesAndMeasures(db);
        if (oldVersion < 4) await _createShapes(db);
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

  Future<void> _createDamagesAndMeasures(Database db) async {
    await db.execute('''
      CREATE TABLE damages (
        id TEXT PRIMARY KEY,
        kind TEXT NOT NULL,
        lat REAL NOT NULL,
        lon REAL NOT NULL,
        accuracy REAL,
        found_on TEXT NOT NULL,
        amount REAL,
        status TEXT,
        note TEXT,
        photos TEXT,
        parcel_id TEXT,
        updated_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE measures (
        id TEXT PRIMARY KEY,
        owner_id TEXT,
        art TEXT NOT NULL,
        start_on TEXT NOT NULL,
        end_on TEXT,
        status TEXT NOT NULL,
        note TEXT,
        updated_at TEXT NOT NULL
      )
    ''');
  }

  Future<void> _createShapes(Database db) async {
    await db.execute('''
      CREATE TABLE shapes (
        id TEXT PRIMARY KEY,
        kind TEXT NOT NULL,
        points TEXT NOT NULL,
        width REAL,
        name TEXT,
        date_on TEXT,
        status TEXT,
        amount REAL,
        note TEXT,
        photos TEXT,
        area_m2 REAL,
        length_m REAL,
        shares TEXT,
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
      await txn.delete('measures', where: 'owner_id = ?', whereArgs: ['p:$id']);
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
      await txn.delete('measures', where: 'owner_id = ?', whereArgs: ['d:$id']);
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

  // ------------------------------------------------- Schaeden, Massnahmen

  Future<List<Damage>> damages() async {
    final db = await database;
    final rows = await db.query('damages', orderBy: 'found_on DESC');
    return rows.map(Damage.fromMap).toList();
  }

  Future<void> upsertDamage(Damage d) async {
    final db = await database;
    await db.insert('damages', d.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> deleteDamage(String id) async {
    final db = await database;
    await db.delete('damages', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<Measure>> measures({String? ownerId}) async {
    final db = await database;
    final rows = ownerId == null
        ? await db.query('measures', orderBy: 'start_on ASC')
        : await db.query('measures',
            where: 'owner_id = ?', whereArgs: [ownerId], orderBy: 'start_on ASC');
    return rows.map(Measure.fromMap).toList();
  }

  Future<void> upsertMeasure(Measure m) async {
    final db = await database;
    await db.insert('measures', m.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> deleteMeasure(String id) async {
    final db = await database;
    await db.delete('measures', where: 'id = ?', whereArgs: [id]);
  }

  // ------------------------------------------------- Flaechen und Linien

  Future<List<GeoShape>> shapes() async {
    final db = await database;
    final rows = await db.query('shapes', orderBy: 'updated_at DESC');
    return rows.map(GeoShape.fromMap).toList();
  }

  Future<void> upsertShape(GeoShape s) async {
    final db = await database;
    await db.insert('shapes', s.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> deleteShape(String id) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('shapes', where: 'id = ?', whereArgs: [id]);
      await txn.delete('stands', where: 'owner_id = ?', whereArgs: ['s:$id']);
      await txn.delete('kulturen', where: 'owner_id = ?', whereArgs: ['s:$id']);
      await txn.delete('measures', where: 'owner_id = ?', whereArgs: ['s:$id']);
    });
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
