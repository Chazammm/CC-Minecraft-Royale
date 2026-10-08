# Automated reports

This directory is populated by the in-game `report_sync` tool.

- `latest/` always contains the newest uploaded copy of each report type.
- `history/mechanics/` contains timestamped mechanics diagnostics.
- `history/balance/` contains timestamped mixed/fixed simulation reports.
- `history/comparison/` contains timestamped controlled replacement analyses.
- `history/evolution/` contains timestamped BASE-vs-EVO impact analyses.

`latest/evolution_results.txt` always contains the newest isolated Evolution comparison run.

The GitHub token is never stored in this repository. It is kept locally on the CC:Tweaked computer in `.cc_royale/github_token.txt`.
