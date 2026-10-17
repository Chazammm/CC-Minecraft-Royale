"""Negative controls for CI discovery and installer dependency checking."""
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class AuditQuality(unittest.TestCase):
    def test_mechanics_gate_rejects_missing_feature_registration(self):
        runtime = shutil.which('lua5.4') or shutil.which('lua5.2')
        if not runtime:
            self.skipTest('Desktop Lua unavailable')
        with tempfile.TemporaryDirectory(prefix='cc-mechanics-oracle-') as temp:
            sandbox = Path(temp)
            for folder in ('src', 'lib'):
                shutil.copytree(ROOT / folder, sandbox / folder)
            for path in ROOT.glob('*.lua'):
                shutil.copy2(path, sandbox / path.name)
            (sandbox / 'tests').mkdir()
            test = 'tests/test_mechanics_full_ci.lua'
            shutil.copy2(ROOT / test, sandbox / test)
            baseline = subprocess.run([runtime, test], cwd=sandbox,
                                      capture_output=True, text=True)
            self.assertEqual(baseline.returncode, 0, baseline.stdout + baseline.stderr)
            entry = sandbox / 'mechanics_test.lua'
            body = entry.read_text()
            for module, prefix in [('src.frog_worm_mechanics', 'frog_worm_'),
                                   ('src.breeze_sheep_mechanics', 'breeze_sheep_')]:
                registration = f'require("{module}").register(runTest)'
                self.assertEqual(body.count(registration), 1)
                entry.write_text(body.replace(registration, '-- deliberately omitted'))
                mutated = subprocess.run([runtime, test], cwd=sandbox,
                                         capture_output=True, text=True)
                self.assertNotEqual(mutated.returncode, 0,
                                    'Mechanics gate accepted an omitted feature suite')
                self.assertIn(prefix, mutated.stderr)

    def test_general_ci_discovers_future_lua_tests(self):
        workflow = (ROOT / '.github/workflows/lua-ci.yml').read_text()
        self.assertIn('for test in tests/test_*.lua; do', workflow)
        for runtime in ('lua5.2', 'lua5.4'):
            self.assertIn(runtime + ' "$test"', workflow)

    def test_installer_test_rejects_unresolved_runtime_import(self):
        runtime = shutil.which('lua5.4') or shutil.which('lua5.2')
        if not runtime:
            self.skipTest('Desktop Lua unavailable')
        with tempfile.TemporaryDirectory(prefix='cc-manifest-oracle-') as temp:
            sandbox = Path(temp)
            for folder in ('src', 'lib'):
                shutil.copytree(ROOT / folder, sandbox / folder)
            for path in ROOT.glob('*.lua'):
                shutil.copy2(path, sandbox / path.name)
            (sandbox / 'tests').mkdir()
            test = 'tests/test_install_manifest.lua'
            shutil.copy2(ROOT / test, sandbox / test)
            baseline = subprocess.run([runtime, test], cwd=sandbox,
                                      capture_output=True, text=True)
            self.assertEqual(baseline.returncode, 0, baseline.stdout + baseline.stderr)
            module = sandbox / 'src/util.lua'
            module.write_text("local missing=require('src.audit_missing_module')\n" + module.read_text())
            mutated = subprocess.run([runtime, test], cwd=sandbox,
                                     capture_output=True, text=True)
            self.assertNotEqual(mutated.returncode, 0,
                                'Manifest oracle silently ignored an unresolved runtime import')
            self.assertIn('src/audit_missing_module.lua', mutated.stderr)


if __name__ == '__main__':
    unittest.main()
