# Wasmoon Roadmap

WebAssembly Runtime in MoonBit - 开发路线图

## 项目概述

Wasmoon 是一个用 MoonBit 编写的 WebAssembly 运行时，目标是实现一个完整的 WASM 解释器和 JIT 编译器，支持 WebAssembly 规范的核心特性，并最终实现类似 Cranelift 的代码生成器。

## Phase 1: MVP ✅ 已完成

### 1.1 核心数据结构 ✅
- [x] 值类型定义 (I32, I64, F32, F64, FuncRef, ExternRef)
- [x] 指令集枚举 (190+ 指令变体)
- [x] 模块结构 (Module, FuncType, Export, Import 等)

### 1.2 二进制格式解析器 ✅
- [x] 魔数和版本验证
- [x] LEB128 编码解码
- [x] 11 种 Section 解析
- [x] IEEE 754 浮点数解码 (f32/f64)

### 1.3 运行时数据结构 ✅
- [x] 操作数栈 (Stack)
- [x] 线性内存 (Memory)
- [x] 函数引用表 (Table)
- [x] 全局变量 (GlobalInstance)
- [x] 调用帧 (Frame)
- [x] 全局存储 (Store)
- [x] 模块实例 (ModuleInstance)

### 1.4 基础执行引擎 ✅
- [x] i32 算术/比较/位运算
- [x] 常量指令
- [x] 局部变量操作
- [x] 基本控制流

---

## Phase 2: 核心功能扩展 ✅ 已完成

### 2.1 完整的数值运算 ✅
- [x] i64 算术/比较/位运算
- [x] f32/f64 浮点运算
- [x] 数值转换指令 (wrap, extend, trunc, convert, reinterpret)
- [x] 饱和转换指令 (trunc_sat)

### 2.2 内存操作 ✅
- [x] 完整的 load/store 指令族
- [x] 扩展的 load 指令 (load8_s, load8_u, load16_s, load16_u, load32_s, load32_u)
- [x] memory.size 和 memory.grow

### 2.3 控制流 ✅
- [x] 结构化控制流 (block, loop, if-else)
- [x] 分支指令 (br, br_if, br_table)
- [x] select 指令

### 2.4 函数调用 ✅
- [x] 直接函数调用 (call)
- [x] 间接函数调用 (call_indirect)

---

## Phase 3: 完整的 WASM 1.0 支持 ✅ 已完成

### 3.1 全局变量 ✅
- [x] global.get / global.set
- [x] 全局变量初始化表达式

### 3.2 导入导出 ✅
- [x] 函数导入/导出
- [x] 主机函数接口 (Host Functions)
- [x] 内存导入/导出
- [x] 表导入/导出
- [x] 全局变量导入/导出

### 3.3 表操作 ✅
- [x] table.get / table.set
- [x] table.size / table.grow
- [x] table.fill / table.copy

### 3.4 模块初始化 ✅
- [x] Start function 执行
- [x] 数据段初始化 (data segment)
- [x] 元素段初始化 (element segment)

### 3.5 批量内存操作 ✅
- [x] memory.init / memory.copy / memory.fill
- [x] data.drop / elem.drop

### 3.6 引用类型 ✅
- [x] ref.null / ref.is_null / ref.func

### 3.7 多返回值 ✅
- [x] 函数多返回值支持
- [x] block/if 多返回值支持

---

## Phase 4: 模块验证与链接 ✅ 已完成

### 4.1 模块验证器 ✅
- [x] 类型检查
- [x] 栈高度验证
- [x] 控制流验证
- [x] 内存限制验证
- [x] 多内存/多表检查 (MVP 限制)

### 4.2 多模块支持 ✅
- [x] 模块链接
- [x] 符号解析

---

## Phase 5: 工具与测试 ✅ 已完成

### 5.1 规范兼容性 ✅
- [x] 官方测试套件基础设施 (wasm-testsuite)
- [x] 自动化测试运行器 (解析 JSON 测试规范，自动执行测试)
  - 用法: `moon run cmd/main -- test testsuite/data/i32.json`
- [x] 完整通过官方测试套件 (5955 tests passed, 0 failed)

### 5.2 工具链
- [x] WASM 反汇编器
- [x] WAT 文本格式支持
  - [x] 基本 WAT 解析 (flat form)
  - [x] WAT folded form 语法支持 (then/else keywords in if expressions)
  - [ ] **Import 内联函数签名** - 当前不支持 `(import ... (func (param ...) (result ...)))` 语法，必须使用 `(type $t)` 引用预定义类型

