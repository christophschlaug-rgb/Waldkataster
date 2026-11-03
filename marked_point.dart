enum PointStatus { open, found, notFound, buried }

String statusLabel(PointStatus s) {
  switch (s) {
    case PointStatus.open:
      return 'Nicht gesucht';
    case PointStatus.found:
      return 'Gefunden';
    case PointStatus.notFound:
      return 'Nicht gefunden';
    case PointStatus.buried:
      return 'Stein vermutlich unter der Erde';
  }
}

/// Ein Punkt, zu dem sich die App etwas merkt: entweder ein Grenzpunkt aus
/// dem Kataster (kind = 'kataster') oder ein selbst gesetzter Punkt ('eigen').
class MarkedPoint {
  final String id;
  final String kind;
  final String name;
  final double lat;
  final double lon;
  final PointStatus status;
  final String note;

  final double? measuredLat;
  final double? measuredLon;
  final double? measuredAccuracy;
  final int? measuredSamples;
  final DateTime? measuredAt;

  /// Eigenschaften des Katasterpunkts (JSON), damit sie auch offline lesbar sind.
  final String? attributesJson;
  final DateTime updatedAt;

  const MarkedPoint({
    required this.id,
    required this.kind,
    required this.name,
    required this.lat,
    required this.lon,
    this.status = PointStatus.open,
    this.note = '',
    this.measuredLat,
    this.measuredLon,
    this.measuredAccuracy,
    this.measuredSamples,
    this.measuredAt,
    this.attributesJson,
    required this.updatedAt,
  });

  bool get isOwn => kind == 'eigen';
  bool get hasMeasurement => measuredLat != null && measuredLon != null;

  MarkedPoint copyWith({
    String? name,
    PointStatus? status,
    String? note,
    double? measuredLat,
    double? measuredLon,
    double? measuredAccuracy,
    int? measuredSamples,
    DateTime? measuredAt,
  }) {
    return MarkedPoint(
      id: id,
      kind: kind,
      name: name ?? this.name,
      lat: lat,
      lon: lon,
      status: status ?? this.status,
      note: note ?? this.note,
      measuredLat: measuredLat ?? this.measuredLat,
      measuredLon: measuredLon ?? this.measuredLon,
      measuredAccuracy: measuredAccuracy ?? this.measuredAccuracy,
      measuredSamples: measuredSamples ?? this.measuredSamples,
      measuredAt: measuredAt ?? this.measuredAt,
      attributesJson: attributesJson,
      updatedAt: DateTime.now(),
    );
  }

  Map<String, Object?> toMap() => {
        'id': id,
        'kind': kind,
        'name': name,
        'lat': lat,
        'lon': lon,
        'status': status.name,
        'note': note,
        'm_lat': measuredLat,
        'm_lon': measuredLon,
        'm_acc': measuredAccuracy,
        'm_samples': measuredSamples,
        'm_at': measuredAt?.toIso8601String(),
        'attrs': attributesJson,
        'updated_at': updatedAt.toIso8601String(),
      };

  factory MarkedPoint.fromMap(Map<String, Object?> m) => MarkedPoint(
        id: m['id'] as String,
        kind: m['kind'] as String,
        name: m['name'] as String,
        lat: (m['lat'] as num).toDouble(),
        lon: (m['lon'] as num).toDouble(),
        status: PointStatus.values.firstWhere(
          (s) => s.name == m['status'],
          orElse: () => PointStatus.open,
        ),
        note: (m['note'] as String?) ?? '',
        measuredLat: (m['m_lat'] as num?)?.toDouble(),
        measuredLon: (m['m_lon'] as num?)?.toDouble(),
        measuredAccuracy: (m['m_acc'] as num?)?.toDouble(),
        measuredSamples: m['m_samples'] as int?,
        measuredAt: m['m_at'] == null
            ? null
            : DateTime.tryParse(m['m_at'] as String),
        attributesJson: m['attrs'] as String?,
        updatedAt: DateTime.parse(m['updated_at'] as String),
      );
}
