/// Android-Paketname (wird auch als Kennung gegenueber den Kartendiensten genutzt).
const String kAppPackage = 'de.waldkataster.app';

/// Pflichtangabe der Datenlizenz (dl-de/by-2-0) des Landesamts fuer
/// Vermessung und Geobasisinformation Rheinland-Pfalz.
String attributionText() =>
    '©GeoBasis-DE / LVermGeoRP${DateTime.now().year}, dl-de/by-2-0, '
    'www.lvermgeo.rlp.de [Daten bearbeitet]';

/// Beschreibung eines WMS-Kartendienstes.
class WmsServiceDef {
  final String id;
  final String title;
  final String capabilitiesUrl;

  /// true: Ebene wird ueber eine andere Karte gelegt (transparenter Hintergrund).
  final bool overlay;

  /// true: JPEG bevorzugen (Luftbilder sind damit deutlich kleiner).
  final bool preferJpeg;

  const WmsServiceDef({
    required this.id,
    required this.title,
    required this.capabilitiesUrl,
    required this.overlay,
    this.preferJpeg = false,
  });
}

const String _geoportal =
    'https://www.geoportal.rlp.de/mapbender/php/wms.php';

/// Kostenfreie Kartendienste des Landesamts (Open Data, Stand Oktober 2026).
/// Die Ebenennamen werden beim Start aus der Dienstbeschreibung gelesen.
const WmsServiceDef kTopoService = WmsServiceDef(
  id: 'topo',
  title: 'Karte RP',
  capabilitiesUrl:
      '$_geoportal?layer_id=38925&withChilds=1&REQUEST=GetCapabilities&VERSION=1.1.1&SERVICE=WMS',
  overlay: false,
);

const WmsServiceDef kAerialService = WmsServiceDef(
  id: 'dop',
  title: 'Luftbild (DOP20)',
  capabilitiesUrl:
      '$_geoportal?layer_id=61675&withChilds=1&REQUEST=GetCapabilities&VERSION=1.1.1&SERVICE=WMS',
  overlay: false,
  preferJpeg: true,
);

const WmsServiceDef kFlurService = WmsServiceDef(
  id: 'flur',
  title: 'Flurkarte (Liegenschaften RP)',
  capabilitiesUrl:
      '$_geoportal?layer_id=61680&withChilds=1&REQUEST=GetCapabilities&VERSION=1.1.1&SERVICE=WMS',
  overlay: true,
);

const WmsServiceDef kAccuracyService = WmsServiceDef(
  id: 'gst',
  title: 'Genauigkeit des Katasters',
  capabilitiesUrl:
      '$_geoportal?layer_id=49310&withChilds=1&REQUEST=GetCapabilities&VERSION=1.1.1&SERVICE=WMS',
  overlay: true,
);

const List<WmsServiceDef> kServiceDefs = [
  kTopoService,
  kAerialService,
  kFlurService,
  kAccuracyService,
];
