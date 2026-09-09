from pathlib import Path
import json
import shutil
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'scripts'))
import run_wasmtime_misc as misc


class MiscRunnerTests(unittest.TestCase):
    def test_complete_unchanged_snapshot(self):
        snapshot, cases = misc.validate_snapshot()
        self.assertEqual(len(cases), 382)
        self.assertEqual(sum(e['path'].endswith('.wat') for e in snapshot['files']), 4)
        self.assertEqual(len({c['name'] for c in cases}), 382)
        self.assertEqual({c['lane'] for c in cases}, {'core', 'component'})

    def test_modified_missing_or_added_sources_are_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            corpus = Path(tmp) / 'corpus'
            shutil.copytree(misc.CORPUS, corpus)
            source = corpus / 'upstream/tests/misc_testsuite/add.wast'
            original = source.read_bytes()
            source.write_bytes(original + b'\n')
            with self.assertRaisesRegex(ValueError, 'hash mismatch'):
                misc.validate_snapshot(corpus)
            source.unlink()
            with self.assertRaisesRegex(ValueError, 'inventory'):
                misc.validate_snapshot(corpus)
            source.write_bytes(original)
            source.with_name('new.wast').write_text('(module)')
            with self.assertRaisesRegex(ValueError, 'inventory'):
                misc.validate_snapshot(corpus)

    def test_only_leading_configuration_is_parsed(self):
        self.assertEqual(misc.test_config(';;! gc = true\n;;! bulk_memory = false\n(module)\n;;! ignored = true'),
                         {'gc': True, 'bulk_memory': False})
        self.assertEqual(misc.test_config(';; comment\n;;! gc = true'), {})
        with self.assertRaisesRegex(ValueError, 'boolean'):
            misc.test_config(';;! gc = 1')

    def test_exclusions_are_contracts_not_passes(self):
        _, cases = misc.validate_snapshot()
        indexed = {c['name']: c for c in cases}
        self.assertIsNone(misc.exclusion(indexed['canonicalize-nan-scalar.wast'], False))
        missing_host = indexed['add.wast'] | {'host_contract': 'Test-only missing host contract'}
        self.assertEqual(misc.exclusion(missing_host, False)[0], 'unsupported')
        self.assertEqual(misc.exclusion(indexed['big-memory-behavior.wast'], False)[0], 'deferred')
        self.assertIsNone(misc.exclusion(indexed['big-memory-behavior.wast'], True))
        self.assertIsNone(misc.exclusion(indexed['add.wast'], False))
        for status in ('unsupported', 'deferred'):
            self.assertEqual(misc.verdict([{'status': status}]), 1)
        self.assertEqual(misc.verdict([]), 1)
        self.assertEqual(misc.verdict([{'status': 'pass'}, {'status': 'fail'}]), 1)
        self.assertEqual(misc.verdict([{'status': 'script_only'}]), 0)

    def test_status_tally_and_assertion_inventory_must_agree(self):
        scenarios = [
            (0, 2, 0, 0, ['assert_return'], 'pass'),
            (1, 2, 0, 0, ['assert_return'], 'fail'),
            (0, 2, 1, 0, ['assert_return'], 'fail'),
            (0, 2, 0, 1, ['assert_return'], 'fail'),
            (0, 0, 0, 0, ['assert_return'], 'fail'),
            (0, 0, 0, 0, [], 'fail'),
            (0, 0, 0, 0, ['module', 'invoke'], 'script_only'),
        ]
        with tempfile.TemporaryDirectory() as tmp:
            stdout = Path(tmp) / 'stdout.txt'
            for code, passed, failed, skipped, commands, expected in scenarios:
                with self.subTest(code=code, passed=passed, failed=failed, skipped=skipped, commands=commands):
                    stdout.write_text(f'Results:\n  Passed: {passed}\n  Failed: {failed}\n  Skipped: {skipped}\n'
                                      'WAST JIT trace: attempts=2 compiled_modules=2 compiled_functions=5\n')
                    result = misc.parse_core_result({'status': 'pass' if code == 0 else 'fail',
                                                     'returncode': code, 'stdout': str(stdout)}, commands)
                    self.assertEqual(result['status'], expected)
                    self.assertEqual(result['jit_compilation']['functions'], 5)
            for text in ('Passed: 4\n', 'Results:\nPassed: 0\nFailed: 0\n'):
                stdout.write_text(text)
                self.assertEqual(misc.parse_core_result({'status': 'pass', 'returncode': 0,
                                                         'stdout': str(stdout)})['status'], 'fail')

    def test_timeout_and_harness_error_survive_result_parsing(self):
        for status in ('timeout', 'harness_error'):
            result = {'status': status}
            self.assertEqual(misc.parse_core_result(result), result)

    def test_excluded_cases_do_not_launch_an_engine(self):
        _, cases = misc.validate_snapshot()
        case = next(c for c in cases if c['name'] == 'add.wast')
        case = case | {'host_contract': 'Test-only missing host contract'}
        with tempfile.TemporaryDirectory() as tmp:
            result = misc.run_case(case, 'jit', Path('missing'), Path(tmp), 1, Path('missing'), Path('missing'))
            self.assertEqual(result['status'], 'unsupported')
            self.assertEqual(list(Path(tmp).iterdir()), [])

    def test_outer_component_timeout_kills_tools_in_the_same_group(self):
        with tempfile.TemporaryDirectory() as tmp:
            directory = Path(tmp)
            child = ("import os,time; from pathlib import Path; "
                     "Path('group.txt').write_text(str(os.getpid()) + ':' + str(os.getpgrp())); "
                     "time.sleep(1.5); Path('survived.txt').touch(); time.sleep(60)")
            code = (
                f'import sys,os; sys.path.insert(0, {str(ROOT / "scripts")!r}); '
                'import run_component_wast as c; '
                'os.environ["WASMOON_COMPONENT_SHARED_PROCESS_GROUP"]="1"; '
                f'c.run_command([sys.executable,"-c",{child!r}],timeout_sec=60)'
            )
            result = misc.execute([sys.executable, '-c', code], directory, 1)
            self.assertEqual(result['status'], 'timeout')
            pid, group = map(int, (directory / 'group.txt').read_text().split(':'))
            self.assertNotEqual(pid, group)  # The tool did not detach into its own group.
            import time
            time.sleep(1)
            self.assertFalse((directory / 'survived.txt').exists())


if __name__ == '__main__':
    unittest.main()
