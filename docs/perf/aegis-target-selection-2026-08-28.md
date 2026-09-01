# AEGIS-128L Indexed Target Selection (2026-08-28)

## Revisions and method

- Baseline: `e5a48fec` (ISS-441 closing state)
- Final: `fa2dd65d`
- Host: Apple M3 Max, arm64, macOS 26.5.2 (25F84)
- Workload: `examples/algorithms/aead_aegis128l.wasm`
- Seven detailed, serial, cache-isolated final captures
- Baseline target-lowering median: 18,887 us

The final captures used a distinct `WASMOON_JIT_CACHE_DIR` for each process and
enabled schema-5 detailed metrics. No other corpus workload was run.

## Results

| Run | Target total | Analysis | VCode construction | VCode validation |
| ---: | ---: | ---: | ---: | ---: |
| 1 | 16,101 | 3,485 | 6,166 | 5,155 |
| 2 | 14,982 | 3,076 | 6,162 | 4,860 |
| 3 | 15,232 | 3,133 | 6,240 | 4,975 |
| 4 | 14,983 | 3,142 | 6,068 | 4,863 |
| 5 | 15,029 | 3,100 | 6,134 | 4,881 |
| 6 | 15,036 | 3,138 | 6,083 | 4,925 |
| 7 | 15,136 | 3,073 | 6,155 | 5,000 |
| Median | 15,036 | 3,133 | 6,155 | 4,925 |

Target lowering fell by 3,851 us, or 20.39 percent. The final module-compile
median was 131,891 us and register allocation was 54,016 us, so equivalent
work did not move into regalloc or the module residual.

The production AArch64 and x64 selectors no longer call the semantic MachV
snapshot APIs for blocks, block parameters, block instructions, instruction
operands, instruction results, or instruction metadata. They consume stable
indexed storage, reuse one CFG order, map semantic operands directly into
required VCode arrays, and read GC metadata through an opaque view.

## Artifact identity

A temporary detached worktree built the baseline revision. One cold-cache
AEGIS run from each revision produced byte-identical v9 AArch64 `.cwasm`
artifacts:

`0c31ca17b8f04e9ecd0022eb185d367d7027d197ba83f87cd762a8e2f4639840`

The seven measured final reports also retained the 59,428-byte code-size vector
and 16,036-byte function 56. Strict native allocation validation passed
2,677/2,677 tests, and the module-boundary audit passed.

## Next constraint

The split metric shows that completed target VCode construction now costs
6,155 us, while a separate full target verifier still costs 4,925 us. The next
change should make trusted target construction produce a sealed verified state
without weakening validation of externally supplied VCode; further snapshot
getter tuning cannot recover this cost.
