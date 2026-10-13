#!/usr/bin/env python3
"""Bounded retention for CC Royale GitHub-uploaded diagnostic reports.

Only recognizes fixed timestamped reports/history/<kind>/ files.
Never touches reports/latest, unknown files, or explicitly pinned reports.
The pre-retention archive branch remains the durable historical snapshot.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import re
from pathlib import Path

KEEP_RECENT = 10
ARCHIVE_BRANCH = "archive/reports-pre-retention-20261013"
REPORT_NAMES = {
    "mechanics": "mechanics_report.txt",
    "balance": "balance_results.txt",
    "comparison": "comparison_results.txt",
    "evolution": "evolution_results.txt",
}
REVISION = re.compile(r"(?m)^CODE_REVISION\|([0-9a-fA-F]{7,40})\s*$")


def historical_files(root: Path, kind: str) -> list[tuple[int, Path]]:
    """Timestamp sorting is numeric; unfamiliar files are NEVER deleted."""
    folder = root / "reports" / "history" / kind
    if not folder.exists():
        return []
    if not folder.is_dir() or folder.is_symlink():
        raise ValueError(f"History folder is not a regular directory: {folder}")

    name = re.compile(r"^([0-9]{13})_" + re.escape(REPORT_NAMES[kind]) + r"$")
    found = []
    for path in folder.iterdir():
        if not path.is_file() or path.is_symlink():
            continue
        match = name.fullmatch(path.name)
        if match:
            found.append((int(match.group(1)), path))
    return sorted(found, key=lambda entry: (entry[0], entry[1].name))


def read_pins(root: Path) -> set[str]:
    file = root / "reports" / "retention_pins.txt"
    if not file.exists():
        return set()
    if file.is_symlink():
        raise ValueError("Retention pins file must not be a symlink")
    pins = set()
    for raw in file.read_text(encoding="utf-8").splitlines():
        value = raw.strip()
        if not value or value.startswith("#"):
            continue
        if value in pins:
            raise ValueError(f"Duplicate pinned path: {value}")
        pins.add(value)
    return pins


def retention_plan(root: Path) -> tuple[list[Path], list[dict]]:
    """Pure planning pass: validate all pins before deleting anything."""
    all_items = []
    for kind in REPORT_NAMES:
        for stamp, path in historical_files(root, kind):
            all_items.append((kind, stamp, path))

    recognized = {p.relative_to(root).as_posix() for _, _, p in all_items}
    pins = read_pins(root)
    invalid_pins = pins - recognized
    if invalid_pins:
        raise ValueError("Unknown or missing retention pin(s): "
                         + ", ".join(sorted(invalid_pins)))

    discard = []
    retain = []
    for kind in REPORT_NAMES:
        items = [(stamp, path) for k, stamp, path in all_items if k == kind]
        newest = {path for _, path in items[-KEEP_RECENT:]}
        for stamp, path in items:
            relative = path.relative_to(root).as_posix()
            if path in newest or relative in pins:
                retain.append((kind, stamp, path, relative in pins))
            else:
                discard.append(path)

    index = []
    for kind, stamp, path, pinned in sorted(retain, key=lambda x: (x[0], x[1], x[2].name)):
        data = path.read_bytes()
        revision = REVISION.search(data.decode("utf-8", errors="replace"))
        index.append({
            "kind": kind,
            "path": path.relative_to(root).as_posix(),
            "timestamp_ms": stamp,
            "code_revision": revision.group(1) if revision else None,
            "bytes": len(data),
            "sha256": hashlib.sha256(data).hexdigest(),
            "pinned": pinned,
        })

    return discard, index


def run(root: Path, apply: bool) -> tuple[int, int]:
    root = root.resolve()
    to_delete, index = retention_plan(root)
    manifest = {
        "schema_version": 1,
        "keep_recent_per_kind": KEEP_RECENT,
        "pre_retention_archive_branch": ARCHIVE_BRANCH,
        "retained": index,
    }
    index_path = root / "reports" / "history_index.json"
    serialized = json.dumps(manifest, indent=2, ensure_ascii=False) + "\n"
    print(f"Retention: keep {len(index)} historical reports, prune {len(to_delete)}; "
          f"archive: {ARCHIVE_BRANCH}; mode: {'apply' if apply else 'dry-run'}")
    if apply:
        # Read and validate all retained files and pinned paths before pruning.
        for path in to_delete:
            path.unlink()
        if not index_path.exists() or index_path.read_text(encoding="utf-8") != serialized:
            index_path.write_text(serialized, encoding="utf-8")
    return len(to_delete), len(index)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path("."))
    parser.add_argument("--apply", action="store_true",
                        help="Actually prune known old reports and write history_index.json")
    args = parser.parse_args()
    run(args.root, apply=args.apply)


if __name__ == "__main__":
    main()
