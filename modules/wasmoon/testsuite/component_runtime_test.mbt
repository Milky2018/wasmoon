///|
fn append_bytes(dst : Array[Byte], src : Array[Byte]) -> Unit {
  for b in src {
    dst.push(b)
  }
}

///|
fn leb_u32(n : Int) -> Array[Byte] {
  let mut value = n
  let bytes : Array[Byte] = []
  while true {
    let mut byte = value & 0x7f
    value = value >> 7
    if value != 0 {
      byte = byte | 0x80
    }
    bytes.push(byte.to_byte())
    if value == 0 {
      break
    }
  }
  bytes
}

///|
fn build_component(sections : Array[(Int, Array[Byte])]) -> Bytes {
  let bytes : Array[Byte] = [
    b'\x00', b'\x61', b'\x73', b'\x6d', b'\x0d', b'\x00', b'\x01', b'\x00',
  ]
  for entry in sections {
    let (id, payload) = entry
    bytes.push(id.to_byte())
    append_bytes(bytes, leb_u32(payload.length()))
    append_bytes(bytes, payload)
  }
  Bytes::from_array(bytes)
}

///|
fn encode_name(name_bytes : Array[Byte]) -> Array[Byte] {
  let out : Array[Byte] = [b'\x00']
  append_bytes(out, leb_u32(name_bytes.length()))
  append_bytes(out, name_bytes)
  out
}

///|
fn vec_payload(entries : Array[Array[Byte]]) -> Array[Byte] {
  let payload : Array[Byte] = []
  append_bytes(payload, leb_u32(entries.length()))
  for entry in entries {
    append_bytes(payload, entry)
  }
  payload
}

///|
fn import_entry_func(name_bytes : Array[Byte], type_idx : Int) -> Array[Byte] {
  let entry : Array[Byte] = []
  append_bytes(entry, encode_name(name_bytes))
  entry.push(b'\x01')
  append_bytes(entry, leb_u32(type_idx))
  entry
}

///|
fn export_entry_func(name_bytes : Array[Byte], func_idx : Int) -> Array[Byte] {
  let entry : Array[Byte] = []
  append_bytes(entry, encode_name(name_bytes))
  entry.push(b'\x01')
  append_bytes(entry, leb_u32(func_idx))
  entry.push(b'\x00')
  entry
}

///|
fn export_entry_core_func(
  name_bytes : Array[Byte],
  func_idx : Int,
) -> Array[Byte] {
  let entry : Array[Byte] = []
  append_bytes(entry, encode_name(name_bytes))
  entry.push(b'\x00')
  entry.push(b'\x00')
  append_bytes(entry, leb_u32(func_idx))
  entry.push(b'\x00')
  entry
}

///|
fn alias_core_export_func(
  core_inst_idx : Int,
  name_bytes : Array[Byte],
) -> Array[Byte] {
  let entry : Array[Byte] = []
  entry.push(b'\x00')
  entry.push(b'\x00')
  entry.push(b'\x01')
  append_bytes(entry, leb_u32(core_inst_idx))
  append_bytes(entry, leb_u32(name_bytes.length()))
  append_bytes(entry, name_bytes)
  entry
}

///|
fn core_instance_instantiate(module_idx : Int) -> Array[Byte] {
  let entry : Array[Byte] = []
  entry.push(b'\x00')
  append_bytes(entry, leb_u32(module_idx))
  entry.push(b'\x00')
  entry
}

///|
fn canon_lift_entry(core_func_idx : Int, type_idx : Int) -> Array[Byte] {
  let entry : Array[Byte] = []
  entry.push(b'\x00')
  entry.push(b'\x00')
  append_bytes(entry, leb_u32(core_func_idx))
  entry.push(b'\x00')
  append_bytes(entry, leb_u32(type_idx))
  entry
}

///|
fn canon_lower_entry(func_idx : Int) -> Array[Byte] {
  let entry : Array[Byte] = []
  entry.push(b'\x01')
  entry.push(b'\x00')
  append_bytes(entry, leb_u32(func_idx))
  entry.push(b'\x00')
  entry
}

