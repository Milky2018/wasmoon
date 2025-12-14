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

#### 6. 忽略函数返回值
- ❌ **错误做法**: 使用 `let _ =` 模式
  ```moonbit
  let _ = func()
  let _ = array.pop()
  let _ = store.alloc_table(table)
  ```
- ✅ **正确做法**: 使用 `|> ignore` 管道
  ```moonbit
  func() |> ignore
  array.pop() |> ignore
  store.alloc_table(table) |> ignore
  ```
- ⚠️ **带 catch 块时需要括号**:
  ```moonbit
  // ❌ 错误（语法错误）
  func() catch { _ => () } |> ignore

  // ✅ 正确
  (func() catch { _ => () }) |> ignore
  ```

#### 7. 布尔取反
- ❌ **错误做法**: 使用 `not()` 函数
  ```moonbit
  if not(condition) { ... }
  ```
- ✅ **正确做法**: 使用 `!` 一元运算符
  ```moonbit
  if !(condition) { ... }
  if !flag { ... }
  ```

#### 8. 函数调用语法（无感叹号）
- ❌ **错误做法**: 使用 `!` 后缀调用可能抛出错误的函数
  ```moonbit
  inspect!(value, content="expected")
  func!()
  ```
- ✅ **正确做法**: 直接调用，不需要 `!`
  ```moonbit
  inspect(value, content="expected")
  func()
  ```
- **说明**: `f!(..)` 语法已废弃，MoonBit 现在自动处理错误传播
- ⚠️ **重要**: 当 `moon check` 出现 warning 时，不要完全忽视。除非你明确知道该 warning 可以安全忽略（如某些变量/类型暂时未使用），否则应该修复它们。特别是语法废弃警告，必须修复。

#### 9. 循环的正确写法
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
          instructions.push(item)      // push 返回 Unit
          continue instructions         // 继续循环
        }
    }
  }
  ```

- ⚠️ **重要**: `Array::push()` 返回 `Unit`，不能直接用于 `continue`
  ```moonbit
  // ❌ 错误
  continue instructions.push(item)

  // ✅ 正确
  instructions.push(item)
  continue instructions
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

  // 逻辑右移（无符号）- 见第6条"无符号运算处理"
  a.lsr(shift)  // ❌ 废弃
  // 使用 reinterpret_as_uint 后再右移
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

### MoonBit 命令行工具

#### 10. `moon run` 传递参数
- 使用 `--` 分隔 moon 命令和程序参数
  ```bash
  moon run cmd/main -- demo      # 传递 "demo" 参数给程序
  moon run cmd/main -- --help    # 传递 "--help" 参数给程序
  ```
- **说明**: `--` 之前的参数由 moon 处理，之后的参数传递给程序

---

## 2025-11-28

### MoonBit 类型转换最佳实践

#### 1. 优先使用直接转换方法
- ❌ **错误做法**: 使用连续的类型转换链
  ```moonbit
  a.to_double().to_uint64().to_uint()  // 冗余
  a.reinterpret_as_uint().to_int64()   // 冗余
  ```
- ✅ **正确做法**: 查找并使用直接转换方法
  ```moonbit
  a.to_double().to_uint()              // Double 有 to_uint()
  a.to_uint64()                        // Int 有 to_uint64()
  ```

#### 2. 常用类型转换方法速查
- **Int**: `to_float()`, `to_double()`, `to_int64()`, `to_uint()`, `to_uint64()`, `reinterpret_as_uint()`, `reinterpret_as_float()`
- **Int64**: `to_int()`, `to_float()`, `to_double()`, `to_uint64()`, `reinterpret_as_uint64()`, `reinterpret_as_double()`
- **UInt**: `to_int()`, `to_float()`, `to_double()`, `to_uint64()`, `reinterpret_as_int()`, `reinterpret_as_float()`
- **UInt64**: `to_int()`, `to_int64()`, `to_float()`, `to_double()`, `to_uint()`, `reinterpret_as_int64()`, `reinterpret_as_double()`
- **Float**: `to_int()`, `to_double()`, `reinterpret_as_int()`, `reinterpret_as_uint()`
- **Double**: `to_int()`, `to_int64()`, `to_uint()`, `to_uint64()`, `to_float()`, `reinterpret_as_int64()`, `reinterpret_as_uint64()`

#### 3. reinterpret vs 数值转换
- **reinterpret**: 保持位模式不变，只改变类型解释
  ```moonbit
  let f : Float = 1.0
  f.reinterpret_as_int()  // = 1065353216 (IEEE 754 位模式)
  ```
