# Wasmoon JIT ABI for AArch64 (v2)

本文档定义了 wasmoon JIT 编译器在 AArch64 架构上使用的调用约定（Application Binary Interface）。

## 概述

Wasmoon v2 ABI 采用**混合设计**：

1. **用户参数传递**: 兼容 AAPCS64，参数通过 X0-X7 传递
2. **运行时上下文**: 通过 callee-saved 寄存器 X19 传递 context 指针
3. **多返回值支持**: 通过 X0/X1、D0/D1 和 extra_results_buffer 支持

### v2 ABI 设计理念

- **X19 = context_ptr**: 由调用者设置，被调用者保存（callee-saved）
- **X0-X7 = 用户参数**: 直接用于 WASM 函数参数，无上下文参数占用
- **Prologue 从 context 加载**: func_table、memory_base 等从 `[X19]` 加载

## 寄存器约定

### 通用寄存器 (X0-X30)

| 寄存器 | 用途 | 调用者/被调用者保存 |
|--------|------|---------------------|
| X0-X1 | WASM 参数 0-1 / 返回值 1-2 | 调用者保存 |
| X2-X7 | WASM 参数 2-7 | 调用者保存 |
| X7 | WASM 参数 7 / extra_results_buffer (多返回值时) | 调用者保存 |
| X8-X15 | 临时寄存器 (CallIndirect marshalling, spill) | 调用者保存 |
| X16-X17 | 平台 scratch / IP0, IP1 | 调用者保存 |
| X18 | 平台保留 (不使用) | - |
| **X19** | **context_ptr (JIT 上下文指针)** | 被调用者保存 |
| **X20** | **func_table_ptr (从 context 加载)** | 被调用者保存 |
| **X21** | **memory_base (从 context 加载)** | 被调用者保存 |
| **X22** | **memory_size (从 context 加载)** | 被调用者保存 |
| **X23** | **extra_results_buffer 指针** | 被调用者保存 |
| **X24** | **indirect_table_ptr (从 context 加载)** | 被调用者保存 |
| X25-X28 | 可分配 (callee-saved) | 被调用者保存 |
| X29 (FP) | 帧指针 | 被调用者保存 |
| X30 (LR) | 链接寄存器 | 被调用者保存 |
| X31 (SP) | 栈指针 | - |

### 浮点寄存器 (D0-D31 / S0-S31)

| 寄存器 | 用途 | 调用者/被调用者保存 |
|--------|------|---------------------|
| D0/S0 | 浮点返回值 1 | 调用者保存 |
| D1/S1 | 浮点返回值 2 | 调用者保存 |
| D2-D7 | 浮点临时寄存器 | 调用者保存 |
| D8-D15 | 可分配 (callee-saved) | 被调用者保存 |
| D16-D31 | 浮点临时寄存器 | 调用者保存 |

**注意**：S 寄存器是 D 寄存器的低 32 位。例如 S0 是 D0 的低 32 位。

## JIT Context 结构

v2 ABI 使用固定布局的 context 结构体：

```c
typedef struct {
    void **func_table;      // +0:  函数表指针
    void **indirect_table;  // +8:  间接调用表指针
    uint8_t *memory_base;   // +16: 线性内存基地址
    size_t memory_size;     // +24: 内存大小 (字节)
    // ... 其他字段
} jit_context_v2_t;
```

Prologue 从 X19 加载这些字段：

```asm
LDR X20, [X19, #0]    ; func_table
LDR X24, [X19, #8]    ; indirect_table
LDR X21, [X19, #16]   ; memory_base
LDR X22, [X19, #24]   ; memory_size
```

## 参数传递

### 入口参数 (FFI -> JIT)

v2 ABI 的参数布局：

```
X19 = context_ptr      (JIT 上下文指针，由 FFI trampoline 设置)
X0 = arg[0]            (第 1 个 WASM 参数)
X1 = arg[1]            (第 2 个 WASM 参数)
X2 = arg[2]            (第 3 个 WASM 参数)
X3 = arg[3]            (第 4 个 WASM 参数)
X4 = arg[4]            (第 5 个 WASM 参数)
X5 = arg[5]            (第 6 个 WASM 参数)
X6 = arg[6]            (第 7 个 WASM 参数)
X7 = arg[7] 或 extra_results_buffer (多返回值时)
```