///|
test "component runtime: host import canonical roundtrip" {
  let type_payload : Array[Byte] = [0x01, 0x40, 0x01, 0x00, 0x7a, 0x00, 0x7a]
  let import_payload = vec_payload([import_entry_func([], 0)])
  let canon_payload = vec_payload([canon_lower_entry(0), canon_lift_entry(0, 0)])
  let export_payload = vec_payload([export_entry_func([], 1)])
  let bytes = build_component([
    (7, type_payload),
    (10, import_payload),
    (8, canon_payload),
    (11, export_payload),
  ])
  let component = @component.parse_component(bytes) catch {
    e => return fail("parse component failed: \{e}")
  }
  let linker = @runtime_impl.ComponentLinker::ComponentLinker()
  let func_type : @component.FuncType = {
    is_async: false,
    params: [{ label: "", ty: Prim(S32) }],
    result: Some(Prim(S32)),
  }
  let host = fn(
    args : Array[@runtime_impl.ComponentValue],
  ) -> Array[@runtime_impl.ComponentValue] raise @runtime_impl.ComponentRuntimeError {
    match args {
      [S32(n)] => [S32(n + 1)]
      _ => raise HostCallError("unexpected args")
    }
  }
  linker.add_func("", func_type, host)
  let validated = @component_model.validate_component_for_instantiation_with_config(
    component,
    @component_model.ComponentValidationConfig(false),
  )
  let instance = linker.instantiate("host_import", validated)
  let results = instance.call_exported_func("", [S32(41)])
  debug_inspect(results, content="[S32(42)]")
}

///|
test "component runtime: canon lift core func" {
  let wat = "(module (func (export \"inc\") (param i32) (result i32) local.get 0 i32.const 1 i32.add))"
  let mod_ = @wat.parse(wat) catch {
    e => return fail("parse wat failed: \{e}")
  }
  let wasm_bytes : Array[Byte] = @encoder.encode(mod_).map(v => v.to_byte())
  let core_instance_payload = vec_payload([core_instance_instantiate(0)])
  let name_inc : Array[Byte] = [b'i', b'n', b'c']
  let alias_payload = vec_payload([alias_core_export_func(0, name_inc)])
  let type_payload : Array[Byte] = [0x01, 0x40, 0x01, 0x00, 0x7a, 0x00, 0x7a]
  let canon_payload = vec_payload([canon_lift_entry(0, 0)])
  let export_payload = vec_payload([export_entry_func(name_inc, 0)])
  let bytes = build_component([
    (1, wasm_bytes),
    (2, core_instance_payload),
    (6, alias_payload),
    (7, type_payload),
    (8, canon_payload),
    (11, export_payload),
  ])
  let component = @component.parse_component(bytes) catch {
    e => return fail("parse component failed: \{e}")
  }
  let linker = @runtime_impl.ComponentLinker::ComponentLinker()
  let validated = @component_model.validate_component_for_instantiation_with_config(
    component,
    @component_model.ComponentValidationConfig(false),
  )
  let instance = linker.instantiate("canon_lift", validated)
  let results = instance.call_exported_func("inc", [S32(41)])
  debug_inspect(results, content="[S32(42)]")
}

