# Wasmoon JIT 优化计划

本文档记录当前 JIT 编译器的 ABI 设计问题、代码坏味道及优化建议。

## 目录

1. [Calling Convention 问题](#1-calling-convention-问题)
2. [FFI 设计问题](#2-ffi-设计问题)
3. [编码规范问题](#3-编码规范问题)
4. [架构坏味道](#4-架构坏味道)
5. [优化建议汇总](#5-优化建议汇总)
6. [ABI 重构方案](#6-abi-重构方案)
7. [实施进度](#7-实施进度)

---

## 1. Calling Convention 问题

### 1.1 自定义 ABI 与标准 AAPCS64 不兼容

**现状**：当前使用自定义 JIT ABI：

```
JIT 函数调用约定：
  X0  = func_table_ptr      (函数表指针)
  X1  = memory_base         (线性内存基址)
  X2  = memory_size         (线性内存大小)
  X3  = 用户参数 0
  X4  = 用户参数 1
  X5  = 用户参数 2
  X6  = 用户参数 3
  X7  = 用户参数 4 / extra_results_buffer (多返回值时)
  X8  = 用户参数 5
  X9  = 用户参数 6
  X10 = 用户参数 7
  栈  = 用户参数 8+

保留寄存器：
  X20 = func_table_ptr (prologue 后)
  X21 = memory_base    (prologue 后)
  X22 = memory_size    (prologue 后)
  X23 = extra_results_buffer (可选)
  X24 = indirect_table_ptr
```

**问题**：

1. **与标准 AAPCS64 不兼容**：无法直接调用标准 C 函数，需要额外的 trampoline
2. **X7 语义复用冲突**：X7 既是第 5 个用户参数，又是 `extra_results_buffer` 指针
   - 当函数有多返回值时，X7 被占用，参数 4 需要特殊处理
   - 代码中需要根据 `needs_extra_results` 条件判断 X7 用途
3. **WASI trampoline 浪费**：所有 WASI 函数都需要接收 `func_table, mem_base` 两个无用参数

```c
// ffi_jit.c:356 - WASI trampoline 签名
static int64_t wasi_fd_write_impl(
    int64_t func_table,  // 无用，被忽略
    int64_t mem_base,    // 无用，使用全局 g_jit_context
    int64_t fd,
    int64_t iovs,
    int64_t iovs_len,
    int64_t nwritten_ptr
) {
    (void)func_table;  // unused
    (void)mem_base;    // we use global context instead
    // ...
}
```

**影响**：
- 增加调用开销（多传 2-3 个参数）
- 代码复杂度增加
- 难以与外部 C 库集成

---

### 1.2 浮点参数通过 GPR 传递

**现状**：

```moonbit
// emit.mbt:2574-2579
// FFI passes all args as Int64 in X registers
// Float params need special handling:
//   - For f32: lower 32 bits of X register contain f32 bit pattern
//   - For f64: full 64 bits of X register contain f64 bit pattern
```

所有参数（包括浮点数）都通过 X3-X10 传递，然后在 prologue 中转换：

```moonbit
// emit.mbt:2600-2607
Float32 => {
  // Float32 param: extract f32 from lower 32 bits
  // FMOV S(dest), W(x_src) - bit-exact transfer, no conversion
  emit_fmov_w_to_s(mc, s_dest, x_src)
}
Float64 => {
  // Float64 param: extract f64 from full 64 bits
  emit_fmov_x_to_d(mc, d_dest, x_src)
}
```

**问题**：

1. **违反 AAPCS64**：标准约定浮点参数应通过 D0-D7 传递
2. **额外转换开销**：每个浮点参数需要一条 FMOV 指令
3. **FFI 层需要特殊处理**：C 代码调用 JIT 时需要将浮点数 reinterpret 为 int64

---

### 1.3 寄存器分配池优化

**现状**（已完成优化）：

```moonbit
// target.mbt - 当前状态
/// X8-X15 可分配作为 scratch 寄存器
pub fn allocatable_scratch_regs() -> Array[PReg] {
  [
    { index: 8 }, { index: 9 }, { index: 10 },
    { index: 11 }, { index: 12 }, { index: 13 },
    { index: 14 }, { index: 15 },
  ]  // 8 个 scratch
}

/// Callee-saved registers available for allocation
pub fn allocatable_callee_saved_regs() -> Array[PReg] {
  [
    { index: 19, class: Int },
    { index: 23, class: Int },
    { index: 25, class: Int },
    { index: 26, class: Int },
    { index: 27, class: Int },
    { index: 28, class: Int },
  ]
}
```

**已完成**：

1. ✅ **Scratch 寄存器从 1 个增加到 8 个** (X8-X15)
   - 大幅减少了对 callee-saved 寄存器的依赖
   - 降低了 prologue/epilogue 开销
2. ✅ **CallIndirect 已重构**
   - 使用栈传递参数，不再硬编码占用 X11-X15
   - X11-X15 完全回收给寄存器分配器使用

**寄存器使用现状**：

| 寄存器 | 用途 | 状态 |
|--------|------|------|
| X0-X2 | JIT ABI 参数 (v1) / 用户参数 (v2) | 调用后可用 |
| X3-X7 | 用户参数 (v1) | 调用后可用 |
| X8-X15 | scratch | ✅ 已可分配 |
| X16-X17 | IP0/IP1 (linker/emit scratch) | 临时可用 |
| X18 | 平台保留 (Apple) | 保留 |
| X19 | callee-saved | ✅ 已可分配 |
| X20-X22 | context 保留 | 保留 |
| X23 | extra_results / callee-saved | 条件可用 |
| X24 | indirect_table | 保留 |
| X25-X28 | callee-saved | ✅ 已可分配 |
| X29 | FP | 保留 |
| X30 | LR | 否 |

---

## 2. FFI 设计问题

### 2.1 全局状态依赖

**现状**：

```c
// ffi_jit.c:211
static jit_context_t *g_jit_context = NULL;

// WASI 函数使用全局 context
static int64_t wasi_fd_write_impl(...) {
    if (!g_jit_context || !g_jit_context->memory_base) {
        return 8; // ERRNO_BADF
    }
    uint8_t *mem = g_jit_context->memory_base;
    // ...
}
```

**问题**：

1. **不支持多线程**：全局变量在多线程环境下会导致数据竞争
2. **不支持多实例**：无法同时运行多个 WASM 实例
3. **违背隔离原则**：WebAssembly 设计要求实例间完全隔离
4. **测试困难**：全局状态使单元测试相互影响

---

### 2.2 信号处理的线程安全问题

**现状**：

```c
// ffi_jit.c:36-38
static sigjmp_buf g_trap_jmp_buf;
static volatile sig_atomic_t g_trap_code = 0;
static volatile sig_atomic_t g_trap_active = 0;

// 信号处理器
static void trap_signal_handler(int sig) {
    if (g_trap_active) {
        g_trap_code = 1;
        siglongjmp(g_trap_jmp_buf, 1);  // 使用全局 jump buffer
    }
}
```

**问题**：

1. **线程不安全**：多线程同时执行 JIT 代码时，全局 `g_trap_jmp_buf` 会被覆盖
2. **信号处理器竞态**：`g_trap_active` 的检查和 `siglongjmp` 之间存在竞态窗口
3. **嵌套调用问题**：如果 JIT 代码调用 C 代码再调用 JIT 代码，trap 处理会混乱

---

### 2.3 Volatile 变量 Hack

**现状**：

```c
// ffi_jit.c:927-930
// CRITICAL: Save the parameters that are used AFTER the BLR call.
// The compiler may allocate these in registers that get clobbered by our
// register setup for the JIT call.
volatile int saved_num_results = num_results;
volatile int64_t *saved_results = results;
volatile int *saved_result_types = result_types;
```

**问题**：

1. **编译器依赖**：这是为了绕过编译器优化的 hack，可能在不同编译器/版本上表现不同
2. **性能损失**：`volatile` 强制内存访问，阻止优化
3. **根本原因**：内联汇编的 clobber list 可能不完整

---

## 3. 编码规范问题

### 3.1 魔法数字泛滥

**现状**：

```moonbit
// emit.mbt 中大量硬编码偏移
emit_str_imm(mc, 21, 31, 8)   // 8 是什么？X21 在栈上的偏移
emit_str_imm(mc, 22, 31, 16)  // 16 是什么？X22 在栈上的偏移

// 条件码硬编码
emit_b_cond(mc, 2, default)   // 2 = HS (unsigned greater or equal)
```

**问题**：

1. **可读性差**：数字含义不明确
2. **维护困难**：修改栈布局需要找到所有相关数字
3. **容易出错**：手动计算偏移容易出错

**建议**：

```moonbit
// 定义栈布局常量
let STACK_OFFSET_X20 = 0
let STACK_OFFSET_X21 = 8
let STACK_OFFSET_X22 = 16
let STACK_OFFSET_X23 = 24
let STACK_OFFSET_X24 = 32

// 使用常量
emit_str_imm(mc, 21, 31, STACK_OFFSET_X21)
```

---

### 3.2 寄存器用途分散定义

**现状**：

寄存器约定分散在多个文件：

| 文件 | 定义内容 |
|------|----------|
| `vcode/target.mbt` | 可分配寄存器列表 |
| `vcode/emit.mbt` | X20-X24 保留用途 |
| `jit/jit_ffi/ffi_jit.c` | 调用约定注释 |
| `vcode/regalloc.mbt` | 寄存器类型判断 |

**问题**：

1. **信息分散**：理解完整 ABI 需要阅读多个文件
2. **不一致风险**：修改一处可能忘记修改其他地方
3. **文档缺失**：没有统一的 ABI 文档

**建议**：

创建 `vcode/abi.mbt` 集中定义：

```moonbit
// vcode/abi.mbt

/// JIT ABI 寄存器约定
///
/// 参数传递：
///   X0  = func_table_ptr
///   X1  = memory_base
///   X2  = memory_size
///   X3-X10 = 用户参数 0-7
///   栈 = 用户参数 8+
///
/// 保留寄存器：
///   X20 = func_table_ptr (函数内)
///   X21 = memory_base (函数内)
///   X22 = memory_size (函数内)
///   X23 = extra_results_buffer (可选)
///   X24 = indirect_table_ptr

pub let ABI_FUNC_TABLE_REG = 20
pub let ABI_MEM_BASE_REG = 21
pub let ABI_MEM_SIZE_REG = 22
pub let ABI_EXTRA_RESULTS_REG = 23
pub let ABI_INDIRECT_TABLE_REG = 24

pub let ABI_PARAM_BASE_REG = 3
pub let ABI_MAX_REG_PARAMS = 8
```

---

### 3.3 全局变量改为 const ✅

**已完成**：

`vcode/abi.mbt` 中的常量已从 `pub let` 改为 `pub const`，并使用大写命名：

```moonbit
// vcode/abi.mbt (已更新)
pub const CTX_FUNC_TABLE_OFFSET : Int = 0
pub const CTX_INDIRECT_TABLE_OFFSET : Int = 8
pub const CTX_MEMORY_BASE_OFFSET : Int = 16
pub const CTX_MEMORY_SIZE_OFFSET : Int = 24

pub const REG_CONTEXT : Int = 20
pub const REG_MEMORY_BASE : Int = 21
pub const REG_MEMORY_SIZE : Int = 22
pub const REG_EXTRA_RESULTS : Int = 23
pub const REG_INDIRECT_TABLE : Int = 24

pub const PARAM_BASE_REG : Int = 0
pub const MAX_REG_PARAMS : Int = 8
pub const FLOAT_PARAM_BASE_REG : Int = 0
pub const MAX_FLOAT_REG_PARAMS : Int = 8

pub const LEGACY_PARAM_BASE_REG : Int = 3
pub const LEGACY_MAX_REG_PARAMS : Int = 8

pub const SCRATCH_REG_1 : Int = 16
pub const SCRATCH_REG_2 : Int = 17

pub const ABI_VERSION : Int = 1
```

**收益**：

1. ✅ **语义准确**：`const` 明确表示编译期常量
2. ✅ **性能提升**：`const` 可以被编译器内联
3. ✅ **MoonBit 规范**：符合编译期常量的命名和定义规范

**待处理**：
- `vcode/vcode.mbt`: `spill_slot_base` → `SPILL_SLOT_BASE` (可选，影响范围较小)

---

### 3.4 重复代码模式

**现状**：

```moonbit
// emit.mbt 中多处类似的 prologue 设置
emit_mov_reg(mc, 20, 0) // MOV X20, X0 (func_table_ptr)
emit_mov_reg(mc, 21, 1) // MOV X21, X1 (memory_base)
emit_mov_reg(mc, 22, 2) // MOV X22, X2 (memory_size)

// CallIndirect 中也有类似设置
emit_mov_reg(mc, 0, 20) // MOV X0, X20
emit_mov_reg(mc, 1, 21) // MOV X1, X21
emit_mov_reg(mc, 2, 22) // MOV X2, X22
```

**建议**：

```moonbit
fn emit_save_abi_context(mc: MachineCode) {
  emit_mov_reg(mc, ABI_FUNC_TABLE_REG, 0)
  emit_mov_reg(mc, ABI_MEM_BASE_REG, 1)
  emit_mov_reg(mc, ABI_MEM_SIZE_REG, 2)
}

fn emit_restore_abi_context(mc: MachineCode) {
  emit_mov_reg(mc, 0, ABI_FUNC_TABLE_REG)
  emit_mov_reg(mc, 1, ABI_MEM_BASE_REG)
  emit_mov_reg(mc, 2, ABI_MEM_SIZE_REG)
}
```

---

## 4. 架构坏味道

### 4.1 memory.grow 的栈操作 Hack

**现状**：

```moonbit
// emit.mbt:3963-3975
// 调用 memory_grow 后更新 X21/X22
emit_mov_reg(mc, 21, 0) // MOV X21, X0 (new memory_base)
// Update the saved X21 on stack so epilogue restores the new value
emit_str_imm(mc, 21, 31, 8) // STR X21, [SP, #8]

emit_mov_reg(mc, 22, 0) // MOV X22, X0 (new memory_size)
// Update the saved X22 on stack so epilogue restores the new value
emit_str_imm(mc, 22, 31, 16) // STR X22, [SP, #16]
```

**问题**：

1. **耦合过紧**：`MemoryGrow` 指令发射代码需要知道栈布局细节
2. **偏移硬编码**：假设 X21 在 `[SP+8]`，X22 在 `[SP+16]`
3. **脆弱设计**：修改 prologue 栈布局会破坏这段代码
4. **"欺骗" epilogue**：直接修改栈上保存的值，绕过正常的寄存器恢复流程

**建议**：

方案 A：不在栈上保存 X21/X22，让 memory.grow 后直接使用新值
方案 B：定义栈槽位常量，统一管理

---

### 4.2 帧大小计算分散复杂

**现状**：

```moonbit
// emit.mbt:2517-2520
let frame_size = clobbered_gpr_size +
  clobbered_fpr_size +
  spill_size +
  call_results_buffer_size

// 栈布局隐式定义：
// [SP + 0]                  : X20, X21 (pair)
// [SP + 16]                 : X22, X23/X24 (pair)
// [SP + clobbered_gpr_size] : D8, D9 (pair)
// ...
// [SP + gpr + fpr]          : spill slots
// [SP + gpr + fpr + spill]  : call_results_buffer
```

**问题**：

1. **隐式布局**：栈布局没有明确的数据结构描述
2. **计算分散**：frame_size 计算在一处，各区域偏移计算散布各处
3. **难以调试**：出问题时难以确定具体偏移

**建议**：

使用 `StackFrame` 结构统一管理（已有 `stacklayout.mbt`，但未充分使用）：

```moonbit
struct JITStackFrame {
  // 区域大小
  gpr_save_size: Int
  fpr_save_size: Int
  spill_size: Int
  call_buffer_size: Int

  // 区域起始偏移
  gpr_save_offset: Int    // = 0
  fpr_save_offset: Int    // = gpr_save_size
  spill_offset: Int       // = gpr_save_size + fpr_save_size
  call_buffer_offset: Int // = ... + spill_size

  // 总大小
  total_size: Int
}
```

---

### 4.3 X23 的条件使用增加复杂度

**现状**：

```moonbit
// emit.mbt:2490
let uses_x23 = needs_extra_results || calls_multi_value

// X23 的两种用途：
// 1. needs_extra_results = true: X23 = 调用者提供的 buffer 指针 (from X7)
// 2. calls_multi_value = true:   X23 = 栈上分配的本地 buffer 指针
```

**问题**：

1. **语义不统一**：X23 的来源和用途取决于多个条件
2. **增加分支**：prologue/epilogue 都需要条件判断
3. **难以理解**：需要同时考虑作为调用者和被调用者两个角色

---

### 4.4 BrTable 实现假设连续 targets

**现状**：

```moonbit
// emit.mbt:4215-4250
BrTable(index, targets, default) => {
  // 边界检查
  if num_targets <= 4095 {
    emit_cmp_imm(mc, index_reg, num_targets)
  } else {
    emit_load_imm64(mc, 17, num_targets.to_int64())
    emit_cmp_reg(mc, index_reg, 17)
  }
  emit_b_cond(mc, 2, default)  // B.HS default

  // 跳转表
  emit_adr(mc, 16, 12)  // ADR X16, .+12 (跳过后续指令)
  emit_add_shifted(mc, 16, 16, index_reg, Lsl, 2)  // X16 += index * 4
  emit_br(mc, 16)  // BR X16

  // 跳转表项（每项 4 字节 B 指令）
  for target in targets {
    emit_b(mc, target)
  }
}
```

**问题**：

1. **代码膨胀**：每个 target 一条 B 指令（4 字节）
2. **缓存效率**：大跳转表可能跨多个缓存行
3. **Branch19 限制**：B.cond 只有 19 位偏移，大函数可能溢出

**已修复**：num_targets > 4095 时使用寄存器比较（PR #169）

---

## 5. 优化建议汇总

### 5.1 高优先级

| 问题 | 建议 | 预期收益 |
|------|------|----------|
| 全局状态 | 将 context 作为参数传递，移除全局变量 | 支持多线程/多实例 |
| 寄存器池太小 | 回收 X9-X15 给普通分配使用 | 减少 spill，提升性能 |
| 线程安全 | 使用 TLS 或 per-context trap handling | 支持多线程 |

### 5.2 中优先级

| 问题 | 建议 | 预期收益 |
|------|------|----------|
| 浮点参数传递 | 使用 D0-D7 传递浮点参数 | 减少转换开销 |
| 魔法数字 | 定义栈布局常量 | 提高可维护性 |
| memory.grow hack | 统一栈布局管理 | 降低耦合 |

### 5.3 低优先级

| 问题 | 建议 | 预期收益 |
|------|------|----------|
| 代码重复 | 提取公共函数 | 代码整洁 |
| ABI 文档 | 创建统一的 ABI 定义文件 | 方便维护 |
| volatile hack | 完善 inline asm clobber list | 代码健壮性 |

---

## 6. 实施路线图

### Phase 1: 提升可维护性（低风险）

1. 创建 `vcode/abi.mbt` 集中定义寄存器约定和常量
2. 消除魔法数字，使用常量替代
3. 提取重复代码为公共函数

### Phase 2: 增加可分配寄存器（中风险）

1. 分析 CallIndirect 实际使用的寄存器
2. 将 X9-X15 中不冲突的寄存器加入分配池
3. 更新 liveness analysis 处理临时保留

### Phase 3: 支持多线程（高风险）

1. 移除全局 `g_jit_context`，通过寄存器传递 context
2. 使用 TLS 或 per-context 的 trap handling
3. 测试多线程并发执行

### Phase 4: 优化调用约定（高风险）

1. 重新设计 JIT ABI，减少与 AAPCS64 的差异
2. 使用 D0-D7 传递浮点参数
3. 更新所有 WASI trampoline

---

## 附录 A: 当前寄存器使用一览

```
X0  - 用户参数 0 (v2) / func_table_ptr (v1)
X1  - 用户参数 1 (v2) / memory_base (v1)
X2  - 用户参数 2 (v2) / memory_size (v1)
X3  - 用户参数 3 (v2) / 用户参数 0 (v1)
X4  - 用户参数 4 (v2) / 用户参数 1 (v1)
X5  - 用户参数 5 (v2) / 用户参数 2 (v1)
X6  - 用户参数 6 (v2) / 用户参数 3 (v1)
X7  - 用户参数 7 (v2) / 用户参数 4 / extra_results_buffer (v1)
X8  - scratch (可分配)
X9  - scratch (可分配)
X10 - scratch (可分配)
X11 - scratch (可分配, CallIndirect 已重构)
X12 - scratch (可分配, CallIndirect 已重构)
X13 - scratch (可分配, CallIndirect 已重构)
X14 - scratch (可分配, CallIndirect 已重构)
X15 - scratch (可分配, CallIndirect 已重构)
X16 - IP0 (emit scratch, 不可分配)
X17 - IP1 (emit scratch, br_table 使用, 不可分配)
X18 - 平台保留 (Apple)
X19 - callee-saved (可分配)
X20 - context_ptr (v2) / func_table_ptr (v1)
X21 - memory_base (函数内缓存)
X22 - memory_size (函数内缓存)
X23 - extra_results_buffer (条件使用) / callee-saved (可分配)
X24 - indirect_table_ptr
X25 - callee-saved (可分配)
X26 - callee-saved (可分配)
X27 - callee-saved (可分配)
X28 - callee-saved (可分配)
X29 - FP (frame pointer)
X30 - LR (link register)
X31 - SP/ZR

D0-D7   - 浮点参数/返回值 (caller-saved)
D8-D15  - callee-saved
D16-D31 - caller-saved
```

---

## 附录 B: 相关文件列表

| 文件 | 内容 |
|------|------|
| `vcode/target.mbt` | 寄存器定义、可分配寄存器列表 |
| `vcode/emit.mbt` | 指令发射、prologue/epilogue |
| `vcode/regalloc.mbt` | 寄存器分配器 |
| `vcode/lower.mbt` | IR 到 VCode 转换 |
| `vcode/stacklayout.mbt` | 栈帧布局（未充分使用）|
| `jit/jit_ffi/ffi_jit.c` | FFI 接口、WASI trampoline |
| `vcode/abi.mbt` | ABI 常量定义（新增）|

---

## 6. ABI 重构方案

### 6.1 核心思路

**关键洞察**：`func_table`, `memory_base`, `memory_size` 在整个 WASM 实例生命周期内基本不变（只有 `memory.grow` 会改变 memory）。这些值不需要每次调用都传递，可以存储在 context 结构中，函数内部从固定位置加载。

### 6.2 新旧 ABI 对比

```
旧 JIT ABI:
┌─────────────────────────────────────────────────────┐
│ X0 = func_table_ptr   ← 每次调用都传递              │
│ X1 = memory_base      ← 每次调用都传递              │
│ X2 = memory_size      ← 每次调用都传递              │
│ X3-X10 = 用户参数     ← 只剩 8 个位置               │
│ X7 = extra_results    ← 与参数 4 冲突！             │
└─────────────────────────────────────────────────────┘

新 JIT ABI:
┌─────────────────────────────────────────────────────┐
│ X0-X7 = 用户参数      ← 完整 8 个位置 (AAPCS64)     │
│ D0-D7 = 浮点参数      ← 完整 8 个位置 (AAPCS64)     │
│ X20 = context_ptr     ← callee-saved, 函数间共享    │
└─────────────────────────────────────────────────────┘
```

### 6.3 JITContext 结构

```c
// C 端定义
typedef struct {
    void **func_table;       // +0:  函数指针表
    void **indirect_table;   // +8:  call_indirect 表
    uint8_t *memory_base;    // +16: 线性内存基址
    size_t memory_size;      // +24: 线性内存大小
    // WASI 相关（可选）
    char **args;             // +32: 命令行参数
    int argc;                // +40: 参数数量
    char **envp;             // +48: 环境变量
    int envc;                // +56: 环境变量数量
} jit_context_t;
```

```moonbit
// MoonBit 端常量定义 (vcode/abi.mbt)
pub let CTX_FUNC_TABLE_OFFSET = 0
pub let CTX_INDIRECT_TABLE_OFFSET = 8
pub let CTX_MEMORY_BASE_OFFSET = 16
pub let CTX_MEMORY_SIZE_OFFSET = 24
```

### 6.4 新的寄存器约定

```
参数寄存器 (遵循 AAPCS64):
  X0-X7   = 整数参数 0-7
  D0-D7   = 浮点参数 0-7
  栈      = 参数 8+

返回值寄存器:
  X0, X1  = 整数返回值
  D0, D1  = 浮点返回值
  X7 指向的 buffer = 额外返回值 (当 >2 个返回值时)

保留寄存器 (callee-saved):
  X20 = context_ptr       // JITContext 指针
  X21 = memory_base       // 缓存，加速内存访问
  X22 = memory_size       // 缓存，加速边界检查
  X23 = extra_results_ptr // (仅多返回值函数使用)
  X24 = indirect_table    // 缓存，加速 call_indirect
```

### 6.5 Prologue 变化

**旧实现**:
```asm
; 每次调用都传入 X0=func_table, X1=mem_base, X2=mem_size
mov x20, x0          ; 保存 func_table
mov x21, x1          ; 保存 memory_base
mov x22, x2          ; 保存 memory_size
ldr x24, [x20, #-8]  ; 加载 indirect_table
; 用户参数从 X3 开始
```

**新实现**:
```asm
; X20 已经由调用者设置好 (callee-saved)
; 首次进入时由 C trampoline 设置
ldr x21, [x20, #16]  ; memory_base = ctx->memory_base
ldr x22, [x20, #24]  ; memory_size = ctx->memory_size
ldr x24, [x20, #8]   ; indirect_table = ctx->indirect_table
; 用户参数从 X0 开始 (AAPCS64!)
```

### 6.6 JIT-to-JIT 调用变化

**旧方式** (浪费):
```asm
mov x0, x20          ; func_table
mov x1, x21          ; memory_base
mov x2, x22          ; memory_size
; 参数从 x3 开始...
blr x17
```

**新方式** (高效):
```asm
; X20 是 callee-saved，自动保持
; 直接传参数，参数从 x0 开始
blr x17
```

### 6.7 C FFI 入口点变化

**旧 FFI**:
```c
int wasmoon_jit_call_multi_return(
    int64_t func_ptr,
    int64_t func_table_ptr,    // 浪费
    int64_t* args,
    int num_args,
    ...
)
```

**新 FFI**:
```c
int wasmoon_jit_call_v2(
    jit_context_t* ctx,        // context 指针
    int64_t func_ptr,
    int64_t* args,
    int num_args,
    int64_t* results,
    int* result_types,
    int num_results
)
```

### 6.8 WASI Trampoline 变化

**旧 WASI**:
```c
static int64_t wasi_fd_write_impl(
    int64_t func_table,  // 无用
    int64_t mem_base,    // 无用
    int64_t fd,
    int64_t iovs,
    ...
)
```

**新 WASI**:
```c
static int64_t wasi_fd_write_v2(
    int64_t fd,          // 直接接收用户参数
    int64_t iovs,
    int64_t iovs_len,
    int64_t nwritten_ptr
)
```

### 6.9 memory.grow 处理

```moonbit
MemoryGrow => {
  // 调用 memory_grow
  emit_mov_reg(mc, 0, delta_reg)      // X0 = delta
  emit_load_imm64(mc, 16, grow_ptr)
  emit_blr(mc, 16)

  // 保存结果到 X19
  emit_mov_reg(mc, 19, 0)

  // 更新 context 和缓存寄存器
  emit_load_imm64(mc, 16, get_base_ptr)
  emit_blr(mc, 16)
  emit_str_imm(mc, 0, 20, CTX_MEMORY_BASE_OFFSET)  // 更新 context
  emit_mov_reg(mc, 21, 0)                           // 更新缓存

  emit_load_imm64(mc, 16, get_size_ptr)
  emit_blr(mc, 16)
  emit_str_imm(mc, 0, 20, CTX_MEMORY_SIZE_OFFSET)  // 更新 context
  emit_mov_reg(mc, 22, 0)                           // 更新缓存

  emit_mov_reg(mc, result_reg, 19)
}
```

### 6.10 收益分析

| 方面 | 旧 ABI | 新 ABI | 改善 |
|------|--------|--------|------|
| 用户参数寄存器 | 8 个 (X3-X10) | 8 个 (X0-X7) | AAPCS64 兼容 |
| 浮点参数 | 通过 GPR 转换 | 直接 D0-D7 | 减少 2 条指令/参数 |
| JIT-to-JIT 调用 | 设置 3 个 context 参数 | 无需设置 | 减少 3 条指令 |
| WASI trampoline | 2 个无用参数 | 无 | 代码更干净 |
| C 函数互调 | 需要 wrapper | 可直接调用 | 更灵活 |

---

## 7. 实施进度

### Phase 1: 定义新结构 ✅

- [x] 创建 `vcode/abi.mbt` 定义 ABI 常量
- [x] 创建 `jit_context_v2_t` 结构（新布局）
- [x] 添加新的 FFI 入口点 `wasmoon_jit_call_v2`
- [x] 添加 v2 context 管理函数
- [x] 保持旧 API 兼容

### Phase 2: 更新 emit.mbt ✅

- [x] 修改 `emit_prologue`: 从 X20 加载 context (v2 模式)
- [x] 修改 `CallIndirect`: 不再设置 X0-X2 (v2 模式)
- [x] 修改参数映射: X0-X7 而非 X3-X10 (v2 模式)
- [x] 更新 `memory.grow` 实现 (保持原有逻辑, v2 模式由 C 端更新 context)

### Phase 3: 更新 regalloc.mbt ✅

- [x] 调整参数预分配寄存器 (使用 ABI 常量)
- [x] 更新可分配寄存器池 (X8-X15)
- [x] 回收 X11-X15 作为 scratch (CallIndirect 已重构，使用栈传递避免寄存器冲突)

### Phase 4: 更新 WASI

- [ ] 创建新版 WASI trampoline (无 dummy 参数)
- [ ] 更新 trampoline 获取函数
- [ ] 测试所有 WASI 函数

### Phase 5: 测试与清理

- [ ] 更新所有测试用例
- [ ] 运行 br_table.wast 等测试
- [ ] 移除旧 API (可选)
- [ ] 更新文档
