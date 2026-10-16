# CC Royale – Post-Update Integrity Audit

Review: [Pull Request #23](https://github.com/Chazammm/CC-Minecraft-Royale/pull/23), aufbauend auf #22.

## A. Repository-Snapshot und Aussagegrenze

Stand: 16.10.2026 (UTC). Dies ist ein frischer Audit, keine Übernahme historischer PASS-Angaben.

| Bereich | Revision / Status |
| --- | --- |
| Produktives `origin/main` | `6e85dc77553bd17422deeb9cb51258cefda06fe5`, Merge #19 |
| Neuester Implementierungskandidat | PR #22, `5b6b89264e1a7591b2bc5a9a9e639baf28f25706`, **OPEN**, nicht produktiv gemergt |
| Audit-Code für die Langläufe | `259da467f26025bf816307d5ab1539257b6236b2`; danach nur zusätzliche Host-Diagnosen, Test-/Register-/Berichtspflege |
| Audit-Branch | `audit/post-update-integrity-20261016`, eigenes Worktree |
| Stabiler Vergleich | `6e85dc7` für den Kandidaten; `4490cbd` (letzter System-Audit vor #19) zur Einordnung aller jüngeren Änderungen |
| Weitere offene PRs | #20: fünf Mod-/Custom-Grafikpaare, `5f86ac3`; #21: vier Custom-Konzepte, `a0da310` |

Der Audit-PR ist auf #22 gestapelt. Sein eigener Diff enthält keine Karten-, Combat-, Bot-, Movement-, Renderer- oder Balanceänderung. #20/#21 bleiben getrennte Asset-/Konzeptpakete. Es wurde weder `main` noch ein fremdes Worktree geändert, kein PR gemergt und kein Report nach `reports/latest` hochgeladen.

[Inventur](evidence/post_update_20261016/inventory.json): sämtliche 275 am Eingang des Kandidaten getrackten Dateien mit Größe und SHA-256; 114 Lua-Dateien, Importgraph, Testdateien, Workflow-Lücken. Alle Dateien wurden inventarisiert; das ist **keine Behauptung einer manuellen Zeilenprüfung jeder Datei**. Vertieft geprüft wurden insbesondere `src/game.lua`, `cards.lua`, `arena.lua`, `bot.lua`, `spatial.lua`, `combat_modifiers.lua`, `headless_match.lua`, die Mechanics-/Diagnostikmodule, Renderer/PixelBox, Hardware-/Event-Grenzen, Installer, Preset-/Report-/Token-Persistenz und alle Test-Einstiegspunkte. JSON/PNG/GIF-, Manifest-, Workflow- und Dokumentationsdateien wurden entsprechend ihres Formats validiert bzw. als historische Dokumente eingeordnet.

Die [Änderungsklassen seit dem letzten Audit](evidence/post_update_20261016/since_prior_audit.json) und der [Kandidat gegenüber main](evidence/post_update_20261016/candidate_since_main.json) trennen Spiellogik, Assets, Rendering, Tests/Diagnostik, Infrastruktur und Dokumentation. Produktions-Simulationsprogramme und Shared Runner wurden für Frog/Worm nicht dupliziert oder ersetzt. Der Literal-Importgraph hat keine fehlende lokale Abhängigkeit und keinen Zyklus. Optionale CraftOS-Module wie `cc.audio.dfpwm` sind Plattformabhängigkeiten, keine fehlenden Repository-Dateien.

Dynamische Registrierung: `main` hat 25 auswählbare Karten, der Kandidat 27; insgesamt 28 einschließlich Dev Guardian. Sechs auswählbare Evolutionen, sieben einschließlich Dev Elder Guardian. [Aktuelle Kartendaten](evidence/post_update_20261016/cards_runtime.tsv). Crab/Centipede, Piglich und die anderen offenen Asset-Designs sind keine fehlenden produktiven Features.

## B. Test-Matrix und Testqualität

Status bedeutet tatsächliche Ausführung. PASS beschreibt die geprüften Fälle; statischer Review, Host-Lua und virtuelle Monitore ersetzen keinen Cobalt-/Minecraft-Test.

| Testbereich | Status | Assertions / Umfang | Lua / Host | Evidence |
| --- | --- | --- | --- | --- |
| main: komplette Lua-Suiten | PASS | 47 Suiten je Runtime; Assertions siehe Einzelprotokoll | 5.2 / 5.4 | [Evidenz](evidence/post_update_20261016/tests_main.json) |
| Kandidat + Audit: komplette Lua-Suiten | PASS | 52 Suiten je Runtime, 104 erfolgreiche Prozesse | 5.2 / 5.4 | [Evidenz](evidence/post_update_20261016/tests_final.json) |
| Syntax aller finalen Lua-Dateien | PASS | 120 Dateien × 2; main/Asset-PRs zusätzlich separat | 5.2 / 5.4 | [Evidenz](evidence/post_update_20261016/syntax_final.json) |
| Tatsächlicher Mechanics-Runner | PASS | 118/118 Fälle; davon je 43 Four-Mob und Frog/Worm | 5.2 / 5.4; CLI zusätzlich 5.4 | [Evidenz](evidence/post_update_20261016/final_cli_8_mechanics_test_.txt) |
| Gameplay/System/Economy/Evo/Recovery | PASS | u. a. 23 Systemfälle/160 Checks; Core-Stress 290.695 Assertions; Presets 125 Szenarien | 5.2 / 5.4 | [Evidenz](evidence/post_update_20261016/tests_final.json) |
| Renderer/Cache/Palette/Overlays | PASS | 35 Legacy-Modelle/556 Checks; Four-Mob 150 Captures/42.377 Checks; Frog/Worm 54 Fälle + Szene/25.267 Checks; Frame-Diff 38 Checks | 5.2 / 5.4 | [Evidenz](evidence/post_update_20261016/tests_final.json) |
| Frog/Worm-PNGs und echte Vorschauen | PASS | 2 RGBA-Master, 9 native Raster; exakte frische Blit-Captures | 5.2 / 5.4 + Pillow | [Evidenz](evidence/post_update_20261016/assets_frog_worm.log) |
| Offene Asset-PRs #20 / #21 | PASS | 150 / 253 Asset-Verträge; native echte Captures beider Lua-Versionen; jeweils im eigenen unveränderten PR-Stand | 5.2 / 5.4 + Pillow | [Evidenz](evidence/post_update_20261016/assets_pr21.log) |
| Isolierte Mutationskontrollen | PASS | 11 erkannte Mutanten je Runtime; 12 zusätzliche Projektilkorruptionen je Runtime | 5.2 / 5.4 | [Evidenz](evidence/post_update_20261016/mutations54.json) |
| Python Safety / Testqualität | PASS | 8 Fälle, 0 Fail/Skip | Python 3.12.14 | [Evidenz](evidence/post_update_20261016/python_final.log) |
| Workflow-Syntax | PASS | alle vier Workflows, actionlint 1.7.7, Exit 0 | Host | [Evidenz](evidence/post_update_20261016/actionlint.log) |
| Historische Phase-1-Validatoren | NOT APPLICABLE | 3 echte fehlgeschlagene Versuche aufgrund vor Integration geltender Guards; keine aktuellen Release-Gates | 5.2 / 5.4 / Python | [Evidenz](evidence/post_update_20261016/assets_phase1.log) |
| Physische Monitore/Cobalt/Speaker | UNVERIFIED HARDWARE | keine entsprechende Hardware verfügbar | CraftOS/Cobalt | [Evidenz](evidence/post_update_20261016/environment.json) |


Die vollständigen Ergebnisse stehen in [initialen Kandidatentests](evidence/post_update_20261016/tests_initial.json), [main-Tests](evidence/post_update_20261016/tests_main.json), [finalen Kandidatentests](evidence/post_update_20261016/tests_final.json) und [Python-Ergebnissen](evidence/post_update_20261016/python_final.log). Es gibt keinen einheitlichen Assertion-Zähler über alle Frameworks; daher werden Suiten, Mechanikfälle, Prüfticks und explizit gemeldete Checks getrennt angegeben und nicht zu einer erfundenen Gesamtzahl addiert.

Die initialen 100 erfolgreichen Lua-Ausführungen übersahen den späteren Fehler bei Match 443. Außerdem akzeptierten bestehende Tests einen fehlenden Runtime-Import und eine komplett entfernte Frog/Worm-Mechanikregistrierung. Diese Negativkontrollen belegen, warum die anfänglich grüne CI allein nicht genügte.

[Elf isolierte Mutationen pro Lua-Version](evidence/post_update_20261016/mutations54.json) prüfen falsche Frog-HP, falschen Worm-Turmschaden, Hooks gegen Gebäude, falsche Worm-Platzierung, falsche Hero-Zyklen, doppelte Deckkarten, ungültige Sieger, fehlende Imports/Registrierung, fehlendes Lua-5.2-Gate und ungültige Sprite-Tokens. Alle Mutanten wurden erkannt; zuvor bestand jeweils die unveränderte Kontrollsuite. Arbeitskopien lagen in temporären Verzeichnissen und wurden verworfen. Das ist eine begrenzte Sensitivitätsprüfung, keine vollständige Mutation-Coverage.

Wichtige Oracle-Grenzen:

- Live-/Headless-Parität nutzt dieselbe Game-/Bot-Implementierung. Sie erkennt abweichende Treiber und kosmetische Seiteneffekte, beweist aber allein keine korrekten Kampfregeln. Feste HP-/Damage-/Timing-Erwartungen, unabhängige Ziel-/Geometrieprüfungen und negative Fixtures ergänzen sie.
- `test_headless_runner` teilt einen Countdown-Einstieg mit dem Runner; zusätzlich prüfen `test_diagnostic_contracts` tatsächliche Live-Countdowns (0 / 0,23 / 3 s) und die neuen Full-Match-Tests echte Live-Treiber.
- Acht vollständige Legacy-Matches wurden auf **zwei verschiedenen Revisionen und beiden Lua-Versionen** mit 768 kanonischen Trace-Zeilen je Lauf bytegenau verglichen. [Ergebnis/Hash](evidence/post_update_20261016/cross_revision_legacy.json). Nur leere neue Deployment- und nullwertige Refund-Felder werden normalisiert; aktive Mechaniken blieben sichtbar. Dies sichert die ausgewählten Altdecks ab, nicht jede denkbare Kombination.
- Die vier ursprünglichen Mob-Asset-Sätze werden gegen eine separate genehmigte Pixel-Fixture geprüft. Frog/Worm-Master/Previews werden zusätzlich über feste Manifest-Hashes und frische tatsächliche Blit-Captures geprüft. Ein Canvas-Vergleich mit dem eigenen Frame ist allein kein unabhängiges Kunstqualitätsurteil.
- Jede Lua-Testdatei läuft in einem eigenen Prozess. Der in-game Mechanics-Runner hat zusätzlich einen explizit getesteten Restore-Mechanismus für Card-/Config-Änderungen und Exceptions. Kein zufälliger globaler Zustand einer vorigen Testdatei wird vorausgesetzt.

### CI-Registrierung

Vorher fehlten die drei Frog/Worm-Dateien in der allgemeinen Testliste. Der Zusatzworkflow konnte PRs prüfen, lief nach einem Merge aber nicht auf allgemeinen `main`-Pushes. Jetzt entdeckt die allgemeine CI alle `tests/test_*.lua` automatisch und führt jede Datei unter beiden Lua-Versionen aus. Python verwendet ebenfalls Discovery. Bestehende Syntax-, Performance-, Retention- und echten CLI-Gates bleiben erhalten; doppelte manuelle Testlisten entfallen. Der Asset-Workflow folgt relevanten Lua-/Asset-Änderungen auf allen Branches. Der Release-Register-Checker erkennt die tatsächlich ausgeführte Glob-Schleife; Entfernen des Lua-5.2-Aufrufs wird weiter erkannt.

Die historischen Phase-1-Tools `assets/proposed/four_mobs_phase1/tools/test_assets.lua` (beide Lua-Versionen) und `validate_previews.py` wurden versuchsweise ausgeführt und scheitern an ihren **vor Integration geltenden** Annahmen: etwa „Ravager darf keine Karte sein“ und unveränderte Baseline-Dateihashes. Für den aktuellen Produktionsstand sind diese Gate-Bedingungen **NOT APPLICABLE**; ihre realen Fehler werden nicht als PASS umetikettiert. Der damalige Workflow ist auf den alten Phase-1-Branch begrenzt. Aktive `test_four_mob_*`-Tests sichern die integrierten Modelle ab. Die historischen Werkzeuge wurden nicht durch Abschwächen ihrer Erwartungen grün gemacht.

## C. Spielsysteme, Rendering und Simulationen

| System | Vertieft geprüfte Verträge / Nachweise |
| --- | --- |
| Combat | Nah-/Fernkampf, AoE-Radius, Primary-Target-Tod im Flug, Cooldowns/Bruchteile, Lock/Retarget, Air/Ground/Wasser, gleichzeitige Treffer und sofortiger Freeze nach einem siegbringenden Treffer; Mechanics-/System-/Timer-/Four-Mob-Suiten |
| Movement | Bridge-/River-Geometrie, Flieger, Uferreichweite, Lane-Ziele, Teleport/Summons/Death-Splits, endliche Positionen und unmittelbare Spatial-Neuindizierung nach Hooks. Die Engine verwendet Punktpositionen, keine neu erfundene Körperkollision. |
| Match/Lobby/Admin | Countdown, Regulation, Overtime 2×/3×, Sudden Death, Tiebreaker, Result-Freeze, Admin-Pause/Clear/Spawn, 20 aufeinanderfolgende Resets, keine aktiven Deck-/Preset-Mutationen |
| Economy/Deck | 8 verschiedene erlaubte Karten; Hand/Queue 4+4, gültiger Cycle, Emerald-Kosten/-Cap/-Regeneration, fehlgeschlagene Platzierung ohne Kosten/Evo-Zyklus, Refund nur in verfügbare Cap-Lücke; aggregierte Karten-/Spielerstatistik |
| Evolutionen | Alle sechs produktiven Evolutionen im Mechanics-Runner und im Vergleichsmodus; zusätzliche Dev-Guardian-Mechanik. Auswahl/Zyklen/Kosten, Ruleset aus, Normal-/Evo-Stat-Trennung, Reset, Summons und dauerhafte Netze. |
| Ravager/Dragon/Mino/Hero | Registrierung/echte Erzeugung, Rider-Zweitwaffe/Bewegung/Initial Impact, Dragon-Air/Ground-AoE und tote Primärziele, Mino-Einzeltreffer, Hero-Reservierung/Refund/Permanenz/Death/Result; echte Frames/Effekte, Bot und Full-Match-Parität |
| King Frog | 3E / 550 HP; Hook ohne eigenen Schaden, danach normale 40er Nahkampftreffer; schwere Bodeneinheiten/Banken, keine Luft/Wasser/Gebäude/Türme; legaler Zugpfad, Cooldown-Erhalt, bewegte Opfer, einmaliger Zug pro Opfer/Tick, beide Besitzer |
| Nether Worm | 3E / 350 HP; legale Platzierung auf beiden Hälften, auch hinter Türmen; Wasser-/Abstandsprüfung, 1,4-s-Warnung + 0,6-s-angreifbares Auftauchen, keine verborgene lebende Entity; bounded Korrektur/Abbruch/Refund; 95 gegen Gebäude, 47,5 gegen Princess/King, einmaliger +85-Opener gegen Units einschließlich Villager/Bank; kein dauerhaftes Untertauchen |
| Bot | Alle Schwierigkeiten, symmetrische Aktionsreihenfolge, gültige Platzierungen, kein Ground-Worm als Notantwort gegen Luft, echte wirtschaftliche Ambush-Ziele; keine Balance-Tuning-Änderung |
| Rendering/Animation | 35 Legacy-Modelle, 25 genehmigte Unit-Frames + 15 Effekte der vorherigen Erweiterung, 9 Frog/Worm-Raster einschließlich Warnmarker; beide Kameras, drei virtuelle Monitorgrößen, Damage-Flash, HP/Team/Web-Overlays, Transparenz, Cache/Forced-Encode-Parität, Ghost-Pixel-Entfernung, Resize-/Schreibfehler-Recovery |

Headless verwendet dieselben `Game.update`, Combat-, Placement-, Movement-, Evo-, Economy- und Victory-Funktionen wie Live. Nur Preset-I/O, Sound und kosmetische Animation/Effekte entfallen; der übersprungene Countdown und die Bot-Übergangsaktion werden separat auf Parität geprüft. Bot-Reihenfolge alterniert, Side-Swaps drehen den Offset. Decksampling benutzt einen eigenen deterministischen Generator; Seeds sind revisionsgestempelt. Aktuell gibt es keine zufälligen Combat-Zweige. Künftige verschachtelte/parallelisierte Matches müssten den globalen Lua-Gameplay-RNG zusätzlich isolieren.

Der zusätzliche Host-Observer ruft keine alternative Engine auf: Er instrumentiert den Shared Runner der **echten CLI-Programme**, prüft jeden Tick und aggregiert unabhängig Plays/Spending/Unit-/Tower-Damage. Er prüft außerdem Hand/Queue und beendet bei Projektilen mit über 30 simulierter Sekunden Lebensdauer. Die 100-Match-Reports sind mit und ohne Observer auf beiden Lua-Versionen bytegleich. [Paritätsnachweis](evidence/post_update_20261016/observer_parity.json).

### Simulations-Matrix

Alle folgenden finalen Zeilen stammen aus real beendeten Prozessen. Laufzeit ist Host-Walltime unter teilweise gleichzeitiger Auditlast, kein Monitor-Benchmark. Fehlerhafte initiale Läufe stehen separat unten.

| Modus | Matches | Seed | Lua | Runtime (s) | Errors | Status / Evidence |
| --- | ---: | --- | --- | ---: | ---: | --- |
| Kandidat / audit_matches | 100 | 20261016 | 5.4 | 85.747 | 0 | PASS · [Evidenz](evidence/post_update_20261016/final_invariants_1_audit_matches_100_20261016.log) |
| Kandidat / audit_matches | 500 | 20261017 | 5.4 | 274.450 | 0 | PASS · [Evidenz](evidence/post_update_20261016/final_invariants_2_audit_matches_500_20261017.log) |
| Kandidat / audit_matches | 1000 | 20261016 | 5.4 | 816.352 | 0 | PASS · [Evidenz](evidence/post_update_20261016/final_invariants_3_audit_matches_1000_20261016.log) |
| Kandidat / audit_matches | 1000 | 20261016 | 5.2 | 1020.242 | 0 | PASS · [Evidenz](evidence/post_update_20261016/final_cross52_1_audit_matches_1000_20261016.log) |
| Kandidat / simulate mixed | 100 | 20261016 | 5.4 | 46.607 | 0 | PASS · [Evidenz](evidence/post_update_20261016/final_cli_1_simulate_100_mixed_20261016.log) |
| Kandidat / simulate mixed | 500 | 20261016 | 5.4 | 592.498 | 0 | PASS · [Evidenz](evidence/post_update_20261016/final_cli_2_simulate_500_mixed_20261016.log) |
| Kandidat / simulate mixed | 1000 | 20261016 | 5.4 | 644.649 | 0 | PASS · [Evidenz](evidence/post_update_20261016/final_cli_3_simulate_1000_mixed_20261016.log) |
| Kandidat / simulate fixed | 100 | 20261016 | 5.4 | 45.450 | 0 | PASS · [Evidenz](evidence/post_update_20261016/final_cli_4_simulate_100_fixed_20261016.log) |
| Kandidat / compare all | 240 | 20261016 | 5.4 | 88.314 | 0 | PASS · [Evidenz](evidence/post_update_20261016/final_cli_5_compare_10_all_20261016.log) |
| Kandidat / compare king_frog nether_worm | 40 | 20261016 | 5.4 | 12.958 | 0 | PASS · [Evidenz](evidence/post_update_20261016/final_cli_6_compare_10_king_frog_nether_worm_20261016.log) |
| Kandidat / evo_compare all | 240 | 20261016 | 5.4 | 84.296 | 0 | PASS · [Evidenz](evidence/post_update_20261016/final_cli_7_evo_compare_10_all_20261016.log) |
| Kandidat / mechanics_test (118 Fälle) | — | — | 5.4 | 0.315 | 0 | PASS · [Evidenz](evidence/post_update_20261016/final_cli_8_mechanics_test_.log) |
| Kandidat / simulate mixed | 100 | 20261016 | 5.2 | 215.898 | 0 | PASS · [Evidenz](evidence/post_update_20261016/final_cli52_1_simulate_100_mixed_20261016.log) |
| main / audit_matches | 100 | 20261016 | 5.4 | 95.738 | 0 | PASS · [Evidenz](evidence/post_update_20261016/final_baseline_1_audit_matches_100_20261016.log) |
| main / simulate mixed | 100 | 20261016 | 5.4 | 48.299 | 0 | PASS · [Evidenz](evidence/post_update_20261016/final_baseline_2_simulate_100_mixed_20261016.log) |


Der 1.000er-Invariantenlauf liefert unter **beiden** Lua-Versionen 2.710.362 Prüfticks, P1 499 / P2 501 / Draws 0 und Fingerprint `1116991901`. Lua 5.2: Post-GC 551,76–552,26 KiB; Lua 5.4: 482,42–483,13 KiB. Im beobachteten Verlauf kein wachsender Retained-State-Trend; das beweist kein generelles Fehlen von Speicherlecks. 32-Bit-Fingerprints sind ein kompakter Replay-Indikator, kein kollisionsfreier vollständiger Beweis; der Legacy-Trace und die 100er-Reports wurden zusätzlich bytegenau verglichen.

Die echte 1.000er-Balance-CLI beendet 1.000 Matches mit P1 500 / P2 500 / Draws 0, 2.713.368 beobachteten Ticks und durchschnittlich 271,2 s Matchdauer. Alle 27 auswählbaren Karten werden tatsächlich gespielt; Frog 4.232 Plays, Worm 4.470, Minoshroom 526, Villager 356. Keine Projektil-Lebensdauerüberschreitung oder Inkonsistenz bei Cycle/Statistiksummen. Der 500er-Lauf beendet ebenfalls alle 500 Matches. Maxima und alle Karten-Plays stehen in den Logs.

Der Evolution-Vergleich wurde für alle sechs Karten ausgeführt, aber nicht jede EVO-Variante wurde von den Bots erreicht: **Villager → Emerald Bank hat in dieser Stichprobe 0% `reached` und 0 Evo-Plays**. Dieser Report belegt daher keinen Bank-Evolutionseffekt. Die Bank-Mechanik, Zyklen, HP/Lifetime und Income-/Death-Interaktionen bestehen die gezielten Engine-Tests; die statistische Bot-Evo-Wirkung bleibt in dieser Vergleichsstichprobe **NOT EXERCISED**. Dies wird nicht durch Behaupten einer erfolgreich ausgespielten Bank-Evolution verdeckt.

`WATCH-` im Mixed-Report ist kein technischer Fehler: Frog erreicht dort 37,2%, Worm 41,7% deckbezogene Score-Rate. Der kontrollierte Frog/Worm-Vergleich (10 Kontexte) hat eine breite 95%-Spanne von −10,16 bis +50,16 Prozentpunkten für B−A. Diese kleinen/abhängigen Stichproben sind kein Beweis für eine konkrete Balancekorrektur; Bot, Synergien und Deckkontext bleiben relevant. Keine Werte wurden geändert.


Der initiale 500er-Invariantentest brach nach 442 vollständig beendeten Matches im 443. ab: [Originalfehler](evidence/post_update_20261016/02_candidate_5.4_audit_matches_500_20261016.log). Dieser Lauf war **FAIL**, nicht „500 bestanden“. Die Korrektur wurde zuerst im kleinen echten Projektil-Regressionsfall geprüft und anschließend mit den finalen Langläufen bestätigt.

Die 100-/500-/1.000-CLI-Batches verwenden absichtlich denselben Seed, sodass kleinere Batches Präfixe reproduzieren. Sie sind separate tatsächliche Ausführungen, **keine 1.600 unabhängigen Deckpaare**. Die 500er-Invariantenstufe nutzt zusätzlich Seed 20261017. Mixed-Audit und Balance-CLI sampeln Decks unterschiedlich; ihre Ergebnisse werden nicht gleichgesetzt. Auch 25er-main-Pool und 27er-Kandidat sind keine direkt vergleichbaren Winrate-Experimente.

## D. Findings und kleinste Korrekturen

| ID | Severity | System / Ursache / Reproduktion | Status |
| --- | --- | --- | --- |
| AF-062 | MEDIUM | CI: manuelle Liste und Feature-Branch-Trigger lassen neue Suiten nach Merge aus; Discovery-Negativtest zunächst rot. | FIXED, automatische Dual-Lua-/Python-Discovery und passender Asset-Trigger; Release-Gate angepasst, nicht abgeschwächt |
| AF-063 | MEDIUM | Installer-Orakel überspringt fehlenden Import; `require('src.audit_missing_module')` wurde trotz PASS akzeptiert. | FIXED, fehlende Module werden verworfen; Audit-CLI als Graphwurzel ergänzt |
| AF-064 | MEDIUM | Zustandsorakel akzeptiert gewöhnliche Projektile mit NaN/negativem Damage/Speed 0; roter gezielter Test. | FIXED, 12 negative Felderprüfungen; erlaubte in-flight Referenzen nach Source-/Target-Tod bleiben zulässig |
| AF-065 | MEDIUM | Komplett fehlende 43 Frog/Worm-Registrierungen ergeben weiterhin „75 PASS“ unter historischer Mindestzahl. | FIXED, PASS-Eintrag jeder exportierten Case-ID aller drei Erweiterungssuiten erforderlich |
| AF-066 | MEDIUM | Seed 20261016 / Paar 222 / Match 443 / Tick 1986: späterer Schuss tötet Ziel eines früher verarbeiteten Netzes. Der Observer verlangt Reservierung eines bereits entfernten Opfers. | FIXED **im Observer**, Engine-Verhalten unverändert; Source- und lebende Target-Reservierung bleiben geprüft; nächster Tick cancelt/refundet tatsächlich |
| OP-006 | MEDIUM | Worm-Bot: 16 Kandidaten je Ziel × vollständiger Entity-Scan für Strukturabstand; steigender Aufwand in dichten synthetischen Szenen. | OPEN OPTIMIZATION; keine Fehlplatzierung/Runtime-Störung belegt. Struktur-Blocker pro Entscheidung cachen bzw. Spatial-Abfrage untersuchen, danach exakte Ziel-/Score-Parität nachweisen |
| OP-007 | MEDIUM | Seed 20261016 / Paar 281 / normal: genau ein abweichendes Ergebnispaar unter 500 Side-Swaps; P2 gewinnt beide Orientierungen (303,2 / 300,6 sim. s). | OPEN RISK; beide Varianten gezielt reproduziert, eigentliche Ursache ungeklärt. Keine eigenmächtige Änderung an Reihenfolge, Targeting oder Balance |
| PA-007 | LOW | Phase-1-README/Tools sind ohne historischen Kontext leicht als aktuelle Gates misszuverstehen. | OPEN Dokumentationspflege; reale alte Verträge nicht umgeschrieben |
| OP-004 | LOW | Veröffentlichte `reports/latest` enthalten frühere Code-Revisions, nicht main/Kandidat. | OPEN Aktualitätsgrenze; frische Audit-Ergebnisse bewusst unter `docs/audits` statt als vermeintliche produktive Live-Reports gespeichert |

Kein bestätigter offener CRITICAL-/HIGH-Fehler im untersuchten Umfang. Die fünf Fixes ändern ausschließlich Absicherung/Diagnostik. Die initiale rote und abschließende grüne Evidenz liegt neben dem Bericht (`quality_red.log`, `registration_red.log`, `diagnostics_red.log`, `web_boundary_red.log`, `web_reproduction*.log`, finale Tests). Ein zwischenzeitlicher Dual-Lua-Testlauf scheiterte noch am alten, nur explizite Dateinamen erkennenden Release-Gate; auch dieser Befund bleibt in `tests_after_first_fix.json` erhalten. Der finale Lauf erkennt die Discovery-Schleife und verlangt weiterhin beide Runtime-Aufrufe.

## E. Performance und Speicher

Drei wiederholte, verschachtelt ausgeführte Legacy-Profile pro Revision und Runtime ([Rohdaten](evidence/post_update_20261016/performance.json)). Die Werte sind native CPU-Zeiten; gleichzeitig liefen andere Audit-Prozesse.

| Runtime / Kontrollprofil | main Median (s) | Kandidat Median (s) | Änderung |
| --- | ---: | ---: | ---: |
| Lua 5.2 / headless_3_matches | 0.955747 | 1.362182 | +42.5% |
| Lua 5.2 / static_arena_30_units_2_monitors | 0.056921 | 0.061116 | +7.4% |
| Lua 5.4 / headless_3_matches | 0.672414 | 0.652043 | -3.0% |
| Lua 5.4 / static_arena_30_units_2_monitors | 0.042736 | 0.042075 | -1.5% |

Die anfängliche Lua-5.2-Messreihe zeigte +42,5% CPU im Kontrollmatch. Wegen der breiten Streuung wurde sie gezielt überprüft: acht abwechselnde A/B-Paare auf derselben zulässigen CPU-Affinität ergeben Mediane von 0.627714 s (main) und 0.591563 s (Kandidat), bei deutlich überlappenden Bereichen. [Alle 16 Kontrollmessungen](evidence/post_update_20261016/cpu_control52.json). Die erste Verlangsamung ist damit nicht als stabile Regression bestätigt; auch die niedrigere zweite Zahl beweist keinen Speedup. Es wird keine Hardware-FPS-Aussage abgeleitet.

Worm-Zielsuche: jeweils zehn echte Entscheidungen, dreimal pro Dichte/Runtime. Mediane in Millisekunden pro Entscheidung:

| Gegner | Lua 5.2 (ms) | Lua 5.4 (ms) | Platzierungsprüfungen / Entscheidung |
| ---: | ---: | ---: | ---: |
| 20 | 1.0635 | 0.8306 | 320 |
| 60 | 7.1539 | 5.0033 | 960 |
| 120 | 33.7604 | 25.9613 | 1920 |
| 240 | 147.3842 | 108.6700 | 3840 |

[Skalierungsdaten](evidence/post_update_20261016/worm_scaling_repeated.json). Der vollständige Entity-Scan je Kandidat erklärt den superlinearen Aufwand (OP-006). Die 1.000 Mixed-CLI-Matches erreichten dagegen höchstens 27 gleichzeitige Entities und sechs Projektile. Der Stressfall ist ein Optimierungsbedarf für hohe Dichten, kein nachgewiesener Watchdog-Ausfall auf CC-Hardware.


Die Side-Swap-Abweichung ist kein Runtime-Absturz oder ungültiger Zustand. Sie ist auch kein Beleg, dass alle Paare exakt spiegeln: [vollständiger Paar-Nachlauf](evidence/post_update_20261016/side_pairs.log). Die betroffenen Decks und beide reproduzierten Ergebnisse sind erhalten. Ohne isolierte Ursache wird daraus weder ein bestätigter Engine-Bug noch eine Freigabe zur Balanceänderung abgeleitet.

Unveränderte Frames verursachen in sämtlichen wiederholten Legacy-Profilen **0 weitere Blit-Zeilen**. Kontrollmatches behalten 9.174 Ticks / 336 Bot-Aktionen. Keine Renderer-Änderung im Audit; daher kein erfundener Speedup durch diese Korrekturen.

Entity-/Projectile-Listen werden kompakt bereinigt, Spatial-Einträge bei Bewegung/Tod aktualisiert, Renderer-Caches verwenden schwache Schlüssel; keine unbegrenzte neue Warnmarker-/Effektliste wurde in den geprüften Läufen beobachtet. Im Headless-Modus entfallen kosmetische Effekte absichtlich; die Live-Renderer-Tests prüfen deren Entfernung separat. CPU-Messungen und native `collectgarbage`-Werte beschreiben diesen Linux-Host, **nicht** die JVM/Cobalt-Speicherverwaltung.

## F. Struktur, Installation, Reports, CI und offene Grenzen

- **Installer PASS im Host-Faultmodell:** alle transitiv wörtlich importierten Runtime-Module und Einstiegspunkte sind ausgeliefert. Revision wird einmal aufgelöst, Downloads sind SHA-gepinnt, Lua-Preflight, Recovery-Marker, Allowlist und Rollback werden durch Fehler-Injektion geprüft. Neue Host-Audit-Skripte/PNG-Master sind absichtlich keine CC-Installationsabhängigkeiten. Dynamisch zusammengesetzte künftige Imports werden durch den Literal-Scanner nicht vollständig bewiesen.
- **Persistenz/Report PASS im Host-Faultmodell:** Token-Rekonfiguration/Backup/Logout, Presets inklusive 125 Recovery-Kombinationen, stilles Write-/Close-/Rename-False, HTTP-Handles, Reportschreib-/Upload-Byteintegrität und Race-Recovery. Keine echten Tokens ausgelesen oder gespeichert. Kein echter In-Minecraft-Upload oder Live-Installer-Lauf behauptet.
- **Retention PASS:** fünf Python-Fälle, unbekannte Dateien/Latest/Pins geschützt, numerische Timestamp-Sortierung, erneute Planung nach Push-Race. Repository selbst nur dry-run: 33 historische Reports behalten, 0 löschen. Archivref tatsächlich gelesen und weiter `426511c886ac7d019354ecca04d42ea99a31072d`. Write-Workflow staged ausschließlich `reports/history` und `reports/history_index.json`, läuft nur auf main bei Schedule/Dispatch, kein Force-Push. Report-only-Commits lösen die allgemeinen Gameplay-/Asset-Gates nicht erneut aus.
- **Versions-/Asset-Verweise:** beide gepinnten Musikdateien existieren weiterhin an ihrer referenzierten Revision (GitHub-Tree-Nachweis). Das bestätigt Existenz, nicht DFPWM-Wiedergabe oder HTTP-Streaming auf einem echten Speaker. Neue Runtime-Sprites werden aus `src/assets` installiert; `assets/proposed` bleibt außerhalb des produktiven Importgraphen.
- **Wartbarkeit INFORMATIONAL:** große Module (`game.lua`, `cards.lua`, `pixel_arena.lua`, `render.lua`) bündeln viele Zuständigkeiten. Vorschlag: später transaktionale Fähigkeiten/Renderer-Assetkataloge separat extrahieren, mit Legacy-Traces und unabhängigen Orakeln absichern. Kein großer Refactor im Audit.
- **UNVERIFIED HARDWARE:** physische Advanced-Monitore, Modem-/Peripheral-Latenz, CC:Tweaked/Cobalt/JVM-Collector/Watchdog, reale Speaker-/HTTP-/Dateisystembedingungen und manuelles PvP nicht verfügbar. Desktop Lua 5.2 ist kein vollständiger Cobalt-Ersatz. Virtuelle Monitorchecks sind ausdrücklich Host-Nachweise.
- **NOT RUN / BLOCKED:** echte Minecraft-Installation/Update/Rollback, echte CraftOS-Reportübertragung und LÖVE-GPU-/Animationslaufzeit mangels Hardware/entsprechendem Runtime-Ziel. LÖVE-Master sind als PNG/Alpha/Manifest geprüft, es existiert hier kein eigenständiges LÖVE-Spiel zum Durchspielen.

Die aktuelle main-Revision hat tatsächlich erfolgreiche Lua-CI- und Retention-Läufe; [API-Snapshot](evidence/post_update_20261016/remote_main_runs.json). Die bereits veröffentlichte Audit-Code-Revision `259da46` hat zwei erfolgreiche Push-Checks: [Lua CI](https://github.com/Chazammm/CC-Minecraft-Royale/actions/runs/38897598606) und [echte Assets](https://github.com/Chazammm/CC-Minecraft-Royale/actions/runs/38897598708). Diese Links belegen genau diese Revision, nicht automatisch einen späteren Dokumentationscommit.

Auch der finale Audit-Source-Commit `fa97817` hat beide Push-Checks bestanden ([Snapshot](evidence/post_update_20261016/remote_source_runs.json)). Sein Runtime-Code ist [nachweislich unverändert](evidence/post_update_20261016/final_scope.json) gegenüber den Langläufen.

Der endgültige Audit-PR-HEAD wird nach Veröffentlichung erneut auf GitHub geprüft; sein tatsächlicher Checkstatus und die Push-/PR-Läufe sind direkt am unten verlinkten PR sichtbar. Im Abschluss wird ein Remote-PASS nur bei wirklich erfolgreich beendeten Checks behauptet. `actionlint` ist zusätzlich lokal erfolgreich, ersetzt diese Remote-Läufe aber nicht.


## G. Schlussbewertung und Abschlussstatus

```text
CURRENT REVISION: main 6e85dc7; Kandidat 5b6b892; Audit-Source fa97817
FILES INSPECTED: 275 Eingangsdateien inventarisiert; 120 finale Lua-Dateien geparst
TESTS DISCOVERED: 52 aktive Lua-Suiten + 2 Python-Dateien (8 Fälle)
TESTS EXECUTED: Kandidat 104 Lua-Prozesse + 8 Python-Fälle; main zusätzlich 94 Lua-Prozesse
TESTS PASSED: alle finalen aktiven Läufe
TESTS FAILED: final 0; initialer 500er-Lauf und rote Kontrollen separat erhalten
TESTS SKIPPED: 0 aktive; historische Phase-1-Gates NOT APPLICABLE
MECHANICS: PASS 118/118
SIMULATION 100: PASS
SIMULATION 500: PASS
SIMULATION 1000: PASS; Invarianten 5.2/5.4, echte Mixed-CLI 5.4
RENDERING / ANIMATIONS / EVOLUTIONS: PASS im dokumentierten Host-Umfang
REPOSITORY STRUCTURE / INSTALLER: PASS im statischen und Host-Faultmodell
CI STATUS: echte erfolgreiche Code-Push-Läufe; finale PR-Checks am PR
PERFORMANCE: gemessen; keine stabile Legacy-Regression bestätigt; OP-006 offen
CRITICAL OPEN: 0
HIGH OPEN: 0
MEDIUM OPEN: 2 (OP-006 Skalierung, OP-007 Side-Swap-Risiko)
LOW OPEN: 2 (historische Gates, veraltete veröffentlichte Latest-Reports)
FIXES IMPLEMENTED: 5 (AF-062–066)
REGRESSIONS ADDED: 2 Lua-Suiten, 1 Python-Datei mit 3 Fällen; bestehende Gates verstärkt
HARDWARE VERIFICATION: UNVERIFIED HARDWARE
UNVERIFIED AREAS: reale CraftOS-Installation/HTTP/Audio/Monitor/JVM; LÖVE-Laufzeit; OP-007-Ursache; Bank-Evo-Impact im Bot-Vergleich
FINAL ASSESSMENT: Host-Prüfungen bestanden; keine uneingeschränkte Release-/Hardwarefreigabe
PULL REQUEST: https://github.com/Chazammm/CC-Minecraft-Royale/pull/23 (gestapelt auf #22, kein Merge)
```

Die geprüften Match-/Karten-/Evo-/Renderingpfade sind technisch konsistent in den ausgeführten Szenarien. Der Langlauf hat einen echten Diagnose-Fehlalarm gefunden, den die ursprüngliche grüne Suite nicht erkannte. Dieser und vier weitere Absicherungslücken sind reproduziert, minimal korrigiert und erneut geprüft. Es wurde kein bestätigter Gameplay- oder Balancefehler durch eigenmächtige Werteänderung verdeckt.

Das ist ein belastbarer **Host-Integritätsnachweis für die genannten Revisionen und Szenarien**, keine Garantie vollständiger Fehlerfreiheit und keine physische CC:Tweaked-Freigabe. Die dichte Worm-Zielsuche, der reproduzierbare Side-Swap-Grenzfall und zwei dokumentierte Pflegepunkte bleiben offen. Produktive Integration des noch offenen #22 sowie Merge dieses Audit-PRs bleiben beim Nutzer.

## Reproduktion

Alle tatsächlichen Befehle, Seeds, Laufzeiten und Rückgabecodes stehen in `evidence/post_update_20261016/final_*.json`. Beispiele aus dem Repository-Root:

```sh
set -eu
for test in tests/test_*.lua; do lua5.2 "$test"; lua5.4 "$test"; done
python3 -m unittest discover -s tests -p 'test_*.py' -v
python3 scripts/audit_negative_controls.py --lua lua5.4 --output /tmp/mutations54.json
lua5.4 scripts/audit_cli_host.lua audit_matches.lua /tmp/unused AUDITED_SHA 1000 20261016
lua5.2 scripts/audit_cli_host.lua audit_matches.lua /tmp/unused AUDITED_SHA 1000 20261016
lua5.4 scripts/audit_observed_cli.lua simulate.lua /tmp/balance.txt AUDITED_SHA 1000 mixed 20261016
lua5.4 scripts/audit_observed_cli.lua compare.lua /tmp/compare.txt AUDITED_SHA 10 all 20261016
lua5.4 scripts/audit_observed_cli.lua evo_compare.lua /tmp/evo.txt AUDITED_SHA 10 all 20261016
lua5.4 scripts/audit_worm_scaling.lua
lua5.4 tests/performance_profile.lua
```

`AUDITED_SHA` durch die tatsächlich ausgecheckte Revision ersetzen. Native-Lua-Binaries und Host-Pillow-Versionen siehe Evidenz-Metadaten. Das Audit-CLI schreibt nach stdout; beim Host-Adapter ist dessen Outputpfad unbenutzt. Für spätere Vergleiche daher zusätzlich stdout umleiten. Keine historischen Reports mit anderen Seeds/Kartenpools als aktuellen Testnachweis verwenden.
