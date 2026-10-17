# CC Royale – Visual-first Card Concepts

**Breeze · Adventure Sheep · Phantom**  
Basis: `main`, `e80ad6919b7eb21a1d3464290d177ee3ab210eee`, untersucht am 17.10.2026.  
**Ergebnis: isoliertes Asset- und Konzeptpaket. Keine Karte registriert und keine Spiellogik implementiert.**

## 1. Aktuelle Grafikarchitektur

Das Spiel verwendet native Lua-Palettenzeilen, die externe Mob-Dispatches und 35 ältere Basissprites auswählen. Die aktuelle Registry enthält 27 Karten und sechs Evolutionen. PixelBox macht aus je 2×3 logischen Pixeln ein Terminalzeichen mit zwei Farben. Die tatsächlichen getesteten Monitorlayouts liefern 90×102, 102×102 beziehungsweise 114×156 logische Kampfpixel; Status und Hand sind abgezogen.

Die Prototypen bleiben bei 16×18, Icons bei 12×12. Der vorhandene 100-ms-Takt wird in den Clipzeiten eingehalten. Die Live-Deckansicht ist textbasiert; die Icon-Vorschläge erfordern später eine gesonderte UI-Entscheidung. Das Werkzeug verwendet den echten Encoder auf einer isolierten Canvas und verändert weder Registry noch Sprite-Tabelle. Details: [ARCHITECTURE.md](ARCHITECTURE.md).

## 2. Vollständige Visual Concepts

![Native und tatsächliche PixelBox-Sprites](previews/roster.png)

| Karte | Kernbild | Sichtbare Material-/Formmerkmale | Native Unit-Posen |
|---|---|---|---:|
| Breeze | Graublauer schwebender Kopf über rotierenden Windbändern | Helle Augen, graue Stirnkante, komprimierter Windkern, versetzte Spiralen | 12 |
| Adventure Sheep | Weißer vierbeiniger Erkunder mit Diamanthelm und Maulschwert | Wollflecken, Cyanhelm, hellblauer Glanz, dunkler Griff, silberne Klinge | 12 |
| Phantom | Blauer Flugjäger mit breiten Flügeln und grünen Augen | Winkelige Flügelrippen, helle Unterseite, enger Dive, erlöschende Augen im Tod | 13 |

Adventure Sheep wurde ungewöhnlich intelligent geboren. Die endlosen Grasflächen der Plains genügten ihm irgendwann nicht mehr: Es setzte einen glänzenden Diamanthelm auf, nahm ein Eisenschwert ins Maul und zog los. Es bleibt ein echtes Schaf; Mut und Abenteuerlust werden durch Haltung und Ausrüstung gezeigt, nicht durch einen menschlichen Körper.

Die Minecraft-Anatomie wurde gegen aktuelle Wiki-Abbildungen von Breeze, Phantom und weißem Schaf geprüft; URLs und Abrufdatum stehen in `evidence/references.json`. Die Bilder selbst werden nicht als eigene Assets mitgeliefert. Der Helm und das Maulschwert sind das originale Adventure-Sheep-Design dieses Pakets.

## 3. Sheets, Icons und reale Vorschauen

- [Breeze-Sheet](previews/breeze_sheet.png), [Schaf-Sheet](previews/adventure_sheep_sheet.png), [Phantom-Sheet](previews/phantom_sheet.png).
- [Schafvarianten im echten PixelBox-Vergleich](previews/sheep_variants.png).
- [Drei Deck-Icon-Vorschläge](previews/deck_icons.png), transparente Icon-PNGs im Ordner `icons/`.
- [Native Effekte](previews/effects.png).
- [Arena aus Sicht 1](previews/arena_p1.png) und [Sicht 2](previews/arena_p2.png).
- [Interaktiver Offline-Viewer](previews/review.html): Datei herunterladen/öffnen, Animation wählen, pausieren, Einzelbilder vergleichen, Tempo ändern. Bilddarstellung mit ganzzahliger 6×-Skalierung.

Alle Sheets zeigen die tatsächlichen Zeilen oder dekodierte Terminal-Captures. Die Arena ist eine gestellte 12-Figuren-Szene, kein neues simuliertes Match. Die zwei Blickrichtungen sind separat erfasst. Außerhalb der CC-Ausschnitte stehen normale Vorschau-Beschriftungen.

## 4. Animationen und Effekte

20 GIFs liegen vor: je Karte Idle, Bewegung, Angriff, Treffer, Tod und eine Angriffsschau; außerdem zwei Arena-Loops. Der Viewer bietet sechs wählbare Aktionen je Karte. Alle exportierten Framezeiten sind mindestens 100 ms und Vielfache des Spieltakts.

