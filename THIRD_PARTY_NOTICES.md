# Third-Party Notices

Wasmoon itself is licensed under Apache-2.0. Some directories contain vendored
test suites, benchmark workloads, or generated diagnostic artifacts from other
projects. Their original licenses are preserved below.

## WebAssembly Core Spec Tests

- Path: `spec/`
- Source: https://github.com/WebAssembly/spec
- Upstream path: `test/`
- License: Apache-2.0
- Local license file: `spec/LICENSE`

## WebAssembly Component Model Tests

- Path: `component-spec/`
- Source: https://github.com/WebAssembly/component-model
- Upstream commit: `e1fdcd10003c2570c77cbd9f6dbcb9db629ecb6a`
- Upstream path: `test/`
- License: Apache-2.0
- Local license files: `component-spec/LICENSE`,
  `component-spec/LICENSE-APACHE`

## Wasmtime Component Tests

- Path: `component-spec/wasmtime/`
- Source: https://github.com/bytecodealliance/wasmtime
- License: Apache-2.0 WITH LLVM-exception
- Local license file:
  `component-spec/wasmtime/LICENSE-Apache-2.0_WITH_LLVM-exception`

## Libsodium WebAssembly Benchmarks

- Path: `examples/algorithms/`
- Source: https://github.com/jedisct1/webassembly-benchmarks
- Upstream commit: `7e86d68e99e60130899fbe3b3ab6e9dce9187a7c`
- License: ISC
- Local license file: `examples/algorithms/LICENSE`

## Wasmtime Explorer Artifact

- Path:
  `docs/perf/baselines/darwin-arm64/2026-02-09-main-e45fec3/wasmtime_aead.explore.html`
- Source: https://github.com/bytecodealliance/wasmtime
- License: Apache-2.0 WITH LLVM-exception
- Local license file:
  `docs/perf/baselines/darwin-arm64/2026-02-09-main-e45fec3/LICENSE-Apache-2.0_WITH_LLVM-exception`

## MoonBit Dependencies

The repository does not vendor `.mooncakes/` in git. Declared package
dependencies are:

- `moonbitlang/x` - Apache-2.0
- `TheWaWaR/clap` - MIT