### 5.3 命令行工具 (对齐 wasmtime CLI)

> 参考 `wasmtime --help` 实现完整的命令行接口

#### 核心命令
- [x] `run` - 运行 WebAssembly 模块
  - [x] 直接运行 `.wasm` 文件
  - [x] `--invoke <FUNCTION>` 指定入口函数
  - [x] 传递命令行参数给 WASM 模块 (`--arg`)
  - [x] `--preload <NAME=MODULE>` 预加载模块
- [x] `compile` - 预编译 WebAssembly 模块 (AOT)
  - [x] 输出 `.cwasm` 预编译格式
  - [x] `-o, --output <PATH>` 指定输出路径
  - [x] `--emit-ir <PATH>` 输出 IR
- [x] `wast` - 运行 WebAssembly 测试脚本
  - [x] 支持 `.wast` 格式测试文件
  - [x] 可替代当前的 JSON 测试格式

#### 现有命令 (已实现)
- [x] `test` - 运行 JSON 格式测试 (当前实现)
- [x] `disasm` - 反汇编 WASM 文件
- [x] `wat` - 解析 WAT 文件
- [x] `demo` - 运行内置示例

#### 检查与探索命令
- [x] `explore` - 探索 WASM 编译过程
  - [x] 显示编译各阶段输出 (WASM → IR → VCode → 寄存器分配)
  - [x] 输出 HTML 报告 (`--html <PATH>`)
- [x] `objdump` - 检查预编译的 `.cwasm` 文件
  - [x] 显示元数据
  - [x] 显示段信息

#### 配置与调试选项
- [x] `-O, --optimize` 优化选项
  - [x] 优化级别 (0-3)
  - [x] 特定优化开关 (`--opt KEY=VALUE`)
- [x] `-D, --debug <KEY=VAL>` 调试选项
  - [x] 详细日志输出 (`-D verbose`)
  - [x] IR 打印 (`-D print-ir`, `-D print-vcode`, `-D print-regalloc`)
- [x] `-W, --wasm <KEY=VAL>` WASM 语义选项
  - [x] 启用/禁用特定提案 (`multi-value`, `bulk-memory`, `simd`, `tail-call`)
  - [x] 内存限制配置 (`max-memory`, `max-table`, `max-call-depth`)

#### WASI 支持 (参见 Phase 12)
- [ ] CLI 选项 (`--dir`, `--env`, `-S`) - 依赖 Phase 12 WASI 核心实现

#### 辅助命令
- [x] `config` - 配置管理
  - [x] `config show` - 显示配置
  - [x] `config path` - 显示配置文件路径
  - [x] `config init` - 初始化配置
- [x] `settings` - 显示可用的编译器设置

#### 错误报告改进
- [ ] **友好的错误信息** - 当前错误仅显示 `Error::to_string()`，缺乏上下文
  - [ ] WAT 解析错误应显示行号、列号和相关代码片段
  - [ ] WASM 验证错误应指明具体位置 (函数索引、指令偏移)
  - [ ] 运行时错误应包含调用栈信息

---

## Phase 6: 中间表示层 (IR) ✅ 已完成

