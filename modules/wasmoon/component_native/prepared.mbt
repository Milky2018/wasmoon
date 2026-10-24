///|
/// Unlinked native code for the static Core modules in a component bundle.
/// Preparation executes no guest code and retains no Store, executable memory,
/// import address or resource lease. The bounded, private artifact snapshot is
/// retained by this owner and its sessions; session teardown is independent.
pub struct NativeComponentCode {
  priv target : @wasmoon_jit.NativeTarget
  priv opt_level : Int32
  priv artifacts : Map[(Bytes, Int32?), @artifact.Artifact]
}

///|
fn component_optimization_level(level : Int32) -> Int32 {
  Int32::max(0, Int32::min(3, level))
}

///|
fn declared_component_memory_max(module_ : @types.Module) -> Int32? {
  fn legacy_max(memory : @types.MemoryType) -> Int32? {
    // Match Memory::get_limits rather than narrowing memory64 maxima.
    match memory.limits.max {
      Some(limit) if limit >= 0L && limit <= 0xFFFF_FFFFL =>
        Some(limit.to_int())
      _ => None
    }
  }
  for import_ in module_.imports {
    if import_.desc is Memory(memory) {
      return legacy_max(memory)
    }
  }
  if module_.memories.length() > 0 {
    legacy_max(module_.memories[0])
  } else {
    None
  }
}

///|
/// Compile static definitions before admitting requests. Repeated definitions
/// share ordinary immutable code data, never address-bound installations.
pub fn prepare_native_component_code(
  components : ArrayView[@component_validator.ValidatedComponent],
  opt_level~ : Int32 = 2,
) -> NativeComponentCode raise @runtime_impl.ComponentRuntimeError {
  let target = @wasmoon_jit.host_native_target() catch {
    error => raise NativeEngineUnavailable(error.to_string())
  }
  let opt_level = component_optimization_level(opt_level)
  let artifacts : Map[(Bytes, Int32?), @artifact.Artifact] = Map([])
  fn prepare(
    component : @component.Component,
  ) -> Unit raise @runtime_impl.ComponentRuntimeError {
    for bytes in component.core_modules {
      let module_ = @parser.parse_module(bytes) catch {
        error => raise NativeCompilationFailed(error.to_string())
      }
      let memory_max = declared_component_memory_max(module_)
      let key = (encoded_component_module(module_), memory_max)
      if !artifacts.contains(key) {
        artifacts[key] = compile_component_artifact(
          module_,
          target,
          memory_max,
          opt_level,
          checkpoint=fn() { () },
        )
      }
    }
    for child in component.components {
      prepare(child)
    }
  }
  for validated in components {
    let component = @component.parse_component(validated.component_bytes()) catch {
      error => raise NativeCompilationFailed(error.to_string())
    }
    prepare(component)
  }
  { target, opt_level, artifacts, }
}

///|
/// Open an independently owned native session. Compilation policy and target
/// are fixed by preparation; actual alias bindings and memory maxima are still
/// checked at installation. Incompatible bindings compile through the ordinary
/// path without growing the shared snapshot.
pub fn NativeComponentCode::open_session(
  self : NativeComponentCode,
  on_compile~ : () -> Unit = fn() { () },
  on_execution~ : (NativeComponentExecutionEvent) -> Unit = fn(_event) { () },
) -> @runtime_impl.CoreExecutionEngine {
  let (engine, _) = native_component_session_with_contexts(
    self.opt_level,
    on_execution,
    prepared_code=Some(self),
    on_compile~,
  )
  engine
}
