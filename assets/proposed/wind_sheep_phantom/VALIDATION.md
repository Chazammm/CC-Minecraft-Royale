# Validierung und Nachweise

Stand 17.10.2026, Basis `e80ad6919b7eb21a1d3464290d177ee3ab210eee`. Alle PASS-Angaben beziehen sich auf tatsächlich ausgeführte Host-Prüfungen. Neu vorgeschlagene Karten wurden nicht produktiv registriert oder in Matches simuliert.

| Bereich | Status | Tatsächlicher Umfang | Nachweis |
|---|---|---|---|
| Neue Lua-Daten und Capture-Werkzeug | PASS | Acht Lua-Dateien je unter Lua 5.2/5.4 syntaktisch geprüft | `evidence/syntax.json` |
| Native Frames/Palette/Zeilen | PASS | 37 Unit-Posen, sieben Effekte, drei Icons und zwei Schafvarianten | `evidence/captures52.json`, `captures54.json` |
| Probe-Matrix | PASS | Je Lua 209 gezählte Pose-/Größen-/Effekt-/Showcase-Fälle, elf Zusatz-Captures, acht Szenen: 228 Proben pro Version | gleiche Captures |
| Assertion-Zähler | PASS | Je Lua 112.053 Checks; enthält viele wiederholte Pixel-/Zeilenprüfungen, keine 112.053 unabhängigen Gameplay-Fälle | Capture-Feld `checks` |
| Monitore/Ansichten | PASS auf Host | Posen bei 51×42/P1 sowie 45×42 und 57×62/P1/P2; zusätzliche Team-/Mirror-Proben und Szenen für beide Betrachter | Capture-Matrix im Werkzeug |
| Echte PixelBox-Ausgabe | PASS auf Host | Tatsächliche Terminalzeichen, Vorder-/Hintergrundfarben; native Canvas separat geprüft | `terminalCrop`, Pipeline-Marker |
| Cross-Lua | PASS | Die gesamten erfassten Daten sind unter Lua 5.2 und 5.4 identisch, einschließlich der gestellten Szenen | `tools/previews.py --check` |
| Export und Transparenz | PASS | 40 nichtleere RGBA-PNGs: 37 native Posen plus drei Icons; Alpha nur 0/255 | `previews/frames/`, `icons/` |
| Sheets und Animationen | PASS | Alle komponierten PNGs, 20 GIFs mit exakten Framepixeln/-zeiten und der HTML-Inhalt geprüft | `tools/previews.py --check` |
| Entfernung/Dirty Rows | PASS im Preview | Gleiche Overlay-Ausgabe sendet keine zusätzlichen Zeilen; Entfernen stellt den tatsächlichen Hintergrund wieder her | Capture-Assertions und `clearedCrop` |
| Browser-Viewer | PASS | Drei Karten, sechs Aktionen je Karte, automatischer Fortschritt, Pause, Scrubbing, Bilddecodierung, ganzzahliges 6×, Neustart, Tod/Entfernung, Tempo | `evidence/browser_check.json` |
| Bestehende Lua-Suites | PASS | 52 entdeckte Suites je Lua 5.2/5.4: 104 erfolgreiche Ausführungen | `evidence/regressions.json` |
| Bestehende Python-Tests | PASS | Acht tatsächliche Tests | `evidence/python_regressions.log` |
| Bestehende Dateien/Imports | PASS | Ausschließlich neue Dateien unter diesem Konzeptpfad; keine Änderung an Live-Registry, Gameplay, Tests, Installer oder Live-Sprites | `evidence/scope_guard.json`, PR-Diff |
| Reproduzierbare Exporte | PASS | Native Lua-Dateien sowie PNG/GIF/HTML/Icons nach erneutem Build bytegleich | `evidence/reproducibility.json` |
| Sheep-1v1 | MODELED | Zwei nominale In-Range-Rechnungen, je 18 deterministische Timingfälle und insgesamt 54 Stat-Sensitivitätsfälle | `evidence/balance_model.json` |
| Wind-/Slow-Budget | MODELED | Alle aktuellen normalen Boden-Kartenstatlinien mit normaler und Hero-Web-Bewegung: höchstens eine Sekunde skalare Rücklaufzeit; kein Pathfinding-Test | `windScalarSafety` im Rechenmodell |
| Neue-Karten-Engine-/Bot-Matches | NOT RUN | Ohne Implementierung/Registrierung nicht vorhanden; diese ist ausdrücklich nicht freigegeben | keine erfundenen Matchreports |
| Neue Fähigkeiten | NOT IMPLEMENTED | Breeze-Knockback, Phantom-Priorität/Dive und Sheep-Gameplay stehen nur im Konzept | `GAMEPLAY.md` |
| Physischer CC-Monitor/ATM | UNVERIFIED HARDWARE | Keine Minecraft-/Peripheral-Hardware vorhanden | keine Hardware-Benchmarkbehauptung |
| LÖVE-Portierung | NOT APPLICABLE | In dieser CC-zentrierten Phase nicht begonnen | keine neuen LÖVE-Dateien |

