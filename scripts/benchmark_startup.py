#!/usr/bin/env python3
"""Repeated serial cold CLI measurements, with separate Wasmoon attribution runs.

All samples, including warmups and failures, are retained. Detailed compiler
metrics deliberately run separately because they bypass normal cache handling.
"""
from __future__ import annotations

import argparse
import json
import os
import platform
import signal
import statistics
import subprocess
import time
from pathlib import Path

from benchmark_algorithms_parity import prepare_isolated_caches, parse_first_number
from benchmark_compiler_memory import digest, paired_change, peak_rss

DEFAULT_WORKLOADS = [
    'auth', 'onetimeauth', 'aead_chacha20poly1305',
    'generichash', 'aead_aegis128l', 'xchacha20',
]
COLD_PHASES = {
    'host_setup_and_preloads', 'read_and_parse', 'validate',
    'instantiate_including_start', 'jit_plan_and_cache_lookup', 'compile',
    'artifact_verify', 'cache_write_and_report', 'jit_load_and_prepare',
    'invoke_including_hostcalls', 'finish_or_early_return',
}


def validate_phases(report: dict) -> dict[str, int]:
    if report.get('schema_version') != 1:
        raise ValueError('unsupported run metrics schema')
    phases = {k: int(v) for k, v in report['phases_us'].items()}
    if set(phases) != COLD_PHASES or any(v < 0 for v in phases.values()):
        raise ValueError('incomplete cold JIT phase report')
    if sum(phases.values()) != int(report['command_us']):
        raise ValueError('run phases do not reconcile to command duration')
    return phases


def measure(binary: Path, engine: str, source: Path, output: Path,
            system: str, mode: str, timeout: int) -> dict:
    output.mkdir(parents=True)
    caches = prepare_isolated_caches(output / 'cache', source)
    env = {k: v for k, v in os.environ.items()
           if not k.startswith(('WASMOON_PERF_', 'WASMOON_RUN_METRICS_',
                                'WASMOON_JIT_CACHE'))}
    cache_report = output / 'cache.json'
    phases_file = output / 'phases.json'
    detail_file = output / 'compiler.json'
    if engine == 'wasmoon':
        command = [str(binary), 'run', str(source)]
        env.update(WASMOON_JIT_CACHE_DIR=str(caches.wasmoon),
                   WASMOON_JIT_CACHE_REPORT=str(cache_report))
        if mode == 'phases':
            env['WASMOON_RUN_METRICS_FILE'] = str(phases_file)
        if mode == 'compiler':
            env.update(WASMOON_PERF_METRICS='1', WASMOON_PERF_METRICS_DETAIL='1',
                       WASMOON_PERF_METRICS_FILE=str(detail_file))
    else:
        command = [str(binary), 'run', '-C', 'parallel-compilation=n',
                   '-C', 'cache=y', '-C', f'cache-config={caches.wasmtime_config}',
                   str(source)]
    row = {'engine': engine, 'mode': mode, 'command': command, 'output': str(output)}
    started = time.perf_counter()
    try:
        process = subprocess.Popen(
            ['/usr/bin/time', '-l' if system == 'Darwin' else '-v',
             '-o', str(output / 'rss.txt'), *command], env=env,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, start_new_session=True)
        try:
            stdout, stderr = process.communicate(timeout=timeout)
        except subprocess.TimeoutExpired:
            os.killpg(process.pid, signal.SIGKILL)
            stdout, stderr = process.communicate()
            row.update(stdout=stdout, stderr=stderr)
            raise ValueError(f'command timed out after {timeout}s; process group killed')
        result = subprocess.CompletedProcess(command, process.returncode, stdout, stderr)
        row.update(wall_seconds=time.perf_counter() - started,
                   returncode=result.returncode, stdout=result.stdout, stderr=result.stderr)
        (output / 'stdout.txt').write_text(result.stdout)
        (output / 'stderr.txt').write_text(result.stderr)
        if result.returncode != 0:
            raise ValueError(f'command failed: {result.returncode}')
        row['peak_rss_bytes'] = peak_rss((output / 'rss.txt').read_text(), system)
        # This is a guest-defined numeric metric, not assumed to be seconds.
        row['guest_metric'] = parse_first_number(result.stdout)
        if row['guest_metric'] is None:
            raise ValueError('missing guest metric')
        if engine == 'wasmoon':
            cache = json.loads(cache_report.read_text())
            row['cache'] = cache
            if cache.get('freshly_compiled') is not True or cache.get('cache_hit') is not False:
                raise ValueError('missing fresh compilation evidence')
            if mode != 'compiler' and cache.get('cache_write_succeeded') is not True:
                raise ValueError('cold run did not write its artifact')
            if mode != 'compiler':
                artifacts = list(caches.wasmoon.glob('*.cwasm'))
                if len(artifacts) != 1:
                    raise ValueError('expected exactly one cold CLI artifact')
                row['artifact_sha256'] = digest(artifacts[0])
            if mode == 'phases':
                row['phases_us'] = validate_phases(json.loads(phases_file.read_text()))
            if mode == 'compiler':
                row['compiler'] = json.loads(detail_file.read_text())
        row['status'] = 'ok'
    except (ValueError, OSError, KeyError, TypeError) as error:
        row.update(status='error', error=str(error))
        row.setdefault('wall_seconds', time.perf_counter() - started)
    (output / 'sample.json').write_text(json.dumps(row, indent=2) + '\n')
    return row


