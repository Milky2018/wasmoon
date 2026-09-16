# Native sanitizer gate

Run `python3 scripts/run_sanitizers.py` from the repository root. The runner
creates an isolated workspace using the current source modules and this
package's declarative `link.native` flags. It copies the existing component and
JIT lifecycle blackbox fixtures from `modules/wasmoon/sanitizer_testsuite`;
there is one fixture source and one instrumented dependency closure. Ordinary
native and Windows builds do not inherit these flags.

The runner selects Moon's supported `MOONBIT_ALLOCATOR=system` so ASan can
observe individual allocations. This selects an allocator; sanitizer compiler
flags remain exclusively in `moon.pkg`. See the [Moon native configuration](https://moonbitlang.github.io/moon/native.html).

The gate checks the binary for ASan and UBSan instrumentation, runs the fixtures,
and runs a separate expected-failure unsafe MoonBit array access. Only an actual
AddressSanitizer diagnostic satisfies the positive control. Logs and a summary
are retained in `target/sanitizers`.

Coverage is generated MoonBit C reachable from this test executable. Hand-written
native stubs, prebuilt MoonBit runtime objects and dynamically emitted JIT machine
code are not instrumented by these package flags. Native allocation interceptors
can still detect some errors involving those allocations, but this is not full
native-stub coverage. The default mimalloc allocator bypasses ASan allocation
redzones, which is why this gate explicitly selects the system allocator. Existing native fiber/trap adapters notify ASan when it is
linked, even when those adapters themselves are not instrumented. Whitebox tests
in other packages are also outside this gate. No compiler shim is used.
