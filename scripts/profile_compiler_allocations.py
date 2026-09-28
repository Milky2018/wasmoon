#!/usr/bin/env python3
"""Build an isolated, serial MoonBit compiler allocation tracer on macOS.

Uses the toolchain's runtime.c, generated C and native link command, without
editing any of them. This is diagnostic instrumentation, not a timing binary.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import shlex
import subprocess

ROOT = Path(__file__).resolve().parents[1]
FIXTURE = 'modules/wasmoon/testsuite/compiler_memory'


def run(command, **kwargs):
    return subprocess.run(command, check=True, **kwargs)


def build(output: Path) -> Path:
    target = output / 'build'
    command = ['moon', 'build', FIXTURE, '--target', 'native', '--release',
               '--target-dir', str(target)]
    run(command)
    dry = subprocess.check_output(command + ['--dry-run'], text=True)
    (output / 'build-commands.txt').write_text(dry)
    candidates = [shlex.split(line) for line in dry.splitlines()
                  if 'compiler_memory.c ' in line and 'libruntime.a' in line]
    if len(candidates) != 1:
        raise RuntimeError('expected exactly one compiler fixture link command')
    home = Path(os.environ.get('MOON_HOME', Path.home() / '.moon'))
    link = [part.replace('$MOON_HOME', str(home)) for part in candidates[0]]
    if '-DMOONBIT_ALLOCATOR=MOONBIT_ALLOCATOR_MIMALLOC' not in link:
        raise RuntimeError('this tracer requires the mimalloc native backend')
    recorder = output / 'recorder.o'
    runtime = output / 'runtime.o'
    source = ROOT / 'scripts/profiling/compiler_allocations.c'
    run(['clang', '-O2', '-g', '-Wall', '-Wextra', '-Werror', '-c', str(source), '-o', str(recorder)])
    # Validate exact accounting separately from the MoonBit program.
    control = output / 'control.c'
    control.write_text('''#include <stdlib.h>
void *probe_alloc(size_t); void probe_free(void*);
void *mi_malloc(size_t n){return malloc(n);} void mi_free(void *p){free(p);}
int main(void){void *a=probe_alloc(20),*b=probe_alloc(30);probe_free(a);probe_free(b);return 0;}
''')
    run(['clang', str(control), str(recorder), '-o', str(output / 'control')])
    run([str(output / 'control')], env=os.environ | {'WASMOON_ALLOC_PROFILE': str(output / 'control.alloc')})
    control_stats, _ = read_trace(output / 'control.alloc')
    if [control_stats[k] for k in ['total', 'count', 'live', 'peak', 'untracked_frees']] != [50, 2, 0, 50, 0]:
        raise RuntimeError(f'allocator control failed: {control_stats}')
    substitutions = ['-Dmi_malloc=probe_alloc', '-Dmi_free=probe_free']
    runtime_source = home / 'lib/runtime/runtime.c'
    run(['clang', '-O2', '-g', '-I' + str(home / 'include'), '-DMOONBIT_ALLOCATOR=2',
         *substitutions, '-c', str(runtime_source), '-o', str(runtime)])
    binary = output / 'compiler-profile'
    link[link.index('-o') + 1] = str(binary)
    archive = next(part for part in link if part.endswith('/libruntime.a'))
    link.insert(link.index(archive), str(runtime))
    link += ['-g', '-fno-omit-frame-pointer', *substitutions, str(recorder)]
    (output / 'instrumented-command.json').write_text(json.dumps(link, indent=2))
    run(link)
    (output / 'runtime-sha256.txt').write_text(hashlib.sha256(runtime_source.read_bytes()).hexdigest() + '\n')
    return binary


def read_trace(path):
    lines = path.read_text().splitlines()
    tokens = lines[0].split()
    stats = {tokens[i]: tokens[i+1] if tokens[i] == 'base' else int(tokens[i+1])
             for i in range(0, len(tokens), 2)}
    rows = []
    for line in lines[1:]:
        fields = line.split()
        rows.append(dict(zip(['bytes', 'count', 'live', 'peak'], map(int, fields[:4]))) | {'addresses': fields[4:]})
    for key, total in [('bytes', 'total'), ('count', 'count'), ('live', 'live')]:
        if sum(row[key] for row in rows) != stats[total]:
            raise RuntimeError(f'inconsistent allocation accounting: {key}')
    return stats, rows


def capture(binary, workload, output):
    trace = output.with_suffix('.alloc')
    artifact = output.with_suffix('.artifact')
    run([str(binary), str(workload), str(artifact)],
        env=os.environ | {'WASMOON_ALLOC_PROFILE': str(trace)})
    stats, rows = read_trace(trace)
    addresses = list(dict.fromkeys(address for row in rows for address in row['addresses']))
    names = []
    for offset in range(0, len(addresses), 200):
        names += subprocess.check_output(['atos', '-o', str(binary), '-l', stats['base'],
                                          *addresses[offset:offset+200]], text=True).splitlines()
    if len(names) != len(addresses):
        raise RuntimeError('incomplete symbolization')
    symbols = dict(zip(addresses, names))
    for row in rows:
        row['stack'] = [symbols[address] for address in row.pop('addresses')]
    result = {'totals': stats, 'input_sha256': hashlib.sha256(workload.read_bytes()).hexdigest(),
              'artifact_sha256': hashlib.sha256(artifact.read_bytes()).hexdigest(),
              'stacks': sorted(rows, key=lambda row: -row['bytes'])}
    output.with_suffix('.json').write_text(json.dumps(result, indent=2) + '\n')
    print(workload.name, stats, flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('workloads', nargs='+', type=Path)
    args = parser.parse_args()
    if platform.system() != 'Darwin':
        parser.error('this diagnostic tracer currently uses macOS atos')
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    binary = build(output)
    for index, workload in enumerate(args.workloads):
        capture(binary, workload.resolve(), output / f'{index}-{workload.stem}')


if __name__ == '__main__':
    main()
