# Validierung: statische LÖVE-Sprites

Ausgeführt am 17.10.2026 auf dem Host. Dies ist der Nachtrag zum separaten CC-Konzeptpaket, kein neuer vollständiger Gameplay-Audit.

| Prüfung | Status | Nachweis |
|---|---|---|
| Drei PNGs lesbar, RGBA, nicht leer | PASS | Pillow-PNG-Verifikation und Pixelprüfung in `tools/package.py --check` |
| Canvas und Anker | PASS | Zwei 256×256, Phantom 320×256; nullbasierter Anker jeweils (Breite/2, 240) |
| Transparenz | PASS | Ausschließlich Alpha 0/255, vollständig transparente Pixel haben RGB 0/0/0 |
| Palette und sichtbare Pixel | PASS | 48 sichtbare RGB-Farben je Sprite, jeweils mehr als 8.000 sichtbare Pixel; Ist-Werte in `index.json` |
| Ränder und Quellzuschnitt | PASS | Mindestens 16 transparente Randpixel; opake Quellfigur berührt keine Schnittgrenze |
| Visuelle Kontrolle | REVIEWED ON HOST | Alle drei tatsächlichen Einzel-PNGs betrachtet; komplettes Breeze, seitliches Maulschwert, intakte Phantom-Flügel |
| Vorschau zeigt echte Dateien | PASS | Neu komponiertes Raster stimmt pixelgenau mit `previews/roster.png` überein |
| Wiederholter Export | PASS | Alle drei PNG-Hashes vor/nach erneutem `tools/export.sh` identisch; `validation.json` |
| Metadaten unter Lua 5.2 und 5.4 | PASS | Beide Interpreter luden `index.lua`; drei Dateien, Maße, Anker, Pose und Nearest-Filter geprüft |
| Bestehende CC-Vorschauen | PASS | `../tools/previews.py --check`: tatsächliche native PNG/GIF/HTML-Vorschauen und vorherige Cross-Lua-Captures unverändert konsistent |
| LÖVE-GPU/Ingame | NOT RUN | Kein `love`-Programm und kein separates LÖVE-Spielprojekt verfügbar |
| Vollständige Gameplay-Test-Suite | NOT RERUN | Ausschließlich isolierte statische Bilder, Asset-Werkzeuge und Dokumentation geändert |
| Neue LÖVE-Animationen | NOT IMPLEMENTED | Ein statisches Bild pro Figur, keine zusätzlichen Animationsframes behauptet |

`source/approved_concept.png` bewahrt die im Gespräch freigegebene Ansicht. `source/sprite_master.png` ist der mit dem Bildwerkzeug bereinigte Exportmaster. Die Host-Sichtprüfung und die Freigabe des Konzepts ersetzen keine spätere Beurteilung der tatsächlichen Ingame-Größe und Animation.

Reproduktion und ZIP-Aufbau: siehe `README.md`. Die PNG-Hashes und tatsächlichen sichtbaren Grenzen sind in `index.json` gespeichert. Ein Paketcheck prüft die Dateien neu; er gilt nur bei erfolgreicher Ausführung als PASS.
