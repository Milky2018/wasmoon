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

### 5.3 命令行工具 (对齐 wasmtime CLI)

> 参考 `wasmtime --help` 实现完整的命令行接口

#### 核心命令
- [x] `run` - 运行 WebAssembly 模块
  - [x] 直接运行 `.wasm` 文件
  - [x] `--invoke <FUNCTION>` 指定入口函数
  - [x] 传递命令行参数给 WASM 模块 (`--arg`)
  - [x] `--preload <NAME=MODULE>` 预加载模块
- [ ] `compile` - 预编译 WebAssembly 模块 (AOT)
  - [ ] 输出 `.cwasm` 预编译格式
  - [ ] `-o, --output <PATH>` 指定输出路径
  - [ ] `--emit-clif <PATH>` 输出 IR (待 IR 实现后)
- [ ] `wast` - 运行 WebAssembly 测试脚本
  - [ ] 支持 `.wast` 格式测试文件
  - [ ] 替换当前的 JSON 测试格式

#### 现有命令 (已实现)
- [x] `test` - 运行 JSON 格式测试 (当前实现)
- [x] `disasm` - 反汇编 WASM 文件
- [x] `wat` - 解析 WAT 文件
- [x] `demo` - 运行内置示例

#### 检查与探索命令
- [ ] `explore` - 探索 WASM 编译过程
  - [ ] 可视化编译各阶段输出
  - [ ] 输出 HTML 报告
- [ ] `objdump` - 检查预编译的 `.cwasm` 文件
  - [ ] 显示元数据
  - [ ] 显示段信息

#### 配置与调试选项
- [ ] `-O, --optimize <KEY=VAL>` 优化选项
  - [ ] 优化级别 (0-3)
  - [ ] 特定优化开关
- [ ] `-D, --debug <KEY=VAL>` 调试选项
  - [ ] 详细日志输出
  - [ ] IR 打印
- [ ] `-W, --wasm <KEY=VAL>` WASM 语义选项
  - [ ] 启用/禁用特定提案
  - [ ] 内存限制配置

#### WASI 支持 (需要先实现 WASI)
- [ ] `-S, --wasi <KEY=VAL>` WASI 选项
- [ ] `--dir <HOST_DIR[::GUEST_DIR]>` 目录映射
- [ ] `--env <NAME=VAL>` 环境变量传递

#### 辅助命令
- [ ] `config` - 配置管理
  - [ ] `--config <FILE>` 使用 TOML 配置文件
- [ ] `settings` - 显示可用的编译器设置
- [ ] `completion` - 生成 shell 补全脚本
  - [ ] 支持 bash, zsh, fish

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

### 8.2 指令选择 (Lowering)
- [x] 高级 IR 到低级 IR 的转换框架
- [x] 模式匹配规则定义 (类似 ISLE DSL)
- [x] 指令合并与优化
- [ ] 目标特定的指令选择规则

### 8.3 目标架构抽象 ✅
- [x] 目标架构接口 (TargetISA trait)
- [x] 寄存器描述
- [x] 调用约定 (Calling Convention)
- [ ] 指令编码规则

---

## Phase 9: 寄存器分配 📊

> 将虚拟寄存器映射到物理寄存器

### 9.1 活跃性分析
- [ ] 活跃区间 (Live Interval) 计算
- [ ] 使用-定义链 (Use-Def Chain)

### 9.2 寄存器分配算法
- [ ] 线性扫描分配器 (Linear Scan)
- [ ] 溢出处理 (Spilling)
- [ ] 重新加载 (Reloading)
- [ ] 寄存器合并 (Coalescing)

### 9.3 栈布局
- [ ] 栈帧布局计算
- [ ] 溢出槽分配
- [ ] 调用者/被调用者保存寄存器处理

---

## Phase 10: 代码生成 💻

> 生成目标平台的机器代码

### 10.1 x86-64 后端（低优先）
- [ ] 指令编码
- [ ] 寻址模式
- [ ] 条件码处理
- [ ] 浮点指令 (SSE/AVX)

### 10.2 AArch64 后端 (高优先)
- [ ] 指令编码
- [ ] 寄存器使用
- [ ] 条件执行

### 10.3 代码发射
- [ ] 机器码缓冲区
- [ ] 重定位处理
- [ ] 分支偏移计算
- [ ] 代码对齐

### 10.4 运行时支持
- [ ] JIT 代码缓存
- [ ] 可执行内存管理
- [ ] 代码卸载

---

## Phase 11: JIT 运行时集成 🚀

> 将 JIT 编译器集成到 WASM 运行时

### 11.1 编译策略
- [ ] 解释执行 + JIT 混合模式
- [ ] 热点检测 (Profiling)
- [ ] 分层编译 (Tiered Compilation)
- [ ] 懒编译 (Lazy Compilation)

### 11.2 运行时接口
- [ ] 编译函数调用
- [ ] 解释器到 JIT 代码的切换
- [ ] 堆栈替换 (On-Stack Replacement)

### 11.3 调试支持
- [ ] 源码映射
- [ ] 断点支持
- [ ] 堆栈跟踪

---

## Phase 12: WASM 扩展提案 🌟

### 12.1 WASM 2.0+ 特性
- [ ] 尾调用 (tail-call)
- [ ] 异常处理 (exception-handling)
- [ ] 垃圾回收 (GC)
- [ ] 组件模型 (Component Model)

### 12.2 SIMD 支持
- [ ] v128 类型
- [ ] SIMD 指令集
- [ ] 向量化优化

### 12.3 线程支持
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
| Phase 8 | 指令选择 | 🔨 进行中 (8.1, 8.3 完成) |
| Phase 9 | 寄存器分配 | 📋 计划中 |
| Phase 10 | 代码生成 | 📋 计划中 |
| Phase 11 | JIT 集成 | 📋 计划中 |
| Phase 12 | WASM 扩展 | 📋 未来计划 |

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

**当前状态**: Phase 8.2 指令合并与优化已完成，支持强度削减优化 (mul/div by power-of-2 -> shift)
**下一步**: 实现 Phase 8.2 目标特定的指令选择规则
