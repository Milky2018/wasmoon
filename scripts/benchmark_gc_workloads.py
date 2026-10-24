#!/usr/bin/env python3
"""Compare asserted GC workloads across Wasmoon, Wasmtime and optimized V8.

Fresh processes and independent cold caches; compilation is serial in every
engine. Wasmoon and V8 additionally report their own compilation/invocation
boundaries. Whole-process CPU/RSS includes compilation and teardown. Generated
Wasm, samples and caches are automatically removed, including on failure.
"""
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


def array_workload(count: int, *, vector: bool, nonzero: bool, size: int | None = None) -> str:
    # Exported mutable state prevents treating every array as a local aggregate.
    element = 'v128' if vector else 'i32'
    if size is None:
        size = 1024 if vector else 4096
    init = ('v128.const i64x2 0 42' if nonzero else 'v128.const i64x2 0 0') if vector else ('i32.const 42' if nonzero else 'i32.const 0')
    check = ('i64x2.extract_lane 1 i64.const ' + ('42' if nonzero else '0') + ' i64.eq') if vector else ('i32.const ' + ('42' if nonzero else '0') + ' i32.eq')
    return f"""(module
      (type $a (array (mut {element})))
      (global $last (export "last") (mut (ref null $a)) (ref.null $a))
      (func (export "probe") (result i32) (local $i i32)
        (loop $again
          {init} i32.const {size} array.new $a global.set $last
          global.get $last i32.const {size - 1} array.get $a
          {check} i32.eqz (if (then unreachable))
          local.get $i i32.const 1 i32.add local.tee $i
          i32.const {count} i32.lt_u br_if $again)
        i32.const 1))"""


def graph_workload(count: int) -> str:
    # A long-lived chain survives several full collections while a reference
    # ring mutates and short-lived arrays provide allocation pressure. The chain
    # is checked after churn, rather than merely checking that allocation works.
    nodes = 32768
    return f"""(module
      (type $node (struct (field (ref null $node)) (field i32)))
      (type $bytes (array (mut i32)))
      (type $ring (array (mut (ref null $node))))
      (global $head (export "head") (mut (ref null $node)) (ref.null $node))
      (global $ring (mut (ref null $ring)) (ref.null $ring))
      (global $last (mut (ref null $bytes)) (ref.null $bytes))
      (func (export "probe") (result i32)
        (local $i i32) (local $cursor (ref null $node)) (local $sum i32)
        ref.null $node global.set $head
        (loop $build
          global.get $head local.get $i struct.new $node global.set $head
          local.get $i i32.const 1 i32.add local.tee $i
          i32.const {nodes} i32.lt_u br_if $build)
        i32.const 256 array.new_default $ring global.set $ring
        i32.const 0 local.set $i
        (loop $churn
          global.get $ring local.get $i i32.const 255 i32.and
          ref.null $node local.get $i struct.new $node array.set $ring
          i32.const 4096 array.new_default $bytes global.set $last
          global.get $last i32.const 4095 array.get $bytes
          (if (then unreachable))
          local.get $i i32.const 1 i32.add local.tee $i
          i32.const {count} i32.lt_u br_if $churn)
        global.get $head local.set $cursor
        (block $done (loop $walk
          local.get $cursor ref.is_null br_if $done
          local.get $sum local.get $cursor struct.get $node 1 i32.add local.set $sum
          local.get $cursor struct.get $node 0 local.set $cursor br $walk))
        local.get $sum i32.const {nodes * (nodes - 1) // 2} i32.eq
        global.get $ring i32.const {(count - 1) & 255} array.get $ring
        struct.get $node 1 i32.const {count - 1} i32.eq i32.and))"""


def workloads(scale: int) -> dict[str, str]:
    count = 10000 * scale
    return {
        'i32-zero': array_workload(count, vector=False, nonzero=False),
        'i32-nonzero': array_workload(count, vector=False, nonzero=True),
        'i32-small-nonzero': array_workload(count * 10, vector=False, nonzero=True, size=4),
        'i32-single-nonzero': array_workload(count * 10, vector=False, nonzero=True, size=1),
        'i32-tail-nonzero': array_workload(count * 10, vector=False, nonzero=True, size=17),
        'v128-high-word': array_workload(count, vector=True, nonzero=True),
        'survivors-and-mutation': graph_workload(count),
    }


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


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
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
    with tempfile.TemporaryDirectory(prefix='wasmoon-gc-throughput-') as directory:
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


if __name__ == '__main__':
    main()
