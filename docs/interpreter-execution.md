# Interpreter execution and resource limits

The interpreter runs guest calls and structured control flow through an explicit
execution stack. Each entry retains its instruction position, operand-stack
base, result arity and exit action. Function entries also retain the caller's
module instance and local-slot count. Branches and exceptions unwind entries in
a loop; tail calls remove the current function before entering their target.
Pure guest calls therefore do not require one native call frame per guest frame.

Suspension retains these same entries. Only the pending host/effect operation is
represented by a resume action; resuming does not traverse a chain of nested
control-flow closures. Existing cooperative scheduling, cancellation and the
single-use continuation API remain in place. Parked continuations pin live GC
roots and release them on completion or cancellation.

## Configuration

Pass `interpreter_limits=InterpreterLimits::new(...)` to `Store::Store` or
`Store::with_c_heap`. Omitted limits use these defaults:

| Limit | Default | Exhaustion |
| --- | ---: | --- |
| `max_frames` | 16,384 | `CallStackExhausted` |
| `max_values` | 1,048,576 | `StackOverflow` |
| `max_controls` | 65,536 | `StackOverflow` |
| `max_host_calls` | 64 | `CallStackExhausted` |

Frame, control and value limits apply to each interpreter context. Value slots
include both live operands and function locals. They bound logical storage, not
exact allocator bytes or the guest GC heap. Controls include function, block,
loop, if and try-table entries. Tail calls reuse the active-call budget.
Configuration values must be positive. These settings also apply when a JIT
import bridge explicitly executes an interpreted function.

Host-call depth is tracked across nested interpreter contexts in the same Store.
A host callback can still consume native stack or recurse through other Stores;
this budget does not sandbox arbitrary host code. Raising it requires the
embedder to account for its native thread stack. Suspended host calls release
the active host-call nesting reservation while parked.

The settings do not change JIT machine stacks, fiber sizes, or the compiler's
auxiliary stack inside guest linear memory. They do not bound parsing or
validation, total process memory, or execution time. An infinite loop or tail-call
chain needs cancellation or a separate execution-time policy, not a frame limit.

WebAssembly permits implementation limits on frames and other execution
resources; it does not require a configurable depth API or an explicit-stack
implementation. This refactor addresses practical interpreter capacity.

## Acceptance

ISS-537 records deep recursion, exact budget boundaries and recovery, tail calls,
structured control, exception unwinding, GC, host reentry and suspension tests,
as well as cross-platform native/external evidence and performance measurements.

## Local performance comparison

On Darwin ARM64, nine alternating-order pairs after one warmup pair compared
an archived pre-refactor release executable with the final refactored executable.
The loop workload's median CLI wall time changed from 22.53 ms to 23.31 ms
(+3.5%); recursive Fibonacci(24) changed from 39.30 ms to 37.42 ms (-4.8%).
Outputs matched. These short measurements include startup and WAT loading;
they are microbenchmarks, not evidence of a general performance improvement.
The baseline is identified by executable hash, not claimed as a freshly rebuilt
Git revision. [Raw samples, guest programs and binary hashes](perf/interpreter-explicit-stack-2026-09-16.json)
permit the measurement inputs and interpretation to be audited.

An initial implementation regressed the call workload by about 15% because
normal function returns copied result arrays unnecessarily. Normal fallthrough
now keeps values in place when the operand stack already has the exact result
height; early returns still discard excess operands correctly.