### 栈参数 (8+ 参数)

当函数有超过 8 个参数时，参数 8 及之后的参数通过栈传递：

```
[SP + frame_size + 0]  = arg[8]   (第 9 个参数)
[SP + frame_size + 8]  = arg[9]   (第 10 个参数)
[SP + frame_size + 16] = arg[10]  (第 11 个参数)
...
```

### 浮点参数编码

- **f32**: 原始 32 位 IEEE 754 位模式存放在 X 寄存器的低 32 位
- **f64**: 原始 64 位 IEEE 754 位模式存放在 X 寄存器

```
f32 值 10.0f:
  位模式: 0x41200000
  X0 值:  0x0000000041200000

f64 值 10.0:
  位模式: 0x4024000000000000
  X0 值:  0x4024000000000000
```

### 函数内部参数处理 (Prologue)

JIT 生成的 prologue：

1. 保存 callee-saved 寄存器 (包括 X19)
2. **从 X19 加载上下文到固定寄存器**：
   ```asm
   LDR X20, [X19, #0]    ; func_table_ptr
   LDR X24, [X19, #8]    ; indirect_table_ptr
   LDR X21, [X19, #16]   ; memory_base
   LDR X22, [X19, #24]   ; memory_size
   ```
3. 将浮点参数从 X 寄存器转换到 S/D 寄存器：
   ```asm
   ; f32 参数: FMOV S, W (位模式传输，无转换)
   FMOV S0, W0   ; 第 1 个 f32 参数

   ; f64 参数: FMOV D, X
   FMOV D0, X0   ; 第 1 个 f64 参数
   ```

## 返回值

### 单返回值

| 类型 | 寄存器 |
|------|--------|
| i32/i64 | X0 |
| f32 | S0 (D0 的低 32 位) |
| f64 | D0 |

### 多返回值

WebAssembly 支持多返回值，JIT 使用以下策略：

- 前 2 个整数返回值 -> X0, X1
- 前 2 个浮点返回值 -> D0/S0, D1/S1
- 额外的返回值 -> 写入 `extra_results_buffer`

#### extra_results_buffer 约定

当函数有 >2 个整数或 >2 个浮点返回值时：

1. **调用方**: 通过 X7 传入 buffer 指针
2. **被调用方**: 将 X7 保存到 X23，额外返回值写入 `[X23 + offset]`

```
; 假设返回 (i32, i32, i32, f32, f32, f32)
; 返回值分布:
;   i32[0] -> X0
;   i32[1] -> X1
;   i32[2] -> [X23 + 0]    (extra buffer)
;   f32[0] -> S0
;   f32[1] -> S1
;   f32[2] -> [X23 + 8]    (extra buffer)
```

## 函数调用 (Call / CallIndirect)

### 直接调用

通过函数表索引调用：

```asm
; func_ptr = func_table[func_idx]
LDR X16, [X20, func_idx * 8]

; 设置参数 (X0-X7 直接用于 WASM 参数)
MOV X0, arg0   ; WASM 参数 0
MOV X1, arg1   ; WASM 参数 1
...

; X19 已包含 context_ptr (callee-saved)
; 调用
BLR X16
```

**注意**：X19 是 callee-saved 寄存器，无需在每次调用前重新设置。被调用函数的 prologue 会保存并恢复 X19。

### 间接调用 (call_indirect)

```asm
; 从 indirect_table 加载函数指针
; table_idx 在运行时计算
LDR X16, [X24, table_idx, LSL #3]

; 检查是否为 null
CBZ X16, trap_label

; 调用 (参数设置同上)
BLR X16
```

### CallIndirect 参数 Marshalling

当 JIT 代码调用另一个函数时，需要将参数从当前寄存器分配移动到 ABI 规定的位置。

v2 ABI 简化了 marshalling，因为 X0-X7 直接用于 WASM 参数：

```asm
; === 保存可能被覆盖的参数到临时寄存器 ===
MOV X11, <arg0_reg>    ; 保存 arg0
MOV X12, <arg1_reg>    ; 保存 arg1
...

; === 从临时寄存器复制到最终位置 ===
MOV X0, X11            ; arg0 -> X0
MOV X1, X12            ; arg1 -> X1
...

; === 栈参数 (args 8+) ===
STR <arg8_reg>, [SP, #0]
STR <arg9_reg>, [SP, #8]
...

; === 调用 ===
BLR X16
```

