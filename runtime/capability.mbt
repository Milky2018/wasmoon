///|
/// Wasmoon runtime version for integration-time compatibility checks.
///
/// Keep this value in sync with `moon.mod.json`.
const WASMOON_RUNTIME_VERSION : String = "0.4.0"

///|
/// Query runtime version.
pub fn runtime_version() -> String {
  WASMOON_RUNTIME_VERSION
}

///|
/// Capability key for generic feature checks.
pub(all) enum RuntimeFeature {
  Interpreter
  JIT
  SIMD
  RelaxedSIMD
  ReferenceTypes
  FunctionReferences
  TailCall
  ExceptionHandling
  GC
  Memory64
  MultiMemory
  ComponentModel
  WasiPreview1
  Threads
}

///|
/// Structured capability snapshot.
pub struct RuntimeCapabilities {
  version : String
  interpreter : Bool
  jit : Bool
  simd : Bool
  relaxed_simd : Bool
  reference_types : Bool
  function_references : Bool
  tail_call : Bool
  exception_handling : Bool
  gc : Bool
  memory64 : Bool
  multi_memory : Bool
  component_model : Bool
  wasi_preview1 : Bool
  threads : Bool
}

///|
/// Generic capability query.
pub fn supports_feature(feature : RuntimeFeature) -> Bool {
  match feature {
    Interpreter => true
    JIT => true
    SIMD => true
    RelaxedSIMD => true
    ReferenceTypes => true
    FunctionReferences => true
    TailCall => true
    ExceptionHandling => true
    GC => true
    Memory64 => true
    MultiMemory => true
    ComponentModel => true
    WasiPreview1 => true
    Threads => false
  }
}

///|
pub fn supports_interpreter() -> Bool {
  supports_feature(Interpreter)
}

///|
pub fn supports_jit() -> Bool {
  supports_feature(JIT)
}

///|
pub fn supports_simd() -> Bool {
  supports_feature(SIMD)
}

///|
pub fn supports_relaxed_simd() -> Bool {
  supports_feature(RelaxedSIMD)
}

///|
pub fn supports_reference_types() -> Bool {
  supports_feature(ReferenceTypes)
}

///|
pub fn supports_function_references() -> Bool {
  supports_feature(FunctionReferences)
}

///|
pub fn supports_tail_call() -> Bool {
  supports_feature(TailCall)
}

///|
pub fn supports_exception_handling() -> Bool {
  supports_feature(ExceptionHandling)
}

///|
pub fn supports_gc() -> Bool {
  supports_feature(GC)
}

///|
pub fn supports_memory64() -> Bool {
  supports_feature(Memory64)
}

///|
pub fn supports_multi_memory() -> Bool {
  supports_feature(MultiMemory)
}

///|
pub fn supports_component_model() -> Bool {
  supports_feature(ComponentModel)
}

///|
pub fn supports_wasi_preview1() -> Bool {
  supports_feature(WasiPreview1)
}

///|
pub fn supports_threads() -> Bool {
  supports_feature(Threads)
}

///|
/// Structured capability query.
pub fn runtime_capabilities() -> RuntimeCapabilities {
  {
    version: runtime_version(),
    interpreter: supports_interpreter(),
    jit: supports_jit(),
    simd: supports_simd(),
    relaxed_simd: supports_relaxed_simd(),
    reference_types: supports_reference_types(),
    function_references: supports_function_references(),
    tail_call: supports_tail_call(),
    exception_handling: supports_exception_handling(),
    gc: supports_gc(),
    memory64: supports_memory64(),
    multi_memory: supports_multi_memory(),
    component_model: supports_component_model(),
    wasi_preview1: supports_wasi_preview1(),
    threads: supports_threads(),
  }
}