///|
test "component runtime: core execution crosses the configured engine seam" {
  let wat = "(module (func (export \"inc\") (param i32) (result i32) local.get 0 i32.const 1 i32.add))"
  let mod_ = @wat.parse(wat) catch {
    e => return fail("parse wat failed: \{e}")
  }
  let wasm_bytes : Array[Byte] = @encoder.encode(mod_).map(v => v.to_byte())
  let core_instance_payload = vec_payload([core_instance_instantiate(0)])
  let name_inc : Array[Byte] = [b'i', b'n', b'c']
  let alias_payload = vec_payload([alias_core_export_func(0, name_inc)])
  let type_payload : Array[Byte] = [0x01, 0x40, 0x01, 0x00, 0x7a, 0x00, 0x7a]
  let canon_payload = vec_payload([canon_lift_entry(0, 0)])
  let export_payload = vec_payload([export_entry_func(name_inc, 0)])
  let bytes = build_component([
    (1, wasm_bytes),
    (2, core_instance_payload),
    (6, alias_payload),
    (7, type_payload),
    (8, canon_payload),
    (11, export_payload),
  ])
  let component = @component.parse_component(bytes) catch {
    e => return fail("parse component failed: \{e}")
  }
  let registrations : Array[(Int, Int)] = []
  let calls : Array[
    (Int, Int, Array[@types.Value], @runtime_impl.CoreExecutionRequest),
  ] = []
  let closes = Ref(0)
  let engine = @runtime_impl.CoreExecutionEngine(
    fn(_store, module_, instance) {
      registrations.push((module_.codes.length(), instance.store_idx))
    },
    fn(
      store,
      instance,
      func_idx,
      args,
      request,
    ) raise @runtime_impl.ComponentRuntimeError {
      calls.push((instance.store_idx, func_idx, args.copy(), request))
      let results = @executor.call_func_by_index(
        store, instance, func_idx, args,
      ) catch {
        e => raise CanonCallError(e.to_string())
      }
      Returned(results)
    },
    close=fn() { closes.val = closes.val + 1 },
  )
  let linker = @runtime_impl.ComponentLinker::with_core_execution_engine(engine)
  let validated = @component_model.validate_component_for_instantiation_with_config(
    component,
    @component_model.ComponentValidationConfig(false),
  )
  let instance = linker.instantiate("engine_seam", validated)
  let results = instance.call_exported_func("inc", [S32(41)])
  linker.close()
  linker.close()
  debug_inspect(
    (registrations, calls, results, closes.val),
    content=(
      #|(
      #|  [(1, 0)],
      #|  [
      #|    (
      #|      0,
      #|      0,
      #|      [I32(41)],
      #|      {
      #|        style: RunToCompletion,
      #|        backend: PreferNative,
      #|        suspension: RunToReturn,
      #|      },
      #|    ),
      #|  ],
      #|  [S32(42)],
      #|  1,
      #|)
    ),
  )
}

///|
test "component runtime: core call style is independent from backend policy" {
  debug_inspect(
    [
      @runtime_impl.CoreExecutionRequest::CoreExecutionRequest(
        RunToCompletion,
        PreferNative,
        RunToReturn,
      ),
      CoreExecutionRequest(CallbackStep, PreferNative, Resumable),
      CoreExecutionRequest(Stackful, PreferNative, Resumable),
      CoreExecutionRequest(RunToCompletion, InterpreterOnly, RunToReturn),
    ],
    content=(
      #|[
      #|  {
      #|    style: RunToCompletion,
      #|    backend: PreferNative,
      #|    suspension: RunToReturn,
      #|  },
      #|  { style: CallbackStep, backend: PreferNative, suspension: Resumable },
      #|  { style: Stackful, backend: PreferNative, suspension: Resumable },
      #|  {
      #|    style: RunToCompletion,
      #|    backend: InterpreterOnly,
      #|    suspension: RunToReturn,
      #|  },
      #|]
    ),
  )
}

///|
test "executor continuation resumes after the suspended instruction" {
  let source =
    #|(module
    #|  (import "host" "suspend" (func $suspend))
    #|  (global $count (mut i32) (i32.const 0))
    #|  (func (export "run") (result i32)
    #|    global.get $count
    #|    i32.const 1
    #|    i32.add
    #|    global.set $count
    #|    call $suspend
    #|    global.get $count
    #|    i32.const 1
    #|    i32.add
    #|    global.set $count
    #|    global.get $count))
  let module_ = @wat.parse(source) catch {
    error => return fail("parse wat failed: \{error}")
  }
  let linker = @runtime.Linker::Linker()
  let attempts = [0]
  linker.add_host_func("host", "suspend", fn(
    _args,
  ) raise @runtime.RuntimeError {
    attempts[0] = attempts[0] + 1
    if attempts[0] == 1 {
      raise Unreachable
    }
    []
  })
  let instance = @executor.instantiate_with_linker(
    linker, "continuation", module_,
  )
  let initial = @executor.call_func_by_index_resumable(
    linker.get_store(),
    instance,
    1,
    [],
    fn(_error) { if attempts[0] == 1 { Some(7L) } else { None } },
  )
  guard initial is Suspended(7L, continuation) else {
    return fail("expected suspended interpreter invocation")
  }
  let resumed = continuation.continue_execution()
  debug_inspect((attempts, resumed), content="([2], Returned([I32(2)]))")
}