## 内存访问

所有 WASM 内存访问通过 `memory_base (X21)` 进行：

```asm
; WASM: i32.load offset=8 (addr)
; addr 在某个寄存器中，假设 X8

; 计算有效地址
ADD X16, X21, X8      ; effective_addr = memory_base + wasm_addr

; 边界检查 (可选)
ADD X17, X8, #12      ; end_addr = wasm_addr + 4 + offset
CMP X17, X22          ; compare with memory_size
B.HI trap             ; trap if out of bounds

; 加载
LDR W9, [X16, #8]     ; load with offset
```

## memory.grow 处理

当执行 `memory.grow` 指令时，内存可能被重新分配（realloc）。因此需要：

1. 调用 `memory_grow_v2(delta, max_pages)` 获取结果
2. 调用 `get_memory_base_v2()` 更新 X21
3. 调用 `get_memory_size_bytes_v2()` 更新 X22

```asm
; memory.grow delta
MOV X0, delta_reg     ; delta 参数
MOV X1, #0            ; max_pages = 0 (无限制)

; 加载并调用 memory_grow_v2
LDR X16, =memory_grow_v2_ptr
BLR X16

; 保存结果到栈 (后续调用会破坏 X0)
STR X0, [SP, #spill_offset]

; 更新 X21 = get_memory_base_v2()
LDR X16, =get_memory_base_v2_ptr
BLR X16
MOV X21, X0

; 更新 X22 = get_memory_size_bytes_v2()
LDR X16, =get_memory_size_bytes_v2_ptr
BLR X16
MOV X22, X0

; 从栈恢复结果
LDR result_reg, [SP, #spill_offset]
```

## 栈帧布局

```
高地址
+------------------------+
|   调用者的栈帧          |
+------------------------+
|   栈参数 (args 8+)     |  <- 如果有超过 8 个参数
+------------------------+ <- 入口时的 SP
|   Callee-saved GPRs    |
|   (X19-X24, etc.)      |
+------------------------+
|   Callee-saved FPRs    |
|   (D8-D15, 如果使用)    |
+------------------------+
|   Spill slots          |
|   (寄存器溢出空间)       |
+------------------------+
|   Call results buffer  |
|   (调用多返回值函数时)   |
+------------------------+ <- 函数执行时的 SP
低地址
```

### Prologue 生成的代码

```asm
; 分配栈帧
SUB SP, SP, #frame_size

; 保存 callee-saved 寄存器 (GPRs)
STP X19, X20, [SP, #0]
STP X21, X22, [SP, #16]
STP X23, X24, [SP, #32]
STP X30, XZR, [SP, #48]   ; X30 = LR (如果函数有调用)

; 保存 callee-saved FPRs (如果使用)
STP D8, D9, [SP, #64]
...

; 从 context (X19) 加载上下文寄存器
LDR X20, [X19, #0]    ; func_table_ptr
LDR X24, [X19, #8]    ; indirect_table_ptr
LDR X21, [X19, #16]   ; memory_base
LDR X22, [X19, #24]   ; memory_size

; 保存 extra_results_buffer (如需要)
MOV X23, X7

; 移动浮点参数到 S/D 寄存器
FMOV S0, W0    ; f32 参数示例
FMOV D1, X1    ; f64 参数示例
```

### Epilogue 生成的代码

```asm
; 恢复 callee-saved FPRs (如果保存了)
LDP D8, D9, [SP, #64]
...

; 恢复 callee-saved GPRs
LDP X19, X20, [SP, #0]
LDP X21, X22, [SP, #16]
LDP X23, X24, [SP, #32]
LDP X30, XZR, [SP, #48]

; 释放栈帧
ADD SP, SP, #frame_size

; 返回
RET
```

## 与 AAPCS64 的对比

