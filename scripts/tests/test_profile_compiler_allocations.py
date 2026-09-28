"""Checks that allocation reports reconcile before attribution is accepted."""
from pathlib import Path
import tempfile
import unittest

from scripts.profile_compiler_allocations import read_trace


class AllocationTraceTests(unittest.TestCase):
    def test_totals_and_live_bytes_reconcile(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'trace'
            path.write_text('base 0x1000 total 50 count 2 live 20 peak 50 untracked_frees 0\n'
                            '20 1 20 20 0x1010\n30 1 0 30 0x1020\n')
            stats, rows = read_trace(path)
            self.assertEqual(stats['peak'], 50)
            self.assertEqual(len(rows), 2)

    def test_mismatched_totals_fail(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'trace'
            path.write_text('base 0x1000 total 50 count 2 live 0 peak 50 untracked_frees 0\n'
                            '20 1 0 20 0x1010\n')
            with self.assertRaisesRegex(RuntimeError, 'inconsistent allocation accounting'):
                read_trace(path)
