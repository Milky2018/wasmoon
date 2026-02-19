///|
/// Run component-model WAST scripts encoded as JSON commands.

///|
pub suberror ComponentTestError {
  ParseError(String)
  ScriptError(String)
} derive(Show)

///|
priv struct ScriptFile {
  commands : Array[JsonCommand]
} derive(FromJson)

///|
priv struct JsonCommand {
  type_ : String
  name : String?
  component : String?
  path : String?
  instantiate : Bool?
  instance : String?
  field : String?
  args : Array[JsonValue]?
  expected : Array[JsonValue]?
  text : String?
} derive(FromJson(fields(type_(rename="type"))))

///|
priv struct JsonValue {
  type_ : String
  value : String?
  items : Array[JsonValue]?
} derive(FromJson(fields(type_(rename="type"))))

///|
priv struct ScriptResult {
  mut passed : Int
  mut failed : Int
  mut skipped : Int
  failures : Array[String]
}

///|
fn ScriptResult::new() -> ScriptResult {
  { passed: 0, failed: 0, skipped: 0, failures: [] }
}

///|
fn ScriptResult::add_passed(self : ScriptResult) -> Unit {
  self.passed += 1
}

///|
fn ScriptResult::add_failed(self : ScriptResult, msg : String) -> Unit {
  self.failed += 1
  self.failures.push(msg)
}

///|
fn ScriptResult::add_skipped(self : ScriptResult) -> Unit {
  self.skipped += 1
}

///|
fn strip_identifier(name : String) -> String {
  if name.has_prefix("$") && name.length() > 1 {
    let view = try! name[1:]
    view.to_string()
  } else {
    name
  }
}

///|
fn strip_underscores(s : String) -> String {
  let buf = StringBuilder::new()
  for c in s {
    if c != '_' {
      buf.write_char(c)
    }
  }
  buf.to_string()
}

///|
fn parse_int_string(s : String) -> (Bool, StringView, Int) {
  let cleaned = strip_underscores(s)
  let mut negative = false
  let mut view : StringView = cleaned[:]
  if cleaned.has_prefix("-") {
    negative = true
    view = try! cleaned[1:]
  }
  if view.has_prefix("0x") || view.has_prefix("0X") {
    (negative, try! view[2:], 16)
  } else {
    (negative, view, 10)
  }
}

///|
fn parse_signed_int(s : String) -> Int raise ComponentTestError {
  let (negative, digits, base) = parse_int_string(s)
  let n = @strconv.parse_int(digits, base~) catch {
    e => raise ComponentTestError::ParseError(e.to_string())
  }
  if negative {
    -n
  } else {
    n
  }
}

///|
fn parse_unsigned_int(s : String) -> UInt raise ComponentTestError {
  let (negative, digits, base) = parse_int_string(s)
  if negative {
    raise ComponentTestError::ParseError("unsigned value cannot be negative")
  }
  @strconv.parse_uint(digits, base~) catch {
    e => raise ComponentTestError::ParseError(e.to_string())
  }
}

///|
fn parse_signed_int64(s : String) -> Int64 raise ComponentTestError {
  let (negative, digits, base) = parse_int_string(s)
  let n = @strconv.parse_int64(digits, base~) catch {
    e => raise ComponentTestError::ParseError(e.to_string())
  }
  if negative {
    -n
  } else {
    n
  }
}

///|
fn parse_unsigned_int64(s : String) -> UInt64 raise ComponentTestError {
  let (negative, digits, base) = parse_int_string(s)
  if negative {
    raise ComponentTestError::ParseError("unsigned value cannot be negative")
  }
  @strconv.parse_uint64(digits, base~) catch {
    e => raise ComponentTestError::ParseError(e.to_string())
  }
}

///|
fn parse_char_value(s : String) -> Char raise ComponentTestError {
  let mut count = 0
  let mut value : Char = '\u{0}'
  for c in s {
    if count == 0 {
      value = c
    } else {
      raise ComponentTestError::ParseError("char literal must be one codepoint")
    }
    count += 1
  }
  if count == 0 {
    raise ComponentTestError::ParseError("empty char literal")
  }
  value
}

