# Testen und Einordnen

## Reproduzierbare automatische Tests

Im Verzeichnis `extensions/windows-space-sync/`:

```sh
npm test
npm run check
```

Node.js 20 oder neuer genügt. Keine Installation von Abhängigkeiten erforderlich. Die Tests verwenden ausschließlich künstliche Records und Browser-/HTTP-Fixtures. Die Browser-Fixture ist kein Chromium und kein Ersatz für einen echten Windows-Test.

Geschützte Verträge: Recordformat/UUIDs/Epochen, uint64-Präzision, unbekannte Felder, Schema-Abweisung, feldweise Konflikte und Cross-Space-Moves, Ordertokens, Ordnerzyklen, stabile IDs, explizite Löschungen, Fensterende/Crash, Wiederherstellung, Massenlöschungsprüfung, Paging und Tokenrotation, Konto-/Umgebungsgrenzen, Outbox-Wiederaufnahme sowie Service-Worker-Persistenz und Nachrichtenautorisierung.

## Optionaler echter Chromium-Test

`scripts/chromium-smoke.mjs` startet mit Playwright einen vollständig neuen temporären Chromium-Testprofilordner. Er nimmt keine Anmeldung vor und greift nicht auf CloudKit zu. Seiten unter `example.org` werden mit künstlichen HTML-Antworten ersetzt. Der Profilordner wird im `finally`-Block entfernt.

Wenn Playwright bereits im Entwicklungsprojekt verfügbar ist:

```sh
npm run test:chromium
```

Andernfalls Playwright als **optionales lokales Testwerkzeug** installieren, nicht in die Erweiterung kopieren:

```sh
npm install --no-save --package-lock=false playwright
npx playwright install chromium
npm run test:chromium
```

Alternativ kann `PLAYWRIGHT_MODULE` auf das `index.mjs` einer vorhandenen Playwright-Installation verweisen. Die Erweiterung selbst enthält diese Abhängigkeit nicht. Der Test prüft Gruppenübernahme, Namensänderung, gespeicherten Ordner/Tab und explizites Tab-Schließen. Er ist weder ein Brave-Akzeptanztest noch ein Zwei-Geräte-CloudKit-Test.

## Manuelle Brave-Abnahme ohne Apple

Ein frisches Testprofil verwenden. Gruppen mit `https://example.org/` und `https://example.com/` reichen aus.

1. Zwei Gruppen erzeugen, übernehmen, Namen/Farbe ändern. Space-Identität und Tabanzahl müssen gleich bleiben.
2. Einen Tab zwischen beiden Gruppen verschieben und die Tabreihenfolge ändern. Keine doppelten Records dürfen entstehen.
3. Gespeicherten Tab, Ordner und Unterordner anlegen. Sie dürfen ohne „Öffnen“ keine zusätzlichen Browser-Tabs erzeugen. Einen Ordner umbenennen, verschieben und löschen: Inhalte müssen erhalten bleiben.
4. Einen offenen Tab schließen: im internen Workspace entsteht ein Tombstone. Eine leere native Gruppe darf den Space nicht löschen.
5. Fenster schließen und Browser neu starten. Spaces/Tabs müssen lokal weiter vorhanden sein; eindeutig wiederhergestellte Tabs werden zugeordnet. Fehlende Seiten über „Space öffnen“ wieder öffnen.
6. Einen Space im Popup löschen. Nur dessen Tabs dürfen entfernt werden. Bei einer entfernten Löschliste mit mehr als zehn Tabs muss zunächst die konkrete Liste gezeigt werden; eine veraltete Freigabe darf nicht gelten.
7. Erweiterung deaktivieren/aktivieren und den Browser mit gespeicherten Ordnern neu starten. Alle lokalen Strukturdaten müssen erhalten bleiben.
8. Popup und Verwaltungstab mit Tastatur bedienen, kleine Fenster und lange Namen prüfen. Screenshot-Nachweise erst aus dem tatsächlich laufenden Browser erzeugen.

## Zwei-Geräte-Abnahme mit Apple

Zuerst `CLOUDKIT.md` befolgen: Development, isolierte `CrestReview-windows-sync`-Zone, künstliche Daten. Die normale Apple-App in `CrestPrivate` ist kein Gegentest.

| Prüfung | Erwartung |
| --- | --- |
| Apple erstellt Space/Tab/Ordner, Windows liest | Dieselben UUIDs, Namen, Zuordnungen und Reihenfolgen |
| Windows erstellt/benennt um/verschiebt | Apple übernimmt im Review-Profil nach Abgleich |
| Windows schließt einen aktuellen Tab | Apple übernimmt den Tombstone; andere Tabs bleiben |
| Apple schließt einen aktuellen Tab | Zugeordnete Windows-Seite wird geschlossen |
| Offline auf beiden Seiten unterschiedliche Felder ändern | Nach Wiederverbindung übereinstimmender Record; Titel und Move möglichst erhalten |
| Auf einer Seite löschen, auf anderer bearbeiten | Explizite Löschung gewinnt; kein Wiederauferstehen |
| Windows-Fenster schließen / Prozess abrupt beenden | Keine neue Serie von Cloud-Tombstones |
| Netzwerk unterbrechen, danach wiederherstellen | Persistente Outbox wird erneut verarbeitet |
| Anmeldung abbrechen oder Token ablaufen lassen | Verständlicher Fehler; lokale Daten erhalten; keine Uploads ohne Anmeldung |
| Anderen Apple-Account anmelden | Blockierung; keine Vermischung |
| Mehr als zehn entfernte Tabs löschen | Windows verlangt Prüfung der angezeigten Liste |

Bei der ersten verschlüsselten Lese-/Schreiboperation zusätzlich die Feldmetadaten mit Apples tatsächlicher Antwort abgleichen, ohne private Payloads oder Token zu protokollieren. Der erwartete `BYTES`/`isEncrypted`-Vertrag und die Nullsetzung des jeweils anderen verschlüsselten Felds sind Teil dieser ausstehenden Interoperabilitätsprüfung.

## Teststatus der Übergabe

Siehe `HANDOFF.md` für die tatsächlich ausgeführten Befehle, Ergebnisse und Blocker. Ein Mock-Erfolg ist dort ausdrücklich von Browser- und CloudKit-Abnahme getrennt.
