# AEGIS-128L Flat VCode Allocation Input (2026-08-28)

## Method

- Baseline: post-ISS-447 `dev`
- Workload: `examples/algorithms/aead_aegis128l.wasm`
- Host: Apple M3 Max, arm64, macOS 26.5.2 (25F84)
- Seven detailed, serial, cache-isolated captures per result

Every process used a distinct `WASMOON_JIT_CACHE_DIR` and enabled schema-5
detailed metrics. No other corpus workload was run.

## Design result

The old `VCodeFunctionView` copied every logical collection into nested arrays.
The replacement normalizes VCode once into flat value, block, instruction,
successor, edge-argument, operand, and clobber tables plus offset vectors.
`FunctionView` returns read-only `ArrayView` spans into those tables, so an
allocator traversal performs one dynamic dispatch per logical span and does
not copy it.

Two rejected prototypes established why both parts matter:

- Direct count/index access over VCode removed the adapter snapshot but repeated
  handle conversion and dynamic dispatch in every allocator pass. A smoke run
  increased aggregate register allocation to 74,971 us.
- Count/index access over a flat normalized snapshot removed repeated conversion
  but retained per-element dynamic dispatch. A smoke run still took 71,242 us.

The final span interface retains independent generic regalloc test views while
removing the nested production representation and the hot per-element dispatch.

## Results

All values are microseconds. Component medians are independent.

| Metric | Baseline | Flat spans | Change |
| --- | ---: | ---: | ---: |
| Module compilation | 121,240 | 120,362 | -0.72% |
| Register allocation | 53,060 | 51,725 | -2.52% |
| Adapter plus input validation | 1,889 | 1,296 | -31.39% |
| Adapter normalization | mixed | 1,198 | separated |
| Input validation | mixed | 98 | separated |
| Live ranges | 5,791 | 5,729 | -1.07% |
| Bundle allocation | 25,325 | 25,328 | +0.01% |
| Operand assignment | 7,465 | 7,427 | -0.51% |
| Plan translation | 4,098 | 3,741 | -8.71% |
| Function 56 register allocation | 22,375 | 22,088 | -1.28% |

The seven final module/register-allocation samples were:

| Run | Module | Regalloc | Adapter | Input validation | Function 56 |
| ---: | ---: | ---: | ---: | ---: | ---: |
| 1 | 129,176 | 53,392 | 1,325 | 142 | 22,088 |
| 2 | 120,362 | 52,038 | 1,198 | 99 | 22,131 |
| 3 | 119,745 | 51,725 | 1,169 | 91 | 21,979 |
| 4 | 119,807 | 51,577 | 1,218 | 97 | 22,135 |
| 5 | 119,038 | 51,293 | 1,198 | 98 | 21,907 |
| 6 | 131,353 | 56,632 | 1,323 | 108 | 24,008 |
| 7 | 120,562 | 51,604 | 1,190 | 98 | 21,854 |
| Median | 120,362 | 51,725 | 1,198 | 98 | 22,088 |

## Correctness boundary

All seven captures have identical allocator loop counters, spill/reload/move
vectors, and per-function code-size vectors. Function 56 remains 16,036 bytes
and total emitted code remains 59,428 bytes. The cacheable `.cwasm` is
byte-identical to the ISS-447 control with SHA-256
`0c31ca17b8f04e9ecd0022eb185d367d7027d197ba83f87cd762a8e2f4639840`.

