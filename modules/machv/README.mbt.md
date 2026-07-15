# MachV

MachV is a virtual-register machine IR. It represents a function after target instruction selection and before physical register allocation and machine-code emission.

```text
MilkIR
  |
  | target lowering and instruction selection
  v
MachV with virtual registers
  |
  | machv_regalloc
  v
allocation locations and edits, or rewritten MachV
  |
  | machv_emit
  v
machine code and relocation metadata
```

At this stage, high-level operations have become machine-oriented instructions, but most values still use virtual registers such as `v0` and `v1`. Register allocation later decides whether each virtual register lives in a physical register or a spill slot.

## Start with one small function

The following example builds a 64-bit integer addition:

```moonbit check
///|
test "build a 64-bit add function" {
  let builder = FunctionBuilder::FunctionBuilder("add64")

  let lhs = builder.add_param(Int)
  let rhs = builder.add_param(Int)
  builder.add_result(I64)

  let sum = builder.new_vreg(Int)
  builder.append(Add(true), uses=[Virtual(lhs), Virtual(rhs)], defs=[
    { reg: Virtual(sum) },
  ])
  |> ignore
  builder.terminate(Return([Virtual(sum)]))

  let func = builder.finish()
  inspect(
    func.print(),
    content=(
      #|machv add64(v0:int, v1:int) -> int {
      #|block0:
      #|    v2 = add v0, v1
      #|    ret v2
      #|}
      #|
    ),
  )
  debug_inspect(func.get_result_kinds(), content="[I64]")
}
```

Read the generated MachV from top to bottom:

```text
machv add64(v0:int, v1:int) -> int {  two integer-register parameters and one result
block0:                               execution starts in block0
    v2 = add v0, v1                  read v0 and v1, then define v2
    ret v2                            return the value in v2
}
```

The four builder operations correspond directly to the function shape:

1. `add_param(Int)` creates an incoming virtual register in the integer register class.
2. `add_result(I64)` records the full result kind used by ABI decisions.
3. `append(...)` adds one machine instruction to the current block.
4. `terminate(...)` gives the block its control-flow exit.

`FunctionBuilder` creates `block0` automatically, so a straight-line function can emit instructions immediately.

## How MachV differs from MilkIR

MilkIR and MachV describe the same program at different levels:

| MilkIR | MachV |
| --- | --- |
| Represents target-independent program semantics. | Represents instructions selected for a machine target. |
| Values have language-level types such as `I32`, `F64`, and `Ptr`. | Registers have allocation classes such as `Int`, `Float64`, and `Vector`. |
| An instruction carries SSA operands and results. | An instruction carries explicit register uses, definitions, and allocation constraints. |
| Control flow uses typed SSA block parameters and jump arguments. | Control flow uses register-level block arguments and machine branch forms. |
| Most semantic optimization happens before instruction selection. | Machine peephole optimization, register allocation, and encoding follow instruction selection. |

MachV is not assembly text. Virtual registers, symbolic call targets, abstract stack locations, and allocation constraints still need later processing.

## Registers: virtual, physical, and writable

MachV uses four related types:

| Type | Meaning | Example |
| --- | --- | --- |
| `VReg` | A virtual register that still needs a location. | `v2` |
| `PReg` | A physical register identified by target register index and class. | `{ index: 0, class: Int }` |
| `Reg` | Either `Virtual(vreg)` or `Physical(preg)`. | `Virtual(sum)` |
| `Writable` | A register used as an instruction destination. | `{ reg: Virtual(sum) }` |

The `Writable` wrapper makes definitions visibly different from inputs. In the addition example:

```text
uses = [v0, v1]
defs = [v2]
```

This information is essential for liveness analysis and register allocation. The allocator needs to know where each old value is read and where each new value is written.

## Register classes and value kinds

`RegClass` answers an allocation question: which register bank can hold this value?

| `RegClass` | Register bank |
| --- | --- |
| `Int` | General-purpose integer and pointer registers. |
| `Float32` | 32-bit floating-point registers. |
| `Float64` | 64-bit floating-point registers. |
| `Vector` | 128-bit SIMD registers. |

`ValueKind` keeps information needed by function signatures and ABI lowering: `I32`, `I64`, `F32`, `F64`, `V128`, or `Ptr`.

Several value kinds can share one register class. Both `I32` and `I64`, for example, use `RegClass::Int`. Function parameters print their register classes, while `FunctionBuilder::add_result` records result kinds separately for ABI decisions; `get_result_kinds()` therefore reports `I64` in the example above.

## Instructions: opcode, uses, definitions, and constraints

Each `Inst` contains:

- an `Opcode` describing the operation;
- `uses`, the registers read by the instruction;
- `defs`, the registers written by the instruction;
- optional constraints for operands that must use particular physical registers.

For integer arithmetic, the Boolean carried by opcodes such as `Add`, `Sub`, and `Mul` selects operand width: `true` means 64-bit and `false` means 32-bit. Therefore `Add(true)` prints as `add`, while `Add(false)` prints as `add32`.

The order of `uses` and `defs` follows the operand contract of the opcode. For example:

```text
Add(true)     uses [lhs, rhs]       defs [result]
Load(I64, 8)  uses [base]           defs [loaded]
Store(I64, 8) uses [base, value]    defs []
Move          uses [source]         defs [destination]
```

MachV also contains comparisons, conversions, calls, traps, stack operations, SIMD operations, and target-oriented instruction forms used by the lowering packages.

## Operand constraints

