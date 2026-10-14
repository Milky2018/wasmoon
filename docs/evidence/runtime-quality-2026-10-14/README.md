# Runtime quality review reproductions

Source: `25381fc764c47e805f318012c272fdd51f62c57f` (main).
Platform: macOS ARM64. MoonBit: stable `0.1.20261012` (`748b63c`).
Engine: interpreter, through the public executor and runtime interfaces.
Tracking: [ISS-624](../../../issues/ISS-624.md),
[ISS-625](../../../issues/ISS-625.md), and
[ISS-626](../../../issues/ISS-626.md).

The review created an independent temporary native MoonBit package importing
the current workspace modules. It did not change production source or existing
tests. The diagnostic intentionally prints observations; it is not a new test
suite. Repository runtime changes after the recorded revision may change its
outcomes.

## Observations

| Case | Validation | Process outcome | Wrapped entries | Objects collected | Objects live after GC |
| --- | --- | --- | ---: | ---: | ---: |
| wrapped | Accepted | Success | 1000 | 0 | 1000 |
| plain | Accepted | Success | 0 | 1000 | 0 |
| invalid | Rejected, type index 99 | SIGABRT | N/A | N/A | N/A |
| memory-limit | Accepted | SIGABRT | N/A | N/A | N/A |

The paired GC cases both create and drop 1000 temporary structs. The wrapped
case additionally converts each struct to externref before dropping it. The
Store remains open during forced collection. The comparison establishes
unreachable retention by the interpreter wrapper registry, not a JIT result or
a universal ownership audit.

The invalid case deliberately continues into the low-level instantiation API
after validation rejects the module. It demonstrates that this interface relies
on an unenforced validation precondition. It does not establish a CLI bypass.

The memory-limit case uses `(module (memory i64 281474976710656))`. The current
validator accepts it. The native size-range check rejects it before allocating
memory; the simple instantiation helper's `try!` turns that recoverable error
into process termination. An outer RuntimeError catch does not catch the panic.
Supporting this allocation is not the requested fix.

## Preserved artifacts

- [probe.mbt](probe.mbt): the final diagnostic source, unchanged from the temporary project.
- [results.json](results.json): observations from independently running the compiled diagnostic executable in four fresh processes, with 20-second subprocess limits.

The JSON records the source SHA-256 and captured stdout/stderr. Machine-specific
workspace, toolchain, temporary-project, and executable paths were replaced with
named placeholders. Outcomes, numeric values, and stack locations are unchanged.
The diagnostic was built with `--deny-warn`. Signal exits are represented as
`-6` by Python subprocess; `moon run` reported exit 134 for the same SIGABRT.

## Reproduction

From the checked-out repository, create an independent temporary workspace using
Python 3.11 or newer:

```sh
review_dir=$(mktemp -d /tmp/wasmoon-runtime-review.XXXXXX)
python3 - "$PWD" "$review_dir" <<'PY'
from pathlib import Path
import json
import shutil
import sys
import tomllib

root, output = map(Path, sys.argv[1:])
shutil.copyfile(root / "docs/evidence/runtime-quality-2026-10-14/probe.mbt",
                output / "main.mbt")
(output / "moon.mod").write_text('''name = "review/runtime_probe"
version = "0.1.0"
import { "Milky2018/wasmoon@0.16.0", "Milky2018/wasm_core@0.16.0" }
preferred_target = "native"
''')
(output / "moon.pkg").write_text('''import {
  "Milky2018/wasm_core/wat",
  "Milky2018/wasm_core/validator",
  "Milky2018/wasmoon/executor",
  "moonbitlang/core/env",
}
options("is-main": true)
''')
members = tomllib.loads((root / "moon.work").read_text())["members"]
members = [str((root / member).resolve()) for member in members]
members.append(str(output.resolve()))
(output / "moon.work").write_text("members = " + json.dumps(members) + "\n")
PY

cd "$review_dir"
moon run . --target native --deny-warn
moon run . --target native --deny-warn -- plain
moon run . --target native --deny-warn -- invalid
moon run . --target native --deny-warn -- memory-limit
```

Run the signal-producing cases in separate processes. The recorded source
revision's normal dependency setup is required. These commands reproduce
observations; they do not turn expected crashes into passing acceptance tests.