- **数值转换**: 转换数值，可能改变位模式
  ```moonbit
  let f : Float = 1.0
  f.to_int()  // = 1 (数值截断)
  ```

#### 4. Git Commit Message 规范
- ❌ **错误做法**: 使用中文编写 commit message
- ✅ **正确做法**: 所有 commit message 使用英文
  ```
  feat: implement numeric conversion instructions
  fix: correct overflow handling in trunc_sat
  refactor: split runtime into separate modules
  ```

#### 5. Git 分支工作流
- ❌ **错误做法**: 直接在 master/main 分支上开发
- ✅ **正确做法**: 每次改动或添加功能都开新分支
  ```bash
  git checkout -b feat/memory-operations   # 新功能
  git checkout -b fix/trunc-overflow       # 修复 bug
  git checkout -b refactor/parser-cleanup  # 重构
  ```
- 完成后通过 PR 合并到主分支

#### 10. 循环语法优化
- ❌ **错误做法**: 使用传统 C 风格 for 循环
  ```moonbit
  for i = 0; i < n; i = i + 1 {
    arr.push(items[i])
  }
  ```
- ✅ **正确做法**: 使用 `for-in` 循环
  ```moonbit
  // 遍历集合
  for item in items {
    arr.push(item)
  }

  // 需要索引时
  for i in 0..<n {
    process(i)
  }

  // 不需要索引时
  for _ in 0..<n {
    arr.push(default_value)
  }
  ```

#### 11. 测试专用依赖
- ❌ **错误做法**: 在 `import` 中添加仅测试需要的依赖
  ```json
  {
    "import": [
      "Milky2018/wasmoon/types",
      "Milky2018/wasmoon/executor"
    ]
  }
  ```
- ✅ **正确做法**: 使用 `test-import` 声明测试专用依赖
  ```json
  {
    "test-import": [
      "Milky2018/wasmoon/types",
      "Milky2018/wasmoon/executor"
    ]
  }
  ```
- **说明**: `test-import` 中的依赖仅在测试时可用，不会影响正式构建

#### 12. 库选择
- **文件系统操作**:
  - ⚠️ **重要**: 不要混用阻塞 API 和异步 API
  - **同步文件操作**: 使用 `moonbitlang/x/fs`
    ```json
    {
      "import": [
        "moonbitlang/x/fs"
      ]
    }
    ```
    ```moonbit
    let content = @fs.read_file_to_string(path)
    @fs.write_string_to_file(path, content)
    let bytes = @fs.read_file_to_bytes(path)
    @fs.write_bytes_to_file(path, bytes)
    ```
  - **异步文件操作**: 使用 `moonbitlang/async/fs`（仅当整个程序使用 async 时）
  - ❌ **错误做法**: 在非 async 函数中调用 async/fs 的 API

- **JSON 解析**:
  - ❌ **错误做法**: 使用 `moonbitlang/x/json`
  - ✅ **正确做法**: 使用标准库的 `@json`（内置，无需额外导入）
  ```moonbit
  // 直接使用标准库
  let parsed : Json = @json.parse(json_string)
  ```

#### 13. derive(FromJson) 字段重命名
- 当 JSON 字段名与 MoonBit 保留字冲突时（如 `type`、`as`、`module`），需要重命名
- ✅ **正确做法**: 使用 `FromJson(fields(...))` 语法
  ```moonbit
  priv struct JsonCommand {
    type_ : String     // 对应 JSON 中的 "type"
    as_ : String?      // 对应 JSON 中的 "as"
    module_ : String?  // 对应 JSON 中的 "module"
  } derive(FromJson(fields(type_(rename="type"), as_(rename="as"), module_(rename="module"))))
  ```
- ❌ **错误做法**: 尝试分开写 `FromJson` 和 `fields`
  ```moonbit
  // 这是错误的！
  } derive(FromJson, fields(type_(rename="type")))
  ```
- **说明**: `fields()` 必须放在 `FromJson()` 的括号内

#### 14. 使用 `if-is` 替代含 `None => ()` 或 `_ => ()` 的 match
- ❌ **错误做法**: 使用 match 然后用 `_ => ()` 或 `None => ()` 忽略另一个分支
  ```moonbit
  match optional_value {
    Some(value) => do_something(value)
    None => ()
  }

  match enum_value {
    SomeVariant(data) => process(data)
    _ => ()
  }
  ```
