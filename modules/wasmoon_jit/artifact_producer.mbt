///|
/// Version of the Wasmoon internal JIT calling and runtime contract.
pub const WASMOON_JIT_ABI_VERSION : Int = 3

///|
/// Revision of the current semantic-MachV target code generator.
pub const WASMOON_CODEGEN_REVISION : String = "machv-vcode-1"

///|
extern "c" fn host_operating_system_abi_tag() -> Int = "wasmoon_jit_host_operating_system_abi"

///|
fn artifact_architecture(target : NativeTarget) -> @code_object.Architecture {
  match target {
    X64 => X64
    AArch64 => AArch64
  }
}

///|
pub fn host_native_target() -> NativeTarget raise JitPipelineError {
  match @jit_ffi.c_jit_host_target_arch() {
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
  required_cpu_features? : Array[@artifact.CpuFeature] = [],
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
    codegen_revision: WASMOON_CODEGEN_REVISION,
    module_identity,
    policy,
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
  required_cpu_features? : Array[@artifact.CpuFeature] = [],
) -> @artifact.CompatibilityManifest raise JitPipelineError {
  build_artifact_manifest(
    host_native_target(),
    host_operating_system_abi(),
    module_identity~,
    policy~,
    required_cpu_features~,
  )
}

///|
pub fn artifact_compatibility(
  manifest : @artifact.CompatibilityManifest,
  available_cpu_features~ : Array[@artifact.CpuFeature],
  runtime_symbols~ : Array[@semantic_machv.ExternalSymbol],
  data_symbols~ : Array[@semantic_machv.DataSymbol],
) -> ArtifactCompatibility {
  {
    target: manifest.target,
    available_cpu_features: available_cpu_features.copy(),
    jit_abi_version: manifest.jit_abi_version,
    codegen_revision: manifest.codegen_revision,
    module_identity: manifest.module_identity,
    policy: manifest.policy,
    runtime_symbols: runtime_symbols.copy(),
    data_symbols: data_symbols.copy(),
  }
}

///|
fn wasm_value_type(ty : @types.ValueType) -> @semantic_machv.ValueType {
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
) -> @semantic_machv.Signature {
  @semantic_machv.Signature::new(
    function_type.params.map(wasm_value_type),
    function_type.results.map(wasm_value_type),
  )
}

///|
fn wasm_function_symbol(function_index : Int) -> String {
  "wasm.func.\{function_index}"
}

///|
pub fn wasm_import_identity(
  function_index : Int,
  module_name : String,
  function_name : String,
  function_type : @types.FuncType,
) -> @artifact.ImportIdentity {
  {
    function_index,
    module_name,
    function_name,
    symbol: @semantic_machv.ExternalSymbol::new(
      wasm_function_symbol(function_index),
    ),
    signature: wasm_function_signature(function_type),
  }
}

///|
fn artifact_function_from_code_object(
  object : @code_object.UnlinkedCodeObject,
  frame_size~ : Int,
  function_index~ : Int,
  signature~ : @semantic_machv.Signature,
) -> @artifact.FunctionCode {
  {
    identity: {
      function_index,
      symbol: @semantic_machv.CodeSymbol::new(
        wasm_function_symbol(function_index),
      ),
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
pub fn compile_wasm_body_artifact_function(
  function : @milkir.Function,
  validation_context : @wasm_milkir.WasmValidationContext,
  target : NativeTarget,
  function_index~ : Int,
  signature~ : @semantic_machv.Signature,
  use_subtype_indirect_check? : Bool = true,
  canonical_type_indices? : Array[Int] = [],
) -> @artifact.FunctionCode raise JitPipelineError {
  if function_index < 0 {
    raise InvalidFunctionIndex(index=function_index)
  }
  match target {
    AArch64 => {
      let compiled = compile_wasm_body_aarch64_target(
        function, validation_context, use_subtype_indirect_check, canonical_type_indices,
      )
      artifact_function_from_code_object(
        compiled.object,
        frame_size=compiled.frame_size,
        function_index~,
        signature~,
      )
    }
    X64 => {
      let compiled = compile_wasm_body_x64_target(
        function, validation_context, use_subtype_indirect_check, canonical_type_indices,
      )
      artifact_function_from_code_object(
        compiled.object,
        frame_size=compiled.frame_size,
        function_index~,
        signature~,
      )
    }
  }
}
