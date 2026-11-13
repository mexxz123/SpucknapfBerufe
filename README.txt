SpucknapfBerufe v0.8.4 (Testversion)

Installiere den Ordner SpucknapfBerufe unter Interface/AddOns.
/spb oeffnen - Fenster
/spb scan Lederverarbeitung - aktuellen Berufsreiter eindeutig zuordnen und Rezepte erfassen
/spb sync - gespeicherte Berufe und Rezepte an Gilde senden
/spb list - gespeicherte Berufe anzeigen

Neu: Materialnamen neben Icons, /spb sync, automatische Aktualisierung des zuletzt explizit gescannten Berufs bei Berufslisten-Events.
Hinweis: Bei einem Berufsreiterwechsel zuerst /spb scan <Berufsname> verwenden. Vollstaendige Synchronisierung grosser Rezeptbuecher muss mit zwei Clients getestet werden.
Sichere SavedVariables vor dem Update.

0.4.5: Sequenzierte Uebertragung, Paketzaehlung, Empfangsbestaetigung, Wiederholung und Schutz vor Ueberschreiben laufender Sendungen.

Version 0.4.9: Minimap button (left click toggles UI, drag to reposition; saved position).

0.5.0: WoW-inspirierte Rahmen, Rezeptgruppen, Sortierung (Skill nur wenn API-Werte vorhanden).

Version 0.5.1: groesseres Fenster (970x655), groessere Materialicons (30px), ruhigere Innenflaechen, Skill-Sortierung meldet fehlende Skilldaten. Synchronisierung unveraendert.

Version 0.5.4: /spb recipeinfo prueft GetRecipeInfo mit Integer-Parametern 0/1/2 und zeigt verfuegbare Skill-API-Funktionen. Nur Diagnose, keine Datenveraenderung.

Version 0.5.5: Groessere, weichere Blizzard-Buttons fuer Scannen, Synchronisieren und Sortierung. Diagnose aus 0.5.4 bleibt erhalten.

Version 0.5.6: Groessere Schrift in Listen/Materialien. Neue Scans speichern maxTrivialLevel; Skill-Sortierung nutzt diesen Wert als Ersatz, nicht als Mindestskill. Bestehende gespeicherte Rezepte muessen neu gescannt werden.

Version 0.5.7: Schwierigkeit als separate, rechtsbuendige Zahl ohne T-Klammern; Sortierbutton umbenannt; ueberlappenden Hinweis entfernt. Werte sind Trivialitaetsgrenzen, keine Mindestskills.

Version 0.5.8: Schwierigkeitswerte werden nicht mehr in Rezeptzeilen angezeigt, bleiben aber fuer die Sortierung erhalten. Sortierbutton: Name A-Z / Schwierigkeit abwaerts / Schwierigkeit aufwaerts (Pfeilsymbole).

Version 0.5.9: Sortierbutton breiter, Pfeile als WoW-Texturen statt Schriftzeichen. Rezeptkategorien sind fuer eine spaetere Version geplant.

Version 0.6.0: Aufklappbare Rezeptkategorien, bevorzugt Original-API-Kategorien, sonst vorsichtige Zuordnung anhand von Rezeptnamen. Kochkunst-Buffkategorien erfordern noch zusaetzliche Daten. Bei Suche werden passende Kategorien automatisch geoeffnet.

Version 0.6.1: Ruestungssets werden vor Brust-Erkennung als Ruestungsverstaerkungen erkannt. Bei gecachten Itemdaten hat der echte Ausruestungsplatz Vorrang. Kochkunst: erste bekannte Original-Kategorien fuer eindeutig zugeordnete Gerichte, Rest bleibt sichtbar als noch nicht zugeordnet. Kein Neuscan erforderlich.

Version 0.6.4: Originale Rezeptkategorien werden beim erneuten Scan per GetRecipeInfo(categoryID) und GetCategoryInfo ermittelt und gespeichert. Kategorie wird auch bei neuer Synchronisation mitgesendet. Alte gespeicherte Rezepte brauchen einen neuen Scan.

Version 0.6.5: Sync-Test: Versandintervall 0.16s statt 0.32s, ACK-Wartezeit 55s, Reparaturanfragen mit groesserem Abstand, laengere Empfangsfenster. Protokoll SPB03 unveraendert. Zwei gleichzeitig eingeloggte Gildenmitglieder fuer Test erforderlich.


