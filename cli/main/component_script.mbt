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
) -> @component.ComponentValue raise ComponentTestError {
  let kind = val.type_
  let raw = match val.value {
    Some(v) => v
    None => raise ComponentTestError::ParseError("missing value")
  }
  match kind {
    "bool" =>
      @component.ComponentValue::Bool(
        @strconv.parse_bool(raw) catch {
          e => raise ComponentTestError::ParseError(e.to_string())
        },
      )
    "u8" =>
      @component.ComponentValue::U8(
        parse_unsigned_int(raw).reinterpret_as_int(),
      )
    "s8" => @component.ComponentValue::S8(parse_signed_int(raw))
    "u16" =>
      @component.ComponentValue::U16(
        parse_unsigned_int(raw).reinterpret_as_int(),
      )
    "s16" => @component.ComponentValue::S16(parse_signed_int(raw))
    "u32" =>
      @component.ComponentValue::U32(
        parse_unsigned_int(raw).reinterpret_as_int(),
      )
    "s32" => @component.ComponentValue::S32(parse_signed_int(raw))
    "u64" =>
      @component.ComponentValue::U64(
        parse_unsigned_int64(raw).reinterpret_as_int64(),
      )
    "s64" => @component.ComponentValue::S64(parse_signed_int64(raw))
    "char" => @component.ComponentValue::Char(parse_char_value(raw))
    "str" => @component.ComponentValue::String(raw)
    "string" => @component.ComponentValue::String(raw)
    _ => raise ComponentTestError::ScriptError("unsupported value type")
  }
}

///|
fn parse_values(
  vals : Array[JsonValue]?,
) -> Array[@component.ComponentValue] raise ComponentTestError {
  let result : Array[@component.ComponentValue] = []
  match vals {
    Some(arr) =>
      for v in arr {
        result.push(parse_component_value(v))
      }
    None => ()
  }
  result
}

///|
fn values_equal(
  a : Array[@component.ComponentValue],
  b : Array[@component.ComponentValue],
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
  linker : @component.ComponentLinker,
  name : String,
  component : @component.Component,
) -> Result[@component.ComponentInstance, @component.ComponentRuntimeError] {
  try? linker.instantiate(name, component)
}

///|
fn run_invoke(
  instance : @component.ComponentInstance,
  field : String,
  args : Array[@component.ComponentValue],
) -> Result[Array[@component.ComponentValue], @component.ComponentRuntimeError] {
  try? instance.call_exported_func(field, args)
}

///|
fn make_const_u32_func(value : Int) -> @component.ComponentFunc {
  let func_type : @component.FuncType = {
    is_async: false,
    params: [],
    result: Some(@component.ValType::Prim(@component.PrimValType::U32)),
  }
  let func = fn(
    _args : Array[@component.ComponentValue],
  ) -> Array[@component.ComponentValue] raise @component.ComponentRuntimeError {
    if false {
      raise @component.ComponentRuntimeError::HostCallError("unreachable")
    }
    [@component.ComponentValue::U32(value)]
  }
  @component.ComponentFunc::Host(func_type, func)
}

///|
fn make_instance(
  name : String,
  store : @runtime.Store,
  exports : Map[String, @component.ComponentExtern],
) -> @component.ComponentInstance {
  {
    name,
    types: [],
    funcs: [],
    values: [],
    components: [],
    instances: [],
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
  let linker = @component.ComponentLinker::new()
  let store = linker.get_store()
  let return_two = make_const_u32_func(2)
  let return_three = make_const_u32_func(3)
  let return_four = make_const_u32_func(4)
  linker.add_import(
    "host-return-two",
    @component.ComponentExtern::Func(return_two),
  )
  let simple_module_wat = "(module (func (export \"f\") (result i32) i32.const 101) (global (export \"g\") i32 (i32.const 100)))"
  let simple_module = @wat.parse(simple_module_wat) catch {
    e => {
      println("component-test error: \{e}")
      return
    }
  }
  let nested_exports : Map[String, @component.ComponentExtern] = {}
  nested_exports.set(
    "return-four",
    @component.ComponentExtern::Func(return_four),
  )
  let nested_instance = make_instance("host::nested", store, nested_exports)
  let host_exports : Map[String, @component.ComponentExtern] = {}
  host_exports.set("return-two", @component.ComponentExtern::Func(return_two))
  host_exports.set(
    "return-three",
    @component.ComponentExtern::Func(return_three),
  )
  host_exports.set(
    "simple-module",
    @component.ComponentExtern::CoreModule(simple_module),
  )
  host_exports.set(
    "nested",
    @component.ComponentExtern::Instance(nested_instance),
  )
  let host_instance = make_instance("host", store, host_exports)
  linker.add_instance("host", host_instance)
  let components : Map[String, @component.Component] = {}
  let instances : Map[String, @component.ComponentInstance] = {}
  let mut last_component : @component.Component? = None
  let mut last_component_name : String? = None
  let mut last_instance : @component.ComponentInstance? = None
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
