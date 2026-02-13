///|
test "runtime_version is exposed" {
  inspect(runtime_version(), content="0.4.0")
}

///|
test "supports_feature basic matrix" {
  inspect(supports_feature(Interpreter), content="true")
  inspect(supports_feature(JIT), content="true")
  inspect(supports_feature(SIMD), content="true")
  inspect(supports_feature(RelaxedSIMD), content="true")
  inspect(supports_feature(ReferenceTypes), content="true")
  inspect(supports_feature(FunctionReferences), content="true")
  inspect(supports_feature(TailCall), content="true")
  inspect(supports_feature(ExceptionHandling), content="true")
  inspect(supports_feature(GC), content="true")
  inspect(supports_feature(Memory64), content="true")
  inspect(supports_feature(MultiMemory), content="true")
  inspect(supports_feature(ComponentModel), content="true")
  inspect(supports_feature(WasiPreview1), content="true")
  inspect(supports_feature(Threads), content="false")
}

///|
test "runtime_capabilities snapshot is coherent" {
  let caps = runtime_capabilities()
  inspect(caps.version, content="0.4.0")
  inspect(caps.interpreter, content="true")
  inspect(caps.jit, content="true")
  inspect(caps.simd, content="true")
  inspect(caps.relaxed_simd, content="true")
  inspect(caps.reference_types, content="true")
  inspect(caps.function_references, content="true")
  inspect(caps.tail_call, content="true")
  inspect(caps.exception_handling, content="true")
  inspect(caps.gc, content="true")
  inspect(caps.memory64, content="true")
  inspect(caps.multi_memory, content="true")
  inspect(caps.component_model, content="true")
  inspect(caps.wasi_preview1, content="true")
  inspect(caps.threads, content="false")
}
