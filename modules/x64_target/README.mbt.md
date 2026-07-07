# x64_target

x64 target support for MilkIR-to-MachV lowering.

This module provides x86-64 ABI policy, machine-environment construction, and
target lowering hooks used by the generic ISA lowering pipeline.

## Package

- `Milky2018/x64_target`: x64 target descriptor, ABI policy, machine
  environment, and lowering entry points.

## Boundary

This module is a target backend. It should stay independent from Wasmoon
runtime glue and embedding-specific helper resolution.
