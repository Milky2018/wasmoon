# Windows native runtime

The Windows port targets AMD64, using the native MoonBit toolchain and LLVM
Clang from an x64 Visual Studio developer environment. Interpreter and JIT
execution are both implemented and verified. [Acceptance CI 34936397161](https://github.com/Milky2018/wasmoon/actions/runs/34936397161)
at `4840bc78` passed Windows AMD64, Linux AMD64 and macOS ARM64; ISS-525,
ISS-177 and the discovered trailing-slash capability issue ISS-526 are closed.

## Build and validation

The Microsoft compiler path uses `cl.exe` for C and `ml64.exe` for assembly.
Install Visual Studio C++ Build Tools with the Windows SDK and AddressSanitizer
component for the native sanitizer tests. From an x64 developer PowerShell:

```powershell
. ./scripts/msvc/setup.ps1
moon update
moon build --target native --release --jobs 2 --target-dir target/windows-build
```

The setup script builds a compiler driver because Moon passes all native stubs,
including assembly, to its C compiler. The driver forwards C compilation and
linking to the actual Microsoft tools and assembles `.S` stubs using their
checked-in MASM counterparts. No C compilation falls back to Clang. Re-run setup
in each new shell. MSVC C11 atomics are enabled explicitly by the driver.

Guest helper addresses use generated SysV-to-Win64 assembly bridges with MSVC;
Clang uses its calling-convention attribute. Run
`python scripts/msvc/generate_guest_bridges.py --check` to verify generated
bridges. `scripts/tests/test_wasi_windows_guest_abi.py` executes every bridge
against Microsoft-compiled host functions, including stack arguments.

MSVC acceptance is tracked in ISS-527. The Windows CI matrix runs both compiler
configurations independently and retains separate evidence artifacts.

For the Clang configuration, use the commands below. After an MSVC build, skip
the `MOON_CC` assignment and use the same executable-copy and test commands.

Use PowerShell in the x64 developer environment, with `moon`, `clang`, Python
3.12 or later, and `wasm-tools` 1.254.0 on `PATH`:

```powershell
$env:MOON_CC = "clang"
moon update
moon build --target native --release --jobs 2 --target-dir target/windows-build
Copy-Item target/windows-build/native/release/build/Milky2018/wasmoon/cmd/wasmoon/wasmoon.exe wasmoon.exe
Copy-Item target/windows-build/native/release/build/Milky2018/wasmoon/cmd/wasmoon-tools/wasmoon-tools.exe wasmoon-tools.exe
python -m unittest discover -s scripts/tests -p 'test_wasi_windows_*.py' -v
python scripts/run_windows_readiness.py
python scripts/run_all_wast.py --rec --dump-failures
python scripts/run_native_packages.py --output target/windows-native-tests
```

The `Check and Test` workflow runs the Windows build, native descriptor probes,
actual readiness guests, both core engines, all three component suites in both
engines, native package tests, the complete misc suite, and WASIp1 tests.
`windows_only=true` selects the Windows diagnostic job. A final acceptance run
must also pass Linux AMD64 and macOS ARM64. Evidence is uploaded even when a
Windows test step fails. Native compilation and individual package execution
have explicit deadlines; a timeout fails the job and is not a skipped test.

The Windows acceptance run executed all 2452 native tests across 44 packages,
including 167 JIT tests. Both engines passed 258 core WAST files (62563 assertions
per engine), all three component suites (845/153/387 commands per engine), and
12 readiness guest executions in total. The full misc corpus produced 692
assertion-bearing passes and 72 script-only passes. WASIp1 produced 116
explicit-rights passes plus four stdio smoke passes; the intentionally
out-of-scope hostcall-fuel test is excluded in each engine. All 38 native
Windows C/AddressSanitizer probes passed.

The pinned upstream corpora and component corrections use Git `-text`
attributes. Their exact bytes must survive `core.autocrlf`; do not change
snapshot hashes to accommodate checkout conversion.

## Descriptor readiness

Both engines use the shared WASIp1 host implementation on Windows. JIT guest
code still executes as native code; its hostcalls pass through the existing
MoonBit hostcall bridge. Subscription validation, clock deadlines, event order,
rights checks, and event encoding remain shared.

| Host descriptor | Readiness behavior |
| --- | --- |
| Regular file | Requested read/write readiness is immediate, including reads at EOF. |
| Anonymous or named pipe | Non-consuming NT pipe queries observe readable bytes, writable quota, and disconnection. Unread bytes remain available after peer closure. |
| Console input | Console records are inspected without removing them. Line input waits for a terminating key; key-up and unrelated records do not imply readable text. |
| Console output | Writable immediately. |
| Winsock socket | `WSAPoll` supplies read/write/error/hangup status. Pointer-sized sockets have distinct owned descriptor IDs. |
| NUL | Requested read/write readiness is immediate. |
| Invalid descriptor | Rejected or reported as an invalid event at the corresponding WASIp1/native boundary. |
| Other character device | An explicit host error, rather than invented readiness. |

Synchronous pipes and consoles do not provide a uniform non-consuming wait.
The adapter rechecks these handles after sleeps of at most 10 milliseconds;
mixed waits use the same monotonic deadline and check handles again before
returning a timeout. This adds polling latency and does not guarantee immediate
notification. Socket-only waits use `WSAPoll`. Alertable handle waits report
APC interruption as `EINTR`; the shared WASIp1 loop retries as appropriate.

The readiness guest runner checks pending clocks, delayed binary pipe input,
regular-file input, pipe EOF, invalid guest descriptors, and duplicate
subscriptions in both engines. Native Windows tests additionally exercise
console input, APC interruption, socket readiness, pipe backpressure, and
handle ownership. A separate executable exercises descriptor ownership and
file buffers with Windows AddressSanitizer. No readiness probe consumes guest input.

## Files, sockets, and native execution

Windows file I/O preserves binary bytes, including inherited standard streams.
The adapter owns mutable descriptor flags; duplicates share append/nonblocking
state and retain independent lifetime ownership. Append writes address the
kernel end-of-file position. Positioned reads/writes use a separate overlapped
handle for the same object, preserve the original shared cursor, and do not
upgrade the original handle's access rights.

Capability-relative opens and mutations use held directory handles. Symlink
creation through a held parent installs a reparse point on the newly created
object. If the OS requires the symlink privilege, the adapter enables an
already-granted privilege on a private thread token for that operation and
restores the caller's token. An account without that privilege can receive a
permission error. Host absolute-path creation uses the Windows symbolic-link
API, including its unprivileged-creation option. Symlink targets can be read
back; following an absolute target through a capability remains forbidden.

The native reactor owns duplicate handles until completion or cancellation.
DNS resolution runs in a CRT worker thread and signals a pipe; workers do not
enter MoonBit. Windows fibers own guest stacks. The private x64 guest calling
convention is bridged explicitly to Win64 host calls, and trap recovery uses
non-unwinding register restoration rather than unwinding through generated
code with the CRT `longjmp`.

Windows fiber reservations include space beyond the committed stack so exact
MiB stack sizes retain an inaccessible lower region. Guard access is tested
at 64 KiB, 128 KiB, 1 MiB and 2 MiB, including a fault after suspension and
resumption with structured trap attribution and a captured backtrace.
