"""Regression checks for compiler benchmark evidence and platform units."""
import unittest

from scripts.benchmark_compiler_memory import peak_rss, paired_change


class CompilerMemoryBenchmarkTests(unittest.TestCase):
    def test_peak_rss_units(self):
        self.assertEqual(peak_rss('  1048576  maximum resident set size\n', 'Darwin'), 1048576)
        self.assertEqual(peak_rss('Maximum resident set size (kbytes): 1024\n', 'Linux'), 1048576)

    def test_missing_measurement_is_an_error(self):
        with self.assertRaises(ValueError):
            peak_rss('process failed', 'Darwin')

    def test_change_is_paired_not_a_ratio_of_independent_medians(self):
        result = paired_change([100, 1000, 10000], [90, 900, 9000])
        self.assertAlmostEqual(result['median_percent'], -10)
        for bound in result['bootstrap_95_percent']:
            self.assertAlmostEqual(bound, -10)

    def test_incomplete_pairs_are_rejected(self):
        with self.assertRaises(ValueError):
            paired_change([1, 2], [1])