def summarize(rows: list[dict], *, allow_artifact_differences: bool = False) -> dict:
    summaries = {}
    engines = ['before', 'after'] if any(r['engine'] == 'before' for r in rows) else ['wasmtime', 'wasmoon']
    for workload in dict.fromkeys(r['workload'] for r in rows):
        selected = [r for r in rows if r['workload'] == workload]
        plain = {e: [r for r in selected if r['engine'] == e and r['mode'] == 'plain']
                 for e in engines}
        if any(r['status'] != 'ok' for group in plain.values() for r in group):
            summaries[workload] = {'error': 'failed ordinary sample; no filtered summary'}
            continue
        medians = {e: {metric: statistics.median(r[metric] for r in group)
                       for metric in ['wall_seconds', 'peak_rss_bytes', 'guest_metric']}
                   for e, group in plain.items()}
        artifacts_equal = None
        if engines == ['before', 'after']:
            hashes = {e: {r['artifact_sha256'] for r in group} for e, group in plain.items()}
            if any(len(values) != 1 for values in hashes.values()):
                raise ValueError(f'CLI artifact bytes vary within one build: {workload}')
            artifacts_equal = hashes['before'] == hashes['after']
            if not artifacts_equal and not allow_artifact_differences:
                raise ValueError(f'CLI artifact bytes differ: {workload}')
        summaries[workload] = {
            'artifacts_equal': artifacts_equal,
            'medians': medians,
            'paired_wall_change_percent': paired_change(
                [r['wall_seconds'] for r in plain[engines[0]]],
                [r['wall_seconds'] for r in plain[engines[1]]]),
        }
    return summaries


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--wasmoon', type=Path, default=Path('./wasmoon'))
    reference = parser.add_mutually_exclusive_group(required=True)
    reference.add_argument('--wasmtime', type=Path)
    reference.add_argument('--before', type=Path, help='compare two Wasmoon builds instead')
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--repetitions', type=int, default=15)
    parser.add_argument('--diagnostics', type=int, default=3)
    parser.add_argument('--timeout', type=int, default=120)
    parser.add_argument('--allow-artifact-differences', action='store_true',
                        help='compare intentional codegen/ABI changes; each build must still be deterministic')
    parser.add_argument('workloads', type=Path, nargs='*')
    args = parser.parse_args()
    system = platform.system()
    if system not in {'Darwin', 'Linux'} or args.repetitions < 3 or args.diagnostics < 1:
        parser.error('requires macOS/Linux, at least 3 repetitions and 1 diagnostic')
    if os.environ.get('DYLD_INSERT_LIBRARIES') or os.environ.get('LD_PRELOAD'):
        parser.error('disable injected allocation/profiling libraries before timing')
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    binaries = ({'before': args.before.resolve(), 'after': args.wasmoon.resolve()}
                if args.before else
                {'wasmoon': args.wasmoon.resolve(), 'wasmtime': args.wasmtime.resolve()})
    sources = args.workloads or [Path(f'examples/algorithms/{n}.wasm') for n in DEFAULT_WORKLOADS]
    sources = [p.resolve() for p in sources]
    report = {'schema_version': 1, 'platform': platform.platform(),
              'allow_artifact_differences': args.allow_artifact_differences,
              'repetitions': args.repetitions, 'diagnostics': args.diagnostics,
              'binary_sha256': {e: digest(p) for e, p in binaries.items()},
              'versions': {e: subprocess.check_output([str(p), '--version'], text=True).strip()
                           for e, p in binaries.items()},
              'input_sha256': {str(p): digest(p) for p in sources},
              'rows': []}

    def record(engine: str, source: Path, mode: str, iteration: int, index: int) -> None:
        directory = output / f'{index}-{source.stem}' / engine / f'{mode}-{iteration}'
        kind = 'wasmtime' if engine == 'wasmtime' else 'wasmoon'
        row = measure(binaries[engine], kind, source, directory, system, mode, args.timeout)
        row.update(engine=engine, workload=str(source), iteration=iteration)
        report['rows'].append(row)
        (output / 'summary.json').write_text(json.dumps(report, indent=2) + '\n')
        print(source.stem, engine, mode, iteration, row['status'], flush=True)

    # Warm executable/filesystem pages; every run still receives empty JIT caches.
    for iteration in range(-1, args.repetitions):
        for index, source in enumerate(sources):
            order = list(binaries)
            if (index + iteration) % 2:
                order.reverse()
            for engine in order:
                record(engine, source, 'warmup' if iteration < 0 else 'plain', iteration, index)
    # Instrumentation never overlaps or enters the ordinary timing sample set.
    for index, source in enumerate(sources):
        for engine in binaries:
            if engine == 'wasmtime':
                continue
            for iteration in range(args.diagnostics):
                record(engine, source, 'phases', iteration, index)
            record(engine, source, 'compiler', 0, index)
    report['summaries'] = summarize(report['rows'], allow_artifact_differences=args.allow_artifact_differences)
    report['failures'] = sum(r['status'] != 'ok' for r in report['rows'])
    (output / 'summary.json').write_text(json.dumps(report, indent=2) + '\n')
    return int(report['failures'] != 0)


if __name__ == '__main__':
    raise SystemExit(main())
