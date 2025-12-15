# Wasmoon JIT Calling Convention

本文档详细说明 wasmoon 的 JIT calling convention，包括寄存器使用、参数传递、Context管理等。

## 一、寄存器分配总览

### 1.1 保留寄存器（Reserved Registers）

这些寄存器有特殊用途，**不参与寄存器分配**：

| 寄存器 | 用途 | 类型 | 说明 |
|--------|------|------|------|
| **X19** | Context pointer | Callee-saved | 指向 JITContext 结构体，在整个调用过程中保持不变 |
| **X20** | Func table pointer | Callee-saved | 缓存的 func_table 指针 `[X19+0]` |
| **X21** | Memory base | Callee-saved | 缓存的 memory_base 指针 `[X19+16]` |
| **X22** | Memory size | Callee-saved | 缓存的 memory_size (字节数) `[X19+24]` |
| **X23** | Extra results buffer | Callee-saved | 当函数返回 >2 个值时使用 |
| **X24** | Indirect table pointer | Callee-saved | 缓存的 indirect_table 指针 `[X19+8]` (table 0) |
| **X16** | Scratch register 1 | Platform temp | 代码生成临时寄存器（load imm64, BLR等） |
| **X17** | Scratch register 2 | Platform temp | 代码生成临时寄存器（br_table等） |
| **X29** | Frame pointer | Callee-saved | 帧指针（FP） |
| **X30** | Link register | Callee-saved | 返回地址（LR） |
| **X31** | Stack pointer | Special | 栈指针（SP） |

### 1.2 可分配寄存器（Allocatable Registers）

#### Caller-saved（调用者保存）
这些寄存器在函数调用时会被破坏，调用者需要保存：

```
X8, X9, X10, X11, X12, X13, X14, X15  (8个整数寄存器)
D0-D7                                   (8个浮点寄存器，参数/返回值用)
D16-D31                                 (16个浮点寄存器，可自由使用)
```

#### Callee-saved（被调用者保存）
这些寄存器需要被调用者保存和恢复：

```
X25, X26, X27, X28  (4个整数寄存器，X19-X24已被保留)
D8-D15              (8个浮点寄存器)
```

### 1.3 参数和返回值寄存器

#### 整数参数/返回值
```
X0-X7:  参数传递（最多8个整数参数）
X0-X1:  返回值（最多2个整数返回值）
```

#### 浮点参数/返回值
```
D0-D7 (或 S0-S7):  参数传递（最多8个浮点参数）
D0-D3 (或 S0-S3):  返回值（最多4个浮点返回值）
```

## 二、JITContext 结构体布局

JITContext (v2) 的内存布局必须与 C 代码 `ffi_jit.c` 中的 `jit_context_v2_t` 严格一致：

```c
typedef struct {
    void **func_table;        // +0:  函数指针数组
    void **indirect_table;    // +8:  间接调用表（table 0）
    uint8_t *memory_base;     // +16: 线性内存基地址
    size_t memory_size;       // +24: 内存大小（字节）
    void ***indirect_tables;  // +32: 多表支持（表指针数组）
    int table_count;          // +40: 表的数量
    // ... 其他字段（不被JIT直接访问）
} jit_context_v2_t;
```

**关键点：**
- 前 48 字节的布局是固定的，被 JIT prologue 直接访问
- X19 始终指向这个结构体
- X20/X21/X22/X24 在 prologue 中从 X19 加载

## 三、函数调用流程

### 3.1 JIT 到 JIT 调用（WASM 函数互调）

**调用前（Caller）：**
1. 准备参数：
   - 整数参数 → X0-X7
   - 浮点参数 → D0-D7（或 S0-S7）
   - 超过8个参数的部分 → 栈
2. 如果被调用者返回 >2 个值：
   - X7 = X23（extra results buffer pointer）
3. X19 不需要改变（callee-saved，被调用者会保持）
4. 加载目标函数地址到 X17：
   ```
   X17 = [X20 + func_idx * 8]  // 从 func_table 加载
   ```
5. 调用：`BLR X17`

**调用后（Caller）：**
1. 重新加载 X20（因为被调用者可能修改了它）：
   ```
   X20 = [X19 + 0]  // 重新加载 func_table
   ```
2. 收集返回值：
   - 整数返回值：X0, X1
   - 浮点返回值：D0-D3
   - 额外返回值：从 X23 指向的 buffer 读取

**被调用者 Prologue：**
1. 分配栈帧：`SUB SP, SP, #frame_size`
2. 保存 callee-saved 寄存器（使用 STP）
3. 从 X19 加载 cached pointers：
   ```
   X20 = [X19 + 0]   // func_table
   X21 = [X19 + 16]  // memory_base
   X22 = [X19 + 24]  // memory_size
   X24 = [X19 + 8]   // indirect_table (table 0)
   ```
4. 如果需要 extra results buffer：`X23 = X7`
5. 移动参数到分配的寄存器（如果需要）

**被调用者 Epilogue：**
1. 恢复 callee-saved 寄存器
2. 释放栈帧：`ADD SP, SP, #frame_size`
3. 返回：`RET`

### 3.2 JIT 到 C 调用（调用 Runtime 函数）

**示例：memory.fill 调用 C 函数**

```moonbit
// C 函数签名：
// void wasmoon_jit_memory_fill_v2(int32_t dst, int32_t val, int32_t size)

// 代码生成：
MOV X0, <dst_reg>   // 参数1
MOV X1, <val_reg>   // 参数2
MOV X2, <size_reg>  // 参数3
MOVZ X16, #<addr_low>
MOVK X16, #<addr_mid>, LSL #16
MOVK X16, #<addr_high>, LSL #32
BLR X16
```

