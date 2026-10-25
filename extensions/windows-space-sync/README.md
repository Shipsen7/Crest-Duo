# Fennavio Windows Spaces Sync — Preview

Eigenständige Manifest-V3-Erweiterung für Brave, Chrome und Edge. Fennavio ist ein unabhängiger Fork von Crest und wird nicht von Crest oder Paul Davis unterstützt. MPL-2.0; siehe die Lizenz im Repository.

**Stand dieser Preview:** Lokale Spaces, Tabs und Ordner sind implementiert. Der direkte CloudKit-Web-Services-Adapter ist implementiert, aber noch nicht mit einem echten Apple-Account oder dem privaten Fennavio-Container getestet. Production-Schreibzugriffe sind im Code gesperrt. Ein erfolgreicher Mock-Test belegt keine echte CloudKit-Verbindung.

## In Brave installieren

1. Diesen Branch herunterladen oder auschecken: `feature/windows-spaces-sync-extension`.
2. In einem **separaten Brave-Testprofil** `brave://extensions` öffnen und den Entwicklermodus einschalten.
3. **Entpackte Erweiterung laden** wählen und den Unterordner `extensions/windows-space-sync/extension` auswählen. Kein Build und keine npm-Installation nötig.
4. Eine Testgruppe mit zwei harmlosen HTTP(S)-Tabs anlegen. Das Erweiterungssymbol öffnen und **Browsergruppen übernehmen** wählen.
5. Im Popup einen Space erstellen, gespeicherte Tabs und Ordner ergänzen und die Änderungen prüfen. `↗` öffnet dieselbe Verwaltung in einem eigenen Tab.

Für Chrome: `chrome://extensions`. Für Edge: `edge://extensions`. Windows-11-/Brave-Akzeptanz ist noch manuell durchzuführen; hier liegt kein verifizierter Windows-Lauf vor.

## Grenzen

- Synchronisiert wird die Organisation. **Keine** Übertragung oder Isolation von Cookies, Passwörtern, Website-Daten oder Anmeldesitzungen. Chromium-Gruppen teilen das Browserprofil.
- Nur übernommene Gruppen und deren Tabs werden verwaltet. Ungegliederte neue Tabs bleiben außerhalb. Neue Gruppen werden nach der ersten Übernahme automatisch erfasst; mehrdeutig wiederhergestellte Gruppen müssen bewusst übernommen werden.
- Leere Spaces und gespeicherte Tabs/Ordner bleiben in der Erweiterung, ohne leere native Tabs zu erzwingen.
- Chromium-Pins stehen außerhalb nativer Gruppen; ihre Space-Zuordnung bleibt in der Erweiterung erhalten.
- Gruppenfarben werden auf Fennavios vier Akzentfamilien angenähert; die genaue Chromium-Farbe bleibt lokal.
- Geschützte Spaces und native Fennavio-Inhalte werden nicht in Chromium geöffnet oder bearbeitet. History, Archive, Splits und Website-Sitzungen sind nicht Teil dieser Erweiterung.
- Beim Fensterende oder nach einem Absturz werden keine fehlenden Records gelöscht. Eindeutige Wiederherstellungen werden wieder zugeordnet. Fehlende Seiten lassen sich mit **Space öffnen** erneut öffnen.
- Eine verschwundene Chromium-Gruppe allein löscht keinen Space. **Space bearbeiten → Space löschen** ist die eindeutige Aktion für eine strukturelle Löschung.
- CloudKit benötigt eine manuelle Web-API-Konfiguration und Anmeldung. Details und Testabfolge folgen in `docs/`.

## Entwicklung und Tests

Node.js 20 oder neuer: `npm test` und `npm run check` in diesem Verzeichnis. Die Erweiterung selbst hat keine Laufzeitabhängigkeiten. Die Tests verwenden synthetische Daten und lokale Mock-Transporte; keine produktiven Schreibtests.

Ausgangscommit: `eeba7159eceda1864f1b68d9ce4cf3f538b57ceb`. Alle Änderungen bleiben in diesem Verzeichnis; Apple-Apps und CloudKit-Schema werden nicht verändert.
