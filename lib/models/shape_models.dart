import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import 'forest_models.dart';

/// Art einer Flaeche oder Linie (Kaefernest, Rueckegasse, ...).
class ShapeType {
  final String key;
  final String label;
  final bool isLine;
  final Color color;
  final IconData icon;
  final double defaultWidth;
  final List<String> statusOptions;
  final String? amountLabel;
  final bool hasDate;

  const ShapeType({
    required this.key,
    required this.label,
    required this.isLine,
    required this.color,
    required this.icon,
    this.defaultWidth = 0,
    this.statusOptions = const [],
    this.amountLabel,
    this.hasDate = false,
  });
}

const List<ShapeType> kShapeTypes = [
  ShapeType(
    key: 'kaefer',
    label: 'Käfernest',
    isLine: false,
    color: Color(0xFFC62828),
    icon: Icons.bug_report,
    statusOptions: kKaeferStatus,
    amountLabel: 'Anzahl befallener Bäume',
    hasDate: true,
  ),
  ShapeType(
    key: 'sturm',
    label: 'Sturmschaden',
    isLine: false,
    color: Color(0xFFEF6C00),
    icon: Icons.storm,
    statusOptions: kSturmStatus,
    amountLabel: 'Geschätzte Menge in Festmetern',
    hasDate: true,
  ),
  ShapeType(
    key: 'wild',
    label: 'Wildschadensfläche',
    isLine: false,
    color: Color(0xFF8D6E63),
    icon: Icons.pets,
    statusOptions: ['Neu', 'Dokumentiert', 'Behoben'],
    hasDate: true,
  ),
  ShapeType(
    key: 'teil',
    label: 'Teilfläche',
    isLine: false,
    color: Color(0xFF00897B),
    icon: Icons.grid_view,
  ),
  ShapeType(
    key: 'polter',
    label: 'Holzpolter',
    isLine: false,
    color: Color(0xFF6D4C41),
    icon: Icons.layers,
    statusOptions: ['Eingeschlagen', 'Abgefahren'],
    amountLabel: 'Menge in Festmetern',
    hasDate: true,
  ),
  ShapeType(
    key: 'rueckegasse',
    label: 'Rückegasse',
    isLine: true,
    color: Color(0xFF8E24AA),
    icon: Icons.timeline,
    defaultWidth: 4,
  ),
  ShapeType(
    key: 'schneise',
    label: 'Jagdschneise',
    isLine: true,
    color: Color(0xFF1E88E5),
    icon: Icons.timeline,
    defaultWidth: 3,
  ),
  ShapeType(
    key: 'weg',
    label: 'Weg',
    isLine: true,
    color: Color(0xFF616161),
    icon: Icons.timeline,
    defaultWidth: 3,
  ),
];

ShapeType shapeTypeOf(String key) {
  for (final t in kShapeTypes) {
    if (t.key == key) return t;
  }
  return kShapeTypes.first;
}

/// Anteil einer Flaeche oder Linie an einer Parzelle (parcelId '' = ausserhalb
/// aller eigenen Parzellen).
class ParcelShare {
  final String parcelId;
  final double areaM2;
  final double lengthM;

  const ParcelShare({
    required this.parcelId,
    required this.areaM2,
    required this.lengthM,
  });

  Map<String, Object?> toJson() => {'p': parcelId, 'a': areaM2, 'l': lengthM};

  factory ParcelShare.fromJson(Map<String, dynamic> m) => ParcelShare(
        parcelId: (m['p'] as String?) ?? '',
        areaM2: ((m['a'] as num?) ?? 0).toDouble(),
        lengthM: ((m['l'] as num?) ?? 0).toDouble(),
      );
}

class GeoShape {
  final String id;
  final String kind;
  final List<LatLng> points; // Flaeche: Aussenring (offen), Linie: Linienpunkte
  final double width; // Meter, nur Linien
  final String name;
  final DateTime? dateOn;
  final String status;
  final double? amount;
  final String note;
  final List<String> photos;
  final double areaM2;
  final double lengthM;
  final List<ParcelShare> shares;
  final DateTime updatedAt;

