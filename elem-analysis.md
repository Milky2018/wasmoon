# elem.wast 分析报告

## 问题总结

elem.wast 在 JIT 模式下有 19 个失败，解释器模式下全部通过（72 个测试）。

### 根本原因

**主要问题**：JIT 编译器在初始化元素段时，只处理简单的 `i32.const` 偏移量，对于使用常量表达式（如 `i32.add`, `i32.sub`, `i32.mul`）计算的偏移量，错误地使用 0 作为默认值。

**受影响文件**：
- `main/wast.mbt:351-354`
- `testsuite/compare.mbt:381-384`

**错误代码**：
```moonbit
let offset = match offset_expr {
  [I32Const(n)] => n
  _ => 0  // BUG: 常量表达式被忽略
}
```

## 修复方案

### 1. 添加常量表达式求值函数

在 `main/wast.mbt` 和 `testsuite/compare.mbt` 中添加了 `eval_elem_offset_expr` 函数：

```moonbit
fn eval_elem_offset_expr(instrs : Array[@types.Instruction]) -> Int {
  let stack : Array[Int] = []
  for instr in instrs {
    match instr {
      I32Const(n) => stack.push(n)
      I32Add =>
        if stack.length() >= 2 {
          let b = stack.pop()
          let a = stack.pop()
          stack.push(a.unwrap() + b.unwrap())
        }
      I32Sub =>
        if stack.length() >= 2 {
          let b = stack.pop()
          let a = stack.pop()
          stack.push(a.unwrap() - b.unwrap())
        }
      I32Mul =>
        if stack.length() >= 2 {
          let b = stack.pop()
          let a = stack.pop()
          stack.push(a.unwrap() * b.unwrap())
        }
      _ => ()
    }
  }
  if stack.length() > 0 {
    stack[stack.length() - 1]
  } else {
    0
  }
}
```

### 2. 修改元素段初始化

替换简单的 match 表达式：
```moonbit
let offset = eval_elem_offset_expr(offset_expr)
```

## 修复效果

- **修复前**：19 个失败（解释器 0 个失败）
- **修复后**：12 个失败（解释器 0 个失败）
- **解决的问题**：
  - 常量表达式偏移量（i32.add, i32.sub, i32.mul）现在正确计算
  - "uninitialized element" 陷阱检测现在正常工作（4 个测试从失败变为通过）

## 剩余问题

修复后还有 12 个失败，属于以下几类独立问题：

### 1. table.init 指令的边界检查 (2 个失败)
- **Lines**: 706, 716
- **问题**：使用已被隐式丢弃的元素段进行 table.init 应该触发 "out of bounds table access"
- **原因**：Active 元素段在模块实例化后被隐式丢弃，但 table.init 没有正确检测

### 2. 多模块共享表 (7 个失败)
- **Lines**: 921, 959, 960, 972, 973, 974, 1109
- **问题**：多个模块共享同一个表，后续模块添加的元素对前面的模块不可见
- **原因**：JIT 为每个模块创建独立的间接表，没有正确处理导入的表

### 3. externref 元素初始化 (2 个失败)
- **Lines**: 1016, 1029
- **问题**：元素段初始化覆盖了已有的 externref 值
- **原因**：元素段初始化时没有正确处理 ref.null extern

### 4. 全局变量引用 (1 个失败)
- **Line**: 1053
- **问题**：元素段使用导入的全局变量作为初始化表达式
- **原因**：eval_elem_offset_expr 不支持 GlobalGet 指令

## 验证

```bash
# 解释器模式 - 全部通过
./wasmoon test --no-jit testsuite/data/elem.wast
# Results: Passed: 72, Failed: 0

# JIT 模式 - 修复前
./wasmoon test testsuite/data/elem.wast
# Results: Passed: 53, Failed: 19

# JIT 模式 - 修复后
./wasmoon test testsuite/data/elem.wast
# Results: Passed: 60, Failed: 12
```

## 建议后续工作

1. **table.init 边界检查**：在 executor 中正确实现元素段的丢弃状态追踪
2. **多模块表共享**：重构 JIT 表管理，支持跨模块共享表实例
3. **externref 处理**：修复元素段初始化时的引用类型处理
4. **全局变量支持**：在 eval_elem_offset_expr 中添加 GlobalGet 支持（需要运行时上下文）