///|
fn parse_component_value(
  val : JsonValue,
) -> @runtime_impl.ComponentValue raise ComponentTestError {
  let kind = val.type_
  let raw = val.value
  match kind {
    "list" => {
      let out : Array[@runtime_impl.ComponentValue] = []
      match val.items {
        Some(items) =>
          for item in items {
            out.push(parse_component_value(item))
          }
        None => ()
      }
      @runtime_impl.ComponentValue::List(out)
    }
    "bool" =>
      @runtime_impl.ComponentValue::Bool(
        @strconv.parse_bool(
          match raw {
            Some(v) => v
            None => raise ComponentTestError::ParseError("missing value")
          },
        ) catch {
          e => raise ComponentTestError::ParseError(e.to_string())
        },
      )
    "u8" =>
      @runtime_impl.ComponentValue::U8(
        parse_unsigned_int(
          match raw {
            Some(v) => v
            None => raise ComponentTestError::ParseError("missing value")
          },
        ).reinterpret_as_int(),
      )
    "s8" =>
      @runtime_impl.ComponentValue::S8(
        parse_signed_int(
          match raw {
            Some(v) => v
            None => raise ComponentTestError::ParseError("missing value")
          },
        ),
      )
    "u16" =>
      @runtime_impl.ComponentValue::U16(
        parse_unsigned_int(
          match raw {
            Some(v) => v
            None => raise ComponentTestError::ParseError("missing value")
          },
        ).reinterpret_as_int(),
      )
    "s16" =>
      @runtime_impl.ComponentValue::S16(
        parse_signed_int(
          match raw {
            Some(v) => v
            None => raise ComponentTestError::ParseError("missing value")
          },
        ),
      )
    "u32" =>
      @runtime_impl.ComponentValue::U32(
        parse_unsigned_int(
          match raw {
            Some(v) => v
            None => raise ComponentTestError::ParseError("missing value")
          },
        ).reinterpret_as_int(),
      )
    "s32" =>
      @runtime_impl.ComponentValue::S32(
        parse_signed_int(
          match raw {
            Some(v) => v
            None => raise ComponentTestError::ParseError("missing value")
          },
        ),
      )
    "u64" =>
      @runtime_impl.ComponentValue::U64(
        parse_unsigned_int64(
          match raw {
            Some(v) => v
            None => raise ComponentTestError::ParseError("missing value")
          },
        ).reinterpret_as_int64(),
      )
    "s64" =>
      @runtime_impl.ComponentValue::S64(
        parse_signed_int64(
          match raw {
            Some(v) => v
            None => raise ComponentTestError::ParseError("missing value")
          },
        ),
      )
    "char" =>
      @runtime_impl.ComponentValue::Char(
        parse_char_value(
          match raw {
            Some(v) => v
            None => raise ComponentTestError::ParseError("missing value")
          },
        ),
      )
    "str" =>
      @runtime_impl.ComponentValue::String(
        match raw {
          Some(v) => v
          None => raise ComponentTestError::ParseError("missing value")
        },
      )
    "string" =>
      @runtime_impl.ComponentValue::String(
        match raw {
          Some(v) => v
          None => raise ComponentTestError::ParseError("missing value")
        },
      )
    _ => raise ComponentTestError::ScriptError("unsupported value type")
  }
}

///|
fn parse_values(
  vals : Array[JsonValue]?,
) -> Array[@runtime_impl.ComponentValue] raise ComponentTestError {
  let result : Array[@runtime_impl.ComponentValue] = []
  if vals is Some(arr) {
    for v in arr {
      result.push(parse_component_value(v))
    }
  }
  result
}

///|
fn values_equal(
  a : Array[@runtime_impl.ComponentValue],
  b : Array[@runtime_impl.ComponentValue],
) -> Bool {
  if a.length() != b.length() {
    return false
  }
  for i in 0..<a.length() {
    if a[i] != b[i] {
      return false
    }
  }
  true
}

///|
fn load_component(
  path : String,
) -> @component.Component raise ComponentTestError {
  let bytes = @fs.read_file_to_bytes(path) catch {
    IOError(e) => raise ComponentTestError::ParseError(e)
  }
  @component.parse_component(bytes) catch {
    e => raise ComponentTestError::ParseError(e.to_string())
  }
}

///|
fn instantiate_component(
  linker : @runtime_impl.ComponentLinker,
  name : String,
  component : @component.Component,
) -> Result[
  @runtime_impl.ComponentInstance,
  @runtime_impl.ComponentRuntimeError,
] {
  try? linker.instantiate(name, component)
}