  const GeoShape({
    required this.id,
    required this.kind,
    required this.points,
    this.width = 0,
    this.name = '',
    this.dateOn,
    this.status = '',
    this.amount,
    this.note = '',
    this.photos = const [],
    this.areaM2 = 0,
    this.lengthM = 0,
    this.shares = const [],
    required this.updatedAt,
  });

  ShapeType get type => shapeTypeOf(kind);
  bool get isLine => type.isLine;

  String get title => name.isEmpty ? type.label : '${type.label} $name';

  GeoShape copyWith({
    List<LatLng>? points,
    double? width,
    String? name,
    DateTime? dateOn,
    bool clearDate = false,
    String? status,
    double? amount,
    bool clearAmount = false,
    String? note,
    List<String>? photos,
    double? areaM2,
    double? lengthM,
    List<ParcelShare>? shares,
  }) {
    return GeoShape(
      id: id,
      kind: kind,
      points: points ?? this.points,
      width: width ?? this.width,
      name: name ?? this.name,
      dateOn: clearDate ? null : (dateOn ?? this.dateOn),
      status: status ?? this.status,
      amount: clearAmount ? null : (amount ?? this.amount),
      note: note ?? this.note,
      photos: photos ?? this.photos,
      areaM2: areaM2 ?? this.areaM2,
      lengthM: lengthM ?? this.lengthM,
      shares: shares ?? this.shares,
      updatedAt: DateTime.now(),
    );
  }

  Map<String, Object?> toMap() => {
        'id': id,
        'kind': kind,
        'points': jsonEncode([
          for (final p in points) [p.latitude, p.longitude],
        ]),
        'width': width,
        'name': name,
        'date_on': dateOn?.toIso8601String(),
        'status': status,
        'amount': amount,
        'note': note,
        'photos': jsonEncode(photos),
        'area_m2': areaM2,
        'length_m': lengthM,
        'shares': jsonEncode([for (final s in shares) s.toJson()]),
        'updated_at': updatedAt.toIso8601String(),
      };

  factory GeoShape.fromMap(Map<String, Object?> m) {
    final pts = <LatLng>[];
    try {
      for (final e in jsonDecode(m['points'] as String) as List) {
        pts.add(LatLng((e[0] as num).toDouble(), (e[1] as num).toDouble()));
      }
    } catch (_) {}
    var photos = <String>[];
    try {
      final raw = m['photos'] as String?;
      if (raw != null && raw.isNotEmpty) {
        photos = (jsonDecode(raw) as List).map((e) => e.toString()).toList();
      }
    } catch (_) {}
    var shares = <ParcelShare>[];
    try {
      final raw = m['shares'] as String?;
      if (raw != null && raw.isNotEmpty) {
        shares = [
          for (final e in jsonDecode(raw) as List)
            ParcelShare.fromJson(Map<String, dynamic>.from(e as Map)),
        ];
      }
    } catch (_) {}
    return GeoShape(
      id: m['id'] as String,
      kind: m['kind'] as String,
      points: pts,
      width: ((m['width'] as num?) ?? 0).toDouble(),
      name: (m['name'] as String?) ?? '',
      dateOn: m['date_on'] == null ? null : DateTime.tryParse(m['date_on'] as String),
      status: (m['status'] as String?) ?? '',
      amount: (m['amount'] as num?)?.toDouble(),
      note: (m['note'] as String?) ?? '',
      photos: photos,
      areaM2: ((m['area_m2'] as num?) ?? 0).toDouble(),
      lengthM: ((m['length_m'] as num?) ?? 0).toDouble(),
      shares: shares,
      updatedAt: DateTime.parse(m['updated_at'] as String),
    );
  }
}
