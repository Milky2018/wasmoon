///|
/// Version of the Wasmoon internal JIT calling and runtime contract.
pub const WASMOON_JIT_ABI_VERSION : Int32 = 8

///|
/// Revision of the current direct native target code generator.
///
/// Advance this value whenever compiler changes can alter emitted code while
/// preserving the artifact format and JIT ABI. Persistent caches use it as part
/// of their compatibility identity.
pub const WASMOON_CODEGEN_REVISION : String = "direct-vcode-54"

///|
extern "c" fn host_operating_system_abi_tag() -> Int32 = "wasmoon_jit_host_operating_system_abi"

///|
const AARCH64_LSE_FEATURE : String = "aarch64-lse"

///|
extern "c" fn host_has_aarch64_lse() -> Int32 = "wasmoon_jit_host_has_aarch64_lse"

///|
pub fn host_cpu_features() -> Array[@artifact.CpuFeature] {
  if host_has_aarch64_lse() != 0 {
    [{ name: AARCH64_LSE_FEATURE, }]
  } else {
    []
  }
}

///|
fn contains_atomic_add(body : ReadOnlyArray[@types.Instruction]) -> Bool {
  body.any(fn(instruction) {
    match instruction {
      // WebAssembly subopcodes for the seven integer RMW-add forms.
      Atomic(op, _, _, _) => op >= 0x1E && op <= 0x24
      Block(_, body) | Loop(_, body) | TryTable(_, _, body) =>
        contains_atomic_add(body)
      If(_, yes, no) => contains_atomic_add(yes) || contains_atomic_add(no)
      _ => false
    }
  })
}

///|
/// Select the optional host feature only for shared-memory modules that
/// contain an eligible operation. Other artifacts keep the baseline profile.
pub fn wasm_host_cpu_requirements(
  mod_ : @types.Module,
) -> Array[@artifact.CpuFeature] {
  let shared = mod_.memories.any(memory => memory.is_shared) ||
    mod_.imports.any(item => item.desc is Memory(memory) && memory.is_shared)
  if shared &&
    host_has_aarch64_lse() != 0 &&
    mod_.codes.any(code => contains_atomic_add(code.body)) {
    [{ name: AARCH64_LSE_FEATURE, }]
  } else {
    []
  }
}

///|
fn artifact_architecture(target : NativeTarget) -> @code_object.Architecture {
  match target {
    X64 => X64
    AArch64 => AArch64
  }
}

///|
pub fn host_native_target() -> NativeTarget raise JitPipelineError {
  match c_jit_host_target_arch() {
    1 => X64
    2 => AArch64
    value => raise UnsupportedHostArchitecture(tag=value)
  }
}

///|
pub fn artifact_module_identity(
  name : String,
  source_module : Bytes,
  semantic_features : Bytes,
) -> @artifact.ModuleIdentity {
  {
    name,
    source_digest: {
      bytes: Bytes::from_iter(@crypto.sha256(source_module).iter()),
    },
    semantic_features_digest: {
      bytes: Bytes::from_iter(@crypto.sha256(semantic_features).iter()),
    },
  }
}

///|
/// Build the exact compatibility manifest for a selected target.
///
/// `required_cpu_features` contains only optional features beyond the baseline
/// architecture contract. AArch64 Advanced SIMD and x64 SSE2 are baseline
/// requirements of the corresponding Wasmoon targets and are therefore not
/// repeated here.
pub fn build_artifact_manifest(
  target : NativeTarget,
  operating_system_abi : @artifact.OperatingSystemAbi,
  module_identity~ : @artifact.ModuleIdentity,
  policy~ : @artifact.CompilationPolicy,
  required_cpu_features~ : Array[@artifact.CpuFeature] = [],
  context_shape~ : ContextShape = Legacy,
) -> @artifact.CompatibilityManifest {
  {
    format_version: @artifact.FORMAT_VERSION,
    target: {
      architecture: artifact_architecture(target),
      operating_system_abi,
      endianness: Little,
      pointer_width: Bits64,
    },
    required_cpu_features: required_cpu_features.copy(),
    jit_abi_version: WASMOON_JIT_ABI_VERSION,
    codegen_revision: if offset_reference_codegen_enabled {
      "direct-vcode-offset-experiment-9"
    } else {
      WASMOON_CODEGEN_REVISION
    },
    module_identity,
    policy,
    context_shape,
  }
}

