# Architektur und Wiederanlauf

Die Erweiterung ist eine eigenständige Organisationsprojektion außerhalb des Apple-Browsers. Sie greift weder in CrestCore noch in SwiftUI oder die Browserengine ein. Sie bietet insbesondere keine Sicherheitsgrenze zwischen Chromium-Tabgruppen.

## Komponenten

| Datei | Verantwortung |
| --- | --- |
| `core/record.js` | Validierung, UUIDs, Cloud-Recordmodell, Versionsvergleich, Konfliktregeln |
| `core/order.js` | Bestehende Ordertoken-Strategie mit 64-Bit-Präzision |
| `core/workspace.js` | Space-/Tab-/Ordneraktionen und persistente Outbox |
| `core/sync.js` | Konto prüfen, vollständig ziehen, atomar speichern, Uploads bestätigen |
| `cloud/codec.js` | Bestehendes Fennavio-Envelope ↔ Web-Services-Dictionaries |
| `cloud/client.js` | Private Datenbank, Tokenrotation, Paging, Compare-and-swap-Uploads |
| `cloud/auth.js` | Apple-Anmeldung, Redirect- und Callback-Prüfung |
| `browser/projection.js` | Chromium-Ereignisse, stabile Zuordnung und native Darstellung |
| `worker.js` | Serialisierte MV3-Ereigniswarteschlange, Speicher, UI-Kommandos, Alarme |
| `ui/` | Popup, eigener Verwaltungstab und CloudKit-Einstellungen |

Der Transportvertrag besteht aus `currentUser()`, `pull(cursor)` und `push(records, tags)`. Tests liefern dafür deterministische In-Memory- und HTTP-Fixtures. Ein Ersatztransport muss dieselben Records und IDs transportieren; ein paralleles serverseitiges Datenmodell ist nicht vorgesehen.

## Persistenz und Konflikte

`chrome.storage.local.workspace` hält Records, Gerätekennung, logische Uhr, Outbox, CloudKit-Cursor, Change Tags, Browser-Zuordnungen und Konfiguration in **einem** Schreibvorgang. Es gibt keine Ableitung von Löschungen aus einer fehlenden Liste. Die Version ist ein Dezimalstring; Berechnungen verwenden BigInt.

Ein Pull wird vollständig paginiert und validiert. Die Workspace-Übernahme wird in einer Kopie vorbereitet und erst bei vollständigem Erfolg übernommen. Erst nach Speicherung der Records samt Cursor wird hochgeladen. Neue lokale Änderungen werden nur dann bestätigt, wenn die Bestätigung exakt ihren versandten Inhalt betrifft. Ein unterbrochener Upload bleibt im Journal und wird beim nächsten Pull mit dem Server abgeglichen.

Versionsvergleich: logische Uhr, danach Geräte-UUID. Explizite Löschungen gewinnen gegenüber Änderungen. Nicht explizite Bereinigungen dürfen durch später aktivierte Tabs überholt werden. Innerhalb desselben Space werden Tabtitel-/Positionszeitstempel, Ordner-Collapse und relevante Space-Felder getrennt zusammengeführt; beim Wechsel zwischen Spaces bleibt der gewinnende Record vollständig zusammen. Bekannte Split-Metadaten werden konservativ erhalten und ihre vorhandenen Feldzeitstempel berücksichtigt; Splits können unter Windows nicht erstellt werden.

Aktualisierungen verwenden `recordChangeTag` und `update`, neue Records `create`. Keine Force-Updates, keine Replace-Operationen und keine physischen Cloud-Löschungen. Bei konkurrierenden Writes wird erneut gezogen und zusammengeführt. Löschungen bleiben als Tombstones gespeichert; es gibt keine automatische Tombstone-Bereinigung.

## Verhalten bei Browserereignissen

| Ereignis | Wirkung |
| --- | --- |
| Zugeordneten offenen Tab bewusst schließen | Expliziter Tab-Tombstone |
| Lokale Seite eines gespeicherten Tabs schließen | Gespeicherter Record bleibt erhalten; eine separate plattformübergreifende Live-Seiten-Zustandskennung existiert im Schema nicht |
| Space im Erweiterungsmenü löschen | Explizite Tombstones für Space und seine bekannten Tabs/Ordner |
| Chromium-Gruppenrahmen verschwindet | Space behalten; leere Gruppe ist keine Löschautorisierung |
| Ganze native Gruppe schließen | Eindeutige Tab-Schließereignisse schließen offene Tabs; Space bleibt als leere Struktur bestehen |
| Fenster schließen / Browser beenden | Records behalten; keine Löschung durch `isWindowClosing` |
| Absturz / verlorene Tab-Liste | Records behalten; keine Löschung durch Abwesenheit |
| Browserneustart | Native IDs verwerfen; nur eindeutige Gruppe+Farbe+URL-Kandidaten wieder zuordnen |
| Temporär keine Internetverbindung | Lokale Änderungen erhalten; automatische Wiederholung mit Backoff |
| Mehr als zehn entfernte automatische Tab-Schließungen | Native Schließungen anhalten und konkrete Liste im Popup prüfen lassen |

