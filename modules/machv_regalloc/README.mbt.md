# machv_regalloc

MachV adapter for the reusable register allocator.

`machv_regalloc` bridges `Milky2018/machv` virtual-register functions to the
target-independent `Milky2018/regalloc` algorithm. It projects MachV into the
generic allocation model, applies allocation output, and keeps edge-copy and
layout behavior compatible with MachV emission.

## Packages

- `Milky2018/machv_regalloc`: projection, allocation entry points, application,
  validation, spill handling, and output construction.
- `Milky2018/machv_regalloc/layout`: block layout utilities for MachV
  functions.

## Boundary

This module may depend on MachV and regalloc, but should not depend on Wasmoon
runtime packages or native embedding details.
