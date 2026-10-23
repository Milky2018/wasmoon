# Parse-double numerical targets: local investigation checkpoint

The targets remain **unmet**: invocation at most 1.05x and compilation at most
1.5x optimized single-threaded V8. No CFG inliner has been promoted, and no
commit, push, merge or publication is part of this checkpoint.

The [receipt](issue568-numerical-targets-2026-10-23.json) records the dirty
working tree based on `7cf4fe98`, the unchanged asserted 20000-iteration guest,
source hashes, individual diagnostic samples and local gates. Experimental
timings are not a final numerical acceptance run. In particular, isolated
inliners increased compilation substantially while invocation remained around
2.1--2.3 seconds. V8's default invocation median was 0.774 seconds.

## What the V8 controls establish

Node 25.2.1 ran with `--no-liftoff --no-wasm-lazy-compilation
--wasm-num-compilation-tasks=1`. Each process compiled the same bytes, created
an instance, invoked the same self-checking export and required result `1`.
File reading occurred before the compile timer. Each control changed one flag.

| V8 configuration | Compile median, seconds | Invoke median, seconds |
| --- | ---: | ---: |
| Default optimizing compiler | 0.4370 | 0.7740 |
| `--no-wasm-inlining` | 0.1611 | 1.4823 |
| `--no-wasm-loop-peeling` | 0.3940 | 0.8156 |
| `--no-turboshaft-wasm-load-elimination` | 0.4385 | 0.7696 |

These controls establish that inlining matters substantially to **V8** on this
guest. They do not establish that mechanically expanding Wasmoon calls will
produce the same benefit. The acceptance reference remains default optimized
V8; disabling its optimizations is not a way to satisfy the target.

V8's own `--trace-wasm-inlining` output confirms nested `shift`, `left_shift`,
`new_digits` and `trim` expansion into `to_double_priv`. It also reports
`fold_digits` expansion through its caller. A standalone callee disassembly
therefore does not describe every hot execution of that callee.

## Isolated controls and their limits

- Changing MilkIR SSA `Value` to a value type did not establish a stable gain.
- Caching loop write-region queries did not establish a useful compile gain.
- Avoiding overwritten allocation zero stores did not establish a useful gain.
- The first CFG inliner spent its growth budget on outer/cold wrappers before
  expanding the desired nested calls. Normalizing candidate IR and inspecting
  the resulting caller exposed this limitation. A depth-first variant and a
  second leaf pass still did not justify their roughly doubled compile cost.
- The CFG prototypes cloned value definitions, block parameters, branches,
  returns and global-value declarations, rejected handler/continuation/tail
  scopes, bounded growth and pruned unreachable continuations. They are not a
  completed safety implementation: permanent ownership-safe layout APIs,
  transactional validation, inline debug frames and full regression gates
  would still be required before production use. No prototype is in the
  working tree.

The next design must connect inlining to aggregate field propagation and
preserve collecting, reentrant, heap-replacing and alias barriers. A larger
source threshold alone is not the solution. In particular, immutable-field
forwarding must not silently bypass raw-entry validation or a heap lifetime
transition after a callback.

## Allocation/admission profile

A separate, untimed instrumented process counted the existing word-struct
reservation, slow-struct allocator and struct-view admission helpers. The
asserted export returned `1`. Arrays and wide allocators are outside these
counters. No timing from this instrumented process is acceptance evidence.

| Local type | Fast reservations | Slow allocations | Struct-view admissions |
| --- | ---: | ---: | ---: |
| `StringView` (43) | 11,791,951 | 11,616 | 36,598,010 |
| Mutable i32 local (303) | 6,350,158 | 6,158 | 585,322 |
| Mutable i64 local (462) | 1,602,265 | 1,514 | 0 |
| `StringBuilder` (231) | 239,760 | 240 | 7,547,120 |
| All counted types | 25,333,637 | 1,097,548 | 84,061,688 |

This identifies aggregate construction and repeated admission as concrete
remaining work. It does not license allocation elimination that changes
quotas, failure injection, observable lifetimes or precise roots.

## Working-tree changes and validation

The checkpoint retains the previously measured reference-allocation change,
bounded-work compiler fixes, contextual-validated small GC leaf inlining,
conditional private-box scalar propagation, safepoint indexing and simpler
field-address arithmetic. ISS-672 separately records the CLI recursive-group
partition repair; its loading/preparation saving is not a compilation saving.

- Native: 3060/3060 with regalloc validation, GC verification and barrier
  assertions; actual wasm: 1455/1455. Strict checks on both targets, info/fmt,
  module boundaries and generated MSVC bridges pass.
- Python: 178 tests, 54 existing platform skips, no failures.
- Fresh isolated macOS ASan/UBSan: 289/289 with both ASan controls detected.
  This is dirty local evidence; macOS does not establish Linux LSan acceptance.
- Native interpreter, actual wasm interpreter and native JIT: each passes all
  258 Core files and 62563 assertions, zero failures/unsupported.
- Component interpreter and JIT: each passes all 59 files/1385 commands,
  zero failures/skips, through the three exact pinned suites and unchanged
  documented corrections. The raw-directory diagnostic bypassed those three
  corrections and failed 15 commands in three files; that run is not acceptance.

The compiled CLI used by corpus checks predates formatting-only changes to
the same functional sources. These results are not clean CI or actual x64
execution. A fresh final binary and repeated serial numerical comparisons
remain required for the target acceptance.

Owned temporary sources, builds, caches, profiles and raw logs are removed
after extracting this compact receipt. One accidentally created default-cache
entry for this unique diagnostic guest is removed; unrelated caches and files
are preserved.
