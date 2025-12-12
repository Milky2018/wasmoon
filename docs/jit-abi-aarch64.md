# Wasmoon JIT ABI for AArch64

本文档定义了 wasmoon JIT 编译器在 AArch64 架构上使用的调用约定（Application Binary Interface）。

## 概述

Wasmoon 使用**自定义的 JIT ABI**，而非标准的 AAPCS64。这是为了：

1. 支持 WebAssembly 运行时上下文（函数表、线性内存）
2. 简化参数传递（所有参数统一用整数寄存器传递位模式）
3. 支持 WebAssembly 的多返回值特性

## 寄存器约定

### 通用寄存器 (X0-X30)

| 寄存器 | 用途 | 调用者/被调用者保存 |
|--------|------|---------------------|
| X0 | 入参: func_table_ptr / 返回值 1 | 调用者保存 |
| X1 | 入参: memory_base / 返回值 2 | 调用者保存 |
| X2 | 入参: memory_size | 调用者保存 |
| X3-X7 | WASM 函数参数 0-4 | 调用者保存 |
| X7 | WASM 参数 4 / extra_results_buffer (多返回值时) | 调用者保存 |
| X8-X10 | WASM 函数参数 5-7 | 调用者保存 |
| X11-X15 | CallIndirect 参数 marshalling 临时寄存器 | 调用者保存 |
| X16-X17 | 平台 scratch / spill 临时寄存器 | 调用者保存 |
| X18 | CallIndirect func_ptr 临时保存 | 调用者保存 |
| X19 | 可分配 (callee-saved) | 被调用者保存 |
| **X20** | **func_table_ptr (JIT 内部)** | 被调用者保存 |
| **X21** | **memory_base (JIT 内部)** | 被调用者保存 |
| **X22** | **memory_size (JIT 内部)** | 被调用者保存 |
| **X23** | **extra_results_buffer 指针** | 被调用者保存 |
| **X24** | **indirect_table_ptr (JIT 内部)** | 被调用者保存 |
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

## 参数传递

### 入口参数 (FFI → JIT)

所有参数通过整数寄存器传递，浮点值以**原始位模式**传递：

```
X0 = func_table_ptr    (函数表基地址)
X1 = memory_base       (WASM 线性内存基地址)
X2 = memory_size       (内存大小，字节)
X3 = arg[0]            (第 1 个 WASM 参数)
X4 = arg[1]            (第 2 个 WASM 参数)
X5 = arg[2]            (第 3 个 WASM 参数)
X6 = arg[3]            (第 4 个 WASM 参数)
X7 = arg[4] 或 extra_results_buffer (多返回值时)
X8 = arg[5]            (第 6 个 WASM 参数)
X9 = arg[6]            (第 7 个 WASM 参数)
X10 = arg[7]           (第 8 个 WASM 参数)
```

### 栈参数 (8+ 参数)

当函数有超过 8 个参数时，参数 8 及之后的参数通过栈传递：

```
[SP + frame_size + 0]  = arg[8]   (第 9 个参数)
[SP + frame_size + 8]  = arg[9]   (第 10 个参数)
[SP + frame_size + 16] = arg[10]  (第 11 个参数)
...
```

栈参数在调用者的栈帧中，位于被调用者栈帧之上。被调用者通过 `LoadStackParam` 指令在函数体中加载这些参数。

#### 浮点参数编码

- **f32**: 原始 32 位 IEEE 754 位模式存放在 X 寄存器的低 32 位
- **f64**: 原始 64 位 IEEE 754 位模式存放在 X 寄存器

```
f32 值 10.0f:
  位模式: 0x41200000
  X3 值:  0x0000000041200000

f64 值 10.0:
  位模式: 0x4024000000000000
  X3 值:  0x4024000000000000
```

### 函数内部参数处理 (Prologue)

JIT 生成的 prologue 会：

1. 保存 callee-saved 寄存器
2. 将上下文复制到固定寄存器：
   ```
   MOV X20, X0   ; func_table_ptr
   MOV X21, X1   ; memory_base
   MOV X22, X2   ; memory_size
   ```
