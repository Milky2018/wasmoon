# Wasmoon Roadmap

WebAssembly Runtime in MoonBit - 开发路线图

## 项目概述

Wasmoon 是一个用 MoonBit 编写的 WebAssembly 运行时，目标是实现一个完整的 WASM 解释器，支持 WebAssembly 1.0 规范的核心特性。

## Phase 1: MVP (最小可行产品) ✅ 已完成

### 1.1 核心数据结构 ✅
- [x] 值类型定义 (I32, I64, F32, F64, FuncRef, ExternRef)
- [x] 指令集枚举 (190+ 指令变体)
- [x] 模块结构 (Module, FuncType, Export, Import 等)
- [x] 使用 `pub(all)` 导出必要的类型以支持手动构造

**文件**: `wasmoon.mbt` (356 行)

### 1.2 二进制格式解析器 ✅
- [x] 魔数和版本验证
- [x] LEB128 编码解码（有符号和无符号）
- [x] 11 种 Section 解析 (Type, Import, Function, Table, Memory, Global, Export, Start, Element, Code, Data)
- [x] 错误处理使用 `suberror`/`raise` 模式
- [x] 使用 MoonBit 函数式 `loop` 语法
- [x] IEEE 754 浮点数解码 (f32/f64)

**文件**: `parser.mbt` (~800 行)

### 1.3 运行时数据结构 ✅
- [x] 操作数栈 (Stack) - 支持类型化 push/pop
- [x] 线性内存 (Memory) - 64KB 页，支持 load/store
- [x] 函数引用表 (Table) - 动态增长
- [x] 全局变量 (GlobalInstance) - 可变/不可变
- [x] 调用帧 (Frame) 和标签 (Label)
- [x] 全局存储 (Store) - 管理所有运行时资源
- [x] 模块实例 (ModuleInstance)

**文件**: `runtime.mbt` (433 行)

### 1.4 基础执行引擎 ✅
- [x] i32 算术运算 (add, sub, mul, div, rem)
- [x] i32 比较运算 (eq, ne, lt, gt, le, ge, eqz)
- [x] i32 位运算 (and, or, xor, shl, shr_s, shr_u)
- [x] 常量指令 (i32.const, i64.const, f32.const, f64.const)
- [x] 局部变量 (local.get, local.set, local.tee)
- [x] 基本控制流 (nop, drop, return)
- [x] 函数调用和参数传递

**文件**: `executor.mbt` (318 行)

### 1.5 测试和示例 ✅
- [x] 16 个测试用例（全部通过）
- [x] 示例程序展示 MVP 功能
- [x] 简单加法函数
- [x] 带常量的乘法加法
- [x] 使用局部变量的复杂表达式
- [x] i32/i64/f32/f64 数值运算测试
- [x] Parser 单元测试（LEB128、浮点数解码）

**文件**: `wasmoon_test.mbt`, `parser.mbt`, `cmd/main/main.mbt`

**测试结果**: Total tests: 16, passed: 16, failed: 0 ✅

---

## Phase 2: 核心功能扩展 🚧 进行中

### 2.1 完整的数值运算 ✅ 已完成
- [x] i64 算术运算 (add, sub, mul, div, rem)
- [x] i64 比较和位运算
- [x] f32 浮点运算 (add, sub, mul, div, sqrt, abs, neg, ceil, floor)
- [x] f64 浮点运算
- [x] 数值转换指令 (wrap, extend, trunc, convert, reinterpret)
- [x] 饱和转换指令 (trunc_sat)

**状态**: 已完成

### 2.2 内存操作
- [ ] 完整的 load 指令族 (i32.load, i64.load, f32.load, f64.load)
- [ ] 扩展的 load 指令 (load8_s, load8_u, load16_s, load16_u, load32_s, load32_u)
- [ ] 完整的 store 指令族
- [ ] memory.size 和 memory.grow
- [ ] 内存边界检查优化

**预估**: ~150 行代码

### 2.3 控制流
- [ ] 结构化控制流 (block, loop, if-else)
- [ ] 分支指令 (br, br_if, br_table)
- [ ] 标签栈管理
- [ ] 多返回值支持

**预估**: ~250 行代码

### 2.4 函数调用
- [ ] 直接函数调用 (call)
- [ ] 间接函数调用 (call_indirect)
- [ ] 尾调用优化（可选）

**预估**: ~100 行代码

---

## Phase 3: 模块系统 📦 计划中

