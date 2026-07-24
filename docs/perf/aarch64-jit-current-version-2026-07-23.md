# AArch64 JIT Current-Version Performance Evidence

This report records the result of the ISS-252 optimization sequence. It compares
the current Wasmoon AArch64 JIT with Wasmtime for diagnostic context. It is not a
CI threshold and does not restore the retired fixed-legacy comparison gate.

## Provenance

| Item | Value |
| --- | --- |
| Wasmoon commit | `8e0a0c4482aec71e48549fe4591b5bee63b3a66d` |
| Host | Apple Silicon (`arm64`, `ARM64_T6031`) |
| OS | macOS 26.5.2 (25F84), Darwin 25.5.0 |
| MoonBit | `moon 0.1.20260717 (438c06f 2026-07-17)` |
| Wasmtime | `wasmtime 40.0.0 (68a6afd4f 2025-11-22)` |
| Python | 3.14.5 |
| Workload | `examples/algorithms/aead_aegis128l.wasm` |
| Benchmark shape | one warmup, seven measured pairs, alternating engine order |

The Wasmoon cache was isolated from the normal user cache. Its final artifact
was:

```text
v9-aarch64-macos-o2-small-direct-no-cancel-no-debug-r006d0061006300680076002d00760063006f00640065002d0035-seaa87f6e73636360bfb158126515b71dcc56bc8e63a3abd9b7b4d76240ce3bf4-x67abdd721024f0ff4e0b3f4c2fc13bc5bad42d0b7851d456d88d203d15aaa450.cwasm
```

The revision component is `machv-vcode-5`. The warmup created one artifact and
none of the seven measured pairs compiled a fresh artifact.

## AEGIS Paired Results

The benchmark command was:

```sh
python3 scripts/benchmark_algorithms_parity.py \
  --wasmoon ./wasmoon \
  --wasmtime wasmtime \
  --workloads-dir /tmp/wasmoon-final-aegis-v5 \
  --summary-file /tmp/wasmoon-final-aegis-v5.json \
  --markdown-file /tmp/wasmoon-final-aegis-v5.md \
  --iterations 7 \
  --warmup 1 \
  --timeout-sec 30
```

The reported value is an opaque guest-produced measurement. The wall column is
host elapsed time for the complete command. Ratios are Wasmoon divided by
Wasmtime.

| Pair | Order | Wasmoon value | Wasmtime value | Value ratio | Wasmoon wall (s) | Wasmtime wall (s) | Wall ratio |
| ---: | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| 0 | Wasmoon / Wasmtime | 4,429,720,000 | 3,803,400,000 | 1.164674 | 0.893495 | 0.769585 | 1.161009 |
| 1 | Wasmtime / Wasmoon | 4,703,465,000 | 3,761,400,000 | 1.250456 | 0.947688 | 0.761800 | 1.244012 |
| 2 | Wasmoon / Wasmtime | 4,600,895,000 | 3,662,675,000 | 1.256157 | 0.927515 | 0.741913 | 1.250168 |
| 3 | Wasmtime / Wasmoon | 4,334,330,000 | 3,769,900,000 | 1.149720 | 0.873598 | 0.763238 | 1.144593 |
| 4 | Wasmoon / Wasmtime | 4,333,715,000 | 3,682,810,000 | 1.176741 | 0.874271 | 0.745033 | 1.173466 |
| 5 | Wasmtime / Wasmoon | 4,380,070,000 | 3,753,320,000 | 1.166985 | 0.883491 | 0.760515 | 1.161701 |
| 6 | Wasmoon / Wasmtime | 4,339,610,000 | 3,760,925,000 | 1.153868 | 0.874385 | 0.761190 | 1.148708 |

| Summary | Guest-reported value ratio | Wall ratio |
| --- | ---: | ---: |
| Median paired ratio | 1.166985 | 1.161701 |
| Geometric-mean paired ratio | 1.187647 | 1.182674 |
| Initial cache-isolated runner result | 1.270317 | 1.264638 |
| Relative median-ratio improvement | 8.13% | 8.14% |

These short runs establish the direction and size of the demonstrated
optimization, not a release-grade statistical bound.

## Cold Compilation, Warm Execution, and Fixed Overhead

The cold Wasmoon warmup took 2.257274 seconds. Complete phase metrics from a
separate fresh compilation report 1,183,840 microseconds for module compilation.
The seven cached Wasmoon executions had a median wall time of 0.883491 seconds.

