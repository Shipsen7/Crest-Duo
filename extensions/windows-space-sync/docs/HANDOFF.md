# Übergabe zur Prüfung

Stand: 25.10.2026, 20:28 Uhr (Europe/Berlin).

Branch: `feature/windows-spaces-sync-extension`

Basis: `eeba7159eceda1864f1b68d9ce4cf3f538b57ceb`

Draft-PR: https://github.com/Shipsen7/Fennavio/pull/1

**Implementierte Preview mit automatisierten Mock-Tests; keine bestätigte produktive Windows-/Apple-Synchronisierung.** Installation: [README](../README.md), anschließend künstliche Gruppen in einem separaten Brave-Profil übernehmen. Kein Build nötig.

## Tatsächlicher Funktionsstand

| Bestandteil | Status |
| --- | --- |
| MV3, Popup, Verwaltungstab, Einstellungen | Implementiert; Syntax/Entry Points geprüft; echte UI-Abnahme offen |
| Stabile IDs, Persistenz, Outbox | Implementiert, Unit-/Service-Worker-Fixtures erfolgreich |
| Spaces: Erstellen, Name, Farbe, Reihenfolge, Löschen | Implementiert; simulierte Browser-API-Tests erfolgreich |
| Aktuelle Tabs: Öffnen/Schließen, Navigation, Verschieben, Reihenfolge | Implementiert; simulierte Browser-API-Tests erfolgreich |
| Angeheftete Tabs und Reihenfolge | Implementiert; simulierte Browser-API-Tests erfolgreich |
| Gespeicherte Tabs, Ordner und Unterordner | Implementiert; Modell-/Adaptertests erfolgreich; manuelle UI-Abnahme offen |
| Offline, Wiederverbindung, Konflikte, unterbrochener Upload | Synthetische Zwei-Geräte-/Transporttests erfolgreich |
| Neustart, Fensterende, verlorene IDs, Massenlöschungsschutz | Implementiert; simulierte Wiederanlauf-/Browsertests erfolgreich |
| Bestehender CloudKit-Codec und direkter Web-Services-Adapter | Implementiert; HTTP-Fixtures erfolgreich; echte Interoperabilität offen |
| Apple-Anmeldung/Abmeldung | Implementiert; Callback-/Redirect-/Fehlergrenzen mit Mocks getestet; echte Anmeldung fehlt |
| Production-Schreiben | Absichtlich im Transport gesperrt |
| Windows 11 / Brave / Chrome / Edge real | Noch nicht durchgeführt |
| Zwei Apple-Geräte plus Windows real | Durch Apple-Konfiguration, Anmeldung und reale Testgeräte blockiert |

## Tatsächlich ausgeführte Prüfungen

Linux-Entwicklungsrechner, Node.js v24.22.1. Keine privaten CloudKit-Daten gelesen und keine produktiven Schreibtests.

| Prüfung | Ergebnis |
| --- | --- |
| `npm test` | **54 bestanden, 0 fehlgeschlagen, 0 übersprungen**; synthetische Daten und Browser-/HTTP-Fixtures |
| `npm run check` | 11 JavaScript-Module syntaktisch geprüft; Manifest-Entry-Points vorhanden |
| `python3 Scripts/check-architecture.py` | Bestanden |
| `Scripts/check-swift-format.sh --base main` | Keine geänderten Swift-Dateien |
| `Scripts/validate-cache-hygiene.sh` | Bestanden |
| `python3 Scripts/audit-licenses.py` | Bestanden; keine neuen Runtime-Abhängigkeiten der Erweiterung |
| `git diff --check` | Bestanden |
| `Scripts/bootstrap.sh` | Versucht, blockiert: XcodeGen fehlt auf Linux. Keine Apple-App gebaut. |
| Playwright Chromium installieren | Versucht, fehlgeschlagen: ungültiges/unvollständiges Downloadarchiv |
| `npm run test:chromium` mit vorhandenem Playwright | Versucht, Start blockiert: Chromium-Executable fehlt. **Kein erfolgreicher echter Browser-Test.** |