### 3.1 导入导出
- [ ] 函数导入
- [ ] 内存导入
- [ ] 表导入
- [ ] 全局变量导入
- [ ] 主机函数接口 (Host Functions)

**预估**: ~200 行代码

### 3.2 模块验证器
- [ ] 类型检查
- [ ] 栈高度验证
- [ ] 控制流验证
- [ ] 局部变量验证
- [ ] 表和内存边界验证

**预估**: ~300 行代码 (新文件 `validator.mbt`)

### 3.3 模块链接
- [ ] 多模块支持
- [ ] 模块依赖解析
- [ ] 符号解析

**预估**: ~150 行代码

---

## Phase 4: 高级特性 🚀 未来计划

### 4.1 全局变量
- [ ] 可变全局变量
- [ ] 全局变量初始化表达式
- [ ] global.get / global.set 完整实现

### 4.2 表操作
- [ ] table.get / table.set
- [ ] table.size / table.grow
- [ ] table.fill / table.copy
- [ ] elem.drop

### 4.3 数据段
- [ ] 数据段初始化
- [ ] memory.init / memory.copy / memory.fill
- [ ] data.drop

### 4.4 引用类型
- [ ] ref.null / ref.is_null / ref.func
- [ ] 多表支持
- [ ] 引用类型验证

---

## Phase 5: 性能和工具 ⚡ 长期目标

### 5.1 性能优化
- [ ] 指令缓存
- [ ] 热点函数识别
- [ ] 简单 JIT 编译（可选）
- [ ] 内联小函数
- [ ] 栈操作优化

### 5.2 调试支持
- [ ] 指令级跟踪
- [ ] 断点支持
- [ ] 栈帧检查
- [ ] 内存查看器
- [ ] 性能分析

### 5.3 工具链
- [ ] WAT (WebAssembly Text) 格式支持
- [ ] WASM 反汇编器
- [ ] 模块检查工具
- [ ] 基准测试套件

---

## Phase 6: 规范兼容性 📋 长期目标

### 6.1 WASM 1.0 完整支持
- [ ] 通过官方测试套件
- [ ] 规范兼容性验证

### 6.2 WASM 2.0 特性（未来）
- [ ] 多值返回
- [ ] 引用类型
- [ ] 批量内存操作
- [ ] 尾调用

### 6.3 WASM 提案支持（可选）
- [ ] SIMD (v128)
- [ ] 线程和原子操作
- [ ] 异常处理
- [ ] 垃圾回收

---

## 技术债务和改进

### 代码质量
- [ ] 添加更多单元测试
- [ ] 集成测试覆盖
- [ ] 错误消息改进
- [ ] 文档完善

### 架构改进
- [ ] 模块化重构
- [ ] 接口设计优化
- [ ] 性能基准测试

---

## 项目统计

### 当前代码量
- `wasmoon.mbt`: 356 行 (核心数据结构)
- `parser.mbt`: 697 行 (二进制解析器)
- `runtime.mbt`: 433 行 (运行时)
- `executor.mbt`: 318 行 (执行引擎)
- `wasmoon_test.mbt`: 133 行 (测试)
- `cmd/main/main.mbt`: 125 行 (示例)

**总计**: ~2062 行 MoonBit 代码

### 测试覆盖
- 单元测试: 4/4 通过 ✅
- 集成测试: MVP 演示通过 ✅

---

## 贡献指南

### 开发原则
1. **纯函数优先**: 尽可能使用纯函数和不可变数据
2. **函数式循环**: 使用 MoonBit 的 `loop` 语法而非递归辅助函数 `fn go()`
3. **错误处理**: 使用 `raise`/`suberror` 模式，不使用 Result 类型
4. **类型安全**: 充分利用 MoonBit 的类型系统
5. **模式匹配**: 优先使用模式匹配而非条件分支
6. **参考规范**: 遵循 ERRATA.md 中记录的最佳实践

### 代码风格
- 遵循 MoonBit 官方代码风格
- 函数命名使用 snake_case
- 类型命名使用 PascalCase
- 充分的注释和文档

---

## 参考资源

- [WebAssembly Specification](https://webassembly.github.io/spec/)
- [MoonBit Documentation](https://www.moonbitlang.com/docs/)
- [WASM Binary Encoding](https://webassembly.github.io/spec/core/binary/index.html)
- [WASM Semantics](https://webassembly.github.io/spec/core/exec/index.html)

---

**最后更新**: 2025-11-28
**当前状态**: Phase 2.1 已完成 (完整数值运算)
**下一步**: Phase 2.2 (内存操作)
