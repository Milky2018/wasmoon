import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from benchmark_startup import COLD_PHASES, summarize, validate_phases


class StartupEvidenceTests(unittest.TestCase):
    def test_partial_or_nonreconciling_reports_are_not_accepted(self):
        report = {'schema_version': 1, 'command_us': str(len(COLD_PHASES)),
                  'phases_us': {k: '1' for k in COLD_PHASES}}
        self.assertEqual(sum(validate_phases(report).values()), len(COLD_PHASES))
        report['command_us'] = '1000'
        with self.assertRaises(ValueError):
            validate_phases(report)
        del report['phases_us']['compile']
        with self.assertRaises(ValueError):
            validate_phases(report)

    def test_failure_is_not_silently_filtered_out_of_comparison(self):
        rows = [{'workload': 'w', 'engine': e, 'mode': 'plain', 'status': 'error'}
                for e in ['wasmoon', 'wasmtime']]
        self.assertIn('error', summarize(rows)['w'])

    def test_diagnostics_and_warmups_do_not_enter_timing_medians(self):
        rows = []
        for e in ['wasmoon', 'wasmtime']:
            for mode, value in [('plain', 1), ('warmup', 100), ('phases', 200)]:
                rows.append({'workload': 'w', 'engine': e, 'mode': mode, 'status': 'ok',
                             'wall_seconds': value, 'peak_rss_bytes': value,
                             'guest_metric': value})
        self.assertEqual(summarize(rows)['w']['medians']['wasmoon']['wall_seconds'], 1)

    def test_changed_cli_artifact_rejects_a_two_build_comparison(self):
        rows = [{'workload': 'w', 'engine': e, 'mode': 'plain', 'status': 'ok',
                 'wall_seconds': 1, 'peak_rss_bytes': 1, 'guest_metric': 1,
                 'artifact_sha256': e} for e in ['before', 'after']]
        with self.assertRaisesRegex(ValueError, 'artifact bytes differ'):
            summarize(rows)
        result = summarize(rows, allow_artifact_differences=True)['w']
        self.assertFalse(result['artifacts_equal'])
        rows.append({**rows[0], 'artifact_sha256': 'nondeterministic'})
        with self.assertRaisesRegex(ValueError, 'vary within one build'):
            summarize(rows, allow_artifact_differences=True)
