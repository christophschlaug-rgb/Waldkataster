import 'dart:convert';

const List<String> kBaumarten = [
  'Fichte',
  'Kiefer',
  'Lärche',
  'Douglasie',
  'Eiche',
  'Buche',
  'Birke',
  'Ahorn',
  'Esche',
  'Erle',
  'Sonstige',
];

const List<String> kStruktur = [
  'Einschichtig',
  'Zweischichtig',
  'Mehrschichtig',
  'Plenterartig',
  'Verjüngung',
  'Blöße / Lücke',
];

const List<String> kBestandZustand = [
  'Stabil',
  'Geschwächt',
  'Geschädigt',
  'Kalamitätsfläche',
];

const List<String> kPflegebedarf = ['Keiner', 'Pflege nötig', 'Dringend'];

const Map<String, String> kJagdTypen = {
  'leiter': 'Leiter',
  'drueckjagdbock': 'Drückjagdbock',
  'offene_kanzel': 'Offene Kanzel',
  'geschlossene_kanzel': 'Geschlossene Kanzel',
  'mobile_kanzel': 'Mobile Kanzel',
};

const List<String> kJagdZustand = ['In Ordnung', 'Mängel', 'Gesperrt', 'Abgebaut'];

class Parcel {
  final String id;
  final String name;
  final String label;
  final double? area; // Quadratmeter
  final String geometryJson;
  final String? attrsJson;
  final String? deptId;
  final DateTime updatedAt;

  const Parcel({
    required this.id,
    required this.name,
    required this.label,
    required this.area,
    required this.geometryJson,
    this.attrsJson,
    this.deptId,
    required this.updatedAt,
  });

  Parcel copyWith({
    String? name,
    String? label,
    String? deptId,
    bool clearDept = false,
  }) {
    return Parcel(
      id: id,
      name: name ?? this.name,
      label: label ?? this.label,
      area: area,
      geometryJson: geometryJson,
      attrsJson: attrsJson,
      deptId: clearDept ? null : (deptId ?? this.deptId),
      updatedAt: DateTime.now(),
    );
  }

  Map<String, Object?> toMap() => {
        'id': id,
        'name': name,
        'label': label,
        'area': area,
        'geometry': geometryJson,
        'attrs': attrsJson,
        'dept_id': deptId,
        'updated_at': updatedAt.toIso8601String(),
      };

  factory Parcel.fromMap(Map<String, Object?> m) => Parcel(
        id: m['id'] as String,
        name: m['name'] as String,
        label: (m['label'] as String?) ?? '',
        area: (m['area'] as num?)?.toDouble(),
        geometryJson: m['geometry'] as String,
        attrsJson: m['attrs'] as String?,
        deptId: m['dept_id'] as String?,
        updatedAt: DateTime.parse(m['updated_at'] as String),
      );
}

class Dept {
  final String id;
  final String name;
  final String note;
  final DateTime updatedAt;

  const Dept({
    required this.id,
    required this.name,
    this.note = '',
    required this.updatedAt,
  });

  Dept copyWith({String? name, String? note}) => Dept(
        id: id,
        name: name ?? this.name,
        note: note ?? this.note,
        updatedAt: DateTime.now(),
      );

  Map<String, Object?> toMap() => {
        'id': id,
        'name': name,
        'note': note,
        'updated_at': updatedAt.toIso8601String(),
      };

  factory Dept.fromMap(Map<String, Object?> m) => Dept(
        id: m['id'] as String,
        name: m['name'] as String,
        note: (m['note'] as String?) ?? '',
        updatedAt: DateTime.parse(m['updated_at'] as String),
      );
}

/// Bestandsaufnahme zu einer Parzelle (ownerId 'p:<id>') oder Abteilung ('d:<id>').
class Stand {
  final String ownerId;
  final String hauptbaumart;
  final String mischbaumarten;
  final String alter;
  final String struktur;
  final String zustand;
  final String bemerkungen;
  final DateTime updatedAt;

  const Stand({
    required this.ownerId,
    this.hauptbaumart = '',
    this.mischbaumarten = '',
    this.alter = '',
    this.struktur = '',
    this.zustand = '',
    this.bemerkungen = '',
    required this.updatedAt,
  });

  Map<String, Object?> toMap() => {
        'owner_id': ownerId,
        'hauptbaumart': hauptbaumart,
        'mischbaumarten': mischbaumarten,
        'alter_text': alter,
        'struktur': struktur,
        'zustand': zustand,
        'bemerkungen': bemerkungen,
        'updated_at': updatedAt.toIso8601String(),
      };

  factory Stand.fromMap(Map<String, Object?> m) => Stand(
        ownerId: m['owner_id'] as String,
        hauptbaumart: (m['hauptbaumart'] as String?) ?? '',
        mischbaumarten: (m['mischbaumarten'] as String?) ?? '',
        alter: (m['alter_text'] as String?) ?? '',
        struktur: (m['struktur'] as String?) ?? '',
        zustand: (m['zustand'] as String?) ?? '',
        bemerkungen: (m['bemerkungen'] as String?) ?? '',
        updatedAt: DateTime.parse(m['updated_at'] as String),
      );
}