3. 将浮点参数从 X 寄存器转换到 S/D 寄存器：
   ```
   ; f32 参数: FMOV S, W (位模式传输，无转换)
   FMOV S0, W3   ; 第 1 个 f32 参数

   ; f64 参数: FMOV D, X
   FMOV D0, X3   ; 第 1 个 f64 参数
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

- 前 2 个整数返回值 → X0, X1
- 前 2 个浮点返回值 → D0/S0, D1/S1
- 额外的返回值 → 写入 `extra_results_buffer`

#### extra_results_buffer 约定

当函数有 >2 个整数或 >2 个浮点返回值时：

1. **调用方**: 通过 X7 传入 buffer 指针
2. **被调用方**: 将 X7 保存到 X23，额外返回值写入 `[X23 + offset]`

```
; 假设返回 (i32, i32, i32, f32, f32, f32)
; 返回值分布:
;   i32[0] → X0
;   i32[1] → X1
;   i32[2] → [X23 + 0]    (extra buffer)
;   f32[0] → S0
;   f32[1] → S1
;   f32[2] → [X23 + 8]    (extra buffer)
```

## 函数调用 (Call / CallIndirect)

### 直接调用

通过函数表索引调用：

```
; func_ptr = func_table[func_idx]
LDR X16, [X20, func_idx * 8]

; 设置参数
MOV X0, X20    ; func_table_ptr
MOV X1, X21    ; memory_base
MOV X2, X22    ; memory_size
MOV X3, arg0   ; WASM 参数...
...