| Karte | Idle / Bewegung | Windup / Treffer | Hit / Death |
|---|---|---|---|
| Breeze | Windbänder wechseln ihre Phase, leichte Schwebeverschiebung | Windkern wird enger und heller, separater zweiphasiger Windstoß | Weißer Flash, auseinanderfallender Kopf/Wind, danach echte freie Hintergrund-Capture |
| Sheep | Kleine Woll-/Körperänderung, wechselnde vierbeinige Schrittstellung | Kopf zieht zurück, seitlich-tiefer Maulschwertschlag, silberner Bogen | Recoil/Flash, Einknicken, seitliches Zusammenfallen, Restpixel und Entfernen |
| Phantom | Flügel oben, mittig, unten und ausgestreckt | Sichtbare Vorbereitung, schmaler Dive, Öffnen zum Schlag, Recovery | Weißer Flash, schlaffe Flügel/erloschene Augen, Partikel und Entfernen |

[Windstoß](previews/breeze_showcase.gif) · [Maulschwert](previews/adventure_sheep_showcase.gif) · [Sturzflug](previews/phantom_showcase.gif) · [Gestellte Gruppenansicht](previews/arena_p1.gif).

Angriffsposen und Effekte lösen keine Treffer aus. Die GIFs enthalten Vor-/Nachlauf zur Betrachtung und sind kein implementierter Attack-Cooldown. Todesclips blenden die HP-Bar bei den Todesposen aus und enden mit einer rückstandsfreien Hintergrundaufnahme. GIFs wiederholen sich zur Begutachtung; der Viewer hält nach dem Entfernen an.

## 5. Taktische Rollen

**Breeze:** Defensive Positionskontrolle auf einem primären Bodenziel. Jeder dritte Schuss kann einmal zurückstoßen; gemeinsame Opfer-Immunität, ein Weg von höchstens vier Einheiten und einer Sekunde modifizierter Laufstrecke sowie Terrain-/Brückenauswahlprüfungen sollen Push-Schleifen und River-Sprünge verhindern. Die Sicherheitsregeln sind noch keine getestete Engine-Implementierung. Keine Gebäudeverschiebung und kein Anti-Air. Abgrenzung zu Snow Golem (Slow/Anti-Air), King Frog (Pull) und Hero Spider (starker Debuff).

**Adventure Sheep:** Einfacher, verlässlicher Nahkampfduellant. Mehr HP zum höheren Preis, geringere DPS als die beiden 3E-Vergleichskarten. Keine passive Fähigkeit empfohlen. Die Rolle überschneidet sich mit vorhandenem Melee; die optische Identität und der konkrete 4E-Stat-Tradeoff müssen einen zusätzlichen Deckplatz rechtfertigen.

**Phantom:** Einzelner Nahkampf-Flieger gegen lokal erreichbare Ranged-Units. Nur bei neuer legaler Zielsuche priorisieren, niemals intakten Lock brechen. Begrenzter, angreifbarer Sturzflug ohne Teleport und Bonusburst. Normaler Tower-Aggro-Vertrag, halber Gebäudeschaden, klare Gefährdung durch Anti-Air.

## 6. Balancevorschläge

| Karte | Emerald | HP | Schaden | Intervall | Bewegung | Reichweite |
|---|---:|---:|---:|---:|---:|---:|
| Breeze | 3 | 320 | 32 | 1,4 s | 6,6 | 15 |
| Adventure Sheep | 4 | 620 | 82 | 1,1 s | 7,4 | 2,5 |
| Phantom | 4 | 280 | 76 | 1,3 s | 10 | 2,2 |

Breeze: maximal `min(4, effektive Bewegung × 1 s)` Rückstoß; verstärkter Schuss nominell alle 4,2 s; dreisekündige geteilte Opfer-Immunität. Phantom: 38 Schaden gegen Gebäude/Türme; Dive-Windup 0,3 s, Wegbudget vier Einheiten, Speed-Cap 16, höchstens 0,3 s und fünf Sekunden Startabstand. Keine dieser Zahlen ist live.

Vollständige Eigenschaften und Zustände: [GAMEPLAY.md](GAMEPLAY.md). Vergleichswerte und nachvollziehbare Rechenannahmen: [BALANCE.md](BALANCE.md), maschinenlesbar in `BALANCE_PROPOSALS.json`.

## 7. Sheep gegen Zombie und Wither Skeleton

| Gegner | Nomineller Ausgang im Rechenmodell | Endzeit | Sheep-HP übrig |
|---|---|---:|---:|
| Zombie, 3E/523 HP/80 Schaden/1 s | Sheep gewinnt knapp | 6,6 s | 60 |
| Wither Skeleton, 3E/470 HP/88 Schaden/1 s | Sheep gewinnt | 5,5 s | 92 |

Beide stehen bereits in gegenseitiger Reichweite. Der nominale erste Treffer fällt bei t=0; gleichzeitige Treffer werden gemeinsam angewandt. Weitere 18 deterministische Timing-/Reihenfolgefälle pro Gegner geben im untersuchten Bereich denselben Sieger. Es gibt zusätzlich 54 Stat-Sensitivitätsfälle und gespeicherte nominale Treffer-Traces.

