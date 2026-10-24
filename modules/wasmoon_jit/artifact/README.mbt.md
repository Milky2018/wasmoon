# wasmoon_jit/artifact

Target-portable ordinary data for Wasmoon Cwasm files and persistent JIT cache
entries.

The package defines the compatibility manifest, stable import and function
identities, logical signatures, and the complete unlinked code-object payload.
Relocations remain symbolic. Artifacts never contain process addresses,
executable-memory addresses, linked images, MilkIR, Target VCode,
allocation results, or frame-planning objects.

Decoding and encoding belong to this package. Compatibility checks, target
code-object verification, symbol resolution, executable-memory allocation, and
installation belong to the native `Milky2018/wasmoon_jit` facade.

`decode` treats every input as untrusted. `DecodeLimits` bounds the file,
function and import counts, strings, signatures, code, relocations, metadata,
and safepoint roots before allocation. Malformed input, incompatible versions,
invalid UTF-8, unknown tags, truncation, and limit violations are reported as
structured `ArtifactDecodeError` values.

Format 12 retains optional original source-byte offsets and bounded native
source ranges. A range covers `[offset, offset + length)`; gaps and zero-length
legacy point metadata establish no instruction extent. Source offsets are
independent of native instruction offsets. Invalid, overlapping or out-of-code
ranges are rejected during code-object verification before installation. Older
artifact versions are rejected rather than interpreted with the new schema.
