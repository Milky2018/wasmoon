#!/usr/bin/env python3
"""Generate a wasm function whose conditional branch outgrows AArch64's imm19.

A conditional branch reaches only +/-1MB through imm19, so reproducing GitHub
#486 needs a function body past that. This emits an `if` whose then-arm is a
long run of memory read-modify-writes: memory traffic is used rather than
arithmetic so the optimizer cannot fold the body away, and the `if` is what
forces a conditional branch to span all of it.

Roughly 34 bytes of AArch64 per filler op on the current backend, so 33,000
ops lands near 1.12MB -- just past the limit. Compiling it takes minutes,
which is why this lives here rather than in the test suite.

    python3 scripts/gen_wide_branch_wat.py 33000 /tmp/wide33k.wat
    ./wasmoon run /tmp/wide33k.wat --invoke wide --arg 0
    ./wasmoon run --no-jit /tmp/wide33k.wat --invoke wide --arg 0

The two runs must agree. Before ISS-402 the first one failed outright with
BranchOutOfRange(offset=1115408, bits=19).
"""

import sys


def generate(count: int) -> str:
    body = "\n".join(
        f"    (i32.store (i32.const {(i * 4) % 1024}) "
        f"(i32.add (i32.load (i32.const {(i * 4) % 1024})) "
        f"(i32.const {i % 7 + 1})))"
        for i in range(count)
    )
    return f"""(module
  (memory 1)
  (func (export "wide") (param $c i32) (result i32)
    (if (i32.eqz (local.get $c))
      (then
{body}
      ))
    (i32.load (i32.const 0)))
)
"""


def main() -> int:
    if len(sys.argv) != 3:
        print(f"usage: {sys.argv[0]} <filler-op-count> <output.wat>", file=sys.stderr)
        return 2
    count, out = int(sys.argv[1]), sys.argv[2]
    with open(out, "w") as handle:
        handle.write(generate(count))
    print(f"wrote {out}: {count} filler ops")
    return 0


if __name__ == "__main__":
    sys.exit(main())
