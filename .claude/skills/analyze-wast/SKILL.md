---
name: analyze-wast
description: Analyze WebAssembly test (WAST) files to debug compilation issues and create regression tests. Use when the user asks to debug or analyze WAST test failures, investigate compilation bugs in wasmoon, or when encountering test failures in spec/*.wast files. Triggers include "analyze wast", "debug wast", "wast bug", or references to specific .wast test files.
---

# Analyze WAST

1. **Reproduce**: `./wasmoon test spec/<file>.wast`
2. **Explore stages**: `./wasmoon explore <file>.wat --stage ir vcode mc`
3. **Compare modes**: `./wasmoon test --no-jit <file>.wast` (interpreter only)
4. **Create regression test** in `testsuite/<feature>_test.mbt` using `compare_jit_interp()`
5. **Debug crashes**: `lldb -- ./wasmoon test <file>.wast`
