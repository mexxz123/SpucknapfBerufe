SpucknapfBerufe v0.6.9 (Testversion)

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