v0.7.0 Test: Materialicons (GetItemIcon zuerst; GetItemInfo Texturposition korrigiert), mehrzeilige Scan-Hinweise sichtbar.


v0.7.1 TEST: Fenster rechts unten per Ziehgriff vergroessern/verkleinern;
Spalten und Listen passen sich an. Materialbereich: bei mehr als einer Zeile
mit dem Mausrad ueber dem unteren Bereich blaettern. Berufsliste A-Z.
Dezente berufsspezifische WoW-Icon-Wasserzeichen im Rezeptbuch.
Fenstergroesse wird in SavedVariables gespeichert.

Hotfix v0.7.2: kompatible Resize-API-Abfrage fuer WoW-Clients.


v0.7.6 TEST: Erste Design-Etappe: dunklere warme Flaechen, Titelband,
staerkerer Goldrand und lokale Goldrahmen an den drei Spalten und Materialien.
Berufsillustrationen und Buttons werden in einer folgenden Etappe verfeinert.
Scan, Synchronisation, SavedVariables und Resize-Logik unveraendert.
Statische Lua-5.1-Syntaxpruefung; noch nicht im WoW-Client getestet.


v0.7.7 TEST: Zentrierter goldener Gildenname als Header. Alte Eckgrafiken
durch durchgehende, mehrlagige rechteckige Goldrahmen ersetzt.
Syntax statisch geprueft; WoW-Client-Test steht aus.


v0.7.8 TEST: Blizzard-Berufssymbole aus der Berufsliste als dezente
Hintergruende in Handwerker/Rezeptbuch (10 bzw. 7 Prozent Deckkraft).
Quadratische Darstellung mit dynamischer Groesse; Header/Rahmen aus 0.7.7.
Noch nicht im Spiel getestet.


v0.7.9 TEST: Groesserer goldener Ziehgriff mit Hover-Hinweis. Vor dem
ersten Resize wird die aktuelle Position in einen TOPLEFT-Anker umgewandelt;
Fenstergroesse und Bildschirmposition bleiben dabei erhalten.
Die Hinweiszeile unter dem Gildenheader entfaellt.
Bitte ersten Resize nach /reload, Min-/Max-Groesse und Wiedereroeffnen testen.
Statisch geprueft; der Fix muss im WoW-Client bestaetigt werden.


v0.7.10 HOTFIX: Variablenueberschattung im Goldrahmen behoben.
Vorher String statt Blau-Farbwert in SetVertexColor: UI-Aufbau brach ab.
Fehler in Lua-Laufzeit mit UI-Mocks reproduziert; korrigierte Rahmen bestehen.
Vollstaendige Lua-5.1-Syntaxpruefung bestanden. Kein WoW-Client-Test.


v0.7.11 TEST: Resize ueber relative Mausbewegung statt StartSizing.
Groesse bleibt beim Anklicken erhalten, UI-Skalierung wird beruecksichtigt.
Sync uebertraegt jetzt optionale Rezept-Skill-/Trivialitaetswerte.
Fuer Schwierigkeitssortierung beide Clients aktualisieren; Beruf beim
Handwerker im originalen Berufsfenster neu scannen und erneut synchronisieren.
Alte Pakete werden weiter gelesen. Keine erfundenen Schwierigkeitswerte.
WoW-Client-Test steht aus.

Zusaetzlich: Manuelle Namenszuordnung pro Spieler-GUID statt globalem
myFullName. Andere Charaktere behalten ihre Berufe. Leere temporaere
Berufserkennung ueberschreibt bestehende Daten nicht. Bereits verlorene
Daten bitte auf dem betroffenen Charakter neu scannen.
Lua-Laufzeittests mit UI-/API-Mocks fuer Resize, Sync und Charakterwechsel
sowie gesamte Lua-5.1-Syntaxpruefung bestanden; kein WoW-Client-Test.


v0.7.13 TEST: Client-Symbole pro Beruf gespeichert/synchronisiert,
Alchimie-Schreibweise ergaenzt. Dieselben Symbole fuer Liste/Hintergrund.
Sync-Sendeintervall 0.06 statt 0.10 Sekunden; ACK/Reparatur unveraendert.
Alle Korrekturen aus 0.7.11 enthalten. Beide Clients aktualisieren.
Noch nicht im WoW-Client getestet; bitte Laufzeit und Empfang pruefen.