///|
test "executor continuation preserves nested calls and control frames" {
  let source =
    #|(module
    #|  (import "host" "suspend" (func $suspend))
    #|  (global $count (mut i32) (i32.const 0))
    #|  (func $nested (result i32)
    #|    global.get $count
    #|    i32.const 1
    #|    i32.add
    #|    global.set $count
    #|    block (result i32)
    #|      call $suspend
    #|      global.get $count
    #|      i32.const 10
    #|      i32.add
    #|    end)
    #|  (func (export "run") (result i32)
    #|    call $nested
    #|    i32.const 2
    #|    i32.mul))
  let module_ = @wat.parse(source) catch {
    error => return fail("parse wat failed: \{error}")
  }
  let linker = @runtime.Linker::Linker()
  let attempts = [0]
  linker.add_host_func("host", "suspend", fn(
    _args,
  ) raise @runtime.RuntimeError {
    attempts[0] = attempts[0] + 1
    if attempts[0] == 1 {
      raise Unreachable
    }
    []
  })
  let instance = @executor.instantiate_with_linker(
    linker, "nested_continuation", module_,
  )
  let initial = @executor.call_func_by_index_resumable(
    linker.get_store(),
    instance,
    2,
    [],
    fn(_error) { if attempts[0] == 1 { Some(11L) } else { None } },
  )
  guard initial is Suspended(11L, continuation) else {
    return fail("expected nested interpreter invocation to suspend")
  }
  let resumed = continuation.continue_execution()
  debug_inspect((attempts, resumed), content="([2], Returned([I32(22)]))")
}

///|
test "executor continuation resumes repeated loop suspensions" {
  let source =
    #|(module
    #|  (import "host" "suspend" (func $suspend))
    #|  (global $count (mut i32) (i32.const 0))
    #|  (func (export "run") (result i32)
    #|    loop
    #|      call $suspend
    #|      global.get $count
    #|      i32.const 1
    #|      i32.add
    #|      global.set $count
    #|      global.get $count
    #|      i32.const 3
    #|      i32.lt_s
    #|      br_if 0
    #|    end
    #|    global.get $count))
  let module_ = @wat.parse(source) catch {
    error => return fail("parse wat failed: \{error}")
  }
  let linker = @runtime.Linker::Linker()
  let attempts = [0]
  linker.add_host_func("host", "suspend", fn(
    _args,
  ) raise @runtime.RuntimeError {
    attempts[0] = attempts[0] + 1
    if attempts[0] % 2 == 1 {
      raise Unreachable
    }
    []
  })
  let instance = @executor.instantiate_with_linker(
    linker, "loop_continuation", module_,
  )
  let mut outcome = @executor.call_func_by_index_resumable(
    linker.get_store(),
    instance,
    1,
    [],
    fn(_error) { if attempts[0] % 2 == 1 { Some(13L) } else { None } },
  )
  let suspensions = [0]
  while outcome is Suspended(_, _) {
    match outcome {
      Suspended(13L, continuation) => {
        suspensions[0] = suspensions[0] + 1
        outcome = continuation.continue_execution()
      }
      _ => return fail("unexpected continuation token")
    }
  }
  debug_inspect(
    (attempts, suspensions, outcome),
    content="([6], [3], Returned([I32(3)]))",
  )
}

