# Wasmoon JIT 栈布局重构计划

本文档记录栈布局管理的完整重构方案，目标是将 `vcode/stacklayout.mbt` 中的抽象完全集成到代码生成流程中。

## 目录

1. [现状分析](#1-现状分析)
2. [重构目标](#2-重构目标)
3. [设计方案](#3-设计方案)
4. [实施计划](#4-实施计划)
5. [测试策略](#5-测试策略)

---

## 1. 现状分析

### 1.1 当前栈布局实现

**问题**：栈布局管理逻辑分散在多个函数中，缺乏统一抽象。

```moonbit
// emit.mbt:3044-3077 - 栈大小计算分散
let num_base_regs = if ABI_VERSION == 2 { ... } else { ... }
let num_pairs = (num_regs + 1) / 2
let clobbered_gpr_size = num_pairs * 16  // 魔法数字！
let clobbered_fpr_size = num_fpr_pairs * 16  // 魔法数字！
let spill_size = @cmp.maximum((num_spill_slots * 8 + 15) / 16 * 16, 16)
let call_results_buffer_size = if calls_multi_value { 64 } else { 0 }  // 魔法数字！
let frame_size = clobbered_gpr_size + clobbered_fpr_size + spill_size + call_results_buffer_size

// emit.mbt:3077 - 偏移内联计算
let spill_base_offset = clobbered_gpr_size + clobbered_fpr_size

// emit.mbt:2730 - buffer 偏移内联计算
let buffer_offset = clobbered_gpr_size + clobbered_fpr_size + spill_size
```

**栈布局**（从 SP 向高地址）：
```
[SP + 0]                      : GPR 保存区（成对，16 字节/对）
[SP + gpr_size]               : FPR 保存区（成对，16 字节/对）
[SP + gpr + fpr]              : Spill slots（8 字节/槽，16 字节对齐）
[SP + gpr + fpr + spill]      : Call results buffer（64 字节，可选）
```

### 1.2 未使用的 stacklayout.mbt

`vcode/stacklayout.mbt` 提供了完整的栈布局抽象：
- `StackSlot`：表示栈槽位置和用途
- `StackFrame`：管理栈帧布局和分配
- `AArch64StackFrame`：AArch64 特定的栈帧管理

**但是**：这些抽象完全没有在实际代码生成中使用，是预先编写的脚手架代码。

### 1.3 核心问题

| 问题 | 影响 |
|------|------|
| 偏移计算分散 | 难以理解完整栈布局，修改困难 |
| 魔法数字泛滥 | 可读性差，容易出错 |
| 重复计算 | `clobbered_gpr_size` 等在多处重复计算 |
| 耦合过紧 | `MemoryGrow` 硬编码栈偏移（如 `[SP+8]`） |
| 缺乏抽象 | 无法方便地添加新的栈区域 |
| 调试困难 | 无法可视化栈布局 |

---

## 2. 重构目标

### 2.1 功能目标

1. **统一栈布局管理**：所有栈布局计算通过 `StackFrame` API
2. **消除魔法数字**：使用命名常量和计算 API
3. **解耦栈操作**：指令发射代码不需要知道栈布局细节
4. **支持动态分配**：spill slots、call buffers 等动态管理
5. **可视化调试**：能够打印完整的栈帧布局

### 2.2 设计原则

- **单一职责**：`StackFrame` 负责所有栈布局决策
- **最小修改**：保持 `emit.mbt` 的整体结构
- **向后兼容**：不改变实际生成的栈布局
- **渐进重构**：分阶段实施，每步可验证

---

## 3. 设计方案

### 3.1 JITStackFrame 设计

创建专门的 JIT 栈帧类型，封装当前的栈布局逻辑：

```moonbit
// vcode/stacklayout.mbt - 新增 JIT 专用栈帧

///|
/// JIT 栈帧布局管理
pub(all) struct JITStackFrame {
  // ===== 区域大小 =====
  gpr_save_size : Int          // GPR 保存区大小
  fpr_save_size : Int          // FPR 保存区大小
  spill_size : Int             // Spill slots 大小
  call_buffer_size : Int       // Call results buffer 大小

  // ===== 区域偏移（从 SP 开始）=====
  gpr_save_offset : Int        // = 0
  fpr_save_offset : Int        // = gpr_save_size
  spill_offset : Int           // = gpr_save_size + fpr_save_size
  call_buffer_offset : Int     // = ... + spill_size

  // ===== 总大小 =====
  total_size : Int             // 总帧大小

  // ===== 保存的寄存器列表 =====
  saved_gprs : Array[Int]      // 需要保存的 GPR 编号
  saved_fprs : Array[Int]      // 需要保存的 FPR 编号

  // ===== 配置信息 =====
  needs_extra_results : Bool   // 是否需要 extra results buffer
  calls_multi_value : Bool     // 是否调用多返回值函数
  uses_x23 : Bool              // 是否使用 X23
}

///|
/// 构建 JIT 栈帧布局
pub fn JITStackFrame::build(
  clobbered_gprs : Array[Int],     // 用户代码使用的 callee-saved GPRs
  clobbered_fprs : Array[Int],     // 用户代码使用的 callee-saved FPRs
  num_spill_slots : Int,           // Spill slots 数量
  needs_extra_results : Bool,      // 是否需要 extra results buffer
  calls_multi_value : Bool,        // 是否调用多返回值函数
) -> JITStackFrame {
  let uses_x23 = needs_extra_results || calls_multi_value

  // 构建完整的 GPR 保存列表：基础寄存器 + 用户使用的寄存器
  let saved_gprs = build_gpr_save_list(uses_x23, clobbered_gprs)

  // 计算各区域大小
  let gpr_save_size = calc_gpr_save_size(saved_gprs.length())
  let fpr_save_size = calc_fpr_save_size(clobbered_fprs.length())
  let spill_size = calc_spill_size(num_spill_slots)
  let call_buffer_size = if calls_multi_value && !needs_extra_results {
    CALL_RESULTS_BUFFER_SIZE  // = 64
  } else {
    0
  }

  // 计算各区域偏移
  let gpr_save_offset = 0
  let fpr_save_offset = gpr_save_size
  let spill_offset = gpr_save_size + fpr_save_size
  let call_buffer_offset = spill_offset + spill_size

  // 总大小
  let total_size = gpr_save_size + fpr_save_size + spill_size + call_buffer_size

  {
    gpr_save_size,
    fpr_save_size,
    spill_size,
    call_buffer_size,
    gpr_save_offset,
    fpr_save_offset,
    spill_offset,
    call_buffer_offset,
    total_size,
    saved_gprs,
    saved_fprs: clobbered_fprs,
    needs_extra_results,
    calls_multi_value,
    uses_x23,
  }
}

///|
/// 获取 spill slot 的栈偏移
pub fn JITStackFrame::get_spill_offset(self : JITStackFrame, slot_idx : Int) -> Int {
  self.spill_offset + slot_idx * SPILL_SLOT_SIZE
}

///|
/// 获取 call results buffer 的栈偏移
pub fn JITStackFrame::get_call_buffer_offset(self : JITStackFrame) -> Int {
  self.call_buffer_offset
}

///|
/// 打印栈帧布局（用于调试）
pub fn JITStackFrame::print(self : JITStackFrame) -> String {
  let mut s = "JIT Stack Frame Layout (total: \{self.total_size} bytes):\n"
  s = s + "  [SP + \{self.gpr_save_offset}] GPR save area (\{self.gpr_save_size} bytes)\n"
  s = s + "    Saved GPRs: \{self.saved_gprs}\n"
  s = s + "  [SP + \{self.fpr_save_offset}] FPR save area (\{self.fpr_save_size} bytes)\n"
  s = s + "    Saved FPRs: \{self.saved_fprs}\n"
  s = s + "  [SP + \{self.spill_offset}] Spill slots (\{self.spill_size} bytes)\n"
  if self.call_buffer_size > 0 {
    s = s + "  [SP + \{self.call_buffer_offset}] Call results buffer (\{self.call_buffer_size} bytes)\n"
  }
  s
}

// ===== 辅助函数 =====

const SPILL_SLOT_SIZE : Int = 8          // 每个 spill slot 8 字节
const SPILL_ALIGNMENT : Int = 16         // Spill 区域 16 字节对齐
const MIN_SPILL_SIZE : Int = 16          // 最小 spill 区域（用于 MemoryGrow 等）
const CALL_RESULTS_BUFFER_SIZE : Int = 64 // Call results buffer 固定 64 字节
const PAIR_SIZE : Int = 16               // STP/LDP 每对 16 字节

///|
/// 构建需要保存的 GPR 列表
fn build_gpr_save_list(uses_x23 : Bool, clobbered : Array[Int]) -> Array[Int] {
  let base_regs : Array[Int] = if ABI_VERSION == 2 {
    // v2: X19(context), X20-X22, X24, 可选 X23
    if uses_x23 {
      [19, 20, 21, 22, 23, 24]
    } else {
      [19, 20, 21, 22, 24]
    }
  } else {
    // v1: X20-X22, X24, 可选 X23
    if uses_x23 {
      [20, 21, 22, 23, 24]
    } else {
      [20, 21, 22, 24]
    }
  }

  let result : Array[Int] = []
  for reg in base_regs {
    result.push(reg)
  }
  for reg in clobbered {
    result.push(reg)
  }
  result
}

///|
/// 计算 GPR 保存区大小（成对保存，16 字节/对）
fn calc_gpr_save_size(num_gprs : Int) -> Int {
  let num_pairs = (num_gprs + 1) / 2
  num_pairs * PAIR_SIZE
}

///|
/// 计算 FPR 保存区大小（成对保存，16 字节/对）
fn calc_fpr_save_size(num_fprs : Int) -> Int {
  let num_pairs = (num_fprs + 1) / 2
  num_pairs * PAIR_SIZE
}

///|
/// 计算 Spill 区域大小（8 字节/槽，16 字节对齐，最小 16 字节）
fn calc_spill_size(num_slots : Int) -> Int {
  let size = (num_slots * SPILL_SLOT_SIZE + SPILL_ALIGNMENT - 1) / SPILL_ALIGNMENT * SPILL_ALIGNMENT
  @cmp.maximum(size, MIN_SPILL_SIZE)
}
```

### 3.2 emit.mbt 重构

修改 `emit_function`、`emit_prologue`、`emit_epilogue` 使用 `JITStackFrame`：

```moonbit
// vcode/emit.mbt - 重构后

///|
/// Emit machine code for a VCode function
pub fn emit_function(func : VCodeFunction) -> MachineCode {
  let mc = MachineCode::new()

  // 检查配置
  let needs_extra_results = func.needs_extra_results_ptr()
  let calls_multi_value = func.calls_multi_value_function()
  let uses_x23 = needs_extra_results || calls_multi_value

  // 收集需要保存的寄存器
  let clobbered_gprs = collect_used_callee_saved(func, uses_x23)
  let clobbered_fprs = collect_used_callee_saved_fprs(func)

  // *** 核心改动：构建栈帧布局 ***
  let stack_frame = JITStackFrame::build(
    clobbered_gprs,
    clobbered_fprs,
    func.num_spill_slots,
    needs_extra_results,
    calls_multi_value,
  )

  // 可选：打印栈帧布局用于调试
  // println(stack_frame.print())

  // Emit prologue
  emit_prologue_v2(mc, stack_frame, func.params, func.param_pregs)

  // Emit function body
  for block in func.blocks {
    mc.define_label(block.id)
    for inst in block.insts {
      emit_instruction_v2(mc, inst, stack_frame)
    }
    match block.terminator {
      Some(term) =>
        emit_terminator_with_epilogue_v2(
          mc,
          term,
          stack_frame,
          func.result_types,
        )
      None => ()
    }
  }

  mc.resolve_fixups()
  mc
}

///|
/// Emit prologue using stack frame
fn emit_prologue_v2(
  mc : MachineCode,
  frame : JITStackFrame,
  params : Array[VReg],
  param_pregs : Array[PReg?],
) -> Unit {
  // 1. 分配栈空间
  emit_sub_imm(mc, 31, 31, frame.total_size)

  // 2. 保存 GPRs（成对）
  save_gprs_paired(mc, frame.saved_gprs, frame.gpr_save_offset)

  // 3. 保存 FPRs（成对）
  save_fprs_paired(mc, frame.saved_fprs, frame.fpr_save_offset)

  // 4. 设置上下文寄存器（X20-X22, X24）
  setup_context_registers(mc)

  // 5. 设置 X23（如果需要）
  if frame.needs_extra_results {
    emit_mov_reg(mc, 23, 7) // MOV X23, X7
  } else if frame.calls_multi_value {
    let buffer_offset = frame.get_call_buffer_offset()
    emit_add_imm(mc, 23, 31, buffer_offset) // ADD X23, SP, #offset
  }

  // 6. 移动参数到分配的寄存器
  move_parameters_to_registers(mc, params, param_pregs)
}

///|
/// Emit epilogue using stack frame
fn emit_epilogue_v2(
  mc : MachineCode,
  frame : JITStackFrame,
) -> Unit {
  // 1. 恢复 FPRs
  restore_fprs_paired(mc, frame.saved_fprs, frame.fpr_save_offset)

  // 2. 恢复 GPRs（最后一对使用 post-index 同时恢复 SP）
  restore_gprs_paired(mc, frame.saved_gprs, frame.gpr_save_offset, frame.total_size)
}

///|
/// Emit instruction using stack frame
fn emit_instruction_v2(
  mc : MachineCode,
  inst : VCodeInst,
  frame : JITStackFrame,
) -> Unit {
  match inst.opcode {
    SpillLoad(slot_idx) => {
      let offset = frame.get_spill_offset(slot_idx)
      let dest = reg_num(inst.defs[0])
      emit_ldr_imm(mc, dest, 31, offset)
    }
    SpillStore(slot_idx) => {
      let offset = frame.get_spill_offset(slot_idx)
      let src = reg_num(inst.uses[0])
      emit_str_imm(mc, src, 31, offset)
    }
    // ... 其他指令保持不变 ...
    _ => emit_instruction_original(mc, inst, frame.spill_offset, frame.total_size)
  }
}
```

### 3.3 消除耦合：MemoryGrow 重构

当前 `MemoryGrow` 硬编码栈偏移，需要重构：

```moonbit
// 当前代码（耦合）：
MemoryGrow(_) => {
  // ...
  emit_str_imm(mc, 21, 31, 8)   // 假设 X21 在 [SP+8]
  emit_str_imm(mc, 22, 31, 16)  // 假设 X22 在 [SP+16]
}

// 重构后（解耦）：
MemoryGrow(_) => {
  // ...
  // 不再修改栈上的值，改为：
  // 1. 选项 A：不在栈上保存 X21/X22，memory.grow 后直接使用新值
  // 2. 选项 B：通过 StackFrame API 获取 X21/X22 的栈偏移（未来扩展）

  // 采用选项 A（推荐）：
  // memory.grow 后 X21/X22 已经更新，epilogue 会恢复到栈上的旧值
  // 如果需要保持新值，在 epilogue 前不要从栈恢复
  // 或者：memory.grow 只在 tail position 调用
}
```

**决策**：采用选项 A，简化逻辑。`memory.grow` 修改的 X21/X22 在函数返回前会被 epilogue 恢复，这是正确的行为（每次进入函数都会重新从 context 加载）。

---

## 4. 实施计划

### Phase 1: 定义 JITStackFrame（低风险）

**目标**：在 `stacklayout.mbt` 中添加 JIT 专用栈帧类型。

**任务**：
- [ ] 在 `vcode/stacklayout.mbt` 中定义 `JITStackFrame` 结构体
- [ ] 实现 `JITStackFrame::build()` 构造函数
- [ ] 实现辅助函数：`build_gpr_save_list`、`calc_gpr_save_size` 等
- [ ] 实现 `get_spill_offset()`、`get_call_buffer_offset()` 等查询方法
- [ ] 实现 `print()` 用于调试
- [ ] 定义常量：`SPILL_SLOT_SIZE`、`CALL_RESULTS_BUFFER_SIZE` 等

**验证**：
- [ ] 编写单元测试验证 `JITStackFrame` 计算的偏移与当前实现一致
- [ ] 测试各种配置组合（needs_extra_results、calls_multi_value、不同寄存器数量）

**成功标准**：
- `moon check` 通过
- 单元测试覆盖所有分支
- 计算结果与当前实现完全一致

---

### Phase 2: 重构 emit_function（中风险）

**目标**：在 `emit_function` 中使用 `JITStackFrame` 构建栈布局。

**任务**：
- [ ] 修改 `emit_function`：调用 `JITStackFrame::build()` 构建栈帧
- [ ] 创建 `emit_prologue_v2`：接收 `JITStackFrame` 参数
- [ ] 创建 `emit_epilogue_v2`：接收 `JITStackFrame` 参数
- [ ] 创建 `emit_instruction_v2`：接收 `JITStackFrame` 参数
- [ ] 提取辅助函数：`save_gprs_paired`、`restore_gprs_paired` 等
- [ ] **保留旧版本**：`emit_prologue_v1` 等，便于对比测试

**验证**：
- [ ] 对比测试：v1 和 v2 生成的机器码完全相同
- [ ] 运行所有现有测试：`moon test`
- [ ] 运行 WAST 测试：`python3 scripts/run_all_wast.py`

**成功标准**：
- 生成的机器码与重构前完全一致（字节级别）
- 所有测试通过
- 代码可读性提升，魔法数字消除

---

### Phase 3: 清理和优化（低风险）

**目标**：移除旧代码，优化实现。

**任务**：
- [ ] 删除 `emit_prologue_v1`、`emit_epilogue_v2`（旧版本）
- [ ] 重命名 `emit_prologue_v2` → `emit_prologue`
- [ ] 删除重复的偏移计算代码
- [ ] 更新注释，删除过时说明
- [ ] 优化 `JITStackFrame` 实现（如果发现性能问题）

**验证**：
- [ ] 再次运行所有测试确保清理没有引入问题
- [ ] 代码审查：检查是否有遗留的魔法数字

**成功标准**：
- 代码库更简洁，无重复逻辑
- 所有测试通过
- 文档更新完整

---

### Phase 4: 扩展功能（未来）

**可选的未来扩展**：
- [ ] 支持 Outgoing arguments 栈槽（为复杂调用约定准备）
- [ ] 支持调试信息生成（DWARF）
- [ ] 支持栈展开（unwinding）
- [ ] 支持更灵活的 spill 策略

---

## 5. 测试策略

### 5.1 单元测试

在 `vcode/stacklayout_wbtest.mbt` 中添加测试：

```moonbit
///|
/// 测试基本栈帧构建
test "jit_stack_frame_basic" {
  let frame = JITStackFrame::build(
    clobbered_gprs: [],
    clobbered_fprs: [],
    num_spill_slots: 0,
    needs_extra_results: false,
    calls_multi_value: false,
  )

  // v2 ABI: 基础寄存器 [19, 20, 21, 22, 24] = 5 个 → 3 对 → 48 字节
  inspect(frame.gpr_save_size, content="48")
  inspect(frame.fpr_save_size, content="0")
  inspect(frame.spill_size, content="16")  // 最小 16 字节
  inspect(frame.call_buffer_size, content="0")
  inspect(frame.total_size, content="64")
}

///|
/// 测试 X23 使用情况
test "jit_stack_frame_with_x23" {
  let frame = JITStackFrame::build(
    clobbered_gprs: [],
    clobbered_fprs: [],
    num_spill_slots: 0,
    needs_extra_results: true,  // 使用 X23
    calls_multi_value: false,
  )

  // v2 ABI: [19, 20, 21, 22, 23, 24] = 6 个 → 3 对 → 48 字节
  inspect(frame.gpr_save_size, content="48")
  inspect(frame.uses_x23, content="true")
}

///|
/// 测试 call results buffer
test "jit_stack_frame_call_buffer" {
  let frame = JITStackFrame::build(
    clobbered_gprs: [],
    clobbered_fprs: [],
    num_spill_slots: 0,
    needs_extra_results: false,
    calls_multi_value: true,  // 需要 call buffer
  )

  inspect(frame.call_buffer_size, content="64")
  inspect(frame.get_call_buffer_offset(), content="64")  // gpr(48) + fpr(0) + spill(16)
}

///|
/// 测试 spill slots 偏移计算
test "jit_stack_frame_spill_offsets" {
  let frame = JITStackFrame::build(
    clobbered_gprs: [],
    clobbered_fprs: [],
    num_spill_slots: 4,
    needs_extra_results: false,
    calls_multi_value: false,
  )

  inspect(frame.spill_size, content="32")  // 4 * 8 = 32 字节
  inspect(frame.get_spill_offset(0), content="48")  // gpr(48) + fpr(0)
  inspect(frame.get_spill_offset(1), content="56")  // +8
  inspect(frame.get_spill_offset(2), content="64")  // +8
  inspect(frame.get_spill_offset(3), content="72")  // +8
}

///|
/// 测试 FPR 保存
test "jit_stack_frame_with_fprs" {
  let frame = JITStackFrame::build(
    clobbered_gprs: [],
    clobbered_fprs: [8, 9, 10],  // 3 个 FPR
    num_spill_slots: 0,
    needs_extra_results: false,
    calls_multi_value: false,
  )

  inspect(frame.fpr_save_size, content="32")  // 3 个 → 2 对 → 32 字节
  inspect(frame.spill_offset, content="80")   // gpr(48) + fpr(32)
}

///|
/// 测试与旧实现一致性
test "jit_stack_frame_matches_legacy" {
  // 模拟一个复杂场景
  let clobbered = [19, 25, 26, 30]  // 用户使用的 callee-saved + LR
  let clobbered_fprs = [8, 9]
  let num_spill_slots = 5

  let frame = JITStackFrame::build(
    clobbered_gprs: clobbered,
    clobbered_fprs,
    num_spill_slots,
    needs_extra_results: false,
    calls_multi_value: true,
  )

  // 验证与旧实现计算一致：
  // v2 基础: [19, 20, 21, 22, 23, 24] + clobbered [19, 25, 26, 30]
  // 去重后: [19, 20, 21, 22, 23, 24, 25, 26, 30] = 9 个 → 5 对 → 80 字节
  inspect(frame.gpr_save_size, content="80")

  // FPR: 2 个 → 1 对 → 16 字节
  inspect(frame.fpr_save_size, content="16")

  // Spill: 5 * 8 = 40 → 对齐到 48
  inspect(frame.spill_size, content="48")

  // Call buffer: 64
  inspect(frame.call_buffer_size, content="64")

  // Total: 80 + 16 + 48 + 64 = 208
  inspect(frame.total_size, content="208")
}
```

### 5.2 集成测试

```moonbit
///|
/// 对比 v1 和 v2 生成的机器码
test "compare_prologue_v1_v2" {
  // 构建测试函数
  let func = create_test_vcode_function(...)

  // 使用旧实现
  let mc_v1 = MachineCode::new()
  emit_prologue_v1(mc_v1, ...)

  // 使用新实现
  let mc_v2 = MachineCode::new()
  let frame = JITStackFrame::build(...)
  emit_prologue_v2(mc_v2, frame, ...)

  // 比较生成的字节码
  inspect(mc_v1.bytes == mc_v2.bytes, content="true")
}
```

### 5.3 回归测试

- 运行所有现有测试：`moon test`
- 运行 WAST 测试套件：`python3 scripts/run_all_wast.py`
- 对比重构前后的性能（可选）

---

## 6. 风险评估

| 风险 | 可能性 | 影响 | 缓解措施 |
|------|--------|------|----------|
| 偏移计算错误 | 中 | 高 | Phase 1 单元测试覆盖所有场景 |
| 机器码不一致 | 低 | 高 | Phase 2 字节级别对比测试 |
| 性能回退 | 低 | 中 | 保持内联计算，避免过度抽象 |
| 破坏 ABI 兼容性 | 极低 | 高 | 不修改实际栈布局，只重构计算方式 |

---

## 7. 成功标准

**Phase 1 完成**：
- ✅ `JITStackFrame` 实现完整
- ✅ 单元测试覆盖率 > 90%
- ✅ 所有测试计算结果与当前实现一致

**Phase 2 完成**：
- ✅ `emit_function` 使用 `JITStackFrame`
- ✅ 生成的机器码与重构前完全一致
- ✅ 所有 WAST 测试通过

**Phase 3 完成**：
- ✅ 旧代码删除，代码库简洁
- ✅ 无魔法数字
- ✅ 文档完整

**最终目标**：
- ✅ 栈布局管理完全统一
- ✅ 代码可维护性显著提升
- ✅ 为未来扩展（调试信息、栈展开等）奠定基础

---

## 附录 A: 常量定义

```moonbit
// vcode/stacklayout.mbt

const SPILL_SLOT_SIZE : Int = 8           // 每个 spill slot 8 字节
const SPILL_ALIGNMENT : Int = 16          // Spill 区域 16 字节对齐
const MIN_SPILL_SIZE : Int = 16           // 最小 spill 区域（MemoryGrow 使用）
const CALL_RESULTS_BUFFER_SIZE : Int = 64 // Call results buffer 固定 64 字节
const PAIR_SIZE : Int = 16                // STP/LDP 每对寄存器 16 字节
const GPR_SIZE : Int = 8                  // 每个 GPR 8 字节
const FPR_SIZE : Int = 8                  // 每个 FPR 8 字节（D 寄存器）
```

---

## 附录 B: 相关文件

| 文件 | 内容 | 修改类型 |
|------|------|----------|
| `vcode/stacklayout.mbt` | 添加 `JITStackFrame` | 新增 |
| `vcode/emit.mbt` | 重构 prologue/epilogue | 重构 |
| `vcode/abi.mbt` | 添加常量定义 | 新增常量 |
| `vcode/stacklayout_wbtest.mbt` | 单元测试 | 新增测试 |

---

*本文档最后更新：2025-12-14*