**Das sind keine Headless-Matches, keine Winrates und kein Nachweis eines fairen echten Matchups mit Bewegung.** Die Werte erfüllen das gewünschte Duellziel rechnerisch. Laufwege, Kiting, zusätzlicher Schaden und der endgültige erste Treffer können das Ergebnis ändern. Der 4E-Vorschlag ist bewusst konservativ und hat keine überlegene HP-/DPS-Effizienz pro Emerald. Ein relevanter Haltbarkeits-Breakpoint sind 549 Anvil-Schaden: Sheep überlebt mit 71 HP, Zombie und Wither Skeleton nicht. Normale Golems zielen auf Gebäude; ein künstliches erzwungenes Golem-vs-Sheep-Duell wird nicht als normales Gameplay ausgegeben.

## 8. Bestehende Karten und Meta

Sheep verliert gegenüber Zombie/Wither auf Kosten beziehungsweise DPS; Wolf und Spider bleiben schnellere/günstigere Optionen. Golems sind deutlich haltbarer und gebäudeorientiert. Enderman bietet Teleport und höhere DPS für 5E. Sheep ersetzt keine Anti-Air-Karte und ist gegen Gruppen auf Hilfe angewiesen.

Breeze konkurriert mit vorhandenem Support und darf keine weitere Allzweck-Slow-/Anti-Air-Unit werden. Ein einzelner Primär-Rückstoß ist in Gruppen begrenzt, kann aber einem freundlichen Ranged-Block Zeit verschaffen. King-Frog-Pull und Wind-Push können sich gegenseitig behindern.

Phantom unterscheidet sich von Bat Swarm durch Einzelkörper, lokal bevorzugte Erstzielwahl und höheren Preis; von Blaze durch Melee statt Ranged und von Baby Ender Dragon durch Single-Target statt Splash. Anti-Air kann seinen gesamten Anflug beschießen. Bat Swarm allein ist kein nachgewiesener Hardcounter; kombinierte Verteidigung und die vorgeschlagene niedrige HP sind die beabsichtigten Schwächen.

Overtime verändert den Emerald-Nachschub, nicht die vorgeschlagenen Timings. Mehr gleichzeitig verfügbare Controller machen insbesondere die gemeinsame Wind-Immunität wichtig. Meta-, Bot- und volle Match-Ergebnisse wurden für diese nicht registrierten Karten nicht erzeugt.

## 9. Technische Machbarkeit und Grenzen

Die vorhandene Palette, PixelBox, Rastergrößen und visuellen Grundtechniken genügen für die Assets. Der isolierte Generator verändert keine produktiven Render-APIs. Ein späterer Import muss jedoch Dispatch, visuelle Timer und Datenlieferung bewusst ergänzen.

Sheep benötigt am wenigsten neue Logik: normale Melee-Werte plus Animationseinbindung. Breeze braucht eine geprüfte Displacement-Transaktion, Victim-Immunität und Spatial-Index-Pflege. Phantom hat das höchste Risiko durch priorisierte Erwerbung, unangetasteten Retarget-Lock, Bewegungscaps und Anti-Air-/Tower-Interaktion. Ein vorhandenes Fang-, Teleport- oder Frog-System ist kein fertiger Ersatz.

Die Preview-Tests prüfen Zeilen, Palette, Grenzen, echte Terminalausgabe, Entfernung und unveränderte Registry/Sprites. Cross-Lua-Captures werden exakt verglichen. Die Browser-Bedienung wird zusätzlich isoliert geprüft. Die laufende produktive CI testet weiter den Bestand; sie registriert oder simuliert keine dieser vorgeschlagenen Karten.

Physische Minecraft-Monitore und ihre Netzwerk-/Renderlatenz bleiben ungeprüft. Es gibt keinen realen Monitor-Benchmark. Eine LÖVE-Portierung und High-Res-Master wurden in dieser CC-zentrierten Phase nicht begonnen.

## 10. Empfehlung und Stopppunkt

Das Paket ist zur visuellen und konzeptionellen Prüfung bereit. Es ist **keine Implementierungsfreigabe** und kein behauptetes finales Produktions-Roster.

1. Zuerst alle drei Silhouetten, das Maulschwert, die Winddarstellung und den Phantom-Dive beurteilen.
2. Die klar benannten Restschwächen aus [VISUAL_REVIEW.md](VISUAL_REVIEW.md) gezielt überarbeiten.
3. Erst nach gesonderter Freigabe mit Sheep als einfachstem Gameplay-Kandidaten beginnen; Breeze und Phantom nacheinander mit eigenen mechanischen Regressionen prüfen.

**Die Arbeit stoppt nach Konzept, Assets, Vorschauen, Balanceanalyse und Bericht. Keine automatische Umsetzung.**
