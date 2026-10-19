"""Serial, paired guest-interval measurements; run only after all builds/tests stop."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import random
import re
import statistics
import subprocess

p = argparse.ArgumentParser()
p.add_argument('before', type=Path)
p.add_argument('after', type=Path)
p.add_argument('fixtures', type=Path)
p.add_argument('counter_library', type=Path)
p.add_argument('output', type=Path)
a = p.parse_args()
rng = random.Random(638)
cases = [(kind, n) for kind in ('bind', 'suspend') for n in (10, 100, 1000, 10000, 30000)]
binaries = {'before': a.before.resolve(), 'after': a.after.resolve()}
sha = lambda path: hashlib.sha256(path.read_bytes()).hexdigest()
result = {
    'seed': 638, 'warmup_rounds': 2, 'measured_rounds': 21,
    'method': 'Serial subprocesses, shuffled cases and paired version order. Two putchar call boundaries exclude loading/compilation and teardown. Thread CPU time; process retired instructions/cycles. No core affinity or frequency control.',
    'binaries': {k: {'path': str(v), 'sha256': sha(v)} for k, v in binaries.items()},
    'counter_library_sha256': sha(a.counter_library),
    'fixtures': {f'{k}-{n}': sha(a.fixtures / f'{k}-{n}.wast') for k, n in cases},
    'samples': [],
}
for round_no in range(-2, 21):
    order = cases.copy()
    rng.shuffle(order)
    for kind, n in order:
        versions = list(binaries)
        rng.shuffle(versions)
        for version in versions:
            cmd = [str(binaries[version]), 'test', str((a.fixtures / f'{kind}-{n}.wast').resolve()), '--stack-switching']
            env = dict(os.environ, DYLD_INSERT_LIBRARIES=str(a.counter_library.resolve()))
            run = subprocess.run(cmd, env=env, capture_output=True, text=True, timeout=120)
            counters = re.findall(r'\[DEBUG-rootcause-store\] (\d+) (\d+) (\d+)', run.stderr)
            if run.returncode or len(counters) != 1 or not re.search(r'Passed:\s+1\s+Failed:\s+0\s+Skipped:\s+0', run.stdout):
                raise RuntimeError((cmd, run.returncode, run.stdout, run.stderr))
            cpu, instructions, cycles = map(int, counters[0])
            assert min(cpu, instructions, cycles) > 0
            result['samples'].append(dict(round=round_no, case=f'{kind}-{n}', version=version,
                                          cpu_ns=cpu, instructions=instructions, cycles=cycles))
    a.output.write_text(json.dumps(result, indent=2) + '\n')
    print(f'round {round_no} complete', flush=True)
result['summary'] = {}
for kind, n in cases:
    case = f'{kind}-{n}'
    rows = [s for s in result['samples'] if s['round'] >= 0 and s['case'] == case]
    metrics = {}
    for metric in ('cpu_ns', 'instructions', 'cycles'):
        before = [next(s[metric] for s in rows if s['round'] == i and s['version'] == 'before') for i in range(21)]
        after = [next(s[metric] for s in rows if s['round'] == i and s['version'] == 'after') for i in range(21)]
        ratios = [y / x for x, y in zip(before, after)]
        boot = sorted(statistics.median(rng.choices(ratios, k=21)) for _ in range(10000))
        metrics[metric] = {'before_median': statistics.median(before), 'after_median': statistics.median(after),
                           'paired_ratio_median': statistics.median(ratios), 'paired_ratio_bootstrap_95pct': [boot[249], boot[9749]]}
    result['summary'][case] = metrics
assert all(sha(v) == result['binaries'][k]['sha256'] for k, v in binaries.items())
a.output.write_text(json.dumps(result, indent=2) + '\n')
print(json.dumps(result['summary'], indent=2))
