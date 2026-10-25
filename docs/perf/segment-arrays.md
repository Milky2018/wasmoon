# Data-segment arrays

Tracking: [ISS-695](../../issues/ISS-695.md).

Core validation already accepts vector element types for array.new_data and
array.init_data. A public unaligned v128 fixture passes wasm-tools validation
and returns1 in Wasmtime49; the parent ac02661 JIT traps unreachable and its
interpreter CLI raises TypeMismatch. Explicit managed-Store execution instead
constructs null elements. This is a correctness defect, not a measured speedup.

The JIT metadata now distinguishes v128 with the existing six-word type-cache
stride and a16-byte element width. The interpreter uses the same width and an
owned16-byte value. Native segment decoding returns the existing two-word GcSlot;
both data operations use the established wide setter. Scalar conversions retain
their prior bits; element-segment reference writes are unchanged. This does not
add a bulk-copy path, change allocation admission or relax validation.

Source/destination bounds still precede every element write. Dropped segments,
null references and zero-length ranges keep their ordering. Canonical and legacy
native arrays use their existing storage adapters. Public regressions retain both
vector words, unaligned strides, adjacent sentinels and post-collection values;
failed ranges cannot partially initialize the destination. Native JIT and
interpreter controls run at optimization levels0/2/3, and the portable interpreter
tests run on native and actual Wasm. The latter tests are also included in the
fresh sanitizer closure.

Before the repair, both new vector-value portable tests fail on native and Wasm,
while the dropped/null control passes; the native two-test segment matrix also
fails. Afterward native3164 ordinary/verified, Wasm1468, strict both, info/fmt,
C45, boundaries and generated MSVC bridges pass. Fresh clean integration,
sanitisers and exact-head platform acceptance are separate gates. Raw probes and
fixtures remain in automatically cleaned OS temporary workspaces.
