#!/usr/bin/env python3
"""Serial interpreter dispatch/capture/scheduler measurements; no timing gate.

The generated executable, builds and caches live in an auto-cleaned OS directory.
Pass --wasm to include a compiler-produced module without imports, using its
function index and a single i32 iteration argument. Every mode checks its values
against an untimed synchronous invocation of the same instance.
"""
import argparse
import json
from pathlib import Path
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--iterations', type=int, default=1000000)
    parser.add_argument('--trials', type=int, default=3)
    parser.add_argument('--quanta', type=int, nargs='+', default=[1024, 16384])
    parser.add_argument('--wasm', type=Path)
    parser.add_argument('--function-index', type=int, default=0)
    args = parser.parse_args()
    if min(args.iterations, args.trials, *args.quanta) <= 0:
        parser.error('iterations, trials and quanta must be positive')
    workloads = []
    for name, declaration, step in [
        ('loop', '', 'local.get 0 i32.const 1 i32.sub'),
        ('calls', '(func $dec (param i32) (result i32) local.get 0 i32.const 1 i32.sub)',
         'local.get 0 call $dec'),
        ('memory', '(memory 1)',
         'i32.const 0 local.get 0 i32.const 1 i32.sub i32.store '
         'i32.const 0 i32.load'),
    ]:
        source = (f'(module {declaration} (func (export "run") (param i32) '
                  f'(result i32) (loop $again {step} local.tee 0 br_if $again) local.get 0))')
        index = 1 if name == 'calls' else 0
        workloads.append(f'({json.dumps(name)}, @wat.parse({json.dumps(source)}), {index})')
    if args.wasm:
        workloads.append(f'("compiler-module", @parser.parse_module(@fs.read_file_to_bytes('
                         f'{json.dumps(str(args.wasm.resolve()))})), {args.function_index})')
    program = r'''
async fn main {
  let workloads = [WORKLOADS]
  println("workload,mode,quantum,trial,ms,yields,check")
  for (name, module_, index) in workloads {
    @validator.validate_module(module_)
    let (store, instance) = @executor.instantiate_module(module_)
    defer store.close()
    let input = [@types.Value::I32(ITERATIONS)]
    let expected = @executor.call_func_by_index(store, instance, index, input)
    for trial in 0..<TRIALS {
      let started = @async.now()
      let values = @executor.call_func_by_index(store, instance, index, input)
      assert_eq(values, expected)
      println("\{name},sync,0,\{trial},\{@async.now() - started},0,matched")
      for quantum in [QUANTA] {
        for scheduled in [false, true] {
          let started = @async.now()
          let mut yields = 0
          let mut outcome = @executor.call_func_by_index_resumable(
            store, instance, index, input, _ => None,
            cooperative=true, cooperative_quantum=quantum)
          while outcome is Suspended(CooperativeYield, continuation) {
            yields += 1
            if scheduled { @async.sleep(0) }
            outcome = continuation.continue_execution()
          }
          guard outcome is Returned(values) else { fail("unexpected suspension") }
          assert_eq(values, expected)
          let mode = if scheduled { "scheduler" } else { "inline" }
          println("\{name},\{mode},\{quantum},\{trial},\{@async.now() - started},\{yields},matched")
        }
      }
    }
  }
}
'''
    program = program.replace('WORKLOADS', ',\n'.join(workloads))
    program = program.replace('ITERATIONS', str(args.iterations)).replace('TRIALS', str(args.trials))
    program = program.replace('QUANTA', ','.join(map(str, args.quanta)))
    with tempfile.TemporaryDirectory(prefix='wasmoon-quantum-') as directory:
        root = Path(directory)
        members = re.findall(r'"(\./modules/[^"]+)"', (ROOT / 'moon.work').read_text())
        members = [str((ROOT / member).resolve()) for member in members] + ['.']
        (root / 'moon.work').write_text('members = ' + json.dumps(members))
        (root / 'moon.mod').write_text('''name = "wasmoon/quantum_benchmark"
import { "Milky2018/wasmoon_runtime@0.17.1", "Milky2018/wasm_core@0.17.1",
         "moonbitlang/async@0.22.4", "moonbitlang/x@0.5.5" }
''')
        imports = ['Milky2018/wasmoon_runtime/executor',
                   'Milky2018/wasm_core/types', 'Milky2018/wasm_core/wat',
                   'Milky2018/wasm_core/validator', 'moonbitlang/async']
        if args.wasm:
            imports += ['Milky2018/wasm_core/parser', 'moonbitlang/x/fs']
        (root / 'moon.pkg').write_text('import ' + json.dumps(imports).replace('[', '{').replace(']', '}')
                                      + '\npkgtype(kind: "executable")\n')
        (root / 'main.mbt').write_text(program)
        subprocess.run(['moon', 'run', '--target', 'native', '--release', '.'], cwd=root, check=True)


if __name__ == '__main__':
    main()