///|
fn run_invoke(
  instance : @runtime_impl.ComponentInstance,
  field : String,
  args : Array[@runtime_impl.ComponentValue],
) -> Result[
  Array[@runtime_impl.ComponentValue],
  @runtime_impl.ComponentRuntimeError,
] {
  try? instance.call_exported_func(field, args)
}

///|
fn make_const_u32_func(value : Int) -> @runtime_impl.ComponentFunc {
  let func_type : @component.FuncType = {
    is_async: false,
    params: [],
    result: Some(@component.ValType::Prim(@component.PrimValType::U32)),
  }
  let func = fn(
    _args : Array[@runtime_impl.ComponentValue],
  ) -> Array[@runtime_impl.ComponentValue] raise @runtime_impl.ComponentRuntimeError {
    if false {
      raise @runtime_impl.ComponentRuntimeError::HostCallError("unreachable")
    }
    [@runtime_impl.ComponentValue::U32(value)]
  }
  @runtime_impl.ComponentFunc::Host(func_type, [], fn(
    args : Array[@runtime_impl.ComponentValue],
    _table : @runtime_impl.ResourceTable,
  ) -> Array[@runtime_impl.ComponentValue] raise @runtime_impl.ComponentRuntimeError {
    func(args)
  })
}

///|
fn make_instance(
  name : String,
  store : @runtime.Store,
  exports : Map[String, @runtime_impl.ComponentExtern],
) -> @runtime_impl.ComponentInstance {
  let stream_table = @runtime_impl.StreamTable::new()
  let async_state = @runtime_impl.AsyncState::new(stream_table)
  {
    name,
    types: [],
    funcs: [],
    values: [],
    components: [],
    instances: [],
    resource_table: @runtime_impl.ResourceTable::new(),
    stream_table,
    async_state,
    core_modules: [],
    core_instances: [],
    core_funcs: [],
    core_types: [],
    core_tables: [],
    core_mems: [],
    core_globals: [],
    core_tags: [],
    exports,
    store,
  }
}

