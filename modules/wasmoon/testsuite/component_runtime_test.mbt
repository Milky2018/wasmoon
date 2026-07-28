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
test "component runtime: host import export" {
  let type_payload : Array[Byte] = [0x01, 0x40, 0x01, 0x00, 0x7a, 0x00, 0x7a]
  let import_payload = vec_payload([import_entry_func([], 0)])
  let export_payload = vec_payload([export_entry_func([], 0)])
  let bytes = build_component([
    (7, type_payload),
    (10, import_payload),
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
  let instance = linker.instantiate("host_import", component)
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
  let instance = linker.instantiate("canon_lift", component)
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
  )
  let linker = @runtime_impl.ComponentLinker::with_core_execution_engine(engine)
  let instance = linker.instantiate("engine_seam", component)
  let results = instance.call_exported_func("inc", [S32(41)])
  debug_inspect(
    (registrations, calls, results),
    content=(
      #|(
      #|  [(1, 0)],
      #|  [(0, 0, [I32(41)], { style: RunToCompletion, backend: PreferNative })],
      #|  [S32(42)],
      #|)
    ),
  )
}

///|
test "component runtime: core call style is independent from backend policy" {
  debug_inspect(
    [
      @runtime_impl.CoreExecutionRequest(RunToCompletion, PreferNative),
      @runtime_impl.CoreExecutionRequest(CallbackStep, PreferNative),
      @runtime_impl.CoreExecutionRequest(Stackful, PreferNative),
      @runtime_impl.CoreExecutionRequest(RunToCompletion, InterpreterOnly),
    ],
    content=(
      #|[
      #|  { style: RunToCompletion, backend: PreferNative },
      #|  { style: CallbackStep, backend: PreferNative },
      #|  { style: Stackful, backend: PreferNative },
      #|  { style: RunToCompletion, backend: InterpreterOnly },
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
  let instance = linker.instantiate("canon_lower", component)
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