- ✅ **正确做法**: 使用 `if x is Pattern` 语法
  ```moonbit
  if optional_value is Some(value) {
    do_something(value)
  }

  if enum_value is SomeVariant(data) {
    process(data)
  }
  ```
- ⚠️ **注意**: 多模式匹配时需要加括号
  ```moonbit
  if char is (Some('-') | Some('+')) {
    // 处理符号
  }
  ```
- **说明**: `if-is` 语法更简洁，避免了无意义的空分支

#### 15. 测试中检查错误的写法
- ❌ **错误做法**: 使用复杂的 try-catch 模式检查是否抛出错误
  ```moonbit
  let result = try {
    f() |> ignore
    false // Should not reach here
  } catch {
    SomeErr => true // Expected
    _ => false
  }
  inspect(result, content="true")
  ```
- ✅ **正确做法**: 使用 `try?` 配合 `inspect`
  ```moonbit
  inspect(try? f(), content="Err(SomeErr)")
  ```
- **说明**: `try?` 将结果转换为 `Result` 类型，可直接用 `inspect` 检查错误类型

---

## 2025-11-30

### Git 操作规范

#### 1. 不要使用 `git push -f` (force push)
- ❌ **错误做法**: 使用 `git commit --amend` 修改已推送的 commit，然后 `git push -f`
  ```bash
  git commit --amend --no-edit
  git push -f  # 强制推送，覆盖远程历史
  ```
- ✅ **正确做法**: 创建新的 commit 来修复问题
  ```bash
  git add -A
  git commit -m "fix: mark internal types as priv in wat module"
  git push
  ```
- **原因**:
  1. 如果有人已经基于该分支工作，force push 会导致他们的历史混乱
  2. 丢失了 commit 历史，难以追溯修改过程
  3. 在 PR review 中无法清楚看到每次修改的内容
- **例外**: 只有在 commit 尚未推送到远程时，才可以使用 `--amend`

### MoonBit 可见性控制

#### 2. 外部包需要访问 enum 变体时使用 `pub(all) enum`
- ❌ **错误做法**: 使用 `pub enum` 然后写工厂函数绕过访问限制
  ```moonbit
  pub enum Type {
    I32
    I64
    F32
    F64
  }

  // 不必要的工厂函数
  pub fn Type::i32_() -> Type { Type::I32 }
  pub fn Type::i64_() -> Type { Type::I64 }
  pub fn Type::f32_() -> Type { Type::F32 }
  pub fn Type::f64_() -> Type { Type::F64 }
  ```
- ✅ **正确做法**: 直接使用 `pub(all) enum`
  ```moonbit
  pub(all) enum Type {
    I32
    I64
    F32
    F64
  }
  ```
- **说明**:
  - `pub enum` 的变体在外部包中是只读的，外部包不能直接使用 `@pkg.Type::I32`
  - `pub(all) enum` 允许外部包直接构造和使用变体
  - 工厂函数是不必要的 workaround，会污染 API

---

## 待补充

_请在此处继续添加新的意见和建议_

