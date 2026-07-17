# aarch64_target

AArch64 ABI and register policy for the native backend.

This module describes AAPCS64 register sets, callee-saved and caller-saved
policy, scratch registers, and the register-allocation machine environment. It
does not lower MilkIR; verified MilkIR first becomes target-neutral MachV.

## Package

- `Milky2018/aarch64_target`: AArch64 Target VCode instructions and verifier,
  ABI lowering, allocation, frame planning, machine-code emission, target
  descriptor, and register policy.

## When to use it

Use this module when target lowering or register allocation needs AAPCS64
argument registers, callee-saved registers, allocatable registers, or scratch
register policy.

## Example: inspect AAPCS64 policy

The target API exposes the ABI details a compiler backend needs before register
allocation and emission.

```moonbit check
///|
test "inspect AArch64 ABI policy" {
  let abi = abi_policy()
  inspect(abi.pointer_size, content="8")
  inspect(abi.stack_alignment, content="16")
  inspect(abi.int_argument_regs.length(), content="8")
  inspect(abi.float_argument_regs.length(), content="8")
}
```

## Example: inspect the register-allocation environment

```moonbit check
///|
test "inspect AArch64 machine environment" {
  let env = build_machine_env()
  inspect(env.scratch_int.length(), content="2")
  inspect(env.scratch_float.length(), content="2")
}
```

## Integration

Use this package for the complete AArch64 target pipeline after semantic
MachV. It produces a verified `Milky2018/machv/code_object` value. Runtime
symbol resolution, relocation application, and executable-memory ownership
remain responsibilities of the embedding application.

Internal functions use the tail-call convention: an ordinary internal caller
places stack arguments in its reserved outgoing area, the callee pops that
incoming area on return, and the call pseudo immediately restores the caller's
frame-base SP. A function containing true tail calls enlarges its incoming area
in the prologue to the maximum tail-callee requirement, then reuses that area
when transferring control. Platform calls continue to use ordinary AAPCS64
caller-owned stack arguments.
