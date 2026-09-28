#!/usr/bin/env python3
"""Compare fresh-process compiler time/RSS with serial, cold-cache samples.

Uses the host's /usr/bin/time (macOS or Linux). Artifacts, metrics, input hashes,
raw logs, and per-sample results are retained for independent inspection.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import statistics
import subprocess
import tempfile
import time


def function(name: str, operations: int) -> str:
    step = 'local.get 0 i32.add i32.const 5 i32.rotl i32.const 1664525 i32.mul'
    return f'(func ${name} (param i32) (result i32) local.get 0 ' + ' '.join([step] * operations) + ')'


def workload(sizes: list[int]) -> str:
    functions = [function(f'f{i}', size) for i, size in enumerate(sizes)]
    calls = [f'i32.const {i + 1} call $f{i} drop' for i in range(len(sizes))]
    return '(module\n' + '\n'.join(functions) + '\n(func (export "main") (result i32) ' + ' '.join(calls) + ' i32.const 42))\n'


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


def sample(binary: Path, case: Path, directory: Path, system: str, metrics_enabled: bool) -> dict:
    directory.mkdir(parents=True)
    metrics = directory / 'metrics.json'
    cache_report = directory / 'cache.json'
    with tempfile.TemporaryDirectory(prefix='wasmoon-compile-cache-') as cache:
        env = os.environ | {
            'LC_ALL': 'C', 'WASMOON_JIT_CACHE_DIR': cache,
            'WASMOON_JIT_CACHE_REPORT': str(cache_report),
            'WASMOON_PERF_METRICS': '1' if metrics_enabled else '0',
            'WASMOON_PERF_METRICS_DETAIL': '1' if metrics_enabled else '0',
            'WASMOON_PERF_METRICS_FILE': str(metrics),
        }
        command = ['/usr/bin/time', '-l' if system == 'Darwin' else '-v',
                   str(binary), 'run', '--invoke', 'main', str(case)]
        started = time.monotonic()
        result = subprocess.run(command, capture_output=True, text=True, env=env, timeout=180)
        elapsed = time.monotonic() - started
    (directory / 'stdout.txt').write_text(result.stdout)
    (directory / 'stderr.txt').write_text(result.stderr)
    if result.returncode or (metrics_enabled and not metrics.exists()):
        raise RuntimeError(f'compilation failed or metrics missing: {directory}')
    cache_evidence = json.loads(cache_report.read_text())
    if cache_evidence.get('freshly_compiled') is not True or cache_evidence.get('cache_hit') is not False:
        raise RuntimeError(f'expected cold compilation: {directory}')
    data = json.loads(metrics.read_text()) if metrics_enabled else None
    functions = data['functions'] if data else []
    if metrics_enabled and (not functions or int(data['module_compile_us']) <= 0):
        raise RuntimeError(f'no fresh compilation recorded: {directory}')
    return {
        'compile_us': int(data['module_compile_us']) if data else None,
        'packaging_us': sum(int(p['duration_us']) for f in functions for p in f.get('compile_subphases', []) if p['name'] == 'artifact_packaging') if data else None,
        'peak_rss_bytes': peak_rss(result.stderr, system),
        'wall_seconds': elapsed,
        'functions': len(functions),
        'code_bytes': sum(f['code_size'] for f in functions),
        'stdout': result.stdout,
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--before', type=Path, required=True)
    parser.add_argument('--after', type=Path)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--repetitions', type=int, default=7)
    parser.add_argument('--no-metrics', action='store_true', help='measure ordinary CLI wall time/RSS without profiling allocations')
    args = parser.parse_args()
    if args.repetitions < 1:
        parser.error('repetitions must be positive')
    system = platform.system()
    if system not in {'Darwin', 'Linux'}:
        parser.error('peak RSS collection currently requires macOS or Linux')
    out = args.output.resolve()
    out.mkdir(parents=True, exist_ok=False)
    binaries = {'before': args.before.resolve()}
    if args.after:
        binaries['after'] = args.after.resolve()
    cases = {
        'many-small': [4] * 1500, 'one-medium': [3000],
        'one-large': [30000], 'large-then-small': [30000] + [4] * 1000,
    }
    report = {'platform': platform.platform(), 'repetitions': args.repetitions, 'metrics_enabled': not args.no_metrics,
              'binary_sha256': {k: hashlib.sha256(v.read_bytes()).hexdigest() for k, v in binaries.items()},
              'workloads': {}}
    for name, sizes in cases.items():
        wat = out / (name + '.wat')
        wasm = out / (name + '.wasm')
        wat.write_text(workload(sizes))
        subprocess.run(['wasm-tools', 'parse', str(wat), '-o', str(wasm)], check=True)
        samples = {label: [] for label in binaries}
        for repetition in range(args.repetitions):
            # Alternate order to limit machine-load and thermal drift bias.
            order = list(binaries)
            if repetition % 2:
                order.reverse()
            for label in order:
                value = sample(binaries[label], wasm, out / name / label / str(repetition), system, not args.no_metrics)
                if not args.no_metrics and value['functions'] != len(sizes) + 1:
                    raise RuntimeError(f'incomplete compilation: {name}')
                samples[label].append(value)
                print(name, label, repetition, json.dumps(value), flush=True)
        outputs = {s['stdout'] for rows in samples.values() for s in rows}
        shapes = {(s['functions'], s['code_bytes']) for rows in samples.values() for s in rows}
        if len(outputs) != 1 or len(shapes) != 1:
            raise RuntimeError(f'guest output or emitted-code size differs: {name}')
        report['workloads'][name] = {
            'input_sha256': hashlib.sha256(wasm.read_bytes()).hexdigest(),
            'samples': samples,
            'medians': {label: {key: statistics.median(s[key] for s in rows) if rows[0][key] is not None else None
                               for key in ['compile_us', 'packaging_us', 'peak_rss_bytes', 'wall_seconds']}
                        for label, rows in samples.items()},
        }
        (out / 'summary.json').write_text(json.dumps(report, indent=2) + '\n')
    print('Results:', out / 'summary.json')


if __name__ == '__main__':
    main()
