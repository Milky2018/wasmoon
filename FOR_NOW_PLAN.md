# "For Now" Comments Cleanup Plan

Total: 34 items (8 fixed)

## Priority 1: Quick Fixes (可直接修复)

| # | File | Line | Issue | Action |
|---|------|------|-------|--------|
| ~~1~~ | ~~`wasi/functions.mbt`~~ | ~~377~~ | ~~Simple PRNG (not cryptographically secure)~~ | ~~改用系统随机源~~ |
| ~~2~~ | ~~`cli/main/run.mbt`~~ | ~~109,113~~ | ~~inherit-stdin not implemented~~ | ~~实现 stdin 继承~~ |
| 3 | `cli/tools/wat2wasm.mbt` | 39 | Binary writer not implemented | 需要实现完整编码器 (复杂) |
| ~~4~~ | ~~`cwasm/cwasm.mbt`~~ | ~~452~~ | ~~Simple ASCII encoding~~ | ~~支持完整 UTF-8~~ |

## Priority 2: GC Reference Types (统一处理)

| # | File | Line | Issue | Action |
|---|------|------|-------|--------|
| ~~5~~ | ~~`testsuite/compare.mbt`~~ | ~~72~~ | ~~GC refs treated as null~~ | ~~实现 GC 引用比较~~ |
| ~~6~~ | ~~`wast/jit_support.mbt`~~ | ~~163~~ | ~~GC refs treated as null~~ | ~~实现 GC 引用支持~~ |
| ~~7~~ | ~~`cli/main/run.mbt`~~ | ~~687~~ | ~~GC refs treated as null~~ | ~~实现 GC 引用解析~~ |
| ~~8~~ | ~~`wat/parser.mbt`~~ | ~~2382~~ | ~~Type index as FuncRef~~ | ~~正确解析类型索引~~ |

## Priority 3: JIT/VCode Improvements (编译器优化)

| # | File | Line | Issue | Action |
|---|------|------|-------|--------|
| 9 | `vcode/lower/lower_numeric.mbt` | 259 | Only 64-bit optimized | 添加 32-bit 优化 |
| 10 | `vcode/lower/peephole.mbt` | 158 | DCE disabled | 实现跨块 DCE |
| 11 | `vcode/lower/aarch64_patterns.mbt` | 58 | Simple cases only | 扩展模式匹配 |
| 12 | `vcode/emit/instructions.mbt` | 3412 | Some instructions abort | 实现剩余指令 |
| 13 | `vcode/regalloc/bundle.mbt` | 266 | No loop info | 添加循环信息 |
| 14 | `vcode/regalloc/liverange.mbt` | 373 | Single range simplification | 实现多区间活跃范围 |
| 15 | `vcode/regalloc/stacklayout.mbt` | 329,474 | Prologue/call handling | 完善栈布局 |
| 16 | `vcode/gc_compiler.mbt` | 136,149 | GC not in JIT | 实现 JIT GC 分配 |
| 17 | `jit/engine.mbt` | 128 | JIT decision recording | 改进 JIT 决策逻辑 |

## Priority 4: Exception Handling (异常处理)

| # | File | Line | Issue | Action |
|---|------|------|-------|--------|
| 18 | `vcode/lower/lower_exception.mbt` | 22,35 | Tag-only exceptions | 支持带值异常 |
| 19 | `jit/jit_ffi/exception.c` | 89 | exnref as packed value | 正确实现 exnref |

## Priority 5: Platform Support (平台支持)

| # | File | Line | Issue | Action |
|---|------|------|-------|--------|
| 20 | `vcode/target.mbt` | 73 | Apple ARM64 only | 添加其他平台支持 |
| 21 | `wasi/ffi_native.c` | 116 | Windows empty result | 实现 Windows 支持 |

## Priority 6: Low Priority / Design Decisions (低优先级)

| # | File | Line | Issue | Action |
|---|------|------|-------|--------|
| 22 | `wasi/wasi.mbt` | 19 | Memory wrapper functions | 可能是最终设计 |
| 23 | `runtime/linker.mbt` | 101 | Synthetic module workaround | 需要重新设计 |
| 24 | `executor/instr_gc.mbt` | 314 | Packed field extension | 实现 packed 扩展 |
| 25 | `executor/executor_wbtest.mbt` | 1189 | table.grow test limitation | 改进测试 |
| 26 | `validator/validator.mbt` | 2883 | ref type validation | 完善验证器 |
| 27 | `wat/parser_defs.mbt` | 775 | Skip for assert_invalid | 可能是正确行为 |
| 28 | `testsuite/runner.mbt` | 492 | Skip trapping gets | 实现 trap 测试 |
| 29 | `ir/egraph/rules_skeleton.mbt` | 99 | Pattern recognition | 扩展模式 |
| 30 | `ir/egraph_builder.mbt` | 404,417 | Optimization skipping | 添加更多优化 |

---

## Completed

- [x] `wasi/functions.mbt:293` - clock_time_get 使用真实系统时间 (b93b644)
- [x] `wasi/functions.mbt:377` - random_get 使用系统熵源
- [x] `cli/main/run.mbt:109,113` - inherit-stdin/stdout/stderr 实现
- [x] `cwasm/cwasm.mbt:452` - 完整 UTF-8 编码/解码
- [x] `wat/parser.mbt:2382` - 正确解析类型索引引用
- [x] `testsuite/compare.mbt` - JIT GC 引用类型解码 (i31, struct, array)
- [x] `wast/jit_support.mbt` - JIT GC 引用类型同步
- [x] `cli/main/run.mbt` - JIT GC 引用类型结果解析

## Next Steps

1. ~~先处理 Priority 1 的快速修复~~ ✓
2. ~~统一处理 GC 引用类型问题~~ ✓
3. 逐步改进 JIT/VCode
4. 其他根据需要处理