v0.7.14 HOTFIX: Kein automatischer Rezeptscan ohne explizit gewaehlten
Beruf. Leere Rezeptscans duerfen bestehende Buecher niemals ersetzen.
Zeitweise fehlende Berufe mit gespeicherten Rezepten bleiben erhalten.
Alle Korrekturen aus 0.7.13 enthalten. Kein WoW-Client-Test.


v0.7.15 HOTFIX: Keine Speicherung/Synchronisation unter blossem Vornamen.
Vollstaendige Namen nur per Spieler-GUID-Zuordnung, nativer API oder
GUID-abgeglichenem Gildenroster; keine Praefix-Heuristik.
Bei fehlender Aufloesung je Charakter /spb name Vorname Nachname setzen.
Alte Kurznamens-Dubletten werden separat unter legacyAliases archiviert,
sobald passende vollstaendige Eintraege existieren. Keine geratenen Merges.
Alle bisherigen Korrekturen enthalten. Kein WoW-Client-Test.


v0.7.16: Dezente Versionsanzeige rechts oben neben dem Schliessen-Button.
Sonst gleicher Funktionsstand wie 0.7.15. Automatische Namensaufloesung
ohne manuellen Namen bleibt noch offen. Kein WoW-Client-Test.


v0.7.17 SYNC-HOTFIX: Separate priorisierte Warteschlange fuer Empfangs-
bestaetigungen und Reparaturanfragen. ACK-Nachfrage alle 4 Sekunden,
wenn Versand abgeschlossen: kompletter Empfaenger bestaetigt erneut.
Fehlende Pakete ab letztem Paket bzw. 1 Sekunde Ruhe, max. 8 Anfragen
je 2 Sekunden statt 8 Sekunden Ruhe/12 Sekunden Abstand.
Sendeintervall bleibt 0.06 Sekunden. Beide Clients aktualisieren.
Alte Clients ignorieren CHECK; Timeout/kompletter Retry bleibt erhalten.
Noch nicht im WoW-Client getestet.


v0.7.18 TEST: Alle sieben gewuenschten Herstellungsberufe in der Auswahl, auch vor
dem ersten Scan. Scan bevorzugt den tatsaechlich geoeffneten Beruf.
GetProfessions-Luecken brechen die Berufserkennung nicht mehr ab.
Enthaelt Sync-Hotfix aus 0.7.17. Beide Clients aktualisieren.
Namensaufloesung hat weiterhin den manuellen Fallback bei fehlender GUID-
Rosterzuordnung. Kein WoW-Client-Test.


v0.7.19 TEST: Scans benoetigen keinen manuellen Vollnamen mehr. Solange
der Name fehlt, Speicherung unter eindeutiger Spieler-GUID. Vollname
ueber native API, GUID-Roster oder unsichtbaren Spieler-Tooltip;
spaetere Umbenennung fuehrt Buecher desselben GUID zusammen.
Sync uebertraegt GUID optional; eigener Echo-Beginn kann Namen bestaetigen.
Alle sieben Berufe und Sync-Hotfix aus 0.7.18 enthalten.
Kein WoW-Client-Test.

Sync-Diagnose: Nach dem letzten Fehlversuch automatische Statistik.
Optional /spb syncstatus auf Sender UND Empfaenger zeigt eingegangene
Pakete und noch unvollstaendige Buecher. Nicht als bestaetigter Fix fuer
den im Spiel beobachteten ACK-Ausfall zu verstehen.



v0.7.20 DIAGNOSE: /spb syncstatus zeigt Prefix-Registrierung, Gildenstatus,
echte Sende-API-Aufrufe, blockierte Versuche, API-Fehler/Rueckgaben und
rohe CHAT_MSG_ADDON-Ereignisse vor Filterung. Kein bestaetigter Transportfix.
Beide Clients aktualisieren, /spb ping, kurz warten, /spb syncstatus.
Kein WoW-Client-Test.


v0.7.21 TEST: Sendetimer behaelt Restzeit, statt sie je Paket zu verwerfen.
Weiterhin hoechstens eine Nachricht pro Frame, keine Nachholschleifen.
Empfangsbestaetigung sofort sichtbar; internes 3s-Fenster bleibt bestehen.
Bestaetigung nennt Gesamtdauer, Erstversand und anschliessende Wartezeit
sowie Versuchsanzahl. Protokoll, 0.06s-Intervall, ACK-/Reparaturlogik gleich.
Keine gemessene Verbesserung im WoW-Client behauptet; Spieltest offen.