| 特性 | AAPCS64 | Wasmoon JIT ABI v2 |
|------|---------|-------------------|
| 参数寄存器 (整数) | X0-X7 | X0-X7 (WASM 参数直接使用) |
| 参数寄存器 (浮点) | D0-D7 | 通过 X 寄存器传位模式 |
| 上下文传递 | N/A | X19 = context_ptr |
| 栈参数 | [SP] 及以上 | [SP + frame_size + (i-8)*8] |
| 返回值 (整数) | X0 (X0+X1) | X0, X1 |
| 返回值 (浮点) | D0-D3 | D0, D1 (S0, S1 for f32) |
| X19 用途 | Callee-saved | context_ptr (固定用途) |
| X20-X22,X24 | Callee-saved | 固定用途 (从 context 加载) |
| X23 | Callee-saved | extra_results_buffer |
| 多返回值 | 不支持 | 通过 X23 指向的 buffer 支持 |

## v1 ABI vs v2 ABI 对比

| 特性 | v1 ABI (旧) | v2 ABI (新) |
|------|-------------|-------------|
| 上下文传递 | X0=func_table, X1=mem_base, X2=mem_size | X19=context_ptr |
| WASM 参数起始 | X3 | X0 |
| 最大寄存器参数 | 8 个 (X3-X10) | 8 个 (X0-X7) |
| Prologue 操作 | MOV X20, X0; MOV X21, X1; MOV X22, X2 | LDR X20, [X19, #0]; LDR X21, [X19, #16]; ... |
| indirect_table 加载 | LDR X24, [X20, #-8] | LDR X24, [X19, #8] |
| 内存操作函数 | g_jit_context (v1) | g_jit_context_v2 |

## Trap 处理

当发生运行时错误（如内存越界）时，JIT 代码发出 `BRK #0` 指令：

```asm
BRK #0    ; 编码: 0xD4200000
```

FFI 层通过 signal handler 捕获 SIGTRAP，使用 `siglongjmp` 返回错误码。

## 示例

### 简单函数

```wat
(func (export "add") (param i32 i32) (result i32)
  (i32.add (local.get 0) (local.get 1)))
```

生成的机器码结构：

```asm
; Prologue
SUB SP, SP, #48
STP X19, X20, [SP, #0]
STP X21, X22, [SP, #16]
STP X24, XZR, [SP, #32]

; 从 context 加载
LDR X20, [X19, #0]     ; func_table
LDR X24, [X19, #8]     ; indirect_table
LDR X21, [X19, #16]    ; memory_base
LDR X22, [X19, #24]    ; memory_size

; Function body
; 参数在 X0, X1 (已就位)
ADD W0, W0, W1    ; result = arg0 + arg1

; Epilogue
LDP X19, X20, [SP, #0]
LDP X21, X22, [SP, #16]
LDP X24, XZR, [SP, #32]
ADD SP, SP, #48
RET
```

### 浮点函数

```wat
(func (export "fadd") (param f32 f32) (result f32)
  (f32.add (local.get 0) (local.get 1)))
```

生成的机器码结构：

```asm
; Prologue
SUB SP, SP, #48
STP X19, X20, [SP, #0]
STP X21, X22, [SP, #16]
STP X24, XZR, [SP, #32]

; 从 context 加载
LDR X20, [X19, #0]
LDR X24, [X19, #8]
LDR X21, [X19, #16]
LDR X22, [X19, #24]

; 将参数从 X 寄存器转换到 S 寄存器
FMOV S0, W0       ; 从 X0 低 32 位取 f32
FMOV S1, W1       ; 从 X1 低 32 位取 f32

; Function body
FADD S0, S0, S1   ; result = arg0 + arg1

; Epilogue (S0 已包含返回值)
LDP X19, X20, [SP, #0]
LDP X21, X22, [SP, #16]
LDP X24, XZR, [SP, #32]
ADD SP, SP, #48
RET
```

### 调用其他函数

```wat
(func $helper (param i32) (result i32) ...)
(func (export "caller") (param i32) (result i32)
  (call $helper (local.get 0)))
```

```asm
; Prologue (省略)
...

; 准备调用
; 参数已在 X0 中
; X19 已包含 context_ptr (callee-saved，无需重设)

; 加载目标函数指针
LDR X16, [X20, #helper_idx * 8]

; 调用
BLR X16

; 返回值已在 X0 中

; Epilogue (省略)
...
```
