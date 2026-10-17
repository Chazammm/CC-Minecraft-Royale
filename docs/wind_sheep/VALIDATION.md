# Ausgeführte Prüfung

17.10.2026, Host-Lua 5.2.4 und 5.4.8. Basis `e80ad6919b7eb21a1d3464290d177ee3ab210eee` plus dieser Feature-Diff. Lokale Reports sind ausdrücklich als Working-Tree-Lauf gekennzeichnet; GitHub CI verwendet den tatsächlichen jeweiligen Commit-SHA.

| Prüfung | Status | Umfang / Nachweis |
|---|---|---|
| Lua-Syntax | PASS | Alle 130 Lua-Dateien unter beiden Compilern |
| Vollständige Lua-Regressionen | PASS | 55 entdeckte Suites × zwei Versionen = 110 erfolgreiche Ausführungen; `evidence/lua_suites.json` |
| Python-Tests | PASS | Alle acht Tests, kein Skip im endgültigen Lauf; `evidence/python_tests.log` |
| Neue Mechaniken | PASS | 25 echte Engine-Fälle pro Version, darunter beide Besitzer, Multi-Breeze-Immunität, Slows, Terrain, Brückenwahl, Türme, Platzierung, Kosten und Sheep-Duelle |
| Rotphase / Negativkontrolle | PASS | Zunächst 20 fehlschlagende Feature-Fälle vor Implementierung; separat erkennt der dritte-Schuss-Test eine absichtlich deaktivierte Verschiebung; `evidence/red_before_implementation.log` |
| Mechanik-CLI | PASS | 143 PASS / 0 FAIL / 0 ERROR im vollständigen installierbaren CLI; CI prüft auch die tatsächliche Registrierung aller 25 neuen Fälle |
| Renderer / Cache / Overlays | PASS | Je 45.393 Assertions über 78 Pose/Ansicht/Monitor-Kombinationen plus Gameplay-Szene und Entfernung der Death-Effekte; beide Lua-Versionen |
| Vorschau-Authentizität | PASS | Aktuelle Capture-JSONs, PNG-Pixel und sechs GIFs stimmen exakt; eigene `wind-sheep.yml` prüft neu erzeugte Captures |
| Vollständige Live-/Headless-Matches | PASS | Beide Besitzer, Seeds 20261018/20261019, normale Bots; beide Karten gespielt und Schaden erteilt, echte Wind-Pushes, Tick-Trace-Parität und identische Wiederholung; 262 Assertions pro Version |
| Mixed-CLI | PASS | 100 vollständige Matches je Lua-Version, Seed 20261017; bytegleiche Berichte, aktuelle 29-Karten-Auswahl; `evidence/mixed52.txt`, `mixed54.txt` |
| Invarianten-Audit | PASS | 100 weitere Mixed-Matches unter Lua 5.4, Assertions pro Tick; `evidence/audit100.log` |
| Bestehende Karten | PASS | Alle 28 vorherigen Definitionen einschließlich Guardian, Evolutionen und Collection-Indizes tiefengleich zur Basis |
| Installer / Imports | PASS | Bestehender Dependency-Closure-Test, Installer-/Recovery-Tests und Negativkontrolle mit absichtlich fehlendem Runtime-Import |
| Physische CC:Tweaked-Monitore | UNVERIFIED HARDWARE | Kein Minecraft-/CraftOS-/Peripheral-Endgerät verfügbar; echte Pipeline auf virtuellem Host-Monitor geprüft |
| LÖVE-Laufzeit | NOT APPLICABLE | Nur native CC-Integration; zwei statische LÖVE-Referenz-PNGs, keine Portierung |

Die Live-/Headless-Parität ist keine erfolgreiche Balanceprognose. Der Prüfdecksatz enthält absichtlich beide neuen Karten und teurere Optionen, damit beide tatsächlich eingesetzt werden. Die Testgegner können gewinnen. Normale Mixed-Matches nutzen unverändert den dynamischen Gesamtpool; es wurde weder eine Karte aus dem Pool ausgefiltert noch ein Winrate-Ziel erzwungen.

## Performance

Fünf **abwechselnde** Basis-/Feature-Läufe unter Host-Lua 5.4 nach Ende der Regression-Prozesse; Medianwerte in `evidence/performance.json`. Der unveränderte feste Kontrollsatz bleibt bei 9.174 Ticks und 336 Bot-Aktionen. Drei feste Headless-Matches: Basis 152,90 ms/Match, Feature 153,39 ms/Match, rund +0,32 %. Statisches 30-Unit-/Zwei-Monitor-Rendering: 2,347 gegenüber 2,313 ms/Zeichenaufruf, rund −1,47 %. Solche kleinen Host-Schwankungen sind kein Nachweis realer Minecraft-Leistung.

Eine erste Messserie während paralleler Regression-Prozesse zeigte große Laufzeitschwankungen. Sie wurde nicht als aussagekräftiger Vorher-/Nachher-Vergleich verwendet; der dokumentierte Vergleich lief abwechselnd ohne diese Prozesse. Es wurden keine Performance-Assertions gelockert. Rückstoß prüft maximal 16 Kandidaten pro berechtigtem Treffer; keine neue vollständige Entity-Suche pro Tick. Bestehende Frame-Cache-/Dirty-Row-Checks bleiben grün.

## Wiederholen und Remote-Prüfung

```sh
for test in tests/test_*.lua; do lua5.2 "$test"; lua5.4 "$test"; done
python3 -m unittest discover -s tests -p 'test_*.py' -v
lua5.2 tests/test_breeze_sheep_rendering.lua /tmp/wind52.json
lua5.4 tests/test_breeze_sheep_rendering.lua /tmp/wind54.json
python3 assets/sprites/wind_sheep/tools/previews.py --check --capture52 /tmp/wind52.json --capture54 /tmp/wind54.json
lua5.4 scripts/audit_cli_host.lua simulate.lua /tmp/mixed.txt WORKING_TREE 100 mixed 20261017
lua5.4 scripts/audit_cli_host.lua audit_matches.lua /tmp/unused.txt WORKING_TREE 100 20261017
```

Der Audit-CLI schreibt nach stdout; dessen Log ist der Nachweis, nicht der unbenutzte Adapter-Ausgabepfad. Der Python-Runner muss `lua5.2` beziehungsweise `lua5.4` im PATH finden, sonst markieren zwei bestehende Negativtests sich als SKIP. Im endgültigen aufgezeichneten Lauf waren beide verfügbar und alle acht Tests liefen.

GitHub prüft den jeweiligen Feature-/PR-Commit mit der vollständigen Lua-CI sowie den alten Frog-/Worm- und neuen Wind-/Sheep-Grafikjobs. **Der Merge ist an erfolgreiche aktuelle Checks gebunden.** Den tatsächlichen Remote-Status am PR prüfen; historische oder ältere Läufe gelten nicht als Nachweis für einen neueren Commit.