- [x] 代码中的TODO仍然没有处理啊（f32/f64 IEEE 754 解析） → 已实现
- [x] 为 parser 写至少5个测试，就写在 parser.mbt 文件内部 → 已添加6个测试
- [x] 不要用 not 函数，用一元操作符 `!` → 已添加到第7条
- [x] 函数调用不要用 `!` 后缀 → 已添加到第8条
- [x] 更新 README.md 中的内容（85行） → 已完成
- [x] 完善 `cmd/main`，引入 `moonbitlang/x/sys`，使用 `@sys.get_cli_args()` 获取命令行参数；使用 `moon add TheWaWaR/clap@0.2.6` 引入 clap → 已完成
- [x] 把 README.mbt.md 中的代码块改成正确的 MoonBit 代码，使用 test block 包裹 → 已完成
- [x] 能使用 `for-in` 循环时，不要使用 `for i = 0; i < n; i++` → 已添加到第10条
- [x] 忽略结果的语法，不要使用 `let _ = expr`，而要使用 `ignore(expr)` 或者最好是 `expr |> ignore` → 已更新第6条并修复所有代码
- [x] 所有 match 中出现类似 `_ => ()` 或者 `None => ()` 之类的分支，替换为 `if x is Some(subpattern)` 或者 `guard x is Some(subpattern) else { xxx }` (else 块可省略，相当于 panic) → 已添加到第14条并修复所有代码
- [x] 目前为止，vcode 模块的测试全都是白盒测试，请给出理由，否则修改部分为黑盒测试 → vcode 是编译器内部组件，无公开 API，白盒测试合理
- [x] bench 内容现在非常贫瘠，需要丰富 → 已实现：10 大类基准测试覆盖解释器、JIT、IR、优化、VCode、寄存器分配、代码生成、运行时等
- [x] vcode/aarch64_patterns.mbt 中有非常多的 never constructed variant. 这是怎么导致的？以后会用到吗？还是永远不会用到？ → **设计决策**：当前采用统一 VCode 方案，AArch64 特定 opcode（Madd、AddShifted 等）直接放入 `VCodeOpcode` 枚举。`aarch64_patterns.mbt` 中的 `AArch64Opcode` 是早期设计残留，应当删除。理想架构是分层设计（VCode 目标无关 → AArch64Inst 目标特定），但考虑到项目只针对 AArch64 单一目标，统一方案更务实。如未来需支持多目标，再重构为分层架构
- [x] 现在缺乏很多黑盒测试 → 已为 types、runtime、cwasm 模块添加黑盒测试（35 个新测试）
- [x] main.mbt 现在太大了，适当进行拆分 → 已拆分为：demo.mbt, wast.mbt, settings.mbt, config.mbt, html_report.mbt
- [x] 我完全不理解 `{ "path": "Milky2018/wasmoon/cwasm", "alias": "cwasm" }` 这是在做什么 → 当路径最后一段与 alias 相同时，alias 是多余的。当前项目已移除所有不必要的 alias
- [x] completion 和项目主要功能无关，可以先删掉 → 已删除 completion.mbt
- [x] 有非常多如下形式的测试：应使用 `inspect(try? f(), content="Err(...)")` → 已修复所有测试文件（cwasm_wbtest.mbt, i32_wbtest.mbt, i64_wbtest.mbt, executor_wbtest.mbt, validator_wbtest.mbt）
- [x] 把所有的 `inspect(true, content="true")` 清除掉，这没有任何意义 → 已修复：wast_wbtest.mbt 使用 guard-is 替代，types.mbt 改为验证实际值
- [x] 不要混用阻塞 API 和异步 API，把 main 中所有的 moonbitlang/async/fs 换用为 moonbitlang/x/fs → 已完成：main 包已改用同步 API，移除了所有 async fn
- [x] 代码中仍然有非常多的 `for <identifier> = <initial>; ` 这样的 c 风格循环 → 已修复所有正向迭代的 C 风格循环（保留反向迭代 `i = i - 1` 因为更简洁）
- [x] JIT太奇怪了，干的完全是AOT的活儿，怎么处理更合适？ → **调研结论**：Wasmtime/Wasmer 的"JIT"也是在加载时编译所有函数，不是传统的热点 JIT。Wasmtime 虽有 Winch（快速编译）和 Cranelift（优化编译）两层，但目前不支持自动分层——模块全部用一种编译器。wasmoon 当前实现与业界一致，保留"JIT"命名，在文档中说明是"预编译 JIT"（eager JIT）而非热点 JIT。参考：[Cranelift Progress 2022](https://bytecodealliance.org/articles/cranelift-progress-2022)
- [x] LEB128 的 parsing 缺乏相关测试 → 已添加 9 个 LEB128 验证测试，覆盖 u32/i32/i64 的边界情况和错误检测
- [x] 把 cwasm 后缀纳入 gitignore，并清除已经被 git 跟踪的 cwasm 文件 → 已将 `*.cwasm` 添加到 .gitignore，并用 `git rm --cached` 移除了 5 个已跟踪的 cwasm 文件
- [x] CLI 的诸多命令描述有误，比如现在的 test 命令和 wast 命令实际上是一回事，而且都和 json 无关。`debug` 等参数应该有 choices 参数。在 `.mooncakes/TheWaWaR/clap/src/clap.mbti` 中查看 named 函数的声明。 → 已修复：更新 test 命令描述为 "Run WebAssembly test script (.wast format)"，为 debug 和 config action 参数添加 choices
- [x] Sign/Zero Extension Instructions、br、adr 也需要添加到 "all emit functions disasm" 中
- [ ] `pub fn` 过多了
- [ ] disasm 命令可以删了
- [ ] call_indirect 在 vcode 的 dump 中会打印很长一个东西，比如 `f9 = call_indirect(8) -> 1 results v8, f0, f1, f2, f3, f4, f5, f6, f7`