# CloudKit-Kompatibilität und Einrichtung

## Klare Aussage

Der Adapter ist für das vorhandene Fennavio-Recordformat implementiert und mit synthetischen Web-Services-Antworten getestet. **Eine funktionierende Verbindung zum privaten Container ist nicht nachgewiesen.** Weder Apple-Anmeldung noch verschlüsselte Feldzugriffe wurden hier mit einem realen Account ausgeführt. Ein Web-API-Token, die Freigabe seiner Origins/Callback-URL und ein provisionierter Apple-Gegentest fehlen.

Die aktuelle offizielle Apple-Dokumentation [Encrypting User Data](https://developer.apple.com/documentation/cloudkit/encrypting-user-data) beschreibt unter „Use CloudKit Web Services“ das Speichern verschlüsselter Felder mit `isEncrypted`. Deshalb wird Verschlüsselung nicht pauschal als unmöglich ausgeschlossen. Das ist eine dokumentierte Integrationsmöglichkeit, kein Nachweis für diesen Container oder die konkrete Antwortdarstellung. Ältere Hinweise und unbeantwortete Forenfragen sind hierfür kein belastbarer Gegenbeweis.

## Vorhandenes Schema

Analysierte Basis: `eeba7159eceda1864f1b68d9ce4cf3f538b57ceb`.

| Eigenschaft | Vorhandene Fennavio-Implementierung | Erweiterung |
| --- | --- | --- |
| Container | `iCloud.io.github.shipsen7.fennavio` in beiden App-Konfigurationen | Derselbe feste Container |
| Datenbank | Private CloudKit-Datenbank | Ausschließlich `private` |
| Normale Zone | `CrestPrivate` | Lesbar nach Konfiguration/Anmeldung; Schreiben gesperrt |
| Review-Zone | `CrestReview-<kleingeschriebener-slug>` | Standard `CrestReview-windows-sync` |
| Records | `CrestSpace`, `CrestFolder`, `CrestTab`, außerdem History/Archive | Erste drei Typen; andere werden nicht verändert |
| Recordname | `space:<uuid>`, `folder:<uuid>`, `tab:<uuid>` | Identisches Format und stabile UUIDs |
| Envelope | `schemaVersion`, `spaceID`, `logicalClock`, `deviceID`, optionale `space`-Referenz | Identische Felder, `NONE`-Referenzaktion |
| Inhalt | `encryptedValues.payload` oder `encryptedValues.tombstone`, UTF-8-JSON als Bytes | Base64 `BYTES` mit `isEncrypted: true`; keine Klartext-Ausweichfelder |
| Schema | 1–3; offene Ordner ab 2, native Tab-Inhalte ab 3 | 1–3 lesen; neue gewöhnliche Records 1/2; native Inhalte nicht öffnen |
| IDs im Inhalt | `id`, `spaceID`, `folderID`, `parentID` als `{rawValue: UUID}`; `profileID` unwrapped | Identisches Format |
| Zeitangaben | Cloud: Unix-Sekunden; lokales Apple-Journal: Sekunden seit 2001 | Ausschließlich Cloud-Form mit Unix-Sekunden |
| Reihenfolge | Hexadezimale Ordertokens, bis 16 Zeichen | Port des vorhandenen Anker-/LIS-Algorithmus mit BigInt |
| Version | uint64-Uhr, dann UUID des Geräts ordinal | Dezimalstring/BigInt, keine Rundung auf JavaScript-Number |
| Löschung | Tombstone mit `reason`, `deletedAt` | Keine physischen Record-Löschungen |

Wichtige Referenzen im Repository: `CloudRecordCodec.swift`, `CloudRecordFields+CloudKit.swift`, `BrowserCloudSyncConfiguration.swift`, `SyncRecordBody.cs`, `SyncPayloadForm.cs`, `TabPayload.cs`, `FolderPayload.cs`, `SpacePayload.cs`, `SyncPayloadType.cs`, `SyncRecordStamp.cs`, `SyncVersion.cs`, `SyncOrderTokens.cs`, `NativeSyncCompatibility.cs` und `NativeSyncEvaluator.cs`.

Der Adapter übernimmt nicht Apples archivierte `CKRecord`-Systemfelder. Web Services verwenden den eigenen `recordChangeTag`; native `CKSyncEngine`-Tokens und Web-Services-`syncToken` sind getrennte, lokale Transportzustände.

## Die manuellen Voraussetzungen

1. **Erweiterung zuerst in einem separaten Brave-Testprofil installieren.** In „CloudKit“ die angezeigte Callback-URL kopieren. Sie lautet `https://<erweiterungs-id>.chromiumapp.org/cloudkit` und muss genau zur konkreten Installation gehören.
2. **Im Apple CloudKit Dashboard einen Web-API-Token für den bestehenden Fennavio-Container konfigurieren.** Die Callback-URL hinterlegen und die zulässigen Origins auf die Testinstallation begrenzen. Keine Server-to-Server-Schlüssel verwenden; diese sind kein Ersatz für den privaten Benutzerzugriff. Keine Tokens in GitHub, Logs oder Screenshots kopieren. Wenn das Dashboard die Extension-Origin bzw. Chromium-Callback-URL ablehnt, ist die direkte Anmeldung ein offener Integrationsblocker; die Origin-Beschränkung nicht global abschalten.
3. **Eine provisionierte Fennavio-Review-App mit dem bereits vorhandenen Isolationsmodus starten.** In der Xcode-Run-Konfiguration auf dem Testgerät setzen:

   ```text
   CREST_ISOLATED_SESSION=1
   CREST_ISOLATED_PERSISTENCE_ID=windows-review-apple-a
   CREST_ISOLATED_CLOUD_SYNC_ID=windows-sync
   ```

   Ein zweites Apple-Testgerät verwendet eine andere `PERSISTENCE_ID` und dieselbe `CLOUD_SYNC_ID`. Der bestehende Code wählt dann `CrestReview-windows-sync`; die Provisionierung muss den Fennavio-Container in Development erlauben. Siehe die vorhandene Anleitung `Documentation/Architecture/ControlPlane.md`, Abschnitt „Isolated CloudKit review“. Eine normal gestartete App verwendet weiterhin `CrestPrivate` und ist **kein** Gegentest für diese Review-Zone. Diese Einstellungen wurden hier nicht verändert oder ausgeführt.
4. **In der Erweiterung Development und `CrestReview-windows-sync` wählen**, Web-API-Token eintragen, Konfiguration speichern und „Bei Apple anmelden“ wählen. Zunächst **ohne Schreibfreigabe** lesen. Prüfen, ob die künstlichen Apple-Spaces, Ordner und Tabs korrekt erscheinen. Keine realen Browsing-Daten für diesen Test verwenden.
5. Erst nach erfolgreichem Lesen in dieser isolierten Zone dort die lokale Schreibfreigabe aktivieren, erneut anmelden und die Testfolge in `TESTING.md` durchführen. Das erneute Speichern meldet die lokale Sitzung ab. Kein Schema-Deployment, keine Production-Schreibfreigabe und keine Container-Neuanlage sind Bestandteil dieses Schritts.

Falls eine vorgeschaltete statische HTTPS-Authentifizierungsseite erforderlich wird, muss deren genaue Architektur und Veröffentlichung separat freigegeben werden. In dieser Preview ist keine solche Seite veröffentlicht und kein zweiter Sync-Server eingebaut.

## Authentifizierung und Sicherheit

- Direkte HTTP-Aufrufe an `api.apple-cloudkit.com`; kein extern geladenes CloudKit-JS und kein `eval`, damit der MV3-Code vollständig im Paket bleibt.
- `identity.launchWebAuthFlow` startet nur nach dem ausdrücklichen Klick auf Anmeldung. Apple-Anmeldedaten verarbeitet ausschließlich Apple.
- Anmelde-Redirects werden auf HTTPS-Apple-Domains begrenzt. Der Rücksprung muss Origin und Pfad der eigenen Callback-URL exakt treffen.
- Benutzer-Token nur in `chrome.storage.session` mit `TRUSTED_CONTEXTS`; Web-API-Konfiguration im lokalen Extension-Speicher. Keine Tokens in `storage.sync`, UI-Antworten, Diagnoselogs oder Exporten.
- Web-Auth-Tokens werden gemäß Apples Dokumentation rotiert; Anfragen laufen seriell. Nach Browserende ist eine erneute Anmeldung nötig. Ein offenes Apple-Weblogin kann diese verkürzen, wird aber nicht von der Erweiterung verwaltet.
- Benutzerwechsel oder Wechsel des bereits angebundenen Containers/Environment/Zone werden blockiert. Für getrennte Accounts und Umgebungen getrennte Browserprofile verwenden.
- Abmelden entfernt den lokalen Bearer-Token und beendet automatische Cloudzugriffe. Lokale Daten werden erhalten; der gespeicherte API-Token allein ist keine Benutzeranmeldung.
- Browser-URLs sind im normalen lokalen Extension-Speicher lesbar. Das ist keine zusätzliche Verschlüsselung gegen andere Personen mit Zugriff auf das entsperrte Windows-/Browserprofil.
- Production-Schreiben ist unabhängig von der UI im Transport gesperrt. Development-Schreiben ist nur in `CrestReview-[a-z0-9-]{1,48}` möglich. Die Erweiterung erstellt oder löscht keine Zonen und ändert kein Schema.

## Fehler werden konservativ behandelt

Unbekannte Schemas, fehlende Verschlüsselungskennzeichnung, ungenaue Versionsnummern, beschädigte Inhalte, physische Record-Löschungen, abgelaufene Cursor und unvollständige Seiten werden nicht als Erlaubnis zum Löschen lokaler Daten behandelt. Der Decoder erwartet im Feld `type: BYTES` und `isEncrypted: true`. Liefert Apple eine andere Form, muss der reale, anonymisierte Antwortvertrag zuerst untersucht und der Decoder gezielt angepasst werden; ein Entfernen der Verschlüsselungsprüfung ist keine Lösung.

Neue Apple-Felder im bestehenden bekannten Schema bleiben im Body erhalten. Die Übernahme des vollständigen Apple-Kerns einschließlich History-/Archive-Konflikten und aller Materialisierungsregeln wird nicht behauptet. Production-Schreiben darf erst in einem gesondert geprüften Folgeprojekt freigegeben werden.

## Offizielle Quellen

- [CloudKit JS und API-Token-Voraussetzungen](https://developer.apple.com/documentation/cloudkitjs)
- [Composing Web Service Requests und Benutzeranmeldung](https://developer.apple.com/library/archive/documentation/DataManagement/Conceptual/CloudKitWebServicesReference/SettingUpWebServices.html)
- [Record- und Feld-Dictionaries](https://developer.apple.com/library/archive/documentation/DataManagement/Conceptual/CloudKitWebServicesReference/Types.html)
- [Record Zone Changes](https://developer.apple.com/library/archive/documentation/DataManagement/Conceptual/CloudKitWebServicesReference/FetchingRecordZoneChanges(changeszone).html)
- [Modifying Records und Change Tags](https://developer.apple.com/library/archive/documentation/DataManagement/Conceptual/CloudKitWebServicesReference/ModifyRecords.html)
- [Encrypting User Data](https://developer.apple.com/documentation/cloudkit/encrypting-user-data)
- [Chromium identity](https://developer.chrome.com/docs/extensions/reference/api/identity)
- [Manifest V3 und Remote-Code](https://developer.chrome.com/docs/webstore/program-policies/mv3-requirements)
