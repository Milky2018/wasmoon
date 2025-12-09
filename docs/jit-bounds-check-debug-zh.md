# JIT 内存边界检查调试报告

## 背景

任务目标是为 JIT 编译器实现内存边界检查，使 `testsuite/data/address.wast` 中的 `assert_trap` 测试能够通过。初始状态：207 个测试通过，49 个失败（全部是期望 "out of bounds memory access" 的测试）。

## 实现的功能

### 1. 传递 memory_size 参数

修改 C FFI 层，将 `memory_size` 作为第三个参数（AArch64 调用约定中的 X2 寄存器）传递给 JIT 函数：

```c
// X0 = func_table_ptr
// X1 = memory_base
// X2 = memory_size
// X3+ = WASM 函数参数
```

### 2. 边界检查指令

在 VCode 层添加 `BoundsCheck(offset, access_size)` 指令，生成的机器码会：
1. 将 32 位 WASM 地址零扩展到 64 位
2. 加上 offset + access_size 得到访问结束地址
3. 与 memory_size (X22) 比较
4. 如果越界，执行 `BRK #1` 触发 SIGTRAP 信号

## 发现的 Bug

### Bug 1: IR 优化器错误删除 Load 指令

**问题**：`has_side_effects()` 函数没有将 Load 指令视为有副作用。当 Load 的结果被丢弃时（如 `(drop (i64.load8_u ...))`），死代码消除（DCE）会删除整个 Load 指令。

**影响**：`assert_trap` 测试中被 drop 的 Load 永远不会触发 trap。

**修复**：将所有 Load 变体加入 `has_side_effects()` 函数。

### Bug 2: 神秘的崩溃问题（核心调试过程）

**现象**：
- 有 `fprintf` 调试输出时，测试通过
- 删除调试输出后，测试崩溃（SIGSEGV）
- 添加 `fflush(NULL)` 可以修复崩溃

这是一个非常诡异的现象——删除调试输出竟然会导致程序崩溃！

#### 调试历程

**尝试 1：volatile + 内存屏障** ❌

按照 C 标准，在 setjmp 和 longjmp 之间修改的变量应该声明为 volatile：

```c
volatile int64_t mem_base = 0;
volatile int64_t mem_size = 0;
__asm__ volatile("" ::: "memory");  // 内存屏障
```

结果：仍然崩溃。

**尝试 2：MoonBit FFI 引用计数** ❌

怀疑是 MoonBit 的引用计数机制导致问题。

结论：不相关。崩溃的函数只接收 `Int64` 原始类型，不涉及引用计数对象。

**尝试 3：`__attribute__((optnone))`** ✓

禁用函数的编译器优化：

```c
__attribute__((optnone))
MOONBIT_FFI_EXPORT int64_t wasmoon_jit_call_ctx_i64_i64(...) {
    // ...
}
```

结果：测试通过！确认问题是编译器优化导致的。

**尝试 4：`sigsetjmp/siglongjmp`** ❌

因为 longjmp 是从信号处理函数中调用的，尝试使用专门为信号设计的 `sigsetjmp/siglongjmp`。

结果：仍然崩溃。说明问题不是信号掩码相关的。

#### 最终突破：lldb 调试

使用 lldb 调试崩溃现场，发现了关键信息：

```
* frame #0: wasmoon_jit_call_ctx_i64_i64 + 168
->  str    wzr, [x22, #0x4a0]    ; 崩溃！address=0x104a0
```

**X22 = 0x10000 = 65536 = memory_size（1 个 WASM 页）！**

反汇编 C 代码：

```asm
<+36>:  adrp   x22, 89               ; C 编译器用 X22 存储全局变量页地址
<+100>: str    w1, [x22, #0x4a0]     ; g_trap_active = 1
<+112>: bl     sigsetjmp             ; sigsetjmp 保存 X22（页地址）
...
<+164>: blr    x20                   ; 调用 JIT 函数
<+168>: str    wzr, [x22, #0x4a0]    ; g_trap_active = 0（期望 X22 是页地址）
```

**根本原因找到了！**

JIT prologue 代码：
```moonbit
emit_mov_reg(mc, 20, 0) // MOV X20, X0 - 直接覆盖，没有保存！
emit_mov_reg(mc, 21, 1) // MOV X21, X1 - 直接覆盖，没有保存！
emit_mov_reg(mc, 22, 2) // MOV X22, X2 - 直接覆盖，没有保存！
```

X20, X21, X22 是 **callee-saved 寄存器**。按照 AArch64 调用约定，被调用函数如果要使用这些寄存器，**必须先保存原始值，返回前恢复**。但我们的 JIT 代码直接覆盖了它们！

**崩溃流程**：
1. C 编译器将全局变量页地址存入 X22
2. sigsetjmp 保存当前 X22 值
3. 调用 JIT 函数，JIT prologue 将 memory_size 写入 X22
4. JIT 执行 BRK #1 触发 SIGTRAP
5. 信号处理函数调用 siglongjmp
6. siglongjmp 恢复 X22 为 sigsetjmp 时的值（页地址）
7. C 代码继续执行 `str wzr, [x22, #0x4a0]`
8. 但此时栈上的 X22 备份已经被 JIT 破坏...
9. 实际上 siglongjmp 无法正确恢复，导致 X22 = memory_size
10. 用 memory_size (65536) 作为地址访问 → **崩溃**

## 最终修复

修改 `emit_prologue` 和 `emit_epilogue`，始终保存和恢复 X20, X21, X22：

```moonbit
fn emit_prologue(mc : MachineCode, clobbered : Array[Int]) -> Int {
  // 首先保存 X20, X21, X22（它们是 callee-saved 寄存器！）
  let all_to_save : Array[Int] = [20, 21, 22]
  for reg in clobbered { all_to_save.push(reg) }
  // ... 保存到栈上 ...
  // 然后才能覆盖它们
  emit_mov_reg(mc, 20, 0)
  emit_mov_reg(mc, 21, 1)
  emit_mov_reg(mc, 22, 2)
}
```

## 为什么之前的 workaround 有效？

- **`fflush(NULL)`**：作为外部函数调用，阻止编译器将全局变量地址缓存在 X22 中
- **`__attribute__((optnone))`**：禁用优化，编译器不会使用 X22 存储全局变量
- **`fprintf` 调试输出**：同样是外部函数调用，起到了优化屏障的作用

这些 workaround 只是碰巧让编译器不使用 X22，从而避开了问题，而不是真正的修复。

## 经验教训

1. **WASM 的 Load 指令有副作用**：可能触发 trap，DCE 不能删除它们
2. **调试输出可能掩盖 bug**：`fprintf` 等函数调用会影响编译器优化
3. **Callee-saved 寄存器必须保存/恢复**：这是 ABI 的基本要求，违反会导致难以调试的问题
4. **lldb 反汇编是终极调试手段**：当高层调试方法失效时，看机器码往往能找到真相

## 最终结果

- `address.wast`: **256 passed, 0 failed**
- 不再需要任何 workaround（`fflush`、`optnone` 等）