## Verifikationstiefe

Die Probe lädt die neuen Raster in einem eigenen Host-Prozess. Sie registriert keine neue Karte und fügt keinen produktiven Sprite-Key ein. Vorher und nachher werden die vollständige Live-Sprite-Tabelle und `cards.list` auf Gleichheit geprüft. Das Testwerkzeug malt die Prototypen nur in seine temporäre Canvas und verwendet anschließend den echten PixelBox-Encoder. Die Auswahl der neuen Posen ist ein isolierter Vorschauablauf, kein Beweis einer späteren Live-Dispatch-Integration.

Der Browser-Check lädt den exakten eigenständigen HTML-Inhalt über Chromiums `Page.setDocumentContent` und prüft die tatsächliche DOM-/Bild-/Kontrollfunktion. Die Proben sind Browser-Tests; sie sind kein CC-Spiel und kein Nachweis einer höheren CC-Framerate. Todesclips enthalten einen echten leeren Hintergrund-Capture nach Entfernung statt einer unabhängig gemalten Abblendung.

Der Scope-Guard vergleicht mit dem genannten Basiscommit. Alle davor verfolgten Dateien bleiben unverändert. `MANIFEST.json` inventarisiert die neuen Paketdateien mit SHA-256. Es ist kein neuer produktiver Installer-Manifest-Eintrag notwendig, weil das Spiel diese Host-Dateien nicht importiert.

Die bestehende GitHub-CI prüft weiterhin den produktiven Bestand. Da keine Workflow-Datei verändert wird, sind die neuen Konzept-Werkzeuge **nicht automatisch neue CI-Gates**. Ihre lokalen ausgeführten Nachweise liegen im Paket; ein grüner allgemeiner CI-Lauf allein würde ihre visuelle Qualität nicht beweisen.

## Reproduzieren

Die vollständigen Generierungsbefehle stehen in `README.md`. Ergänzend:

```sh
python3 assets/proposed/wind_sheep_phantom/tools/manifest.py --check
node assets/proposed/wind_sheep_phantom/tools/check_viewer.mjs
```

Nach einem bewusst geänderten Asset erst Captures/Vorschauen und Nachweise neu erzeugen und prüfen; anschließend das Inhaltsmanifest mit `tools/manifest.py` aktualisieren. Ein veraltetes Manifest wird vom Check abgewiesen.

## Offene visuelle und technische Punkte

- Schwertprofil und Beine des Adventure Sheep bei realen Mindestmonitor-Zellproportionen beurteilen.
- Windpartikel und Phantom-Dive in dichten echten Kämpfen auf Überlagerung testen, sobald eine Implementierung ausdrücklich freigegeben wird.
- Produktive Asset-Auswahl, Death-Effects, Bewegungs-/Zielprioritätsmechaniken und Bot-Bewertung sind hier nicht fertig integriert.
- Die 4E-Kosten des Sheep sind ein konservativer Startvorschlag; das reine Duellmodell beweist keine Meta-/Kosteneffizienz.
- Physische Leistung und visuelle Freigabe durch den Nutzer bleiben offen.
