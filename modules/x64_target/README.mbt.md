# x64_target

x64 ABI and register policy for the native backend.

This module describes System V register sets, callee-saved and caller-saved
policy, scratch registers, and the register-allocation machine environment. It
does not lower MilkIR; verified MilkIR first becomes target-neutral MachV.

## Package

- `Milky2018/x64_target`: x64 target descriptor, ABI policy, register sets,
  and machine environment.

## When to use it

Use this module when target lowering or register allocation needs System V
argument registers, callee-saved registers, allocatable registers, or scratch
register policy.

## Example: inspect System V policy

The target API exposes the ABI details a compiler backend needs before
register allocation and emission.

```moonbit check
///|
test "inspect x64 ABI policy" {
  let abi = abi_policy()
  inspect(abi.pointer_size, content="8")
  inspect(abi.stack_alignment, content="16")
  inspect(abi.int_argument_regs.length(), content="6")
  inspect(abi.float_argument_regs.length(), content="8")
}
```

## Example: inspect the register-allocation environment

```moonbit check
///|
test "inspect x64 machine environment" {
  let env = build_machine_env()
  inspect(env.scratch_int.length(), content="2")
  inspect(env.scratch_float.length(), content="2")
}
```

## Integration

Use this package from the x64 Target VCode and allocation pipeline.
Machine-code emission remains in `Milky2018/machv_emit`; runtime symbols and
executable-memory allocation are supplied by the embedding application after
emission.