**关键点：**
1. C 函数使用标准 AAPCS64 calling convention
2. 参数通过 X0-X7 传递
3. C 函数可以访问 `g_jit_context_v2` 全局变量获取 context
4. 返回值在 X0（对于 void 函数无返回值）
5. **Clobbers**: 需要标记 X0-X2, X16 被破坏

### 3.3 间接调用（call_indirect）

**流程：**
1. 检查 table index 合法性
2. 从 indirect_table 加载函数指针：
   ```
   X17 = [X24 + elem_idx * 8]  // 对于 table 0
   ```
3. 检查类型匹配（type check）
4. 其余流程与直接调用相同

**多表支持（table_idx != 0）：**
1. 加载 indirect_tables 数组：
   ```
   X16 = [X19 + 32]  // indirect_tables
   ```
2. 加载特定 table：
   ```
   X16 = [X16 + table_idx * 8]
   ```
3. 从该 table 加载函数指针：
   ```
   X17 = [X16 + elem_idx * 8]
   ```

## 四、多返回值处理

### 4.1 返回值数量 ≤ 2

**整数返回值：**
- 1个：X0
- 2个：X0, X1

**浮点返回值：**
- 1个：D0/S0
- 2个：D0/S0, D1/S1

**混合返回值：**
按顺序分配到整数和浮点寄存器。

### 4.2 返回值数量 > 2

使用 **extra results buffer**：

**Caller：**
1. X7 = X23（将buffer指针传给被调用者）
2. 被调用者将返回值写入 buffer：
   ```
   [X23 + 0]  = 第1个返回值
   [X23 + 8]  = 第2个返回值
   [X23 + 16] = 第3个返回值
   ...
   ```
3. Caller 从 X23 buffer 读取返回值

## 五、Caller-saved vs Callee-saved 总结

### Caller-saved（调用前需要保存）
```
X0-X7    参数/返回值
X8-X15   通用寄存器
X16-X17  平台临时寄存器
D0-D7    浮点参数/返回值
D16-D31  浮点通用寄存器
```

**重要：** 调用 C 函数时，编译器会标记这些寄存器为 clobbered，寄存器分配器会自动处理。

### Callee-saved（被调用者负责保存）
```
X19      Context pointer (保留)
X20      Func table (保留)
X21      Memory base (保留)
X22      Memory size (保留)
X23      Extra results buffer (保留)
X24      Indirect table (保留)
X25-X28  通用寄存器（可分配）
X29      FP
X30      LR
D8-D15   浮点寄存器（可分配）
```

## 六、常见问题

### Q1: 为什么 X19-X24 都是 callee-saved 但被标记为保留？

**A:** 因为这些寄存器有特殊用途（Context pointers），在整个函数执行期间都需要保持值不变。虽然它们是 callee-saved（跨调用保持），但我们不希望寄存器分配器使用它们存储临时值。

### Q2: 调用 C 函数后哪些寄存器会被破坏？

**A:** 按照 AAPCS64：
- X0-X17 被破坏（caller-saved）
- X19-X29 保持（callee-saved）
- D0-D7, D16-D31 被破坏
- D8-D15 保持

但在我们的实现中，C 函数不会修改 X19-X24（Context相关寄存器）。

### Q3: 为什么 memory_fill 只标记 X0-X2, X16 为 clobbered？

**A:** 因为我们的 C 函数实现只使用这些寄存器：
- X0-X2：参数
- X16：函数指针加载

这是一个**优化**，避免不必要的寄存器 spilling。但这要求 C 函数实现遵守约定。

**标准做法：** 标记所有 caller-saved 寄存器（X0-X17, D0-D7）为 clobbered，更安全但可能导致更多 spilling。

### Q4: 为什么有些调用后要重新加载 X20？

**A:** X20（func_table pointer）可能在被调用函数中被修改。虽然 X19 是 callee-saved（被调用者会保持），但 X20-X24 是我们从 X19 派生的缓存值。被调用者可能会根据自己的 context 重新加载这些值。

所以：
- **跨JIT调用：** 需要重新从 X19 加载 X20-X24
- **跨C调用：** C函数不应该修改这些（通过全局变量访问context）

## 七、代码示例

### 示例1：简单的 JIT 到 JIT 调用

```wat
(func $add (param i32 i32) (result i32)
  local.get 0
  local.get 1
  i32.add)

(func $main (result i32)
  i32.const 10
  i32.const 20
  call $add)
```

**$main 的代码生成：**
```asm
; 准备参数
MOV W0, #10
MOV W1, #20

; 加载函数地址
LDR X17, [X20, #<$add的索引 * 8>]

; 调用
BLR X17

; 重新加载 func_table（因为被调用者可能改了）
LDR X20, [X19, #0]

; 返回值在 X0
; (继续使用 X0...)
```

### 示例2：调用 C 函数（memory.fill）

```wat
(func $fill
  i32.const 0    ; dst
  i32.const 0x42 ; val
  i32.const 10   ; size
  memory.fill)
```

**代码生成：**
```asm
; 准备参数
MOV W8, #0      ; dst
MOV W9, #0x42   ; val
MOV W10, #10    ; size

; 移动到参数寄存器
MOV X0, X8
MOV X1, X9
MOV X2, X10

; 加载 C 函数指针
MOVZ X16, #<addr_low>
MOVK X16, #<addr_mid>, LSL #16
MOVK X16, #<addr_high>, LSL #32

; 调用 C 函数
BLR X16

; X0-X2, X16 被破坏
; X19-X24 保持不变（C函数不会修改）
```

## 八、未来改进方向

1. **寄存器压力优化：** 考虑减少保留寄存器数量
2. **更细粒度的 clobber 标记：** 为不同类型的调用使用不同的 clobber set
3. **Context 传递优化：** 考虑使用不同的 Context 传递方式（参数、全局变量等）
