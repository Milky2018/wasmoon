"""Regression checks for compiler benchmark evidence and platform units."""
import unittest

from scripts.benchmark_compiler_memory import peak_rss, workload


class CompilerMemoryBenchmarkTests(unittest.TestCase):
    def test_peak_rss_units(self):
        self.assertEqual(peak_rss('  1048576  maximum resident set size\n', 'Darwin'), 1048576)
        self.assertEqual(peak_rss('Maximum resident set size (kbytes): 1024\n', 'Linux'), 1048576)

    def test_missing_measurement_is_an_error(self):
        with self.assertRaises(ValueError):
            peak_rss('process failed', 'Darwin')

    def test_workload_executes_every_generated_function(self):
        text = workload([2, 1, 3])
        for index in range(3):
            self.assertIn(f'(func $f{index} ', text)
            self.assertIn(f'call $f{index} drop', text)
        self.assertIn('(export "main")', text)