///|
test "ordinary interpreter loops remain iterative" {
  let source =
    #|(module
    #|  (func (export "run") (param i32) (result i32)
    #|    loop
    #|      local.get 0
    #|      i32.const 1
    #|      i32.sub
    #|      local.tee 0
    #|      br_if 0
    #|    end
    #|    local.get 0))
  let module_ = @wat.parse(source) catch {
    error => return fail("parse wat failed: \{error}")
  }
  let linker = @runtime.Linker::Linker()
  let instance = @executor.instantiate_with_linker(
    linker, "iterative_loop", module_,
  )
  let result = @executor.call_func_by_index(linker.get_store(), instance, 0, [
    I32(100000),
  ])
  debug_inspect(result, content="[I32(0)]")
}

///|
test "component runtime: canon lower to core func" {
  let name_inc : Array[Byte] = [b'i', b'n', b'c']
  let name_core : Array[Byte] = [b'c', b'o', b'r', b'e']
  let type_payload : Array[Byte] = [0x01, 0x40, 0x01, 0x00, 0x7a, 0x00, 0x7a]
  let import_payload = vec_payload([import_entry_func(name_inc, 0)])
  let canon_payload = vec_payload([canon_lower_entry(0)])
  let export_payload = vec_payload([export_entry_core_func(name_core, 0)])
  let bytes = build_component([
    (7, type_payload),
    (10, import_payload),
    (8, canon_payload),
    (11, export_payload),
  ])
  let component = @component.parse_component(bytes) catch {
    e => return fail("parse component failed: \{e}")
  }
  let linker = @runtime_impl.ComponentLinker::ComponentLinker()
  let func_type : @component.FuncType = {
    is_async: false,
    params: [{ label: "", ty: Prim(S32) }],
    result: Some(Prim(S32)),
  }
  let host = fn(
    args : Array[@runtime_impl.ComponentValue],
  ) -> Array[@runtime_impl.ComponentValue] raise @runtime_impl.ComponentRuntimeError {
    match args {
      [S32(n)] => [S32(n + 1)]
      _ => raise HostCallError("unexpected args")
    }
  }
  linker.add_func("inc", func_type, host)
  let validated = @component_model.validate_component_for_instantiation_with_config(
    component,
    @component_model.ComponentValidationConfig(false),
  )
  let instance = linker.instantiate("canon_lower", validated)
  let exported = instance.get_export("core")
  let core_func = match exported {
    Some(CoreFunc(f)) => f
    _ => return fail("missing core func export")
  }
  let store = linker.get_store()
  let results = @executor.call_func_by_index(
    store,
    core_func.instance,
    core_func.func_idx,
    [I32(41)],
  ) catch {
    e => return fail("call core func failed: \{e}")
  }
  debug_inspect(results, content="[I32(42)]")
}

///|
/// Regression test for ISS-372.
///
/// A component that defines a nested component stores a closure whose
/// `outer_stack` contains the enclosing instance itself — required for
/// `alias outer` resolution, and a deliberate reference cycle that reference
/// counting can never reclaim. Terminal linker close must break the graph,
/// or every such instance survives close along with its imports and their
/// per-function type-space copies. LeakSanitizer measured 45KB retained per
/// instantiation before the release was added.
test "linker close releases nested-component instance graphs" {
  let bytes = @component_text.parse_component_wat(
    (
      #|(component
      #|  (component $inner
      #|    (core module $m (func (export "f") (result i32) (i32.const 7)))
      #|    (core instance $i (instantiate $m))
      #|    (func (export "f") (result u32) (canon lift (core func $i "f"))))
      #|  (instance $one (instantiate $inner))
      #|  (alias export $one "f" (func $f))
      #|  (export "f" (func $f)))
      #|
    ),
  )
  let component = @component.parse_component(bytes)
  let validated = @component_model.validate_component_for_instantiation_with_config(
    component,
    @component_model.ComponentValidationConfig(false),
  )
  let linker = @runtime_impl.ComponentLinker::ComponentLinker()
  let instance = linker.instantiate("nested", validated)
  // The self-cycle exists while the linker is open: the instance's nested
  // component closures carry the instance itself in their outer stacks.
  debug_inspect(instance.components.length() > 0, content="true")
  linker.close()
  // Terminal close breaks the graph so reference counting can reclaim it.
  debug_inspect(
    (
      instance.components.length(),
      instance.instances.length(),
      instance.funcs.length(),
      instance.exports.size(),
    ),
    content="(0, 0, 0, 0)",
  )
}