> 这是实现 JIT 编译器的基础，参考 [Cranelift](https://cranelift.dev/) 的设计

### 6.1 高级 IR (类似 CLIF)
- [x] SSA (Static Single Assignment) 形式的 IR 定义
- [x] 基本块 (Basic Block) 数据结构
- [x] 控制流图 (CFG) 构建
- [x] IR 类型系统 (与 WASM 类型对应)
- [x] IR 指令集定义
  - [x] 算术运算指令
  - [x] 内存访问指令
  - [x] 控制流指令
  - [x] 函数调用指令
- [x] IR Builder API (类似 Cranelift FunctionBuilder)
- [x] IR 文本格式打印器

### 6.2 WASM 到 IR 的转换
- [x] WASM 指令到 IR 指令的映射
- [x] 栈机模型到寄存器模型的转换
- [x] 控制流重建 (block/loop/if 到 CFG)
- [x] 局部变量和参数处理

### 6.3 IR 验证
- [x] SSA 属性验证
- [x] 类型一致性检查
- [x] 控制流完整性验证

---

## Phase 7: IR 优化 🔨 进行中

> 在高级 IR 上进行目标无关的优化

### 7.1 基础优化
- [x] 死代码消除 (Dead Code Elimination)
- [x] 常量折叠 (Constant Folding)
- [x] 常量传播 (Constant Propagation)
- [x] 复制传播 (Copy Propagation)
- [x] 公共子表达式消除 (CSE)

### 7.2 控制流优化
- [x] 分支简化
- [x] 不可达代码消除
- [x] 基本块合并
- [x] 跳转线程化 (Jump Threading)

### 7.3 循环优化
- [x] 循环不变代码外提 (LICM)
- [x] 循环展开 (Loop Unrolling)
- [x] 强度削减 (Strength Reduction)

### 7.4 高级优化 (可选)
- [ ] E-graph 统一优化框架 (参考 Cranelift 的创新设计)
- [ ] 内联 (Inlining)
- [ ] 尾调用优化

---

## Phase 8: 低级 IR 与指令选择 🔨 进行中

> 类似 Cranelift 的 VCode，目标相关的低级表示

### 8.1 低级 IR (VCode) 设计 ✅
- [x] 虚拟寄存器表示
- [x] 目标相关的指令格式
- [x] 非 SSA 形式 (允许重定义)
- [x] 寄存器约束表示
  - [x] 基本寄存器类型 (Int/Float)
  - [ ] 操作数约束系统 (`OperandKind::Use/Def/UseDef`, `OperandConstraint::Any/Fixed/Reuse` 已定义但未使用)

### 8.2 指令选择 (Lowering) ✅
- [x] 高级 IR 到低级 IR 的转换框架
- [x] 模式匹配规则定义 (类似 ISLE DSL)
- [x] 指令合并与优化
- [x] 目标特定的指令选择规则

### 8.3 目标架构抽象 ✅
- [x] 目标架构接口 (TargetISA trait)
- [x] 寄存器描述
- [x] 调用约定 (Calling Convention)
  - [x] 默认调用约定实现
  - [ ] 多调用约定支持 (`SystemV`, `Aapcs64`, `WindowsFastcall`, `Wasm` 已定义但未使用)
- [x] 指令编码规则

---

## Phase 9: 寄存器分配 ✅ 已完成

> 将虚拟寄存器映射到物理寄存器

### 9.1 活跃性分析 ✅
- [x] 活跃区间 (Live Interval) 计算
- [x] 使用-定义链 (Use-Def Chain)

### 9.2 寄存器分配算法 ✅
- [x] 线性扫描分配器 (Linear Scan)
- [x] 溢出处理 (Spilling)
- [x] 重新加载 (Reloading)
- [ ] 寄存器合并 (Coalescing)

### 9.3 栈布局 ✅
- [x] 栈帧布局计算
- [x] 溢出槽分配
  - [x] 基本溢出槽类型 (`Spill`, `Arg`)
  - [ ] 完整栈槽类型 (`ReturnAddress` 已定义但未使用)
- [x] 调用者/被调用者保存寄存器处理
  - [x] 基本序言/尾声生成
  - [ ] 完整序言操作 (`AdjustSP`, `PushReg`, `PopReg` 已定义但未使用)

---

## Phase 10: 代码生成 💻

> 生成目标平台的机器代码

### 10.1 x86-64 后端（低优先）
- [ ] 指令编码
- [ ] 寻址模式
- [ ] 条件码处理
- [ ] 浮点指令 (SSE/AVX)

### 10.2 AArch64 后端 ✅
- [x] 指令编码
  - [x] 64位整数运算 (ADD, SUB, MUL, SDIV, UDIV)
  - [x] 64位浮点运算 (FADD, FSUB, FMUL, FDIV)
  - [x] 64位/32位内存操作 (LDR, STR)
  - [ ] 8位/16位内存操作 (`MemType::I8/I16` 已定义但未使用)
- [x] 寄存器使用
- [x] 条件执行
- [x] AArch64 特有指令选择
  - [x] 乘加/乘减指令 (MADD, MSUB, MNEG)
  - [x] 带移位操作数指令 (ADD/SUB/AND/OR/XOR shifted)
- [ ] 扩展指令 (`ExtendKind::Signed8To32/Signed8To64/...` 已定义但未使用)

### 10.3 代码发射 ✅
- [x] 机器码缓冲区
- [x] 重定位处理
- [x] 分支偏移计算
- [x] 代码对齐

### 10.4 运行时支持 ✅
- [x] JIT 代码缓存
- [x] 可执行内存管理
- [x] 代码卸载

---

## Phase 11: JIT 运行时集成 🚀

> 将 JIT 编译器集成到 WASM 运行时

### 11.1 编译策略 ✅
- [x] 解释执行 + JIT 混合模式
- [x] 热点检测 (Profiling)
- [x] 分层编译 (Tiered Compilation)
- [x] 懒编译 (Lazy Compilation)

### 11.2 运行时接口 🔨
- [x] 编译函数调用
- [x] 解释器到 JIT 代码的切换
- [ ] 堆栈替换 (On-Stack Replacement)

### 11.3 调试支持 ✅
- [x] 源码映射
- [x] 断点支持
  - [x] 断点管理 API
  - [ ] 完整调试命令 (`StepInto`, `StepOver`, `StepOut` 已定义但未使用)
- [x] 堆栈跟踪

---

## Phase 12: WASI 支持 🔨 进行中

> WebAssembly System Interface - 使 WASM 模块能够与操作系统交互

### 12.1 WASI Preview 1 (wasi_snapshot_preview1)
- [x] 标准 I/O 操作
  - [x] `fd_read` / `fd_write` - stdin/stdout/stderr 读写
  - [x] `fd_close` - 关闭文件描述符
  - [x] `fd_prestat_get` / `fd_prestat_dir_name` - 预开放目录信息
- [ ] 文件系统操作 (未实现 - 返回 ENOSYS)
  - [ ] `fd_seek` / `fd_tell` - 文件定位
  - [ ] `path_open` / `path_create_directory` - 路径操作
  - [ ] `fd_readdir` - 目录读取
- [x] 环境访问
  - [x] `environ_get` / `environ_sizes_get` - 环境变量
  - [x] `args_get` / `args_sizes_get` - 命令行参数
- [x] 时钟
  - [x] `clock_time_get` - 获取时间
  - [ ] `clock_res_get` - 时钟精度 (未实现)
- [x] 随机数
  - [x] `random_get` - 随机数生成 (PRNG, 非密码学安全)
- [x] 进程控制
  - [x] `proc_exit` - 退出进程
  - [ ] `sched_yield` - 让出 CPU (返回 ENOSYS)

### 12.2 WASI 安全模型
- [x] 目录预开放 (Pre-opened directories) - 基础实现
- [ ] 能力机制 (Capability-based security) - 未实现
- [ ] 文件描述符权限管理 - 未实现

### 12.3 WASI CLI 集成
- [ ] `--dir <HOST_DIR[::GUEST_DIR]>` 目录映射
- [ ] `--env <NAME=VAL>` 环境变量传递
- [ ] `-S, --wasi <KEY=VAL>` WASI 选项

---

## Phase 13: WASM 扩展提案 🌟

### 13.1 WASM 2.0+ 特性
- [ ] 尾调用 (tail-call)
- [ ] 异常处理 (exception-handling)
- [ ] 垃圾回收 (GC)
- [ ] 组件模型 (Component Model)

### 13.2 SIMD 支持
- [ ] v128 类型
- [ ] SIMD 指令集
- [ ] 向量化优化

### 13.3 线程支持
- [ ] 共享内存
- [ ] 原子操作
- [ ] 等待/通知

---

## 里程碑时间线

| 阶段 | 目标 | 状态 |
|------|------|------|
| Phase 1-5 | 完整的 WASM 解释器 | ✅ 已完成 |
| Phase 6 | 中间表示层设计 | ✅ 已完成 |
| Phase 7 | IR 优化 | ✅ 已完成 (7.4 可选跳过) |
| Phase 8 | 指令选择 | ✅ 核心完成 (约束系统/多调用约定定义但未使用) |
| Phase 9 | 寄存器分配 | ✅ 核心完成 (合并优化待实现) |
| Phase 10 | 代码生成 | ✅ 核心完成 (8/16位内存操作、扩展指令待实现) |
| Phase 11 | JIT 集成 | 🔨 进行中 (OSR、完整调试命令待实现) |
| Phase 12 | WASI 支持 | 📋 未来计划 |
| Phase 13 | WASM 扩展 | 📋 未来计划 |

---

## 参考资源

### WebAssembly 规范
- [WebAssembly Specification](https://webassembly.github.io/spec/)
- [WASM Binary Encoding](https://webassembly.github.io/spec/core/binary/index.html)
- [WASM Semantics](https://webassembly.github.io/spec/core/exec/index.html)

### Cranelift 参考
- [Cranelift Official Site](https://cranelift.dev/)
- [Cranelift Code Generation Primer](https://bouvier.cc/2021/02/17/cranelift-codegen-primer/)
- [ISLE DSL Reference](https://github.com/bytecodealliance/wasmtime/blob/main/cranelift/isle/docs/language-reference.md)
- [Wasmtime and Cranelift Progress](https://bytecodealliance.org/articles/wasmtime-and-cranelift-in-2023)

### 编译器设计
- [Engineering a Compiler (Cooper & Torczon)](https://www.elsevier.com/books/engineering-a-compiler/cooper/978-0-12-815412-0)
- [SSA Book](http://ssabook.gforge.inria.fr/latest/book.pdf)

---

**当前状态**: Phase 8-11 核心功能已完成，部分高级功能（操作数约束、多调用约定、8/16位内存操作、扩展指令、调试步进命令）已定义接口但未实现
**下一步**: 见下方优先级排序

---

## 剩余任务优先级

> 根据实用性、依赖关系和复杂度排序

### 🔴 高优先级 (P0) - 实用性高、用户可见

| 任务 | 所属阶段 | 理由 |
|------|----------|------|
| **WASI Preview 1 核心接口** | Phase 12 | 无 WASI 支持则无法运行大多数现实世界 WASM 程序 |
| - `fd_read`/`fd_write` (标准输入输出) | 12.1 | 最基础的 I/O，几乎所有程序都需要 |
| - `args_get`/`environ_get` | 12.1 | 命令行程序必需 |
| - `proc_exit` | 12.1 | 程序退出必需 |
| - `clock_time_get` | 12.1 | 计时、性能测量必需 |

### 🟠 中优先级 (P1) - 功能完整性

| 任务 | 所属阶段 | 理由 |
|------|----------|------|
| **WAT Import 内联签名** | Phase 5 | 标准 WAT 语法支持，阻塞 WASI 示例运行 |
| **友好的错误信息** | Phase 5 | 用户体验，当前报错缺乏行号和上下文 |
| **WASI 文件系统** | Phase 12 | 文件操作是常见需求 |
| - `path_open`/`fd_close` | 12.1 | 文件读写必需 |
| - `fd_seek`/`fd_tell` | 12.1 | 随机访问文件 |
| **8/16位内存操作** | Phase 10 | 某些 WASM 程序可能使用 |
| **扩展指令 (ExtendKind)** | Phase 10 | 类型转换完整性 |
| **寄存器合并 (Coalescing)** | Phase 9 | 提升 JIT 代码质量 |

### 🟡 低优先级 (P2) - 锦上添花

| 任务 | 所属阶段 | 理由 |
|------|----------|------|
| **堆栈替换 (OSR)** | Phase 11 | 优化热点代码，非必需 |
| **完整调试命令** (`StepInto/Over/Out`) | Phase 11 | 调试功能，可后补 |
| **E-graph 优化框架** | Phase 7 | 高级优化，现有优化已够用 |
| **内联 (Inlining)** | Phase 7 | 性能优化 |
| **尾调用优化** | Phase 7 | 特定场景优化 |
| **多调用约定** | Phase 8 | 目前单一目标无需 |
| **操作数约束系统** | Phase 8 | 寄存器分配已工作 |
| **完整栈槽类型** | Phase 9 | 当前实现已满足需求 |

### 🔵 远期目标 (P3) - 前沿特性

| 任务 | 所属阶段 | 理由 |
|------|----------|------|
| **x86-64 后端** | Phase 10 | 需要大量工作，AArch64 优先 |
| **尾调用提案** | Phase 13 | WASM 2.0+ 特性 |
| **异常处理** | Phase 13 | WASM 2.0+ 特性 |
| **GC 提案** | Phase 13 | 复杂度高 |
| **SIMD 支持** | Phase 13 | 需要大量指令实现 |
| **线程支持** | Phase 13 | 涉及并发模型 |
| **组件模型** | Phase 13 | 规范仍在演进 |

### 推荐实施路径

```
Phase 12 WASI (P0)
    │
    ├─► fd_write/fd_read (stdout/stderr/stdin)
    ├─► args_get/environ_get
    ├─► proc_exit
    └─► clock_time_get
         │
         ▼
Phase 12 WASI 文件系统 (P1)
    │
    ├─► path_open/fd_close
    └─► fd_seek/fd_tell
         │
         ▼
Phase 10 完善 (P1)
    │
    ├─► 8/16位内存操作
    └─► ExtendKind 指令
         │
         ▼
Phase 9/11 优化 (P2)
    │
    ├─► 寄存器合并
    └─► OSR (可选)
```