///|
pub fn host_operating_system_abi() -> @artifact.OperatingSystemAbi raise JitPipelineError {
  match host_operating_system_abi_tag() {
    1 => MacOS
    2 => LinuxGnu
    3 => LinuxMusl
    4 => WindowsMsvc
    value => raise UnsupportedHostOsAbi(tag=value)
  }
}

///|
/// Build a manifest for the current process without guessing an unsupported
/// architecture or operating-system ABI.
pub fn build_host_artifact_manifest(
  module_identity~ : @artifact.ModuleIdentity,
  policy~ : @artifact.CompilationPolicy,
  required_cpu_features~ : Array[@artifact.CpuFeature] = [],
  context_shape~ : ContextShape = Legacy,
) -> @artifact.CompatibilityManifest raise JitPipelineError {
  build_artifact_manifest(
    host_native_target(),
    host_operating_system_abi(),
    module_identity~,
    policy~,
    required_cpu_features~,
    context_shape~,
  )
}

///|
pub fn artifact_compatibility(
  manifest : @artifact.CompatibilityManifest,
  available_cpu_features~ : Array[@artifact.CpuFeature],
  runtime_symbols~ : Array[@native.ExternalSymbol],
  data_symbols~ : Array[@native.DataSymbol],
) -> ArtifactCompatibility {
  {
    target: manifest.target,
    available_cpu_features: available_cpu_features.copy(),
    jit_abi_version: WASMOON_JIT_ABI_VERSION,
    codegen_revision: manifest.codegen_revision,
    module_identity: manifest.module_identity,
    policy: manifest.policy,
    context_shape: manifest.context_shape,
    runtime_symbols: runtime_symbols.copy(),
    data_symbols: data_symbols.copy(),
  }
}

///|
fn wasm_value_type(ty : @types.ValueType) -> @native.ValueType {
  match ty {
    I32 => I32
    I64 => I64
    F32 => F32
    F64 => F64
    V128 => V128
    FuncRef
    | ExternRef
    | RefFunc
    | RefExtern
    | RefFuncTyped(_)
    | RefNullFuncTyped(_)
    | ContRef
    | RefCont
    | RefContTyped(_)
    | RefNullContTyped(_)
    | NullContRef
    | RefNoCont
    | AnyRef
    | ExnRef
    | StructRef
    | ArrayRef
    | RefStruct(_)
    | RefNullStruct(_)
    | RefArray(_)
    | RefNullArray(_)
    | RefAny
    | RefEq
    | RefNullEq
    | RefI31
    | RefNullI31
    | RefStructAbs
    | RefArrayAbs
    | RefNone
    | NullRef
    | NullFuncRef
    | NullExnRef
    | NullExternRef => GcRef64
  }
}

///|
pub fn wasm_function_signature(
  function_type : @types.FuncType,
) -> @native.Signature {
  @native.Signature::new(
    function_type.params[:].map(wasm_value_type),
    function_type.results[:].map(wasm_value_type),
  )
}

///|
fn wasm_function_symbol(function_index : Int32) -> String {
  "wasm.func.\{function_index}"
}

///|
pub fn wasm_import_identity(
  function_index : Int32,
  module_name : String,
  function_name : String,
  function_type : @types.FuncType,
) -> @artifact.ImportIdentity {
  {
    function_index,
    module_name,
    function_name,
    symbol: @native.ExternalSymbol::new(wasm_function_symbol(function_index)),
    signature: wasm_function_signature(function_type),
  }
}

///|
fn artifact_function_from_code_object(
  object : @code_object.UnlinkedCodeObject,
  frame_size~ : Int32,
  function_index~ : Int32,
  signature~ : @native.Signature,
) -> @artifact.FunctionCode {
  {
    identity: {
      function_index,
      symbol: @native.CodeSymbol::new(wasm_function_symbol(function_index)),
      signature,
    },
    entry_offset: 0,
    frame_size,
    code: object.code(),
    relocations: object.relocations(),
    sources: object.sources(),
    traps: object.traps(),
    safepoints: object.safepoints(),
    unwind: object.unwind(),
  }
}