Ein Löschlisten-Token gilt nur für genau den angezeigten Stand. Eine zwischenzeitlich veränderte Liste benötigt eine neue Prüfung. Das bewusste lokale Löschen eines Space erteilt keine pauschale Freigabe für unabhängige entfernte Löschungen.

Nach einer expliziten entfernten Space-Löschung werden auch zwischenzeitlich offline erzeugte Kind-Records mit Tombstones ausgemustert, anstatt als lebende Waisen hochgeladen zu werden. Fehlende Eltern allein berechtigen nicht zu solchen Tombstones.

Eine zuvor fehlende Seite wird nur bei neuer Record-Version oder „Space öffnen“ wieder geöffnet. Fenster werden nie automatisch erstellt. Mehrdeutige Wiederherstellungen werden nicht anhand einer URL geraten. Es kann deshalb nötig sein, eine nicht eindeutig wiedererkannte Gruppe bewusst zu übernehmen. Eine doppelte Gruppe/URL kann im Grenzfall eine manuelle Bereinigung erfordern; das Verfahren priorisiert Datenerhalt.

## Abbildungsgrenzen

- Chromium-Gruppen sind flach. Die Ordnerstruktur lebt in der Erweiterung und bleibt im kompatiblen Record erhalten.
- Ein angehefteter Chromium-Tab darf nicht zugleich in einer Tabgruppe sein. Seine Space-Zuordnung ist lokal in der Erweiterung sichtbar. Fennavios Grenze von zwölf Pins pro Space wird bei Bearbeitungen geprüft.
- Neue, nicht gruppierte Tabs werden nicht automatisch aufgenommen. Das Entfernen aus einer nativen Gruppe allein hebt die organisatorische Zuordnung nicht auf; zum eindeutigen Verschieben die Erweiterung oder eine andere übernommene Gruppe verwenden.
- Gruppenfarben werden auf `indigo`, `orange`, `teal` und `rose` abgebildet. Eine vollständige mehrfarbige Space-Branding-Definition hat kein direktes Chromium-Pendant.
- Private Fenster, geschützte Spaces und native Nicht-Web-Inhalte werden nicht in native Tabs projiziert. Nicht unterstützte Daten werden nicht als gelöscht interpretiert.
- Es wird kein Verlauf abgefragt. Die Berechtigung `tabs` ist für URL-/Titelbeobachtung der verwalteten Tabs erforderlich; `tabGroups`, `storage`, `alarms` und `identity` haben jeweils eine konkrete Funktion. CloudKit-Hostzugriff ist optional und wird erst beim Anmeldeklick angefragt.

## Scheduling

Lokale Organisationsänderungen stoßen nach dem Speichern einen Abgleich an. Browseränderungen werden bei relevanten Änderungen zeitnah verarbeitet; zusätzliche Ereignisse werden zusammengefasst. Ein nicht ständig neu gesetzter Alarm sichert einen Nachlauf nach ungefähr 30 Sekunden. Zusätzlich wird ungefähr minütlich gepollt. Fehlversuche verwenden 30 Sekunden bis 30 Minuten Backoff und berücksichtigen längere Servervorgaben. Browser-Suspend, Offline-Geräte und Apple-Tokenablauf können die Zustellung verzögern. Es gibt keine Behauptung einer garantierten Echtzeitzustellung.

## Integration in die Apple-App

Aus dem analysierten Quellcode und der aktuellen Apple-Dokumentation ergibt sich noch keine nachgewiesen notwendige Änderung an Fennavio. Die vorhandene Review-Zone ist bereits nutzbar. Es wurde daher **kein Patch an Apple-Dateien implementiert**. Wenn der reale Web-Services-Vertrag die benötigten verschlüsselten Records nicht verfügbar macht, ist das ein offener Integrationsblocker. Eine Klartext-Duplikation der Payloads oder ein neues Schema wird nicht als Umgehung eingebaut.

Die relative Space-Reihenfolge wird innerhalb jedes vorhandenen Chromium-Fensters über `tabGroups.move` projiziert. Fensterzuordnungen bleiben lokal. Bei einer umsortierten Space-Liste können verwaltete Gruppen an das Ende der jeweiligen Tab-Leiste wandern; unverwaltete Tabs werden nicht in andere Spaces übernommen. Angeheftete Tabs werden innerhalb des nativen Pin-Bereichs geordnet.
