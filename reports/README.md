# Automated reports

This directory is populated by the in-game `report_sync` tool.

- `latest/` always contains the newest uploaded copy of each report type.
- `history/mechanics/` contains timestamped mechanics diagnostics.
- `history/balance/` contains timestamped mixed/fixed simulation reports.
- `history/comparison/` contains timestamped controlled replacement analyses.
- `history/evolution/` contains timestamped BASE-vs-EVO impact analyses.

`latest/evolution_results.txt` always contains the newest isolated Evolution comparison run.

The GitHub token is never stored in this repository. It is kept locally on the CC:Tweaked computer in `.cc_royale/github_token.txt`.

## Baseline archive and automated retention

All reports and source tests as of the PR #13 merge are preserved on
[archive/reports-pre-retention-20261013](https://github.com/Chazammm/CC-Minecraft-Royale/tree/archive/reports-pre-retention-20261013),
anchored to commit `426511c886ac7d019354ecca04d42ea99a31072d`.
**Do not move or delete the archive branch.**

The [Report Retention workflow](../.github/workflows/report-retention.yml) runs
daily at 03:17 UTC and supports manual workflow dispatch. Before deleting
anything, it verifies that the archival branch still points to the original
commit. On main it retains **10 newest timestamped reports per kind** plus
any older reports explicitly listed in `retention_pins.txt`.

It never touches `reports/latest/`, unfamiliar file names, local reports,
or game code. After successful cleanup it generates `history_index.json`
with each retained report's path, timestamp, CODE_REVISION, size, SHA-256
and milestone/pinned status.

To preserve an older benchmark on main, add its exact path as a line in
`reports/retention_pins.txt` before cleanup. Example:
`reports/history/balance/1791649407928_balance_results.txt`.

Run `python3 scripts/prune_reports.py` for an offline non-destructive plan,
or `python3 scripts/prune_reports.py --apply` to apply changes locally.
The GitHub workflow commits changes with a normal non-force push.
Historical runs removed from main remain accessible in the archive branch.
