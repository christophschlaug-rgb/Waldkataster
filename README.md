# Waldkataster

Android-App für den Wald in Rheinland-Pfalz: Flurkarte und Luftbild mit
eigener GPS-Position. (Meilenstein 1 der Anforderungen.)

## Funktionen in dieser Version

- Hintergrund wählbar: Karte (Karte RP) oder Luftbild (DOP20, 20 cm)
- Flurkarte (Flurstücksgrenzen und -nummern) darüber, Deckkraft einstellbar,
  Ebenen einzeln wählbar
- Optionale Ebene "Genauigkeit des Katasters" (Lagegenauigkeit)
- Eigene Position live mit Genauigkeitskreis und Anzeige "GPS ± x m"
- Karte nach Norden oder nach Blickrichtung (Kompass, Handy flach halten)
- Zwischenspeicher für Kartenkacheln (Funklöcher, schnelleres Laden)
- Display wach halten (optional)
- Quellenangabe der Geodaten in der Karte
- "Dienste prüfen": zeigt, welche Kartendienste erreichbar sind

## Einrichtung (einmalig)

Die App braucht **keine** Azure-Anmeldung und keine OneDrive-Anbindung.
Nur der Signatur-Schlüssel muss als GitHub-Secret hinterlegt werden.

Im Repository unter **Settings → Secrets and variables → Actions →
New repository secret** vier Secrets anlegen:

| Name | Wert |
|---|---|
| `KEYSTORE_BASE64` | Inhalt der Datei `keystore-base64.txt` |
| `KEYSTORE_PASSWORD` | Passwort des Keystores |
| `KEY_ALIAS` | `holzliste` (bzw. der beim Erzeugen gewählte Alias) |
| `KEY_PASSWORD` | Passwort des Schlüssels |

### Schlüssel neu erzeugen (nur falls nötig)

```
keytool -genkey -v -keystore waldkataster-release.jks -keyalg RSA -keysize 2048 -validity 10000 -alias waldkataster
```

Umwandeln in Base64 (PowerShell):

```
[Convert]::ToBase64String([IO.File]::ReadAllBytes("$env:USERPROFILE\Desktop\waldkataster-release.jks")) | Out-File -Encoding ascii "$env:USERPROFILE\Desktop\keystore-base64.txt"
```

Schlüsseldatei und Passwörter sicher aufbewahren: Ohne sie lassen sich
spätere Updates nicht mehr signieren.

## Build

Jeder Push auf `main` baut eine signierte Release-APK. Manuell:
**Actions → Android Release Build → Run workflow**. Die fertige APK liegt
danach unter **Releases**.

## Installation auf dem Handy (Android 11)

APK herunterladen, öffnen, Installation aus dieser Quelle einmalig erlauben.
Beim ersten Start die Standortfreigabe erteilen ("Beim Verwenden der App").

## Datenquellen

Landesamt für Vermessung und Geobasisinformation Rheinland-Pfalz,
Datenlizenz Deutschland – Namensnennung 2.0 (dl-de/by-2-0). Die Quelle wird
in der Karte angezeigt. Die Flurkarte ist eine Orientierungshilfe und keine
rechtsverbindliche Grenzfeststellung.

## Hinweise zur Technik

Die Ebenennamen und Koordinatensysteme der Kartendienste liest die App beim
Start selbst aus den Dienstbeschreibungen (GetCapabilities). Falls eine Ebene
fehlt, hilft die Seite "Dienste prüfen" (Menü Ebenen → Dienste prüfen).
