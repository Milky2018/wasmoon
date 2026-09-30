#!/usr/bin/env python3
"""Measure complete cold compilation of real modules and compare exact artifacts.

Build testsuite/compiler_memory at both revisions first. Each sample launches a
fresh process; the fixture calls compile_module directly, bypassing the JIT cache.
Allocation instrumentation must not be enabled in these timing binaries.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import platform
import random
import re
import statistics
import subprocess
import time
from pathlib import Path


def peak_rss(log: str, system: str) -> int:
    if system == 'Darwin':
        match = re.search(r'^\s*(\d+)\s+maximum resident set size', log, re.M)
        multiplier = 1
    else:
        match = re.search(r'Maximum resident set size \(kbytes\):\s*(\d+)', log)
        multiplier = 1024
    if not match:
        raise ValueError('missing peak RSS in /usr/bin/time output')
    return int(match[1]) * multiplier


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def paired_change(before: list[float], after: list[float]) -> dict:
    if not before or len(before) != len(after) or any(x <= 0 for x in before):
        raise ValueError('expected positive, equally sized paired measurements')
    changes = [(a / b - 1) * 100 for b, a in zip(before, after)]
    rng = random.Random(586)
    medians = sorted(statistics.median(rng.choices(changes, k=len(changes)))
                     for _ in range(10000))
    return {'median_percent': statistics.median(changes),
            'bootstrap_95_percent': [medians[250], medians[9749]]}


def sample(binary: Path, workload: Path, output: Path, system: str) -> dict:
    output.mkdir(parents=True)
    artifact = output / 'result.artifact'
    started = time.monotonic()
    result = subprocess.run(
        ['/usr/bin/time', '-l' if system == 'Darwin' else '-v', str(binary),
         str(workload), str(artifact)], capture_output=True, text=True, timeout=180,
        env=os.environ | {'WASMOON_PERF_METRICS': '0', 'WASMOON_PERF_METRICS_DETAIL': '0'})
    wall = time.monotonic() - started
    (output / 'stdout.txt').write_text(result.stdout)
    (output / 'stderr.txt').write_text(result.stderr)
    if result.returncode != 0:
        raise RuntimeError(f'compilation failed: {output}')
    duration = int(result.stdout.strip())
    if duration <= 0:
        raise RuntimeError(f'invalid compilation duration: {output}')
    return {'compile_us': duration, 'wall_seconds': wall,
            'peak_rss_bytes': peak_rss(result.stderr, system),
            'artifact_sha256': digest(artifact)}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--before', type=Path, required=True)
    parser.add_argument('--after', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--repetitions', type=int, default=15)
    parser.add_argument('workloads', nargs='+', type=Path)
    args = parser.parse_args()
    if args.repetitions < 3:
        parser.error('at least three pairs are required')
    system = platform.system()
    if system not in {'Darwin', 'Linux'}:
        parser.error('RSS collection requires macOS or Linux')
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    binaries = {'before': args.before.resolve(), 'after': args.after.resolve()}
    report = {'platform': platform.platform(), 'repetitions': args.repetitions,
              'binary_sha256': {k: digest(v) for k, v in binaries.items()},
              'workloads': {}}
    for index, source in enumerate(args.workloads):
        source = source.resolve()
        key = f'{index}-{source.stem}'
        samples = {k: [] for k in binaries}
        # Warm filesystem/code pages once for each binary; artifact caching is absent.
        for label, binary in binaries.items():
            sample(binary, source, output / key / label / 'warmup', system)
        for repetition in range(args.repetitions):
            order = list(binaries)
            if (index + repetition) % 2:
                order.reverse()
            for label in order:
                row = sample(binaries[label], source,
                             output / key / label / str(repetition), system)
                samples[label].append(row)
        if len({r['artifact_sha256'] for rows in samples.values() for r in rows}) != 1:
            raise RuntimeError(f'artifact bytes differ: {source}')
        summary = {
            'input': str(source), 'input_sha256': digest(source), 'samples': samples,
            'medians': {label: {k: statistics.median(r[k] for r in rows)
                                for k in ['compile_us', 'wall_seconds', 'peak_rss_bytes']}
                        for label, rows in samples.items()},
            'paired_compile_change': paired_change(
                [r['compile_us'] for r in samples['before']],
                [r['compile_us'] for r in samples['after']]),
        }
        report['workloads'][key] = summary
        (output / 'summary.json').write_text(json.dumps(report, indent=2) + '\n')
        print(key, summary['medians'], summary['paired_compile_change'], flush=True)


if __name__ == '__main__':
    main()
