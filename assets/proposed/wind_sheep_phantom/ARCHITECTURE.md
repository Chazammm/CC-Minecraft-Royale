# Aktuelle CC-Grafikarchitektur

Untersucht am 17.10.2026, Basis `main` / `e80ad6919b7eb21a1d3464290d177ee3ab210eee`. Der Stand enthält 27 aktive Karten und sechs Evolutionen. Die sechs vorhandenen Worktrees wurden beibehalten; die neue Arbeit liegt auf einem eigenen Konzept-Branch. Offene Asset-/Konzept-PRs #20 und #21 sind keine produktiven Karten.

## Daten und Auswahl

- `src/pixel_arena.lua`: 35 eingebaute Basissprites einschließlich Evolutionsvarianten, beschworener Einheiten und Türme; die Zahl ist keine aktuelle Kartenanzahl. Hinzu kommen die externen registrierten Mob-Assets.
- `src/mob_assets.lua`: Dispatch und kurze Frame-Auswahl für Ravager Rider, Baby Ender Dragon, Minoshroom und Hero Spider. Flugzyklen werden aus `previewSequences` gelesen.
- `src/assets/custom_mobs/dispatch.lua`: registrierte King-Frog-/Nether-Worm-Posen anhand von Bewegung, Angriff, Zunge und Auftauchen.
- `src/assets/custom_mobs/frames.lua`: native Palettenzeilen. PNGs/GIFs werden im CC-Spiel nicht geladen.
- `docs/SPRITE_REVAMP.md` beschreibt die früheren 35 Basismodelle; seine historischen Test- und Größenangaben sind keine vollständige Inventur des aktuellen externen Rosters.

Die aktuellen Tests erlauben kompakte Footprints bis 16×18. Dieses Paket bleibt innerhalb dieser Grenze; es gibt keine Vergrößerung produktiver Units. Die gemeinsame Prototyp-Leinwand ist 16×18. Das Schaf hat seinen Bodenbezug bei `(8,17)`, Breeze und Phantom einen entsprechenden festen Schwebebezug. Diese Anker sind Grafikmetadaten, keine Hitboxen.

## Vorhandene und geplante Nachbarn

Aktiv sind unter anderem Ravager Rider (Gebäudefront plus Schütze), Baby Ender Dragon (fliegender Splash-Support), Minoshroom (schwerer Melee), King Frog (Pull) und Nether Worm (Boden-Ambush). Die sechs aktiven Evolutionen sind Charged Creeper, Mega Mite, Diamond Golem, Ghast Portal, Hero Spider und Emerald Bank.

Die offenen Pakete #20/#21 enthalten weitere Asset-/Konzeptarbeit: Piglich, Martian Raptor, Cyclops, Wilden Chimera und Sculk Behemoth sowie Netherite Crab/Ore Centipede. Daraus wird keine zusätzliche aktive Karte abgeleitet. King Frog und Nether Worm sind bereits als gewählter Teil integriert; die anderen Entwürfe bleiben getrennt. Breeze/Sheep/Phantom erhalten hier keine Evolution.

## Palette und PixelBox

| Token | CC-Farbe | Token | CC-Farbe |
|---|---|---|---|
| W | white | O | orange |
| M | magenta | A | lightBlue |
| Y | yellow | L | lime |
| I | pink | D | gray |
| S | lightGray | C | cyan |
| P | purple | B | blue |
| N | brown | G | green |
| R | red | K | black |

`.` ist transparent. Das produktive Basissystem kennt außerdem `T` für Teamfarben; diese Prototypen benötigen kein zusätzliches Token. Die Vorschauen verwenden die unveränderten Standard-RGB-Werte der CC-Palette. Benutzerdefinierte Monitorpaletten können das physische Erscheinungsbild ändern.

`lib/pixelbox_lite.lua` setzt **2×3 logische Pixel in ein Terminalzeichen mit zwei Farben** um. Native Raster und Terminalausgabe sind deshalb verschiedene Qualitätsstufen. Drei oder mehr Farben im selben Block können Details ersetzen; Gleichstände können zwischen Host-Lua-Versionen anders ausfallen. Helm, Maulgriff, Augen und Phantom-Brust wurden entsprechend gesetzt, statt den Encoder zu verändern.

Der Renderer richtet Sprite-Ursprünge am 2×3-Raster aus. Die Windrotation ist über wenige feste Posen angelegt, die Schafausrüstung bleibt in den Laufposen in stabilen Farbbändern, die Phantom-Augen liegen auf bewusst gruppierten Pixeln. Farbeffekte sind keine Alphablends: Transparenz ist an/aus, Licht entsteht durch feste hellere Palettenpixel.

## Monitore und Timing

`config.lua` empfiehlt mindestens 45×42 Terminalzeichen bei `TEXT_SCALE=0.5`. `src/render.lua:layoutFor` reserviert zwei Statuszeilen und sechs bis acht Handzeilen. Die Kampffläche ist kleiner als der Gesamtmonitor:

| Gesamtmonitor | Arena in Zeichen | Logische Kampfpixel |
|---|---|---|
| 45×42 | 45×34 | 90×102 |
| 51×42 | 51×34 | 102×102 |
| 57×62 | 57×52 | 114×156 |

Das Werkzeug fragt diese Rechtecke aus dem aktuellen Layout ab. Es setzt nicht einfach den ganzen Monitor als Arena voraus. Ein 16×18-Sprite bleibt dabei 16×18, unabhängig von der Weltprojektion und Monitorgröße.

