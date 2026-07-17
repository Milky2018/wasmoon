# machv/code_object

This package is the final reusable boundary between target emission and an
embedding runtime. It stores copied machine-code bytes together with typed
relocations, trap sites, safepoints, root locations, and unwind bytes.

`build` validates architecture-specific alignment, bounds, relocation kinds,
and known instruction encodings before an object can escape. It deliberately
does not resolve runtime symbols, allocate executable memory, or apply
relocations; those operations belong to the embedding product.
