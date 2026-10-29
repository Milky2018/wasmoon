#!/usr/bin/env python3
"""Shared cold-cache, asserted execution protocol for generated workloads."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import signal
import statistics
import subprocess
import tempfile
import time

from benchmark_compiler_memory import peak_rss

V8_FLAGS = ['--no-liftoff', '--no-wasm-lazy-compilation',
            '--wasm-num-compilation-tasks=1']


V8_RUNNER = r"""
const fs = require('node:fs');
const {performance} = require('node:perf_hooks');
const bytes = fs.readFileSync(process.argv[2]);
let start = performance.now();
const module_ = new WebAssembly.Module(bytes);
const compile = (performance.now() - start) * 1000;
start = performance.now();
const instance = new WebAssembly.Instance(module_);
const instantiate = (performance.now() - start) * 1000;
start = performance.now();
const result = instance.exports.probe();
const invoke = (performance.now() - start) * 1000;
if (result !== 1) throw new Error(`workload assertion failed: ${result}`);
console.log(JSON.stringify({result, phases_us: {compile,
  instantiate_including_start: instantiate, invoke_including_hostcalls: invoke}}));
"""


def measure(command: list[str], env: dict, scratch: Path, *, system: str,
            timeout: float, json_output: bool) -> dict:
    timing = scratch / 'time.txt'
    started = time.perf_counter()
    process = subprocess.Popen(
        ['/usr/bin/time', '-l' if system == 'Darwin' else '-v',
         '-o', str(timing), *command], env=env, stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, text=True, start_new_session=True)
    try:
        stdout, stderr = process.communicate(timeout=timeout)
    except subprocess.TimeoutExpired:
        os.killpg(process.pid, signal.SIGKILL)
        process.communicate()
        raise
    result = subprocess.CompletedProcess(command, process.returncode, stdout, stderr)
    result.check_returncode()
    row = {'wall_seconds': time.perf_counter() - started,
           'peak_rss_bytes': peak_rss(timing.read_text(), system)}
    output = json.loads(result.stdout) if json_output else {'result': result.stdout.strip()}
    if output['result'] not in (1, '1'):
        raise RuntimeError(f'workload assertion failed: {result.stdout!r}')
    row['result'] = 1
    cpu = re.search(r'([0-9.]+)\s+user', timing.read_text()) if system == 'Darwin' else re.search(r'User time \(seconds\):\s*([0-9.]+)', timing.read_text())
    if cpu:
        row['user_cpu_seconds'] = float(cpu[1])
    if json_output:
        row['phases_us'] = output['phases_us']
    elif env.get('WASMOON_RUN_METRICS_FILE'):
        report = json.loads(Path(env['WASMOON_RUN_METRICS_FILE']).read_text())
        phases = {k: int(v) for k, v in report['phases_us'].items()}
        if not {'compile', 'invoke_including_hostcalls'} <= phases.keys():
            raise RuntimeError('missing cold compilation/invocation evidence')
        if any(v < 0 for v in phases.values()) or sum(phases.values()) != int(report['command_us']):
            raise RuntimeError('invalid phase accounting')
        row['phases_us'] = phases
    return row


def main(workloads, description: str) -> None:
    parser = argparse.ArgumentParser(description=description)
    parser.add_argument('--wasmoon', type=Path, required=True)
    parser.add_argument('--baseline', type=Path)
    parser.add_argument('--wasmtime', default='wasmtime')
    parser.add_argument('--node', default='node')
    parser.add_argument('--samples', type=int, default=3)
    parser.add_argument('--scale', type=int, default=1)
    parser.add_argument('--timeout', type=float, default=120)
    parser.add_argument('--case', action='append', choices=list(workloads(1)))
    args = parser.parse_args()
    if args.samples < 1 or args.scale < 1 or args.timeout <= 0:
        parser.error('samples, scale and timeout must be positive')
    system = platform.system()
    if system not in ('Darwin', 'Linux'):
        parser.error('per-process RSS requires macOS or Linux')
    binaries = {'wasmoon': args.wasmoon.resolve()}
    if args.baseline:
        binaries['baseline'] = args.baseline.resolve()
    env = {k: v for k, v in os.environ.items()
           if not k.startswith(('WASMOON_PERF', 'WASMOON_RUN_METRICS', 'WASMOON_JIT_CACHE'))
           and k not in ('VCODE_REGALLOC_VALIDATION', 'WASMOON_GC_VERIFY',
                         'WASMOON_GC_ASSERT_BARRIER', 'NODE_OPTIONS')}
    root = Path(__file__).resolve().parents[1]
    report = {'platform': platform.platform(), 'source_sha256': {}, 'samples': [],
              'source_revision': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=root, text=True).strip(),
              'source_dirty': bool(subprocess.check_output(['git', 'status', '--porcelain'], cwd=root, text=True).strip()),
              'binary_sha256': {k: hashlib.sha256(v.read_bytes()).hexdigest() for k, v in binaries.items()},
              'versions': {k: subprocess.check_output(v, text=True).strip() for k, v in {
                  'wasmtime': [args.wasmtime, '--version'], 'v8': [args.node, '-p', 'process.versions.v8'],
                  'wasm-tools': ['wasm-tools', '--version']}.items()},
              'phase_boundaries': {'wasmoon_compile': 'compiler only; parse/validate/install separate',
                                   'v8_compile': 'WebAssembly.Module including validation',
                                   'rss_cpu_wall': 'fresh whole process including compilation/teardown'},
              'v8_flags': V8_FLAGS, 'wasmtime_collector': 'copying'}
    with tempfile.TemporaryDirectory(prefix='wasmoon-workload-throughput-') as directory:
        scratch = Path(directory)
        js = scratch / 'v8.cjs'
        js.write_text(V8_RUNNER)
        for name, wat in workloads(args.scale).items():
            if args.case and name not in args.case:
                continue
            source = scratch / (name + '.wat')
            source.write_text(wat)
            fixture = source.with_suffix('.wasm')
            subprocess.run(['wasm-tools', 'parse', str(source), '-o', str(fixture)], check=True)
            subprocess.run(['wasm-tools', 'validate', str(fixture)], check=True)
            report['source_sha256'][name] = hashlib.sha256(fixture.read_bytes()).hexdigest()
            for sample in range(args.samples):
                engines = ['wasmtime', *binaries, 'v8']
                if sample % 2:
                    engines.reverse()
                for engine in engines:
                    with tempfile.TemporaryDirectory(dir=scratch) as cache:
                        sample_env = env | {'WASMOON_JIT_CACHE_DIR': cache, 'LC_ALL': 'C'}
                        if engine == 'wasmtime':
                            command = [args.wasmtime, 'run', '-C', 'parallel-compilation=n',
                                       '-C', 'cache=n', '-C', 'collector=copying', '--invoke', 'probe', str(fixture)]
                        elif engine == 'v8':
                            command = [args.node, *V8_FLAGS, str(js), str(fixture)]
                        else:
                            command = [str(binaries[engine]), 'run', '--invoke', 'probe', str(fixture)]
                            sample_env['WASMOON_RUN_METRICS_FILE'] = str(Path(cache) / 'phases.json')
                        row = measure(command, sample_env, Path(cache), system=system,
                                      timeout=args.timeout, json_output=engine == 'v8')
                        report['samples'].append({'case': name, 'engine': engine, 'sample': sample, **row})
    report['median'] = {}
    for name in report['source_sha256']:
        report['median'][name] = {}
        for engine in ['wasmtime', *binaries, 'v8']:
            rows = [r for r in report['samples'] if r['case'] == name and r['engine'] == engine]
            stats = {k: statistics.median(r[k] for r in rows)
                     for k in ('wall_seconds', 'user_cpu_seconds', 'peak_rss_bytes') if k in rows[0]}
            if 'phases_us' in rows[0]:
                stats['phases_us'] = {k: statistics.median(r['phases_us'][k] for r in rows)
                                      for k in rows[0]['phases_us']}
            report['median'][name][engine] = stats
    print(json.dumps(report, indent=2))
