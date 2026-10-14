"""Offline safety regressions for bounded GitHub report history retention."""
import json
import sys
import tempfile
import unittest
import subprocess
import shutil
import textwrap
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))
from prune_reports import ARCHIVE_BRANCH, KEEP_RECENT, REPORT_NAMES, retention_plan, run


class ReportRetentionTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        (self.root / "reports" / "latest").mkdir(parents=True)
        (self.root / "reports" / "latest" / "mechanics_report.txt").write_text(
            "LATEST: MUST NEVER BE TOUCHED\n", encoding="utf-8")
        (self.root / "reports" / "retention_pins.txt").write_text(
            "# Historical milestones to preserve\n", encoding="utf-8")
        self.paths = {}
        for kind, filename in REPORT_NAMES.items():
            folder = self.root / "reports" / "history" / kind
            folder.mkdir(parents=True)
            self.paths[kind] = []
            for i in range(12):
                stamp = 1790000000000 + i * 100
                file = folder / f"{stamp}_{filename}"
                file.write_text(f"CODE_REVISION|{'a' * 40}\nRUN|{i}\n", encoding="utf-8")
                self.paths[kind].append(file)
            (folder / "unrecognized_debug_notes.txt").write_text("KEEP", encoding="utf-8")

    def test_prunes_known_old_reports_and_indexes_survivors(self):
        dry_count, dry_retained = run(self.root, apply=False)
        self.assertEqual(dry_count, 8)
        self.assertEqual(dry_retained, 4 * KEEP_RECENT)
        self.assertEqual(len(self.paths["mechanics"]), 12)
        self.assertFalse((self.root / "reports" / "history_index.json").exists())
        count, remaining = run(self.root, apply=True)
        self.assertEqual((count, remaining), (8, 40))
        for kind, paths in self.paths.items():
            self.assertFalse(paths[0].exists())
            self.assertFalse(paths[1].exists())
            for kept in paths[2:]:
                self.assertTrue(kept.exists())
            self.assertTrue((self.root / "reports" / "history" / kind /
                             "unrecognized_debug_notes.txt").exists())
        self.assertEqual(
            (self.root / "reports" / "latest" / "mechanics_report.txt").read_text(),
            "LATEST: MUST NEVER BE TOUCHED\n")
        index = json.loads((self.root / "reports" / "history_index.json").read_text())
        self.assertEqual(index["pre_retention_archive_branch"], ARCHIVE_BRANCH)
        self.assertEqual(len(index["retained"]), 40)
        self.assertTrue(all(len(row["sha256"]) == 64 for row in index["retained"]))
        self.assertTrue(all(row["code_revision"] == "a" * 40 for row in index["retained"]))
        before = (self.root / "reports" / "history_index.json").read_bytes()
        self.assertEqual(run(self.root, apply=True), (0, 40))
        self.assertEqual((self.root / "reports" / "history_index.json").read_bytes(), before)

    def test_pinned_old_mechanics_run_survives(self):
        oldest = self.paths["mechanics"][0]
        (self.root / "reports" / "retention_pins.txt").write_text(
            oldest.relative_to(self.root).as_posix() + "\n", encoding="utf-8")
        removed, kept = run(self.root, apply=True)
        self.assertEqual((removed, kept), (7, 41))
        self.assertTrue(oldest.exists())
        entries = json.loads((self.root / "reports" / "history_index.json").read_text())["retained"]
        self.assertTrue(any(row["path"] == oldest.relative_to(self.root).as_posix()
                            and row["pinned"] for row in entries))

    def test_invalid_pins_fail_closed_without_any_deletion(self):
        path = self.root / "reports" / "retention_pins.txt"
        path.write_text("reports/history/mechanics/../bad.txt\n", encoding="utf-8")
        with self.assertRaisesRegex(ValueError, "Unknown or missing"):
            run(self.root, apply=True)
        self.assertTrue(self.paths["mechanics"][0].exists())
        self.assertFalse((self.root / "reports" / "history_index.json").exists())

    def test_sorting_uses_timestamp_not_filename_order(self):
        mechanic = self.root / "reports" / "history" / "mechanics"
        # Malformed filenames do not enter the deletion plan.
        (mechanic / "bogus_mechanics_report.txt").write_text("never prune", encoding="utf-8")
        plan, entries = retention_plan(self.root)
        self.assertEqual(len(plan), 8)
        self.assertTrue(all(not p.name.startswith("bogus") for p in plan))
        self.assertEqual([row["timestamp_ms"] for row in entries if row["kind"] == "mechanics"],
                         sorted(row["timestamp_ms"] for row in entries if row["kind"] == "mechanics"))

    def test_push_race_recomputes_new_pins_and_index(self):
        # Real local Git race: the cleanup clone plans a deletion, then another
        # clone pins that report on main. A stale rebase must not delete it.
        fixture = Path(self.tmp.name) / "git-race"
        fixture.mkdir()
        remote, cleaner, writer = fixture / "remote.git", fixture / "cleaner", fixture / "writer"
        def git(cwd, *args):
            return subprocess.run(["git", *args], cwd=cwd, check=True,
                                  capture_output=True, text=True)
        git(fixture, "init", "--bare", "--initial-branch=main", str(remote))
        git(fixture, "clone", str(remote), str(cleaner))
        git(cleaner, "config", "user.name", "audit")
        git(cleaner, "config", "user.email", "audit@example.invalid")
        shutil.copytree(self.root / "reports", cleaner / "reports")
        (cleaner / "scripts").mkdir()
        shutil.copyfile(Path(__file__).resolve().parents[1] / "scripts/prune_reports.py",
                        cleaner / "scripts/prune_reports.py")
        git(cleaner, "add", ".")
        git(cleaner, "commit", "-m", "initial reports")
        git(cleaner, "push", "origin", "HEAD:main")
        git(fixture, "clone", str(remote), str(writer))
        git(writer, "config", "user.name", "audit writer")
        git(writer, "config", "user.email", "writer@example.invalid")
        oldest = self.paths["mechanics"][0].relative_to(self.root)
        run(cleaner, apply=True)  # the original workflow's planning snapshot
        (writer / "reports/retention_pins.txt").write_text(oldest.as_posix() + "\n")
        new_report = Path("reports/history/mechanics/1790000005000_mechanics_report.txt")
        (writer / new_report).write_text("NEW REPORT\n")
        git(writer, "add", ".")
        git(writer, "commit", "-m", "pin old report and upload new report")
        git(writer, "push", "origin", "HEAD:main")
        workflow = (Path(__file__).resolve().parents[1] / ".github/workflows/report-retention.yml").read_text()
        script = textwrap.dedent(workflow.split("name: Commit bounded history to main", 1)[1]
                                 .split("run: |", 1)[1])
        result = subprocess.run(["bash", "-c", script], cwd=cleaner,
                                capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertTrue((cleaner / oldest).is_file(), "Raced pin was deleted by stale cleanup")
        self.assertTrue((cleaner / new_report).is_file(), "Raced upload was lost")
        index = json.loads((cleaner / "reports/history_index.json").read_text())["retained"]
        self.assertTrue(any(row["path"] == oldest.as_posix() and row["pinned"] for row in index))
        self.assertTrue(any(row["path"] == new_report.as_posix() for row in index),
                        "Index was computed against stale main")


if __name__ == "__main__":
    unittest.main(verbosity=2)