v0.7.22: X-Button rechts im Suchfeld, sichtbar bei nichtleerer Suche.
Ein Klick leert den Filter sofort; Fokus bleibt zum Weitertippen im Feld.
Sonst gleicher Funktionsstand wie 0.7.21. Kein WoW-Client-Test.


v0.8.0 TEST: Minimap-Button ausserhalb der Karte, Abstand abhaengig
von Kartengroesse und Skalierung. Ziehen speichert Winkel UND Abstand.
Icon und neuer symmetrischer Goldring zentriert; kein asymmetrischer
TrackingBorder-Atlas mehr. Alle Funktionen aus 0.7.22 enthalten.
Noch nicht im WoW-Client getestet.


v0.8.1 TEST: Button Gildendaten anfordern. Ein Klick fragt online
befindliche Gildenmitglieder an; aktuelle Addons senden automatisch
das eigene gespeicherte Rezeptbuch, zeitversetzt und ohne Neuscan.
Sperrzeit 60 Sekunden fuer Anfragen/automatische Antworten. Laufende
Uploads werden nicht abgebrochen. Offline-Charakterdaten werden nicht
weitergereicht. Alle Teilnehmer benoetigen 0.8.1 fuer automatische Antworten.
Optional /spb anfordern. Alle Funktionen aus 0.8.0 enthalten.
Noch nicht im WoW-Client getestet.


v0.8.2 TEST: Automatischer Hintergrundscan beim Oeffnen/Aktualisieren
des originalen Berufsfensters. Spucknapf-Fenster darf geschlossen bleiben.
Aktiver WoW-Beruf und vorhandene SkillLine-ID muessen uebereinstimmen.
Verzoegerung, stabile Rezeptliste und begrenzte Wiederholungen bis Daten
geladen. Fenster schliessen verwirft wartenden Scan. Kein Login-Rezeptscan.
Automatische Scans duerfen keine bekannten Rezepte entfernen und keine
fehlenden Rezeptdetails uebernehmen. Kein automatischer Versand.
Gildendaten anfordern sendet den aktualisierten lokalen Stand.
Noch nicht im WoW-Client getestet.


v0.8.3 TEST: Versionierter Gildencache fuer Offline-Handwerker.
Nur tatsaechliche lokale Aenderungen werden automatisch verteilt,
8 Sekunden gesammelt, maximal ein automatischer Buchversand pro Minute.
Ohne kuerzlich bestaetigten Cache-Empfaenger zunaechst nur kleiner Ping.
Gildendaten anfordern kann gespeicherte Buecher anderer Handwerker
liefern. Originalautor, Revision, Inhalt und Gilde bleiben erhalten.
Aeltere Kopien ersetzen neuere nicht. Empfangene Buecher loesen KEINEN
automatischen Weiterversand aus. Antworten sind zeitversetzt; bereits
gelieferte Versionen werden bei weiteren Antworten uebersprungen.
Neue Cache-Pakete werden nur von 0.8.3+ verstanden. Manuelles Synchroni-
sieren bleibt mit dem bisherigen Protokoll verfuegbar.
Start: Alle Teilnehmer updaten; jeder Handwerker oeffnet einmal seine
Berufe, waehrend ein weiterer aktueller Addon-Nutzer online ist.
Mindestens ein Empfaenger dieser Daten muss spaeter online sein.
Bestehende alte Buecher ohne Versions-/Gildennachweis werden nicht
blind weitergereicht. Keine externe Speicherung oder Hintergrundserver.
Neue Mehrclient-Laufzeittests bestanden; WoW-Client-Test steht aus.


v0.8.4 TEST: Minimap-Button als benanntes Minimap-Kind wieder fuer
Button-Sammler erkennbar. Nach Uebernahme durch ein Sammelfenster
keine eigene Positionierung oder eigenes Ziehen; ohne Sammler weiterhin
aussen positionierbar mit gespeichertem Abstand. Skalierung angepasst.
Mit den Erkennungsregeln der lokal installierten EllesmereUI abgeglichen.
Kein LibDBIcon-Zwang, keine Aenderung an EllesmereUI-Dateien.
Alle Funktionen aus 0.8.3 enthalten; WoW-Client-Test steht aus.