Most operands use `Any`, allowing register allocation to choose a location. `FixedReg(preg)` requires an operand to use a particular physical register, which is useful for calling conventions and instructions with fixed-register requirements.

```moonbit check
///|
test "attach a fixed-register constraint" {
  let builder = FunctionBuilder::FunctionBuilder("fixed_result")
  let src = builder.add_param(Int)
  builder.add_result(I64)
  let dst = builder.new_vreg(Int)
  let required : PReg = { index: 1, class: Int }

  builder.append(Move, uses=[Virtual(src)], defs=[{ reg: Virtual(dst) }], def_constraints=[
    FixedReg(required),
  ])
  |> ignore
  builder.terminate(Return([Virtual(dst)]))

  let func = builder.finish()
  inspect(
    func.blocks[0].insts[0].def_constraints[0] == FixedReg(required),
    content="true",
  )
}
```

Constraint arrays correspond positionally to `uses` or `defs`. An omitted entry behaves as `Any`.

## Blocks and terminators

A MachV block contains instructions followed by one terminator. `create_block()` returns the numeric block ID used by branch and jump terminators. Call `switch_to_block(id)` before emitting into another block.

```moonbit check
///|
test "build conditional control flow" {
  let builder = FunctionBuilder::FunctionBuilder("choose_path")
  let condition = builder.add_param(Int)
  let then_block = builder.create_block()
  let else_block = builder.create_block()

  builder.terminate(Branch(Virtual(condition), then_block, else_block))

  builder.switch_to_block(then_block)
  builder.terminate(Return([]))

  builder.switch_to_block(else_block)
  builder.terminate(Return([]))

  let func = builder.finish()
  inspect(func.blocks.length(), content="3")
  inspect(func.blocks[0].terminator is Some(Branch(_, _, _)), content="true")
  inspect(func.blocks[1].terminator is Some(Return([])), content="true")
  inspect(func.blocks[2].terminator is Some(Return([])), content="true")
}
```

The main terminators are:

| Terminator | Purpose |
| --- | --- |
| `Jump(target, args)` | Transfer control to one block and pass register arguments. |
| `Branch(condition, then_id, else_id)` | Choose between two blocks. |
| `BranchCmp(...)` | Compare two registers and branch without materializing a Boolean value. |
| `BranchZero(...)` | Branch on a zero or nonzero register value. |
| `BranchCmpImm(...)` | Compare a register with an immediate and branch. |
| `BrTable(index, targets, default)` | Dispatch through a jump table. |
| `Return(values)` | Return registers to the caller. |
| `Trap(payload)` | End execution with an embedding-defined trap payload. |

Every block passed to register allocation or emission needs a terminator.

## Verification boundaries

`Function::verify()` checks the target-independent MachV contract: CFG targets and edge arguments, function returns, constraint-array alignment, exhaustive opcode operand contracts, virtual-register definition uniqueness, use-before-definition, and dominance. `Function::verify_for_isa(isa)` additionally rejects physical registers that are illegal for the selected target. Register allocation uses `verify_for_regalloc_isa(isa)`, which also requires dense block IDs because its tables address blocks by numeric ID.

`FunctionBuilder::finish()` calls `verify()` before returning. The lowering, register-allocation, and emission seams verify again because `Function`, `Block`, and `Inst` expose mutable arrays; callers may legally transform a function after construction, but they cannot bypass validation before a backend consumer processes it. Failures are returned as structured `VerifyError` values.

## Calls, ABI data, and stack state

MachV records the machine-level information needed around calls:

- `CallConventionLayout` describes argument and result registers plus overflow stack layout.
- `EmbeddingABI` groups the calling convention with reserved-register and context-layout data.
- call opcodes record argument counts, result register classes, symbolic targets, and clobber classes.
- `max_outgoing_args_size` records the largest outgoing stack-argument area needed by the function.
- `num_spill_slots` records spill space assigned during register allocation.

Call targets can remain symbolic through MachV and machine-code emission. The embedding application resolves those symbols when installing generated code.

## Construction rules

`FunctionBuilder` records the instruction shape supplied by the caller; it does not infer an opcode's operands. `finish()` verifies that shape. A lowering implementation should maintain these rules:

1. Give every block exactly one terminator.
2. Supply `uses` and `defs` in the order required by the opcode.
3. Use register classes compatible with the selected instruction form.
4. Keep constraint arrays aligned with their corresponding operands.
5. Use `Function::print()` in lowering tests so instruction and control-flow mistakes are easy to inspect.

Call `verify()` after target-independent transformations and `verify_for_isa(isa)` when physical registers or fixed constraints are present. Register allocation and emission also enforce these checks at their public entry points.

## Packages

| Package | Purpose |
| --- | --- |
| `Milky2018/machv` | Function model, `FunctionBuilder`, common instruction types, and printing. |
| `Milky2018/machv/abi` | Virtual and physical registers, operand constraints, calling conventions, and embedding ABI data. |
| `Milky2018/machv/instr` | Machine instructions, calls, traps, and terminators. |
| `Milky2018/machv/block` | Basic-block representation. |
| `Milky2018/machv/isa` | ISA descriptors and target selection. |
| `Milky2018/machv/isa/aarch64` | AArch64 register descriptions. |
| `Milky2018/machv/isa/amd64` | AMD64 register descriptions. |

## Integration

Target lowering packages produce MachV functions. `Milky2018/machv_regalloc` assigns their virtual registers and plans spills and moves, then `Milky2018/machv_emit` emits machine-code bytes and symbolic metadata.
