# block.wast 测试修复记录

本文档记录了修复 `block.wast` 测试套件中 8 个失败用例的完整过程。

## 问题背景

运行 `./wasmoon test testsuite/data/block.wast --jit` 时，发现 8 个测试失败：

1. `select` 指令相关（2个）
2. `i32.ctz` 未实现（2个）
3. `call_indirect` 参数处理问题（2个）
4. `br`/`br_table` 后的不可达代码处理（2个）

## 修复过程

### 1. Select 指令实现

**问题**：`select` 指令的 IR->VCode lowering 不完整，没有正确使用 AArch64 的 CSEL 指令。

**修复**：
- 在 `vcode/lower.mbt` 中完善 `lower_select` 函数
- 在 `vcode/emit.mbt` 中添加 `emit_csel` 函数，生成正确的 AArch64 机器码
- CSEL 指令格式：`CSEL Rd, Rn, Rm, cond` - 根据条件选择 Rn 或 Rm

### 2. Clz/Ctz/Popcnt 位操作指令

**问题**：`i32.ctz`、`i32.clz`、`i32.popcnt` 等位计数指令未实现。

**修复**：

1. **IR 层**（`ir/ir.mbt`）：
   - 添加 `Clz`、`Ctz`、`Popcnt` 到 `Opcode` 枚举
   - 添加 builder 方法、验证和打印支持

2. **WASM->IR 翻译**（`ir/translator.mbt`）：
   ```moonbit
   I32Clz => self.translate_unary_i32(fn(b, a) { b.clz(a) })
   I32Ctz => self.translate_unary_i32(fn(b, a) { b.ctz(a) })
   I32Popcnt => self.translate_unary_i32(fn(b, a) { b.popcnt(a) })
   ```

3. **IR->VCode lowering**（`vcode/lower.mbt`）：
   - 添加 `Clz`、`Ctz`、`Popcnt` VCode 操作码
   - 使用 AArch64 的 CLZ、RBIT（用于 CTZ）指令

4. **机器码发射**（`vcode/emit.mbt`）：
   - `emit_clz`：CLZ 指令
   - `emit_rbit`：RBIT 指令（CTZ = CLZ(RBIT(x))）

### 3. call_indirect 表查找问题

**问题**：这是最复杂的 bug。JIT 使用 `func_table[func_idx]` 查找函数指针，但 `call_indirect` 需要使用 `table[table_idx]`。

**分析过程**：

1. 创建测试用例复现问题：
   ```wat
   (module
     ;; 19 个 dummy 函数
     (func) (func) ... (func)

     (func $func (param i32 i32) (result i32) (local.get 0))
     (type $check (func (param i32 i32) (result i32)))
     (table funcref (elem $func))  ;; table[0] = $func (func_idx=19)

     (func (export "test") (result i32)
       (call_indirect (type $check) (i32.const 1) (i32.const 2) (i32.const 0))
     )
   )
   ```

   问题：`$func` 是 func_19，但 `table[0]` 应该指向它。直接用 `func_table[0]` 会得到错误的函数。

2. 参考 wasmtime 的设计：
   - wasmtime 使用 `vmctx` 模式，table 是独立的运行时数据结构
   - `TableData` 包含 `base_gv`（表基址）和 `bound`（表大小）
   - `call_indirect` 通过 `prepare_table_addr` 计算 `base + index * element_size`

**修复方案**：

1. **C FFI 层**（`jit/ffi_jit.c`）：
   - 添加 `indirect_table` 到 `jit_context_t` 结构
   - 添加 `wasmoon_jit_ctx_alloc_indirect_table`、`wasmoon_jit_ctx_set_indirect` 等函数
   - **关键修复**：`indirect_table` 必须至少和 `func_table` 一样大，并预填充所有函数指针

   ```c
   // 分配至少 func_count 个条目，支持直接调用和间接调用
   int alloc_count = count > ctx->func_count ? count : ctx->func_count;
   ctx->indirect_table = (void **)calloc(alloc_count, sizeof(void *));

   // 预填充 func_table 内容，使直接调用正常工作
   for (int i = 0; i < ctx->func_count; i++) {
       ctx->indirect_table[i] = ctx->func_table[i];
   }
   ```

2. **MoonBit FFI 绑定**（`jit/ffi_jit.mbt`）：
   - 添加 `JITContext::alloc_indirect_table` 和 `set_indirect` 方法
   - `call_multi_return` 使用 `indirect_table_ptr`

3. **运行时初始化**（`main/wast.mbt` 和 `testsuite/compare.mbt`）：
   - 添加 `init_elem_segments` 函数，从 elem segments 初始化 indirect table
   - 在 JIT 模块加载后调用

4. **IR->VCode lowering**（`vcode/lower.mbt`）：
   - 修复 `lower_call_indirect` 的操作数顺序（callee 是第一个操作数，不是最后一个）

### 4. br_table 后的不可达代码

**问题**：`br_table` 后的代码应该标记为不可达，但 `is_unreachable` 标志没有被设置。

**修复**（`ir/translator.mbt`）：
```moonbit
fn Translator::translate_br_table(...) -> Unit {
  // ... br_table 翻译代码 ...

  // br_table 是终结器，之后的代码不可达
  self.is_unreachable = true  // 添加这行
}
```

## 技术要点

### AArch64 JIT 调用约定

```
X0 = func_table_ptr (保存到 X20)
X1 = memory_base (保存到 X21)
X2 = memory_size (保存到 X22)
X3-X6 = 函数参数
```

### indirect_table vs func_table

| 表类型 | 索引方式 | 用途 |
|--------|----------|------|
| `func_table` | `func_idx` | 直接函数调用 `call` |
| `indirect_table` | `table_idx` | 间接调用 `call_indirect` |

**关键洞察**：由于 X20 只能指向一个表，我们让 `indirect_table` 同时支持两种索引方式：
- 对于 `func_idx < func_count`：存储函数指针（支持直接调用）
- 对于 elem segments 指定的 `table_idx`：覆盖为对应的函数指针

### elem segments 处理

WASM elem segments 格式：
```wat
(table funcref (elem $func1 $func2))
;; 等价于: table[0] = $func1, table[1] = $func2
```

初始化代码：
```moonbit
for elem in mod_.elems {
  if elem.mode is Active(_table_idx, offset_expr) {
    let offset = match offset_expr {
      [I32Const(n)] => n
      _ => 0
    }
    for i, init_expr in elem.init {
      let func_idx = match init_expr {
        [RefFunc(idx)] => idx
        _ => continue
      }
      elem_init.push((offset + i, func_idx))
    }
  }
}
jm.init_indirect_table(table_size, elem_init)
```

## 测试结果

修复前：`Passed: 214, Failed: 8`
修复后：`Passed: 222, Failed: 0`

## 新增测试文件

- `testsuite/call_indirect_test.mbt`：4 个 call_indirect 测试用例
- `testsuite/br_test.mbt`：新增 `break_bare` 和 `as_call_value` 测试

## 经验总结

1. **分层调试**：从高层（WAST 测试）到底层（机器码）逐步定位问题
2. **参考成熟实现**：wasmtime 的设计提供了很好的参考
3. **创建最小复现用例**：将失败的 WAST 测试简化为独立的单元测试
4. **理解 WASM 语义**：`call` vs `call_indirect` 的区别是本次调试的核心