///|
/// Regression test for the ISS-357 boundary gaps: validation evidence holds
/// an isolated snapshot rebuilt from the component's sections, so mutating
/// the raw component after validation cannot change what the runtime
/// instantiates.
test "component runtime: evidence survives raw component mutation" {
  let bytes = @component_text.parse_component_wat(
    (
      #|(component
      #|  (core module $m (func (export "f") (result i32) (i32.const 7)))
      #|  (core instance $i (instantiate $m))
      #|  (func (export "f") (result u32) (canon lift (core func $i "f"))))
      #|
    ),
  )
  let component = @component.parse_component(bytes)
  let validated = @component_model.validate_component_for_instantiation_with_config(
    component,
    @component_model.ComponentValidationConfig(false),
  )
  // Erase every mutable view reachable through the caller's raw reference.
  component.binary.sections.clear()
  component.core_modules.clear()
  component.core_instances.clear()
  component.core_types.clear()
  component.types.clear()
  component.imports.clear()
  component.exports.clear()
  component.instances.clear()
  component.aliases.clear()
  component.canons.clear()
  component.components.clear()
  // The evidence's own accessor is no alias either: every call returns a
  // fresh isolated copy, so mutating one returned copy cannot change what a
  // later instantiation of the same evidence reads.
  validated.component().binary.sections.clear()
  let linker = @runtime_impl.ComponentLinker::ComponentLinker()
  let instance = linker.instantiate("mutated", validated)
  let results = instance.call_exported_func("f", [])
  debug_inspect(results, content="[U32(7)]")
  linker.close()
}

///|
/// Lifecycle regression: an engine registration callback that closes its own
/// linker must not let the instantiation commit. Registration now holds a
/// lifecycle lease like invoke, so the close defers until the registration
/// returns, the registration refuses to commit into a closing engine, and
/// the instantiation surfaces `Cancelled` instead of registering an instance
/// graph that nothing would ever release.
test "component runtime: close during engine registration cancels instantiation" {
  let bytes = @component_text.parse_component_wat(
    (
      #|(component
      #|  (core module $m (func (export "f") (result i32) (i32.const 7)))
      #|  (core instance $i (instantiate $m))
      #|  (func (export "f") (result u32) (canon lift (core func $i "f"))))
      #|
    ),
  )
  let component = @component.parse_component(bytes)
  let validated = @component_model.validate_component_for_instantiation_with_config(
    component,
    @component_model.ComponentValidationConfig(false),
  )
  let linker_slot : Ref[@runtime_impl.ComponentLinker?] = Ref(None)
  let registrations = Ref(0)
  let engine = @runtime_impl.CoreExecutionEngine(
    fn(_store, _module, _instance) {
      registrations.val = registrations.val + 1
      if linker_slot.val is Some(linker) {
        linker.close()
      }
    },
    fn(
      _store,
      _instance,
      _func_idx,
      _args,
      _request,
    ) raise @runtime_impl.ComponentRuntimeError {
      raise HostCallError("invoke must not run in this test")
    },
  )
  let linker = @runtime_impl.ComponentLinker::with_core_execution_engine(engine)
  linker_slot.val = Some(linker)
  let outcome = try linker.instantiate("closing", validated) catch {
    Cancelled => "cancelled"
    error => "unexpected error: \{error}"
  } noraise {
    _ => "instantiated"
  }
  debug_inspect(outcome, content="\"cancelled\"")
  debug_inspect(registrations.val, content="1")
  // The aborted instantiation must not resurrect state in the closed linker.
  debug_inspect(linker.get_component("closing") is None, content="true")
  // The linker is terminally closed: later instantiations are refused at
  // entry, before any section runs.
  let after_close = try linker.instantiate("after-close", validated) catch {
    Cancelled => "cancelled"
    error => "unexpected error: \{error}"
  } noraise {
    _ => "instantiated"
  }
  debug_inspect(after_close, content="\"cancelled\"")
  debug_inspect(registrations.val, content="1")
}