Die letzten Gruppen-/Pin-Reihenfolgetests wurden nach den Repository-Gates mit der vollständigen Node-Suite und Syntaxprüfung ausgeführt. Rohlogs, Browserprofile und Bilder bleiben außerhalb des Repositorys. Der wiederverwendbare echte Chromium-Smoke-Test ist vorbereitet; [TESTING.md](TESTING.md) erklärt seinen Start.

## Die wenigen manuellen Voraussetzungen

1. Im Apple-Dashboard einen Web-API-Token für den bestehenden Fennavio-Container mit passender Origin und der in den Erweiterungseinstellungen angezeigten Callback-URL konfigurieren.
2. Eine provisionierte Apple-Review-App im bereits vorhandenen Isolationsmodus in `CrestReview-windows-sync` starten. Die drei genauen Umgebungsvariablen stehen in [CLOUDKIT.md](CLOUDKIT.md). Nur künstliche Testdaten verwenden; eine normal gestartete App in `CrestPrivate` ist kein Gegentest.
3. In der Erweiterung Development/Testzone auswählen, Token eintragen, anmelden und zuerst nur lesen. Nach erfolgreich geprüftem verschlüsseltem Lesen Schreibfreigabe ausschließlich in der isolierten Development-Zone aktivieren und die Zwei-Geräte-Testmatrix abarbeiten.

Branch und Draft-PR benötigen keine weitere GitHub-Konfiguration. Eine spätere Production-Schreibfreigabe ist ein gesondert zu prüfendes Folgeprojekt.

## Bekannte Grenzen und Risiken

- Apples aktuelle Dokumentation beschreibt verschlüsselte Web-Services-Felder mit `isEncrypted`. Der reale Antwortvertrag dieses Containers, die Nullsetzung des anderen verschlüsselten Felds und Apples Origin-/Callback-Akzeptanz wurden nicht bestätigt. Der Adapter stoppt bei fehlender Verschlüsselungskennzeichnung konservativ.
- Kein vollständiger Port von CrestCore: History/Archive, native Dokumente, Splits als Windows-Funktion und sämtliche Apple-Materialisierungs-/Migrationsregeln sind nicht umgesetzt. Unbekannte Felder bleiben erhalten; unbekannte Schemata stoppen den Pull.
- Chromium-Gruppen isolieren keine Cookies oder Website-Anmeldungen. Geschützte Spaces werden nicht geöffnet oder bearbeitet.
- Mehrdeutige Wiederherstellung und doppelte URLs können manuelle Zuordnung bzw. bewusste Übernahme erfordern. Eine doppelte Gruppe kann im Grenzfall entstehen; Datenerhalt hat Vorrang.
- Native Gruppen schließen entfernt offene Tabs, aber keinen Space. Eindeutige strukturelle Löschung erfolgt im Erweiterungsmenü. Ungruppieren allein ist kein eindeutiger Wechsel in einen neuen Fennavio-Space.
- Das Schließen der lokalen Seite eines gespeicherten Tabs erhält den gespeicherten Eintrag. Ein zusätzliches plattformübergreifendes Live-Seiten-Flag bietet das bestehende Schema nicht direkt.
- Bearer-Tokens bleiben nur im Sitzungsspeicher. Nach Browserende ist eine erneute Apple-Anmeldung nötig; Wiederverbindung innerhalb einer gültigen Sitzung läuft automatisch.
- Keine garantierte Echtzeitzustellung. Suspend, Offline-Geräte, ungefähr minütliches Polling und Server-Backoff können verzögern.
- Echte Windows-/Browser-Tests und UI-Screenshots fehlen. Die simulierten APIs können browserspezifische Fehler übersehen.

## Isolationsnachweis

Alle entwickelten Dateien liegen unter `extensions/windows-space-sync/`. Apple-App, Duo-Oberfläche, WebKit-Werbeblocker, bisherige Sync-Komponenten, CloudKit-Schema, globale Workflows und Repository-Einstellungen bleiben unverändert. Die Erweiterung hat ihre eigene Version `0.1.0`. Globale Versions-/Release-Note-Dateien wurden gemäß dem ausdrücklich beschränkten Auftrag nicht verändert; auch diese gewünschte Ergebnisdokumentation bleibt im Erweiterungsverzeichnis.

Kein Merge, kein Store-Release, keine veröffentlichte Authentifizierungswebsite und keine Änderungen an Apple-Entwicklereinstellungen.