///|
/// Compile one verified Wasm MilkIR body directly into the final unlinked
/// artifact representation. Symbolic relocations are retained unchanged.
pub struct NativeCompiler {
  priv target : NativeTarget
  priv context_layout : VMContextLayout
  priv aarch64 : @aarch64_target.CompilationSession?
  priv x64 : @x64_target.CompilationSession?
}

///|
pub fn NativeCompiler::new(
  target : NativeTarget,
  context_shape~ : ContextShape = Legacy,
) -> NativeCompiler {
  native_compiler(target, context_shape, false)
}

///|
/// Select code generation from the same manifest that is verified at install.
pub fn NativeCompiler::for_manifest(
  manifest : @artifact.CompatibilityManifest,
) -> NativeCompiler {
  let target : NativeTarget = match manifest.target.architecture {
    AArch64 => AArch64
    X64 => X64
  }
  native_compiler(
    target,
    manifest.context_shape,
    manifest.required_cpu_features.any(feature => {
      feature.name == AARCH64_LSE_FEATURE
    }),
  )
}

///|
fn native_compiler(
  target : NativeTarget,
  context_shape : ContextShape,
  lse_atomic_add : Bool,
) -> NativeCompiler {
  match target {
    AArch64 =>
      {
        target,
        context_layout: shaped_vmcontext_layout(context_shape),
        aarch64: Some(@aarch64_target.CompilationSession::new(lse_atomic_add~)),
        x64: None,
      }
    X64 =>
      {
        target,
        context_layout: shaped_vmcontext_layout(context_shape),
        aarch64: None,
        x64: Some(@x64_target.CompilationSession::new()),
      }
  }
}

///|
pub fn compile_wasm_body_artifact_function(
  function : @milkir.Function,
  validation_context : @wasm_milkir.WasmValidationContext,
  target : NativeTarget,
  function_index~ : Int32,
  signature~ : @native.Signature,
  context_shape~ : ContextShape = Legacy,
) -> @artifact.FunctionCode raise JitPipelineError {
  NativeCompiler::new(target, context_shape~).compile_wasm_body_artifact_function(
    function,
    validation_context,
    function_index~,
    signature~,
  )
}

///|
/// Compile one function while retaining target allocator scratch capacity for
/// the next serial call on this compiler.
pub fn NativeCompiler::compile_wasm_body_artifact_function(
  self : NativeCompiler,
  function : @milkir.Function,
  validation_context : @wasm_milkir.WasmValidationContext,
  function_index~ : Int32,
  signature~ : @native.Signature,
) -> @artifact.FunctionCode raise JitPipelineError {
  if function_index < 0 {
    raise InvalidFunctionIndex(index=function_index)
  }
  let (object, frame_size) = self.compile_wasm_body(
    function,
    validation_context,
    function_index~,
    record_metrics=@perf.enabled(),
  )
  let packaging_tick = detail_metrics_tick(@perf.enabled())
  let result = artifact_function_from_code_object(
    object,
    frame_size~,
    function_index~,
    signature~,
  )
  record_compile_subphase("artifact_packaging", packaging_tick)
  result
}

///|
fn NativeCompiler::compile_wasm_body(
  self : NativeCompiler,
  function : @milkir.Function,
  validation_context : @wasm_milkir.WasmValidationContext,
  function_index~ : Int32,
  record_metrics~ : Bool = false,
  on_diagnostics~ : ((String, String) -> Unit)? = None,
) -> (@code_object.UnlinkedCodeObject, Int32) raise JitPipelineError {
  match self.target {
    AArch64 => {
      let compiled = compile_wasm_body_aarch64_target(
        function,
        validation_context,
        record_metrics~,
        function_index~,
        context_layout=self.context_layout,
        compilation_session=self.aarch64.unwrap(),
        on_diagnostics~,
      )
      (compiled.object, compiled.frame_size)
    }
    X64 => {
      let compiled = compile_wasm_body_x64_target(
        function,
        validation_context,
        record_metrics~,
        function_index~,
        context_layout=self.context_layout,
        compilation_session=self.x64.unwrap(),
        on_diagnostics~,
      )
      (compiled.object, compiled.frame_size)
    }
  }
}