///|
pub fn run_component_script(path : String) -> Unit {
  let contents = @fs.read_file_to_string(path) catch {
    IOError(e) => {
      println("component-test error: \{e}")
      return
    }
  }
  let json = @json.parse(contents) catch {
    e => {
      println("component-test error: \{e}")
      return
    }
  }
  let script : ScriptFile = @json.from_json(json) catch {
    e => {
      println("component-test error: \{e}")
      return
    }
  }
  let result = ScriptResult::new()
  let linker = @runtime_impl.ComponentLinker::new()
  let store = linker.get_store()
  let return_two = make_const_u32_func(2)
  let return_three = make_const_u32_func(3)
  let return_four = make_const_u32_func(4)
  linker.add_import(
    "host-return-two",
    @runtime_impl.ComponentExtern::Func(return_two),
  )
  let simple_module_wat = "(module (func (export \"f\") (result i32) i32.const 101) (global (export \"g\") i32 (i32.const 100)))"
  let simple_module = @wat.parse(simple_module_wat) catch {
    e => {
      println("component-test error: \{e}")
      return
    }
  }
  let nested_exports : Map[String, @runtime_impl.ComponentExtern] = {}
  nested_exports.set(
    "return-four",
    @runtime_impl.ComponentExtern::Func(return_four),
  )
  let nested_instance = make_instance("host::nested", store, nested_exports)
  let host_exports : Map[String, @runtime_impl.ComponentExtern] = {}
  host_exports.set(
    "return-two",
    @runtime_impl.ComponentExtern::Func(return_two),
  )
  host_exports.set(
    "return-three",
    @runtime_impl.ComponentExtern::Func(return_three),
  )
  host_exports.set(
    "simple-module",
    @runtime_impl.ComponentExtern::CoreModule(simple_module),
  )
  host_exports.set(
    "nested",
    @runtime_impl.ComponentExtern::Instance(nested_instance),
  )

  // Host instance used by component-spec/wasmtime suites.
  let resource1_id = 100
  let resource2_id = 101
  let resource1_type : @component.TypeDef? = Some(
    @component.TypeDef::ResourceType(
      resource1_id,
      0x7f,
      None,
      @component.ResourceKind::HostDefined,
    ),
  )
  let resource2_type : @component.TypeDef? = Some(
    @component.TypeDef::ResourceType(
      resource2_id,
      0x7f,
      None,
      @component.ResourceKind::HostDefined,
    ),
  )
  host_exports.set(
    "resource1",
    @runtime_impl.ComponentExtern::Type(resource1_type),
  )
  host_exports.set(
    "resource2",
    @runtime_impl.ComponentExtern::Type(resource2_type),
  )
  host_exports.set(
    "resource1-again",
    @runtime_impl.ComponentExtern::Type(resource1_type),
  )
  let resource1_drops : Array[Int] = [0]
  let resource1_last_drop : Array[Int] = [0]
  let dtor_core_type : @types.FuncType = {
    params: [@types.ValueType::I32],
    results: [],
  }
  let resource1_dtor = @runtime_impl.alloc_host_core_func(
    store,
    dtor_core_type,
    fn(
      args : Array[@types.Value],
    ) -> Array[@types.Value] raise @runtime.RuntimeError {
      match args {
        [@types.Value::I32(rep)] => {
          resource1_drops[0] = resource1_drops[0] + 1
          resource1_last_drop[0] = rep
          []
        }
        _ => raise @runtime.RuntimeError::Unreachable
      }
    },
  )
  fn resource1_expect_handle(
    table : @runtime_impl.ResourceTable,
    handle : Int,
  ) -> @runtime_impl.ResourceHandle raise @runtime_impl.ComponentRuntimeError {
    match table.get(handle) {
      Some(h) =>
        if h.type_id != resource1_id {
          raise @runtime_impl.ComponentRuntimeError::CanonCallError(
            "handle index \{handle} used with the wrong type",
          )
        } else {
          h
        }
      None =>
        raise @runtime_impl.ComponentRuntimeError::CanonCallError(
          "unknown handle index \{handle}",
        )
    }
  }

  let ctor_types : Array[@component.TypeDef?] = [
    resource1_type,
    Some(@component.TypeDef::Own(0)),
  ]
  let ctor_func_type : @component.FuncType = {
    is_async: false,
    params: [
      { label: "r", ty: @component.ValType::Prim(@component.PrimValType::U32) },
    ],
    result: Some(@component.ValType::TypeIdx(1)),
  }
  let ctor = @runtime_impl.ComponentFunc::Host(ctor_func_type, ctor_types, fn(
    args : Array[@runtime_impl.ComponentValue],
    table : @runtime_impl.ResourceTable,
  ) -> Array[@runtime_impl.ComponentValue] raise @runtime_impl.ComponentRuntimeError {
    match args {
      [@runtime_impl.ComponentValue::U32(rep)] => {
        let handle = table.alloc({
          type_id: resource1_id,
          rep,
          dtor: Some(resource1_dtor),
          kind: @component.ResourceKind::HostDefined,
        })
        [@runtime_impl.ComponentValue::U32(handle)]
      }
      _ =>
        raise @runtime_impl.ComponentRuntimeError::HostCallError(
          "argument type mismatch",
        )
    }
  })
  host_exports.set(
    "[constructor]resource1",
    @runtime_impl.ComponentExtern::Func(ctor),
  )
  let drops_func_type : @component.FuncType = {
    is_async: false,
    params: [],
    result: Some(@component.ValType::Prim(@component.PrimValType::U32)),
  }
  let drops = @runtime_impl.ComponentFunc::Host(drops_func_type, [], fn(
    args : Array[@runtime_impl.ComponentValue],
    _table : @runtime_impl.ResourceTable,
  ) -> Array[@runtime_impl.ComponentValue] raise @runtime_impl.ComponentRuntimeError {
    if args.length() != 0 {
      raise @runtime_impl.ComponentRuntimeError::HostCallError(
        "argument count mismatch",
      )
    }
    [@runtime_impl.ComponentValue::U32(resource1_drops[0])]
  })
  host_exports.set(
    "[static]resource1.drops",
    @runtime_impl.ComponentExtern::Func(drops),
  )
  let last_drop = @runtime_impl.ComponentFunc::Host(drops_func_type, [], fn(
    args : Array[@runtime_impl.ComponentValue],
    _table : @runtime_impl.ResourceTable,
  ) -> Array[@runtime_impl.ComponentValue] raise @runtime_impl.ComponentRuntimeError {
    if args.length() != 0 {
      raise @runtime_impl.ComponentRuntimeError::HostCallError(
        "argument count mismatch",
      )
    }
    [@runtime_impl.ComponentValue::U32(resource1_last_drop[0])]
  })
  host_exports.set(
    "[static]resource1.last-drop",
    @runtime_impl.ComponentExtern::Func(last_drop),
  )
  let assert_types : Array[@component.TypeDef?] = [
    resource1_type,
    Some(@component.TypeDef::Own(0)),
  ]
  let assert_func_type : @component.FuncType = {
    is_async: false,
    params: [
      { label: "r", ty: @component.ValType::TypeIdx(1) },
      {
        label: "rep",
        ty: @component.ValType::Prim(@component.PrimValType::U32),
      },
    ],
    result: None,
  }
  let assert_func = @runtime_impl.ComponentFunc::Host(
    assert_func_type,
    assert_types,
    fn(
      args : Array[@runtime_impl.ComponentValue],
      table : @runtime_impl.ResourceTable,
    ) -> Array[@runtime_impl.ComponentValue] raise @runtime_impl.ComponentRuntimeError {
      match args {
        [
          @runtime_impl.ComponentValue::U32(handle),
          @runtime_impl.ComponentValue::U32(expected),
        ] => {
          let actual = resource1_expect_handle(table, handle)
          // Consume the owned resource.
          table.free(handle) |> ignore
          if actual.rep != expected {
            raise @runtime_impl.ComponentRuntimeError::HostCallError(
              "rep mismatch",
            )
          }
          []
        }
        _ =>
          raise @runtime_impl.ComponentRuntimeError::HostCallError(
            "argument type mismatch",
          )
      }
    },
  )
  host_exports.set(
    "[static]resource1.assert",
    @runtime_impl.ComponentExtern::Func(assert_func),
  )
  let borrow_ty = Some(@component.TypeDef::Borrow(0))
  let simple_types : Array[@component.TypeDef?] = [resource1_type, borrow_ty]
  let simple_func_type : @component.FuncType = {
    is_async: false,
    params: [
      { label: "self", ty: @component.ValType::TypeIdx(1) },
      {
        label: "rep",
        ty: @component.ValType::Prim(@component.PrimValType::U32),
      },
    ],
    result: None,
  }
  let simple = @runtime_impl.ComponentFunc::Host(
    simple_func_type,
    simple_types,
    fn(
      args : Array[@runtime_impl.ComponentValue],
      table : @runtime_impl.ResourceTable,
    ) -> Array[@runtime_impl.ComponentValue] raise @runtime_impl.ComponentRuntimeError {
      match args {
        [
          @runtime_impl.ComponentValue::U32(handle),
          @runtime_impl.ComponentValue::U32(expected),
        ] => {
          let actual = resource1_expect_handle(table, handle)
          if actual.rep != expected {
            raise @runtime_impl.ComponentRuntimeError::HostCallError(
              "rep mismatch",
            )
          }
          []
        }
        _ =>
          raise @runtime_impl.ComponentRuntimeError::HostCallError(
            "argument type mismatch",
          )
      }
    },
  )
  host_exports.set(
    "[method]resource1.simple",
    @runtime_impl.ComponentExtern::Func(simple),
  )
  let take_borrow_func_type : @component.FuncType = {
    is_async: false,
    params: [
      { label: "self", ty: @component.ValType::TypeIdx(1) },
      { label: "b", ty: @component.ValType::TypeIdx(1) },
    ],
    result: None,
  }
  let take_borrow = @runtime_impl.ComponentFunc::Host(
    take_borrow_func_type,
    simple_types,
    fn(
      args : Array[@runtime_impl.ComponentValue],
      table : @runtime_impl.ResourceTable,
    ) -> Array[@runtime_impl.ComponentValue] raise @runtime_impl.ComponentRuntimeError {
      match args {
        [
          @runtime_impl.ComponentValue::U32(a),
          @runtime_impl.ComponentValue::U32(b),
        ] => {
          resource1_expect_handle(table, a) |> ignore
          resource1_expect_handle(table, b) |> ignore
          []
        }
        _ =>
          raise @runtime_impl.ComponentRuntimeError::HostCallError(
            "argument type mismatch",
          )
      }
    },
  )
  host_exports.set(
    "[method]resource1.take-borrow",
    @runtime_impl.ComponentExtern::Func(take_borrow),
  )
  let own_ty = Some(@component.TypeDef::Own(0))
  let take_own_types : Array[@component.TypeDef?] = [
    resource1_type, borrow_ty, own_ty,
  ]
  let take_own_func_type : @component.FuncType = {
    is_async: false,
    params: [
      { label: "self", ty: @component.ValType::TypeIdx(1) },
      { label: "b", ty: @component.ValType::TypeIdx(2) },
    ],
    result: None,
  }
  let take_own = @runtime_impl.ComponentFunc::Host(
    take_own_func_type,
    take_own_types,
    fn(
      args : Array[@runtime_impl.ComponentValue],
      table : @runtime_impl.ResourceTable,
    ) -> Array[@runtime_impl.ComponentValue] raise @runtime_impl.ComponentRuntimeError {
      match args {
        [
          @runtime_impl.ComponentValue::U32(self_handle),
          @runtime_impl.ComponentValue::U32(b_handle),
        ] => {
          resource1_expect_handle(table, self_handle) |> ignore
          if self_handle == b_handle {
            raise @runtime_impl.ComponentRuntimeError::CanonCallError(
              "cannot remove owned resource while borrowed",
            )
          }
          // Consume owned argument.
          match table.free(b_handle) {
            Some(_) => []
            None =>
              raise @runtime_impl.ComponentRuntimeError::CanonCallError(
                "unknown handle index \{b_handle}",
              )
          }
        }
        _ =>
          raise @runtime_impl.ComponentRuntimeError::HostCallError(
            "argument type mismatch",
          )
      }
    },
  )
  host_exports.set(
    "[method]resource1.take-own",
    @runtime_impl.ComponentExtern::Func(take_own),
  )
  let host_instance = make_instance("host", store, host_exports)
  linker.add_instance("host", host_instance)
  let components : Map[String, @component.Component] = {}
  let instances : Map[String, @runtime_impl.ComponentInstance] = {}
  let mut last_component : @component.Component? = None
  let mut last_component_name : String? = None
  let mut last_instance : @runtime_impl.ComponentInstance? = None
  let mut anon_count = 0
  for cmd in script.commands {
    match cmd.type_ {
      "component_definition" => {
        let name = match cmd.name {
          Some(n) => n
          None => {
            result.add_failed("component_definition missing name")
            continue
          }
        }
        let path = match cmd.path {
          Some(p) => p
          None => {
            result.add_failed("component_definition missing path")
            continue
          }
        }
        let component = load_component(path) catch {
          e => {
            result.add_failed("component_definition load failed: \{e}")
            continue
          }
        }
        components.set(name, component)
        linker.add_component(strip_identifier(name), component)
        result.add_passed()
      }
      "component" => {
        let path = match cmd.path {
          Some(p) => p
          None => {
            result.add_failed("component missing path")
            continue
          }
        }
        let component = load_component(path) catch {
          e => {
            result.add_failed("component load failed: \{e}")
            continue
          }
        }
        match cmd.name {
          Some(n) => {
            components.set(n, component)
            linker.add_component(strip_identifier(n), component)
          }
          None => ()
        }
        last_component = Some(component)
        last_component_name = cmd.name
        let should_instantiate = match cmd.instantiate {
          Some(v) => v
          None => true
        }
        if should_instantiate {
          let inst_name = match cmd.name {
            Some(n) => strip_identifier(n)
            None => {
              anon_count += 1
              "component-\{anon_count}"
            }
          }
          match instantiate_component(linker, inst_name, component) {
            Ok(instance) => {
              last_instance = Some(instance)
              match cmd.name {
                Some(n) => {
                  instances.set(n, instance)
                  linker.add_instance(strip_identifier(n), instance)
                }
                None => ()
              }
              result.add_passed()
            }
            Err(e) =>
              result.add_failed(
                "component instantiate failed (\{inst_name}): \{e}",
              )
          }
        } else {
          result.add_passed()
        }
      }
      "component_instance" => {
        let name = match cmd.name {
          Some(n) => n
          None => {
            result.add_failed("component_instance missing name")
            continue
          }
        }
        let comp_name = match cmd.component {
          Some(n) => n
          None => {
            result.add_failed("component_instance missing component")
            continue
          }
        }
        match components.get(comp_name) {
          Some(component) => {
            let inst_name = strip_identifier(name)
            match instantiate_component(linker, inst_name, component) {
              Ok(instance) => {
                instances.set(name, instance)
                linker.add_instance(strip_identifier(name), instance)
                last_instance = Some(instance)
                result.add_passed()
              }
              Err(e) =>
                result.add_failed(
                  "component_instance failed (\{inst_name}): \{e}",
                )
            }
          }
          None => result.add_failed("unknown component \{comp_name}")
        }
      }
      "assert_unlinkable" => {
        let path = match cmd.path {
          Some(p) => p
          None => {
            result.add_failed("assert_unlinkable missing path")
            continue
          }
        }
        let component = load_component(path) catch {
          e => {
            result.add_failed("assert_unlinkable load failed: \{e}")
            continue
          }
        }
        anon_count += 1
        let name = "assert-unlinkable-\{anon_count}"
        match instantiate_component(linker, name, component) {
          Ok(_instance) =>
            result.add_failed("assert_unlinkable unexpectedly instantiated")
          Err(e) =>
            match cmd.text {
              Some(msg) =>
                if e.to_string().contains(msg) ||
                  (
                    msg == "was not found" &&
                    e.to_string().contains("UnknownImport")
                  ) {
                  result.add_passed()
                } else {
                  result.add_failed("assert_unlinkable wrong trap: \{e}")
                }
              None => result.add_passed()
            }
        }
      }
      "invoke" | "assert_return" | "assert_trap" => {
        let field = match cmd.field {
          Some(f) => f
          None => {
            result.add_failed("\{cmd.type_} missing field")
            continue
          }
        }
        let args = parse_values(cmd.args) catch {
          e => {
            result.add_failed("\{cmd.type_} invalid args: \{e}")
            continue
          }
        }
        let instance = match cmd.instance {
          Some(n) =>
            match instances.get(n) {
              Some(i) => i
              None => {
                result.add_failed("unknown instance \{n}")
                continue
              }
            }
          None =>
            match last_instance {
              Some(i) => i
              None =>
                match last_component {
                  Some(c) => {
                    let inst_name = match last_component_name {
                      Some(n) => strip_identifier(n)
                      None => {
                        anon_count += 1
                        "component-\{anon_count}"
                      }
                    }
                    match instantiate_component(linker, inst_name, c) {
                      Ok(i) => {
                        last_instance = Some(i)
                        i
                      }
                      Err(e) => {
                        result.add_failed(
                          "instantiate for invoke failed (\{inst_name}): \{e}",
                        )
                        continue
                      }
                    }
                  }
                  None => {
                    result.add_failed("invoke with no active instance")
                    continue
                  }
                }
            }
        }
        let call_result = run_invoke(instance, field, args)
        match cmd.type_ {
          "invoke" =>
            match call_result {
              Ok(_vals) => result.add_passed()
              Err(e) => result.add_failed("invoke failed: \{e}")
            }
          "assert_return" => {
            let expected = parse_values(cmd.expected) catch {
              e => {
                result.add_failed("assert_return invalid expected: \{e}")
                continue
              }
            }
            match call_result {
              Ok(vals) =>
                if values_equal(vals, expected) {
                  result.add_passed()
                } else {
                  result.add_failed(
                    "assert_return mismatch expected=\{expected} got=\{vals}",
                  )
                }
              Err(e) => result.add_failed("assert_return trapped: \{e}")
            }
          }
          "assert_trap" =>
            match call_result {
              Ok(_vals) =>
                result.add_failed("assert_trap unexpectedly returned")
              Err(e) =>
                match cmd.text {
                  Some(msg) =>
                    if e.to_string().contains(msg) {
                      result.add_passed()
                    } else {
                      result.add_failed("assert_trap wrong trap: \{e}")
                    }
                  None => result.add_passed()
                }
            }
          _ => ()
        }
      }
      _ => result.add_skipped()
    }
  }
  println(
    "RESULT passed=\{result.passed} failed=\{result.failed} skipped=\{result.skipped}",
  )
  for f in result.failures {
    println("FAIL \{f}")
  }
}
