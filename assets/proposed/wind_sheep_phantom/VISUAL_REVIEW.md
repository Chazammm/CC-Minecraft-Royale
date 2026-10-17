# Visuelle Bewertung

Stand: 17.10.2026. Bewertung durch Sichtprüfung der nativen Raster, dekodierter PixelBox-Bilder, Frame-Sheets, Angriffsvorschauen, beider Arenaansichten und des Browser-Viewers. **Vorläufige Designbewertungen**, keine Nutzerfreigabe und kein physischer Monitortest.

## Gewichtung und Rangfolge

Die ersten sechs Kriterien sind visuell und zählen zusammen 85 %. Technik, Gameplay-Mehrwert und Balancefähigkeit zählen je 5 %. Die Gesamtnote ist die gewichtete Summe; höhere Werte sind besser.

| Kriterium | Gewicht | Breeze | Adventure Sheep | Phantom |
|---|---:|---:|---:|---:|
| Spritequalität | 20 % | 8 | 7 | 8 |
| Wiedererkennbarkeit | 15 % | 8 | 8 | 8 |
| Animationen | 15 % | 8 | 7 | 8 |
| Lesbarkeit auf kleinen virtuellen Monitoren | 15 % | 8 | 7 | 7 |
| Visuelle Besonderheit | 10 % | 8 | 9 | 8 |
| Passung zum bisherigen CC-Stil | 10 % | 8 | 8 | 8 |
| Technische Umsetzbarkeit des Gesamtkonzepts | 5 % | 7 | 9 | 6 |
| Gameplay-Mehrwert | 5 % | 8 | 7 | 8 |
| Balancefähigkeit | 5 % | 7 | 8 | 6 |
| **Gewichtete Gesamtnote** | **100 %** | **7,90** | **7,60** | **7,65** |

Die erste visuelle Rangfolge ist Breeze, Phantom, Adventure Sheep. Die empfohlene spätere **Implementierungsreihenfolge** ist trotzdem Sheep, Breeze, Phantom: Sie richtet sich nach Systemrisiko, nicht allein nach der Grafiknote.

## Breeze

**Stärken:** Graublauer Würfelkopf und helle Augen bleiben lesbar. Drei untereinander versetzte Windbänder unterscheiden ihn von Blaze, Snow Golem und Phantom. Rotation, leichte Schwebeverschiebung, zusammengezogener Windup und ausgestoßener Wind haben unterschiedliche Silhouetten. Die Todesbilder lösen Kopf und Wind auf, statt eine gewöhnliche humanoide Fallpose zu kopieren.

**Grenzen:** Dünne Spiralenden verlieren je nach Untergrund einzelne Schattierungsdetails. Bei dichter Überlagerung mit silbernem Schwertbogen können die hellen Effekte zusammenlaufen. Die graublaue Stirn ist absichtlich durch eine graue Oberkante von der hellblauen HP-Bar getrennt.

**Nächste sinnvolle Verbesserung nach Feedback:** Gegen dunkle Gebäude und auf echten Monitorzellen prüfen, ob zwei kräftigere Windbänder besser lesbar sind als drei dünnere. Die Angriffsrichtung lieber durch eine kurze klare Bewegungsfolge als durch weitere Partikel verdeutlichen.

## Adventure Sheep

**Stärken:** Die Seiten-/Dreiviertelansicht zeigt einen horizontalen weißen Wollkörper mit vier gestaffelten Beinen. Der Helm nutzt Cyan plus hellblaue Reflexe. Der schwarze Seitenblick bleibt erhalten. Das Schwert sitzt am Maul, mit dunklerem Griff/Parierstange und heller, quer vorstehender Klinge. Die Kopfrücknahme und der anschließende tiefe Schwertschwung kommen ohne humanoide Hände aus.

**Warum diese Variante:** In der frontlastigen Alternative gerieten Wolle, Gesicht und querliegendes Schwert enger zusammen. Im nativen Raster war der Helm noch präsent, in der PixelBox-Ausgabe aber die Kopf-/Wolltrennung schwächer. Die gewählte Seitenansicht ist für Körperform und Schwertführung klarer. Die echte verworfene Variante bleibt in `sheep_variants.png` sichtbar.

**Grenzen:** Das Maulschwert bleibt bei 16 Pixeln Gesamtbreite kurz. In Gruppen kann es als heller Fortsatz erscheinen, bevor der Schwertbogen die Aktion erklärt. Die vier Beine überlagern sich in einzelnen laufenden Terminalblöcken teilweise. Eine noch größere Wolle-/Gesichts-/Schwertdetailmenge würde diese Trennung eher verschlechtern.

**Nächste sinnvolle Verbesserung nach Feedback:** Kopfgröße und Klingenprofil am physischen Mindestmonitor vergleichen. Falls die Klinge zu wenig nach Eisenschwert aussieht, zuerst Parierstange und Endpixel verändern, nicht den ganzen Sprite vergrößern. Keine humanoide Oberkörperlösung als Ausweg.

**Mechanische Ehrlichkeit:** Zombie und Wither Skeleton decken normalen Medium-Melee bereits ab. Sheep ist keine völlig neue Mechanik. Die vorgeschlagene Abgrenzung ist der teurere, haltbarere Duellant mit weniger DPS; ob dieser eigene Deckplatz sinnvoll ist, muss ein späterer echter Playtest zeigen. Eine passive Fähigkeit nur zur künstlichen Einzigartigkeit ist nicht empfohlen.

## Phantom

**Stärken:** Breite blaue Winkel-Flügel, helle Unterseite und deutlich grüne Augen unterscheiden ihn von den kleineren violetten Bats und den gelben Blaze-Stäben. Aufschlag, ausgestrecktes Gleiten, Abschlag, eng angelegter Dive und Wiederöffnen der Flügel ergeben eine klare Flugfolge. Beim Tod erlöschen die grünen Augen.

**Grenzen:** Der Dive ist im nativen 16×18-Rahmen absichtlich schmal und wirkt für einen kurzen Moment fast kopfbetont. Dünne Flügelrippen werden reduziert. Ein gespiegelter Weltblick ist keine fertige richtungsabhängige Phantom-Animation.

**Nächste sinnvolle Verbesserung nach Feedback:** Die eng angelegten Flügel im Dive mit einem zusätzlichen dunklen Rand oder einer anderen Schulterbreite prüfen, bevor zusätzliche Frames ergänzt werden. Die Augen nicht weiter vergrößern; sonst verdrängen sie die Phantom-Anatomie. Die Zielpriorität muss später erklärbar bleiben, sonst vermittelt eine gute Animation falsche taktische Erwartungen.

## Gemeinsame Entscheidungen

- Keine Hochskalierung winziger CC-Raster als angebliche High-Res-Master. Die 6×/8×-Ansichten sind ausdrücklich Vergrößerungen echter nativer Pixel.
- Keine neue Palette, kein Anti-Aliasing in den nativen Assets und keine eingebrannten Hintergründe in den transparenten Sprite-PNGs.
- Keine Änderungen an bestehenden Live-Sprites zur optischen Angleichung.
- Die Grafiknoten beschreiben die aktuellen **Prototypen**. Das Paket wird zur Beurteilung vorgelegt und nicht als freigegebene Produktionskunst bezeichnet.