///|
/// Lifecycle regression: a closed linker refuses instantiation at entry even
/// for a component with no core sections, which previously committed an
/// instance graph into the closed linker.
test "component runtime: closed linker refuses instantiation at entry" {
  let bytes = @component_text.parse_component_wat("(component)")
  let component = @component.parse_component(bytes)
  let validated = @component_model.validate_component_for_instantiation_with_config(
    component,
    @component_model.ComponentValidationConfig(false),
  )
  let linker = @runtime_impl.ComponentLinker::ComponentLinker()
  linker.close()
  let outcome = try linker.instantiate("late", validated) catch {
    Cancelled => "cancelled"
    error => "unexpected error: \{error}"
  } noraise {
    _ => "instantiated"
  }
  debug_inspect(outcome, content="\"cancelled\"")
  debug_inspect(linker.get_component("late") is None, content="true")
  // The import table is equally terminal: `finish_close` released it, so
  // an extern added afterwards would be retained until the linker dies.
  let add_outcome = try linker.add_import("late-value", Value(U32(1))) catch {
    Cancelled => "cancelled"
    error => "unexpected error: \{error}"
  } noraise {
    _ => "added"
  }
  debug_inspect(add_outcome, content="\"cancelled\"")
  debug_inspect(linker.get_import("late-value") is None, content="true")
  // The host runtime slot is terminal too: `finish_close` dropped it, and a
  // runtime installed afterwards would never be released.
  let runtime_outcome = try linker.host_runtime_state() catch {
    Cancelled => "cancelled"
    error => "unexpected error: \{error}"
  } noraise {
    _ => "installed"
  }
  debug_inspect(runtime_outcome, content="\"cancelled\"")
}

///|
/// Ownership regression: closing a linker must not destroy instances it
/// merely borrowed. `finish_close` used to release the graphs of imported
/// instances recursively, so importing linker A's instance into linker B
/// and closing B emptied the instance's exports — later calls through A
/// failed with `UnknownExport`. Close now releases only the instances this
/// linker's own instantiations registered; imports are dropped by clearing
/// the import table, never by touching their state.
test "component runtime: close releases only owned instances" {
  let bytes = @component_text.parse_component_wat(
    (
      #|(component
      #|  (core module $m (func (export "f") (result i32) (i32.const 7)))
      #|  (core instance $i (instantiate $m))
      #|  (func (export "f") (result u32) (canon lift (core func $i "f"))))
      #|
    ),
  )
  let component = @component.parse_component(bytes)
  let validated = @component_model.validate_component_for_instantiation_with_config(
    component,
    @component_model.ComponentValidationConfig(false),
  )
  let linker_a = @runtime_impl.ComponentLinker::ComponentLinker()
  let provider = linker_a.instantiate("provider", validated)
  let linker_b = @runtime_impl.ComponentLinker::ComponentLinker()
  linker_b.add_instance("a", provider)
  linker_b.close()
  // Linker A still owns the instance; its exports must be intact.
  debug_inspect(provider.call_exported_func("f", []), content="[U32(7)]")
  linker_a.close()
  // A's own close is the owning boundary and does release the graph.
  debug_inspect(provider.exports.length(), content="0")
}

