import 'package:shared_preferences/shared_preferences.dart';

enum BaseMap { topo, aerial }

/// Einstellungen der Karte (keine Zugangsdaten).
class MapSettings {
  BaseMap base;
  bool flurOn;
  double flurOpacity;
  bool gstOn;
  bool headingUp;
  bool keepAwake;

  /// Gewaehlte Ebenen der Flurkarte; null = Standardauswahl der App.
  List<String>? flurLayers;

  MapSettings({
    this.base = BaseMap.aerial,
    this.flurOn = true,
    this.flurOpacity = 0.9,
    this.gstOn = false,
    this.headingUp = false,
    this.keepAwake = false,
    this.flurLayers,
  });

  static Future<MapSettings> load() async {
    final p = await SharedPreferences.getInstance();
    return MapSettings(
      base: p.getString('base') == 'topo' ? BaseMap.topo : BaseMap.aerial,
      flurOn: p.getBool('flurOn') ?? true,
      flurOpacity: p.getDouble('flurOpacity') ?? 0.9,
      gstOn: p.getBool('gstOn') ?? false,
      headingUp: p.getBool('headingUp') ?? false,
      keepAwake: p.getBool('keepAwake') ?? false,
      flurLayers: p.getStringList('flurLayers'),
    );
  }

  Future<void> save() async {
    final p = await SharedPreferences.getInstance();
    await p.setString('base', base == BaseMap.topo ? 'topo' : 'aerial');
    await p.setBool('flurOn', flurOn);
    await p.setDouble('flurOpacity', flurOpacity);
    await p.setBool('gstOn', gstOn);
    await p.setBool('headingUp', headingUp);
    await p.setBool('keepAwake', keepAwake);
    final layers = flurLayers;
    if (layers == null) {
      await p.remove('flurLayers');
    } else {
      await p.setStringList('flurLayers', layers);
    }
  }
}
