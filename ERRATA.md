# Wasmoon 勘误与改进意见

本文档记录项目开发过程中的错误、改进建议和最佳实践。

---

## 2025-11-27

### MoonBit 编码规范

#### 1. 错误处理
- ❌ **错误做法**: 使用 Result 类型进行错误处理
- ✅ **正确做法**: 使用 `suberror` 定义错误类型，函数内使用 `raise` 抛出错误
- **参考**: `../sqlparser/src` 项目

#### 2. 忽略错误时的写法
- ❌ **错误做法**:
  ```moonbit
  try {
    let _result = func()
  } catch {
    _ => ()
  }
  ```
- ✅ **正确做法**:
  ```moonbit
  try! func() |> ignore
  ```

#### 3. 包引用
- 在同一个项目内的子包中引用主包时：
  - `moon.pkg.json` 中使用完整包名: `"Milky2018/wasmoon"`
  - `.mbt` 文件中使用简短引用: `@wasmoon.`

#### 4. 可见性控制
- ❌ **错误做法**: 同时将 struct 和其 fields 标记为 `pub`
- ✅ **正确做法**: 只将需要手动构造的类型标记为 `pub(all)`，fields 保持私有
  ```moonbit
  pub(all) struct Module {
    types : Array[FuncType]  // 不要 pub
    imports : Array[Import]   // 不要 pub
  }
  ```

#### 5. 变量可变性
- ❌ **错误做法**: 对于像 `Array` 这样本身有可变状态的对象使用 `let mut`
- ✅ **正确做法**: 只对变量绑定本身需要重新赋值时使用 `let mut`
  ```moonbit
  let array = [1, 2, 3]  // 正确，array 内容可变但绑定不变
  let mut counter = 0    // 正确，counter 需要重新赋值
  ```

#### 6. 函数调用时不需要结果
- ❌ **错误做法**: `let _result = func()`
- ✅ **正确做法**: `func() |> ignore`

#### 7. 循环的正确写法
- ❌ **错误做法**: 使用递归辅助函数 `fn go()`
  ```moonbit
  fn read_expr(self : Parser) -> Array[Instruction] {
    fn go(instructions : Array[Instruction]) -> Array[Instruction] {
      if condition { instructions }
      else { go(instructions.push(item)) }  // 递归调用
    }
    go([])
  }
  ```

- ✅ **正确做法**: 使用 MoonBit 的函数式 `loop`
  ```moonbit
  fn read_expr(self : Parser) -> Array[Instruction] {
    loop [] {
      instructions =>
        if condition {
          instructions  // 直接返回（自动跳出循环）
        } else {
          continue instructions.push(item)  // 继续循环
        }
    }
  }
  ```

- **Loop 语法规则**:
  1. `loop <初始值> { 模式 => 表达式 }`
  2. 不使用 `continue` 时，表达式的值就是循环返回值（自动跳出）
  3. 使用 `continue <新值>` 进入下一轮迭代
  4. 不需要 `break`

- **示例**：阶乘计算
  ```moonbit
  fn factorial(n : Int) -> Int {
    loop (n, 1) {
      (0, result) => result                      // 返回并跳出
      (i, result) => continue (i - 1, result * i)  // 继续
    }
  }
  ```