An empty cached `_start` module was measured in a separate isolated cache to
estimate CLI startup, artifact loading, installation, and empty execution:

| Measurement | Wall time |
| --- | ---: |
| Empty module, cold | 4.159 ms |
| Empty module, cached median (nine runs) | 3.244 ms |

The empty-module number is a fixed-overhead estimate; it is not subtracted from
the guest-reported value. The difference between the cold AEGIS warmup and its
cached median is 1.374 seconds and includes compilation, installation, cache
creation, and run-to-run noise.

## Compilation Phases

Detailed metrics use schema version 3 and cover all 63 functions:

| Phase | Aggregate time |
| --- | ---: |
| MilkIR optimization | 65,649 us |
| Semantic MachV lowering | 20,429 us |
| AArch64 Target VCode lowering | 31,329 us |
| Register allocation | 1,033,680 us |
| Frame planning | 2,608 us |
| Emission | 19,162 us |
| Complete module compilation | 1,183,840 us |

Register allocation remains the dominant compile-time cost. `func_56` accounts
for 745,945 microseconds of allocation, while its other measured stages total
43,422 microseconds. This is retained as current-version follow-up evidence; the
runtime-oriented work in ISS-252 did not conceal it.

## Generated Code and Allocation

`func_30` is the demonstrated AEGIS runtime hot function:

| Metric | Before the instruction-selection work | Final |
| --- | ---: | ---: |
| Optimized MilkIR instructions | not recorded | 528 |
| Target VCode instructions | not recorded | 296 |
| Stack slots | 19 | 10 |
| Spills | 17 | 8 |
| Reloads | 22 | 10 |
| Machine-code size | 1,568 bytes | 1,296 bytes |
| Memory-base loads | 60 before bounded reuse | 30 |

The final function contains 40 immediate shift or rotate forms and 16
shifted-left additions. It contains none of the previous 56 register-based
shift/rotate sequences. Encodable pointer offsets use
`AddAddressImmediate`. Stable environment fields reuse one prior value within a
bounded block-local pressure region; calls are barriers, mutable fields are
excluded, and no physical register is reserved.

Across the complete module, the final allocator metrics are:

| Metric | Count |
| --- | ---: |
| Machine-code bytes | 67,836 |
| Spill slots | 588 |
| Spills | 498 |
| Reloads | 1,310 |
| Register moves | 126 |
| Spill-to-spill edits | 293 |

## Scaling Probes

The diagnostic large-CFG and register-pressure inputs are read from the
historical workload corpus at commit
`9be65ef2b6a94faa0ab61ba709967b249eddcaf6`. They are not restored as CI gates.

| Workload | IR before / after | Optimize | Semantic lower | Target lower | Regalloc | Frame | Emit | Code | Allocation edits |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| `large_cfg.wast` | 4,609 / 4,608 | 1,333 us | 6,493 us | 9,545 us | 60,149 us | 795 us | 2,463 us | 14,388 B | none |
| `register_pressure.wast` | 352 / 351 | 49 us | 602 us | 493 us | 1,562 us | 40 us | 143 us | 1,332 B | 55 slots / 55 spills / 55 reloads |

The clobber index regression test uses 4,096 clobber points and resolves a query
with 14 comparisons, locking logarithmic lookup instead of a linear rescan.

## Remaining Scope

This host cannot produce a native AMD64 execution trend. ISS-212 is narrowed to
retaining a current-version AMD64 compile trend on a native Linux AMD64 host.
No AArch64 result is reused as AMD64 evidence.

## Validation

The following gates passed on the recorded host:

| Command | Result |
| --- | --- |
| `moon fmt` | pass |
| `moon info` | pass, no interface drift |
| `moon check --target native --warn-list +73` | pass |
| `moon test --target native --warn-list +73` | 2,307 / 2,307 |
| `moon test modules/aarch64_target --target native --warn-list +73` | 201 / 201 |
| `moon test modules/x64_target --target native --warn-list +73` | 98 / 98 |
| `moon test modules/regalloc --target native --warn-list +73` | 65 / 65 |
| `python3 -m unittest discover -s scripts/tests -p 'test_*.py'` | 22 / 22 |
| `python3 scripts/audit_module_boundaries.py` | pass |
| `python3 scripts/run_all_wast.py --rec` | interpreter 258 / 258 files and JIT 258 / 258 files; 62,563 assertions in each mode |
