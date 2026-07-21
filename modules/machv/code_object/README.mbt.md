# machv/code_object

This package is the final reusable boundary between target emission and an
embedding runtime. It stores copied machine-code bytes together with typed
relocations, trap sites, safepoints, root locations, and target-neutral unwind
directives.

`build` validates architecture-specific alignment, bounds, relocation kinds,
known instruction encodings, and unwind state transitions before an object can
escape. An unwind directive's offset is the code offset immediately after the
prologue instruction that establishes the described state. Saved-register
locations are relative to the canonical frame address.

This package deliberately does not encode platform unwind formats, register
unwind data with the host, resolve runtime symbols, allocate executable memory,
or apply relocations. Those operations belong to the embedding product.
