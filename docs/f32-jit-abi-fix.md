# F32 JIT ABI 修复：从 D 寄存器提升到 S 寄存器原始位

## 问题背景

在 AArch64 架构上，JIT 编译的 WebAssembly f32（单精度浮点）函数返回错误的值（通常是 0）。

### 原始策略（有问题）

最初的实现采用"f32 提升到 f64"的策略：
1. f32 值在 JIT 内部被提升为 f64 存储在 D 寄存器中
2. 返回时，FFI 层将 D 寄存器读取为 `double` 类型
3. 然后通过 `Float::from_double()` 转换回 f32

这种方式存在多个问题：
- 使用 `FCVT` 指令进行 f32↔f64 转换会引入精度损失
- 某些特殊值（如 NaN 的位模式）无法正确保留
- 代码路径复杂，容易出错

## 修复方案

### 新策略：f32 使用 S 寄存器的原始位

改为使用 AArch64 的 S 寄存器（32 位浮点寄存器，是 D 寄存器的低 32 位）直接存储 f32 的原始位模式：

1. **JIT 代码生成**：f32 值直接存放在 S 寄存器中，不进行任何转换
2. **FFI 层读取**：将 D 寄存器作为 `uint64_t` 读取原始位，然后提取低 32 位
3. **结果转换**：使用位重解释（reinterpret）而非数值转换

### 关键修改

#### 1. FFI 层 (`jit/ffi_jit.c`)

```c
// 修改前：读取为 double 类型
register double d0 __asm__("d0");
register double d1 __asm__("d1");

// 修改后：读取为 uint64_t 原始位
register uint64_t d0 __asm__("d0");
register uint64_t d1 __asm__("d1");

// 处理 f32 返回值
if (ty == 2) { // F32
    uint64_t bits = (float_idx == 0) ? d0_bits : d1_bits;
    uint32_t float_bits = (uint32_t)(bits & 0xFFFFFFFF);  // 提取低 32 位
    results[i] = (int64_t)float_bits;
}
```

#### 2. FromInt64 Trait (`jit/polycall.mbt`)

新增 `FromInt64` trait 用于类型安全的位重解释转换：

```moonbit
pub trait FromInt64 {
  from_int64_bits(Int64) -> Self
}

// Float 实现：从 Int64 的低 32 位重解释为 Float
pub impl FromInt64 for Float with from_int64_bits(bits) {
  bits.to_int().reinterpret_as_float()
}
```

#### 3. 结果转换 (`main/wast.mbt`, `testsuite/compare.mbt`)

```moonbit
// 修改前：假设 f32 被提升为 f64
F32 => {
  let f64_val = v.reinterpret_as_double()
  @types.Value::F32(Float::from_double(f64_val))  // 错误！
}

// 修改后：直接从原始位重解释
F32 => @types.Value::F32(@jit.FromInt64::from_int64_bits(v))
```

#### 4. 测试代码更新

将所有 `call_with_context` 调用更新为类型安全的 `call_with_context_poly`：

```moonbit
// 修改前
let results = jm.call_with_context(f, args)
let f32_result = Float::from_double(results[0].reinterpret_as_double())

// 修改后
let @jit.Single((result : Float)) = jm.call_with_context_poly(f, args)
```

## 技术细节

### AArch64 寄存器布局

```
D0 (64-bit): |  高 32 位 (未使用)  |  S0 (低 32 位)  |
             |      0x00000000     |   f32 原始位    |
```

- S0-S31：32 位浮点寄存器
- D0-D31：64 位浮点寄存器
- S0 是 D0 的低 32 位

### 位模式示例

对于 f32 值 `10.0f`：
- f32 位模式：`0x41200000`
- 存储在 S0 后，D0 的值为：`0x0000000041200000`

如果错误地将 D0 作为 `double` 读取：
- `0x0000000041200000` 解释为 double ≈ `5.3e-315`（错误）

正确做法是提取低 32 位 `0x41200000`，然后 reinterpret 为 float = `10.0f`

## 修改的文件

1. `jit/ffi_jit.c` - FFI 层读取 D 寄存器为 uint64_t
2. `jit/polycall.mbt` - 新增 FromInt64 trait
3. `main/wast.mbt` - 修复 convert_jit_result 函数
4. `testsuite/compare.mbt` - 修复 jit_results_to_values 函数
5. `testsuite/f32_test.mbt` - 更新测试使用 call_with_context_poly
6. `testsuite/f32_br_table_test.mbt` - 更新测试
7. `testsuite/align_test.mbt` - 更新测试

## 测试结果

修复后：
- `moon test testsuite`: 117/117 通过
- `./wasmoon test testsuite/data/float_exprs.wast`: 819/819 通过