Der konfigurierte Spieltakt beträgt 0,10 Sekunden. Alle exportierten Clipzeiten liegen auf 100-ms-Schritten, das kürzeste Bild dauert 100 ms. Der Phantom-Lauf-/Flugzyklus hat vier 100-ms-Posen. Der interaktive Viewer erlaubt langsamere/schnellere Betrachtung; seine Geschwindigkeitsregelung ist keine Behauptung einer höheren produktiven Framerate.

## Bewegung, Team und Feedback

Die Welt ist 100×160. Spieler 2 sieht die um 180 Grad gespiegelte Weltprojektion. Das produktive normale Unit-Raster wird dabei nicht automatisch entsprechend der Bewegungsrichtung horizontal gespiegelt. Die links/rechts gerichtete Schafansicht wird **nur in diesem Preview-Werkzeug** erprobt. Eine spätere Integration braucht dafür eine bewusste Entscheidung.

Die Vorschauen rufen die vorhandene HP-Bar-Funktion auf: eigene Einheit hellblau, Gegner rot. Die Fell-, Helm- und Flügelfarben werden nicht als Teamfarbe umgefärbt. Trefferframes zeigen denselben weißen Flash-Stil wie das Spiel. Todesposen werden ohne HP-Bar gezeigt; die letzte Vorschau ist die tatsächlich wieder freigelegte Arena ohne Sprite oder Bar.

Aktuell existieren Projektile, prozedurale Effekte, native Effekt-Raster, visuelle Angriffstimer, HP-Overlays und Damage-Flash. Eine allgemeine lebende Unit-Death-Timeline, Kopf-Schwertführung, Knockback-Fähigkeit und Phantom-Sturzflug sind durch diese Grafikdateien **nicht** implementiert.

## Deckbuilder

`src/render.lua:drawCard` zeichnet Namen, Emerald-Kosten, Auswahl-/Bezahlbarkeitshintergrund und Evo-Hinweise als Text. Es zeichnet derzeit keine Portrait-PNGs und keine dieser Icons. Die vorbereiteten Icons sind echte transparente native 12×12-Raster; ihre PixelBox-Prüfung nutzt einen CC-grauen Hintergrund.

Die 12×12-Icons benötigen sechs Terminalspalten und vier Terminalzeilen. Mit einem kompakten Namen (`ADV.SHEEP`) und einer Kostenzeile ergibt das eine optionale Sechs-Zeilen-Handzelle. Die aktuelle fünfzeilige Sammlung und zusätzliche Evo-/Statushinweise benötigen eine eigene Layoutentscheidung. Die früher geprüften 8×9-Entwürfe wurden wegen verlorener Flügel-/Ausrüstungsmerkmale verworfen; Kampfsprites bleiben unverändert 16×18. Es gibt keine geänderte Deckansicht.

## Isolierte Preview-Pipeline

`tools/capture.lua` liest Renderer-Funktionen über Debug-Upvalues auf dem Host. Es verwendet das unveränderte Arena-Layout und den echten PixelBox-Encoder. Die neuen Zeilen werden ausschließlich in eine temporäre Vorschau-Canvas gemalt. **Keine Einträge werden in `SPRITES`, `cards.list` oder den Dispatch geschrieben.** Vorher-/Nachher-Vergleiche prüfen deren unveränderten Inhalt.

Die Arenabilder enthalten sechs bestehende Referenz-Units plus sechs Konzept-Overlays. Sie zeigen Posen und Effekte in einer **gestellten** Gruppenszene. Es läuft kein Combat, keine Zielwahl, kein Knockback und keine Sturzflug-Physik. Die Overlay-Reihenfolge ist keine fertige produktive Depth-Sort-Integration. Beide Betrachtungsseiten sind separat erfasst.

`tools/previews.py` dekodiert die tatsächlich ausgegebenen Terminalzeichen/Farbpaare. Alle Rasterbilder, Sheets, GIFs und der HTML-Viewer stammen aus diesen Captures oder den nativen Zeilen. Beschriftungen außerhalb der PixelBox-Ausschnitte sind Vorschau-Beschriftungen, keine zusätzlichen CC-Grafikfarben.

## Aufwand und Grenzen

Die Produktionskosten dieses Pakets sind null: kein produktiver Import, kein Installer-Eintrag, keine zusätzlichen Match-Updates. Später kostet ein dichtes 16×18-Raster höchstens 288 Pixelpositionen vor Transparenz-Auslassung; separate 16×12-Effekte haben höchstens 192 Positionen. Das sind Datenmengen, keine gemessenen Renderzeiten.

Stationäre Canvas-/Frame-Caches und Dirty-Row-Ausgabe existieren. Ein Clipwechsel muss später in deren bestehenden visuellen Zustandsweg integriert werden; eigenes Zeichnen neben diesem Weg wäre fehleranfällig. Die Preview prüft wiederholte identische Ausgabe sowie rückstandsfreies Entfernen, liefert aber keinen Durchsatznachweis für viele animierte Units auf Minecraft-Hardware.

**Physische CC:Tweaked-/ATM-Monitore wurden nicht getestet.** Quadratische logische Pixel in den PNGs bilden weder alle realen Terminalzell-Proportionen noch Minecraft-Netzwerk-/Peripheral-Latenzen ab.