class Kultur {
  final String id;
  final String ownerId;
  final String baumarten;
  final double? flaecheHa;
  final int? pflanzjahr;
  final String pflegebedarf;
  final String notiz;
  final DateTime updatedAt;

  const Kultur({
    required this.id,
    required this.ownerId,
    this.baumarten = '',
    this.flaecheHa,
    this.pflanzjahr,
    this.pflegebedarf = 'Keiner',
    this.notiz = '',
    required this.updatedAt,
  });

  Map<String, Object?> toMap() => {
        'id': id,
        'owner_id': ownerId,
        'baumarten': baumarten,
        'flaeche_ha': flaecheHa,
        'pflanzjahr': pflanzjahr,
        'pflegebedarf': pflegebedarf,
        'notiz': notiz,
        'updated_at': updatedAt.toIso8601String(),
      };

  factory Kultur.fromMap(Map<String, Object?> m) => Kultur(
        id: m['id'] as String,
        ownerId: m['owner_id'] as String,
        baumarten: (m['baumarten'] as String?) ?? '',
        flaecheHa: (m['flaeche_ha'] as num?)?.toDouble(),
        pflanzjahr: m['pflanzjahr'] as int?,
        pflegebedarf: (m['pflegebedarf'] as String?) ?? 'Keiner',
        notiz: (m['notiz'] as String?) ?? '',
        updatedAt: DateTime.parse(m['updated_at'] as String),
      );
}

/// Punkt-Objekt im Wald: Jagdeinrichtung (kind 'jagd') oder Habitatbaum ('habitat').
class ForestObject {
  final String id;
  final String kind;
  final String subtype; // Jagd: Typ-Schluessel, Habitat: Baumart
  final String number; // Bezeichnung bzw. Nummer (Plakette)
  final double lat;
  final double lon;
  final double? accuracy;
  final String zustand;
  final DateTime? checkedOn;
  final String note;
  final List<String> photos;
  final String? parcelId;
  final DateTime updatedAt;

  const ForestObject({
    required this.id,
    required this.kind,
    this.subtype = '',
    this.number = '',
    required this.lat,
    required this.lon,
    this.accuracy,
    this.zustand = '',
    this.checkedOn,
    this.note = '',
    this.photos = const [],
    this.parcelId,
    required this.updatedAt,
  });

  bool get isJagd => kind == 'jagd';

  String get title {
    if (isJagd) {
      final t = kJagdTypen[subtype] ?? 'Jagdeinrichtung';
      return number.isEmpty ? t : '$t $number';
    }
    final t = subtype.isEmpty ? 'Habitatbaum' : 'Habitatbaum $subtype';
    return number.isEmpty ? t : '$t Nr. $number';
  }

  ForestObject copyWith({
    String? subtype,
    String? number,
    String? zustand,
    DateTime? checkedOn,
    String? note,
    List<String>? photos,
    String? parcelId,
  }) {
    return ForestObject(
      id: id,
      kind: kind,
      subtype: subtype ?? this.subtype,
      number: number ?? this.number,
      lat: lat,
      lon: lon,
      accuracy: accuracy,
      zustand: zustand ?? this.zustand,
      checkedOn: checkedOn ?? this.checkedOn,
      note: note ?? this.note,
      photos: photos ?? this.photos,
      parcelId: parcelId ?? this.parcelId,
      updatedAt: DateTime.now(),
    );
  }

  Map<String, Object?> toMap() => {
        'id': id,
        'kind': kind,
        'subtype': subtype,
        'number': number,
        'lat': lat,
        'lon': lon,
        'accuracy': accuracy,
        'zustand': zustand,
        'checked_on': checkedOn?.toIso8601String(),
        'note': note,
        'photos': jsonEncode(photos),
        'parcel_id': parcelId,
        'updated_at': updatedAt.toIso8601String(),
      };

  factory ForestObject.fromMap(Map<String, Object?> m) {
    var photos = <String>[];
    final raw = m['photos'] as String?;
    if (raw != null && raw.isNotEmpty) {
      try {
        photos = (jsonDecode(raw) as List).map((e) => e.toString()).toList();
      } catch (_) {}
    }
    return ForestObject(
      id: m['id'] as String,
      kind: m['kind'] as String,
      subtype: (m['subtype'] as String?) ?? '',
      number: (m['number'] as String?) ?? '',
      lat: (m['lat'] as num).toDouble(),
      lon: (m['lon'] as num).toDouble(),
      accuracy: (m['accuracy'] as num?)?.toDouble(),
      zustand: (m['zustand'] as String?) ?? '',
      checkedOn: m['checked_on'] == null
          ? null
          : DateTime.tryParse(m['checked_on'] as String),
      note: (m['note'] as String?) ?? '',
      photos: photos,
      parcelId: m['parcel_id'] as String?,
      updatedAt: DateTime.parse(m['updated_at'] as String),
    );
  }
}