///|
/// Lifecycle regression: an instantiation that fails on an open linker must
/// not corrupt anything it had resolved. The abort path releases only the
/// frame's own build state — breaking its `alias outer` cycles — while the
/// imported instance and the linker itself stay fully usable.
test "component runtime: failed instantiation leaves open linker intact" {
  let inner_bytes = @component_text.parse_component_wat(
    (
      #|(component
      #|  (core module $m (func (export "f") (result i32) (i32.const 7)))
      #|  (core instance $i (instantiate $m))
      #|  (func (export "f") (result u32) (canon lift (core func $i "f"))))
      #|
    ),
  )
  let inner = @component.parse_component(inner_bytes)
  let inner_validated = @component_model.validate_component_for_instantiation_with_config(
    inner,
    @component_model.ComponentValidationConfig(false),
  )
  let linker = @runtime_impl.ComponentLinker::ComponentLinker()
  let provider = linker.instantiate("provider", inner_validated)
  linker.add_instance("a", provider)
  // The importing component processes a nested component definition (which
  // creates the `alias outer` cycle the abort path must break) before a core
  // module whose start function traps at runtime.
  let failing_bytes = @component_text.parse_component_wat(
    (
      #|(component
      #|  (import "a" (instance $a (export "f" (func (result u32)))))
      #|  (component $inner
      #|    (core module $m (func (export "g") (result i32) (i32.const 1)))
      #|    (core instance $i (instantiate $m))
      #|    (func (export "g") (result u32) (canon lift (core func $i "g"))))
      #|  (instance $one (instantiate $inner))
      #|  (core module $boom (func $s unreachable) (start $s))
      #|  (core instance $cb (instantiate $boom)))
      #|
    ),
  )
  let failing = @component.parse_component(failing_bytes)
  let failing_validated = @component_model.validate_component_for_instantiation_with_config(
    failing,
    @component_model.ComponentValidationConfig(false),
  )
  // Route root instantiations through a shared host runtime so the frame
  // resource tables of the failing attempts land in one observable map.
  let runtime = linker.host_runtime_state()
  let tables_before = runtime.async_state().resource_tables.size()
  let outcome = try linker.instantiate("failing", failing_validated) catch {
    Cancelled => "cancelled"
    _ => "failed"
  } noraise {
    _ => "instantiated"
  }
  debug_inspect(outcome, content="\"failed\"")
  debug_inspect(linker.get_component("failing") is None, content="true")
  // Registration is transactional: the nested component instance that
  // completed before the trap is rolled back with the root, not left
  // observable in the linker.
  debug_inspect(
    linker.get_component("failing::component0") is None,
    content="true",
  )
  // A second failure must not accumulate resource tables in the shared
  // async state: every aborted frame withdraws its table.
  try linker.instantiate("failing-again", failing_validated) catch {
    _ => ()
  } noraise {
    _ => ()
  }
  debug_inspect(
    runtime.async_state().resource_tables.size() == tables_before,
    content="true",
  )
  // The imported instance the failed frame had resolved is untouched.
  debug_inspect(provider.call_exported_func("f", []), content="[U32(7)]")
  // The linker remains fully usable for later instantiations.
  let again = linker.instantiate("again", inner_validated)
  debug_inspect(again.call_exported_func("f", []), content="[U32(7)]")
  linker.close()
}

///|
/// Regression test for the ISS-357 boundary gaps: a component import enters
/// the linker only as validation evidence. The signature change is the
/// guarantee (a raw component no longer type-checks), and the registered
/// import holds the evidence snapshot, which "evidence survives raw component
/// mutation" above proves is unreachable from the caller's raw reference.
test "component runtime: component import registration requires evidence" {
  let inner_bytes = @component_text.parse_component_wat(
    (
      #|(component
      #|  (core module $m (func (export "f") (result i32) (i32.const 7)))
      #|  (core instance $i (instantiate $m))
      #|  (func (export "f") (result u32) (canon lift (core func $i "f"))))
      #|
    ),
  )
  let inner = @component.parse_component(inner_bytes)
  let inner_validated = @component_model.validate_component_for_instantiation_with_config(
    inner,
    @component_model.ComponentValidationConfig(false),
  )
  let linker = @runtime_impl.ComponentLinker::ComponentLinker()
  linker.add_component("inner", inner_validated)
  debug_inspect(
    linker.get_import("inner") is Some(Component(_)),
    content="true",
  )
  linker.close()
}