- **参考**: [MoonBit Course Lesson 7-2](https://raw.githubusercontent.com/moonbitlang/moonbit-course/a8ad174ef2b424d843f4fe96a913564d0fe15846/course7/lec7-2.mbt.md)

---

### WebAssembly 数值运算实现

#### 1. Int64 字面量
- 所有 Int64 字面量必须使用 `L` 后缀
  ```moonbit
  let a : Int64 = 0L           // 正确
  let b : Int64 = 1000000000L  // 正确
  if b == 0L { ... }           // 正确比较
  ```

#### 2. Int64 位运算
- ⚠️ **废弃的方法**: `lsl()`, `asr()`, `lsr()` 方法已废弃
- ✅ **正确做法**: 使用中缀运算符
  ```moonbit
  // 左移
  a.lsl(shift)  // ❌ 废弃
  a << shift    // ✅ 正确

  // 算术右移（有符号）
  a.asr(shift)  // ❌ 废弃
  a >> shift    // ✅ 正确

  // 逻辑右移（无符号）
  a.lsr(shift)  // ❌ 废弃
  // TODO: 需要正确的无符号右移实现
  ```

#### 3. 浮点运算方法
- Float 和 Double 类型支持的方法：
  ```moonbit
  // 数学运算
  f.abs()     // 绝对值
  f.sqrt()    // 平方根
  f.ceil()    // 向上取整
  f.floor()   // 向下取整
  -f          // 取负

  // 比较（使用标准运算符）
  a < b       // 小于
  a > b       // 大于
  a <= b      // 小于等于
  a >= b      // 大于等于
  a == b      // 等于
  a != b      // 不等于
  ```

#### 4. WebAssembly 比较运算返回值
- WebAssembly 中所有比较运算返回 **i32** 类型（0 或 1），而不是布尔值
  ```moonbit
  // i32/i64/f32/f64 比较都返回 i32
  I32Eq => {
    let b = self.stack.pop_i32()
    let a = self.stack.pop_i32()
    self.stack.push(I32(if a == b { 1 } else { 0 }))  // 返回 i32
  }

  I64LtS => {
    let b = self.stack.pop_i64()
    let a = self.stack.pop_i64()
    self.stack.push(I32(if a < b { 1 } else { 0 }))  // 返回 i32
  }
  ```

#### 5. 除零检查
- **必须**在除法和取余运算前检查除数是否为零
  ```moonbit
  I32DivS => {
    let b = self.stack.pop_i32()
    let a = self.stack.pop_i32()
    if b == 0 {                    // 必须检查
      raise DivisionByZero
    }
    self.stack.push(I32(a / b))
  }

  I64RemS => {
    let b = self.stack.pop_i64()
    let a = self.stack.pop_i64()
    if b == 0L {                   // i64 使用 0L
      raise DivisionByZero
    }
    self.stack.push(I64(a % b))
  }
  ```

#### 6. 无符号运算处理 ✅ 已实现
- MoonBit 的 Int/Int64 是有符号类型，需要通过类型重新解释来实现无符号运算
- **i32 无符号运算**：使用 `reinterpret_as_uint()` 和 `UInt::reinterpret_as_int`
  ```moonbit
  // 无符号除法
  I32DivU => {
    let b = self.stack.pop_i32()
    let a = self.stack.pop_i32()
    if b == 0 { raise DivisionByZero }
    let result = (a.reinterpret_as_uint() / b.reinterpret_as_uint()) |> UInt::reinterpret_as_int
    self.stack.push(I32(result))
  }

  // 无符号右移（注意括号！）
  I32ShrU => {
    let shift = b % 32
    let result = (a.reinterpret_as_uint() >> shift) |> UInt::reinterpret_as_int
    self.stack.push(I32(result))
  }
  ```

- **i64 无符号运算**：使用 `Int64::reinterpret_as_uint64()` 和 `UInt64::reinterpret_as_int64`
  ```moonbit
  // 无符号除法
  I64DivU => {
    if b == 0L { raise DivisionByZero }
    let result = (Int64::reinterpret_as_uint64(a) / Int64::reinterpret_as_uint64(b)) |> UInt64::reinterpret_as_int64
    self.stack.push(I64(result))
  }

  // 无符号右移
  I64ShrU => {
    let shift = b.to_int() % 64
    let result = (Int64::reinterpret_as_uint64(a) >> shift) |> UInt64::reinterpret_as_int64
    self.stack.push(I64(result))
  }
  ```

- ⚠️ **重要**：运算符优先级歧义
  - 必须用括号包裹算术/位运算，否则 `|>` 会产生歧义
  - ❌ 错误：`a / b |> UInt::reinterpret_as_int`
  - ✅ 正确：`(a / b) |> UInt::reinterpret_as_int`

#### 7. 位运算中的移位计数
- 移位运算需要对移位计数取模，防止溢出
  ```moonbit
  I32Shl => {
    let b = self.stack.pop_i32()
    let a = self.stack.pop_i32()
    self.stack.push(I32(a << (b % 32)))  // i32 取模 32
  }

  I64Shl => {
    let b = self.stack.pop_i64()
    let a = self.stack.pop_i64()
    self.stack.push(I64(a << (b.to_int() % 64)))  // i64 取模 64
  }
  ```

---

## 待补充

_请在此处继续添加新的意见和建议_