; 调用
BLR X16
```

### 间接调用 (call_indirect)

```
; 从 indirect_table 加载函数指针
; table_idx 在运行时计算
LDR X16, [X24, table_idx, LSL #3]

; 检查是否为 null
CBZ X16, trap_label

; 调用 (参数设置同上)
BLR X16
```

### CallIndirect 参数 Marshalling (三阶段)

当 JIT 代码调用另一个函数时，需要将参数从当前寄存器分配移动到 ABI 规定的位置。
这是一个复杂的过程，因为寄存器分配器可能将参数值放在任意寄存器中。

**问题**：参数 0-4 可能被分配到 X8-X10（参数 5-7 的目标位置），如果先写 X8-X10 会覆盖这些值。

**解决方案**：使用三阶段 marshalling，确保不会覆盖尚未保存的值：

```
; === Phase 1: 保存 args 0-4 到临时寄存器 X11-X15 ===
; 必须先执行！否则如果 arg0 在 X8，Phase 2 会覆盖它
MOV X11, <arg0_reg>    ; 保存 arg0
MOV X12, <arg1_reg>    ; 保存 arg1
MOV X13, <arg2_reg>    ; 保存 arg2
MOV X14, <arg3_reg>    ; 保存 arg3
MOV X15, <arg4_reg>    ; 保存 arg4

; === Phase 2: 写入 args 5-7 到 X8-X10 ===
; 现在安全了，因为 args 0-4 已保存到 X11-X15
MOV X8, <arg5_reg>     ; arg5 → X8
MOV X9, <arg6_reg>     ; arg6 → X9
MOV X10, <arg7_reg>    ; arg7 → X10

; === Phase 3: 从临时寄存器复制到最终位置 X3-X7 ===
MOV X3, X11            ; arg0 → X3
MOV X4, X12            ; arg1 → X4
MOV X5, X13            ; arg2 → X5
MOV X6, X14            ; arg3 → X6
MOV X7, X15            ; arg4 → X7

; === 栈参数 (args 8+) ===
; 直接存储到栈上
STR <arg8_reg>, [SP, #0]
STR <arg9_reg>, [SP, #8]
...

; === 设置上下文和调用 ===
MOV X0, X20    ; func_table_ptr
MOV X1, X21    ; memory_base
MOV X2, X22    ; memory_size
BLR X18        ; 调用 (func_ptr 之前已保存到 X18)
```

**Spilled 参数处理**：

当参数被溢出到栈上时，使用特殊编码 (`PReg.index >= 256`) 标记。
emit 代码检测到这种情况后，直接从 spill slot 加载到目标位置：

```
; 如果 arg5 被 spill 到 slot 3:
LDR X8, [SP, #spill_base_offset + 24]   ; 直接加载到 X8
```

## 内存访问

所有 WASM 内存访问通过 `memory_base (X21)` 进行：

```
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

## 栈帧布局

```
高地址
+------------------------+
|   调用者的栈帧          |
+------------------------+
|   栈参数 (args 8+)     |  ← 如果有超过 8 个参数
+------------------------+ ← 入口时的 SP
|   Callee-saved GPRs    |
|   (X20-X24, X19, etc.) |
+------------------------+
|   Callee-saved FPRs    |
|   (D8-D15, 如果使用)    |
+------------------------+
|   Spill slots          |
|   (寄存器溢出空间)       |
+------------------------+
|   Call results buffer  |
|   (调用多返回值函数时)   |
+------------------------+ ← 函数执行时的 SP
低地址
```

### Prologue 生成的代码

```asm
; 分配栈帧
SUB SP, SP, #frame_size

; 保存 callee-saved 寄存器 (GPRs)
STP X20, X21, [SP, #0]
STP X22, X23, [SP, #16]
STP X24, X19, [SP, #32]
STP X30, XZR, [SP, #48]   ; X30 = LR (如果函数有调用)

; 保存 callee-saved FPRs (如果使用)
STP D8, D9, [SP, #64]
...

; 设置上下文寄存器
MOV X20, X0    ; func_table_ptr
MOV X21, X1    ; memory_base
MOV X22, X2    ; memory_size
LDR X24, [X20, #-8]  ; indirect_table_ptr (存储在 func_table[-1])
MOV X23, X7    ; extra_results_buffer (如需要)

; 移动参数到目标寄存器
FMOV S0, W3    ; f32 参数示例
MOV X19, X4    ; 需要跨调用保持的整数参数
```

### Epilogue 生成的代码

```asm
; 恢复 callee-saved FPRs (如果保存了)
LDP D8, D9, [SP, #64]
...

; 恢复 callee-saved GPRs
LDP X20, X21, [SP, #0]
LDP X22, X23, [SP, #16]
LDP X24, X19, [SP, #32]
LDP X30, XZR, [SP, #48]

; 释放栈帧
ADD SP, SP, #frame_size

; 返回
RET
```

## 与 AAPCS64 的对比

| 特性 | AAPCS64 | Wasmoon JIT ABI |
|------|---------|-----------------|
| 参数寄存器 (整数) | X0-X7 | X0-X2 固定上下文，X3-X10 用户参数 (最多 8 个) |
| 参数寄存器 (浮点) | D0-D7 | 通过 X 寄存器传位模式 |
| 栈参数 | [SP] 及以上 | [SP + frame_size + (i-8)*8] |
| 返回值 (整数) | X0 (X0+X1) | X0, X1 |
| 返回值 (浮点) | D0-D3 | D0, D1 (S0, S1 for f32) |
| X8-X10 用途 | X8: 间接返回值地址 | 用户参数 5-7 |
| X11-X15 | 临时寄存器 | CallIndirect marshalling 临时寄存器 |
| X16-X17 | 平台 scratch | 平台 scratch / spill 临时寄存器 |
| X18 | 平台保留 | CallIndirect func_ptr 临时保存 |
| X19-X28 | Callee-saved | X20-X22,X24 固定用途，X23 可选 (extra_results)，其余可分配 |
| 多返回值 | 不支持 | 通过 X23 指向的 buffer 支持 |

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
SUB SP, SP, #32
STP X20, X21, [SP]
STP X22, XZR, [SP, #16]
MOV X20, X0
MOV X21, X1
MOV X22, X2

; Function body
ADD W0, W3, W4    ; result = arg0 + arg1

; Epilogue
LDP X20, X21, [SP]
LDP X22, XZR, [SP, #16]
ADD SP, SP, #32
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
SUB SP, SP, #32
STP X20, X21, [SP]
STP X22, XZR, [SP, #16]
MOV X20, X0
MOV X21, X1
MOV X22, X2
FMOV S0, W3       ; 从 X3 低 32 位取 f32
FMOV S1, W4       ; 从 X4 低 32 位取 f32

; Function body
FADD S0, S0, S1   ; result = arg0 + arg1

; Epilogue (S0 已包含返回值)
LDP X20, X21, [SP]
LDP X22, XZR, [SP, #16]
ADD SP, SP, #32
RET
```
