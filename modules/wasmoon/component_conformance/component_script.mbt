///|
/// Run component-model WAST scripts encoded as JSON commands.

///|
priv suberror ComponentTestError {
  ParseError(String)
  ScriptError(String)
} derive(Debug)

///|
priv enum ComponentTestErrorCode {
  CompTestScriptError
  CompTestAssertFailed
  CompTestUnsupportedCommand
}

///|
impl Show for ComponentTestError with fn output(self, logger) {
  logger.write_string(Repr(self).to_string())
}

///|
fn component_test_error_code_string(code : ComponentTestErrorCode) -> String {
  match code {
    CompTestScriptError => "COMP_TEST_SCRIPT_ERROR"
    CompTestAssertFailed => "COMP_TEST_ASSERT_FAILED"
    CompTestUnsupportedCommand => "COMP_TEST_UNSUPPORTED_COMMAND"
  }
}

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
  label : String?
  labels : Array[String]?
} derive(FromJson(fields(type_(rename="type"))))

///|
priv struct ScriptResult {
  mut passed : Int
  mut failed : Int
  skipped : Int
  failures : Array[String]
}

///|
fn ScriptResult::ScriptResult() -> ScriptResult {
  { passed: 0, failed: 0, skipped: 0, failures: [], }
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
fn json_escape_string_component_test(s : String) -> String {
  let buf = StringBuilder::StringBuilder()
  for c in s {
    match c {
      '"' => buf.write_string("\\\"")
      '\\' => buf.write_string("\\\\")
      '\n' => buf.write_string("\\n")
      '\r' => buf.write_string("\\r")
      '\t' => buf.write_string("\\t")
      _ => buf.write_char(c)
    }
  }
  buf.to_string()
}

///|
fn component_test_json(
  ok : Bool,
  code : ComponentTestErrorCode?,
  phase : String,
  detail : String,
  result : ScriptResult?,
) -> String {
  let mut line = "{\"ok\":"
  line = line + (if ok { "true" } else { "false" })
  if code is Some(code) {
    line = line + ",\"code\":\"\{component_test_error_code_string(code)}\""
  }
  line = line + ",\"phase\":\"\{json_escape_string_component_test(phase)}\""
  line = line + ",\"detail\":\"\{json_escape_string_component_test(detail)}\""
  if result is Some(result) {
    line = line + ",\"passed\":\{result.passed}"
    line = line + ",\"failed\":\{result.failed}"
    line = line + ",\"skipped\":\{result.skipped}"
    line = line + ",\"failures\":["
    for i, item in result.failures {
      if i > 0 {
        line = line + ","
      }
      line = line + "\"\{json_escape_string_component_test(item)}\""
    }
    line = line + "]"
  }
  line + "}"
}

///|
fn strip_identifier(name : String) -> String {
  if name.has_prefix("$") && name.length() > 1 {
    let view = name[1:]
    view.to_owned()
  } else {
    name
  }
}

///|
fn strip_underscores(s : String) -> String {
  let buf = StringBuilder::StringBuilder()
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
    view = cleaned[1:]
  }
  if view.has_prefix("0x") || view.has_prefix("0X") {
    (negative, view[2:], 16)
  } else {
    (negative, view, 10)
  }
}

///|
fn parse_signed_int(s : String) -> Int raise ComponentTestError {
  let (negative, digits, base) = parse_int_string(s)
  let n = @string.parse_int(digits, base~) catch {
    e => raise ParseError(e.to_string())
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
    raise ParseError("unsigned value cannot be negative")
  }
  @string.parse_uint(digits, base~) catch {
    e => raise ParseError(e.to_string())
  }
}

///|
fn parse_signed_int64(s : String) -> Int64 raise ComponentTestError {
  let (negative, digits, base) = parse_int_string(s)
  let n = @string.parse_int64(digits, base~) catch {
    e => raise ParseError(e.to_string())
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
    raise ParseError("unsigned value cannot be negative")
  }
  @string.parse_uint64(digits, base~) catch {
    e => raise ParseError(e.to_string())
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
      raise ParseError("char literal must be one codepoint")
    }
    count += 1
  }
  if count == 0 {
    raise ParseError("empty char literal")
  }
  value
}

///|
fn parse_enum_case_tag(s : String) -> Int raise ComponentTestError {
  parse_signed_int(s) catch {
    _ => {
      let mut idx = 0
      let mut acc = 0
      for c in s {
        if idx == 0 {
          if c != 'E' && c != 'e' {
            raise ParseError("unsupported enum case \{s}")
          }
        } else {
          let d = match c {
            '0' => 0
            '1' => 1
            '2' => 2
            '3' => 3
            '4' => 4
            '5' => 5
            '6' => 6
            '7' => 7
            '8' => 8
            '9' => 9
            _ => raise ParseError("unsupported enum case \{s}")
          }
          acc = acc * 10 + d
        }
        idx += 1
      }
      if idx <= 1 {
        raise ParseError("unsupported enum case \{s}")
      }
      acc
    }
  }
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
      List(out)
    }
    "tuple" => {
      let out : Array[@runtime_impl.ComponentValue] = []
      match val.items {
        Some(items) =>
          for item in items {
            out.push(parse_component_value(item))
          }
        None => ()
      }
      Tuple(out)
    }
    "enum" =>
      U32(
        parse_enum_case_tag(
          match raw {
            Some(v) => v
            None => raise ParseError("missing value")
          },
        ),
      )
    "bool" =>
      Bool(
        @string.parse_bool(
          match raw {
            Some(v) => v
            None => raise ComponentTestError::ParseError("missing value")
          },
        ) catch {
          e => raise ParseError(e.to_string())
        },
      )
    "u8" =>
      U8(
        parse_unsigned_int(
          match raw {
            Some(v) => v
            None => raise ParseError("missing value")
          },
        ).reinterpret_as_int(),
      )
    "s8" =>
      S8(
        parse_signed_int(
          match raw {
            Some(v) => v
            None => raise ParseError("missing value")
          },
        ),
      )
    "u16" =>
      U16(
        parse_unsigned_int(
          match raw {
            Some(v) => v
            None => raise ParseError("missing value")
          },
        ).reinterpret_as_int(),
      )
    "s16" =>
      S16(
        parse_signed_int(
          match raw {
            Some(v) => v
            None => raise ParseError("missing value")
          },
        ),
      )
    "u32" =>
      U32(
        parse_unsigned_int(
          match raw {
            Some(v) => v
            None => raise ParseError("missing value")
          },
        ).reinterpret_as_int(),
      )
    "s32" =>
      S32(
        parse_signed_int(
          match raw {
            Some(v) => v
            None => raise ParseError("missing value")
          },
        ),
      )
    "u64" =>
      U64(
        parse_unsigned_int64(
          match raw {
            Some(v) => v
            None => raise ParseError("missing value")
          },
        ).reinterpret_as_int64(),
      )
    "s64" =>
      S64(
        parse_signed_int64(
          match raw {
            Some(v) => v
            None => raise ParseError("missing value")
          },
        ),
      )
    "f32" =>
      F32(
        Float::from_double(
          @string.parse_double(
            match raw {
              Some(v) => v
              None => raise ParseError("missing value")
            },
          ) catch {
            e => raise ParseError(e.to_string())
          },
        ),
      )
    "f64" =>
      F64(
        @string.parse_double(
          match raw {
            Some(v) => v
            None => raise ParseError("missing value")
          },
        ) catch {
          e => raise ParseError(e.to_string())
        },
      )
    "char" =>
      Char(
        parse_char_value(
          match raw {
            Some(v) => v
            None => raise ParseError("missing value")
          },
        ),
      )
    "str" =>
      String(
        match raw {
          Some(v) => v
          None => raise ParseError("missing value")
        },
      )
    "string" =>
      String(
        match raw {
          Some(v) => v
          None => raise ParseError("missing value")
        },
      )
    _ => raise ScriptError("unsupported value type")
  }
}

///|
fn component_func_contract(
  instance : @runtime_impl.ComponentInstance,
  field : String,
) -> (@component_types.FuncType, Array[@component_types.TypeDef?]) raise ComponentTestError {
  match instance.get_export(field) {
    Some(Func(func)) =>
      match func {
        Host(func_type, types, _) | HostAsync(func_type, types, _) =>
          (func_type, types)
        Lifted(_, func_type, _, types, _, _, _, _) => (func_type, types)
      }
    _ => raise ScriptError("unknown exported function \{field}")
  }
}

///|
fn parse_typed_component_value(
  val : JsonValue,
  ty : @component_types.ValType,
  types : Array[@component_types.TypeDef?],
) -> @runtime_impl.ComponentValue raise ComponentTestError {
  match ty {
    Prim(_) => parse_component_value(val)
    TypeIdx(index) => {
      guard types.get(index) is Some(Some(type_def)) else {
        raise ScriptError("unknown component value type \{index}")
      }
      match type_def {
        DefValType(prim) => parse_typed_component_value(val, Prim(prim), types)
        List(element_ty) => {
          if val.type_ != "list" {
            raise ParseError("expected list value")
          }
          let values = []
          if val.items is Some(items) {
            for item in items {
              values.push(parse_typed_component_value(item, element_ty, types))
            }
          }
          List(values)
        }
        FixedList(element_ty, len) => {
          if val.type_ != "list" {
            raise ParseError("expected fixed-length list value")
          }
          let items = val.items.unwrap_or([])
          if items.length() != len {
            raise ParseError("fixed-length list value length mismatch")
          }
          let values = []
          for item in items {
            values.push(parse_typed_component_value(item, element_ty, types))
          }
          List(values)
        }
        MapType(key_ty, value_ty) => {
          if val.type_ != "list" {
            raise ParseError("expected map value")
          }
          let entries = []
          for item in val.items.unwrap_or([]) {
            if item.type_ != "tuple" {
              raise ParseError("expected map entry tuple")
            }
            let pair = item.items.unwrap_or([])
            if pair.length() != 2 {
              raise ParseError("map entry tuple length mismatch")
            }
            entries.push(
              @runtime_impl.ComponentValue::Tuple([
                parse_typed_component_value(pair[0], key_ty, types),
                parse_typed_component_value(pair[1], value_ty, types),
              ]),
            )
          }
          List(entries)
        }
        Tuple(element_types) => {
          if val.type_ != "tuple" {
            raise ParseError("expected tuple value")
          }
          let items = val.items.unwrap_or([])
          if items.length() != element_types.length() {
            raise ParseError("tuple value length mismatch")
          }
          let values = []
          for i in 0..<element_types.length() {
            values.push(
              parse_typed_component_value(items[i], element_types[i], types),
            )
          }
          Tuple(values)
        }
        Record(fields) => {
          if val.type_ != "record" {
            raise ParseError("expected record value")
          }
          let items = val.items.unwrap_or([])
          if items.length() != fields.length() {
            raise ParseError("record value length mismatch")
          }
          let values = []
          for field in fields {
            let mut found : JsonValue? = None
            for item in items {
              if item.label is Some(label) && label == field.label {
                found = Some(item)
                break
              }
            }
            guard found is Some(item) else {
              raise ParseError("missing record field \{field.label}")
            }
            values.push(parse_typed_component_value(item, field.ty, types))
          }
          Tuple(values)
        }
        Variant(cases) => {
          if val.type_ != "variant" {
            raise ParseError("expected variant value")
          }
          guard val.value is Some(label) else {
            raise ParseError("variant value is missing its case")
          }
          let mut tag = -1
          for i, case in cases {
            if case.label == label {
              tag = i
              break
            }
          }
          if tag < 0 {
            raise ParseError("unknown variant case \{label}")
          }
          let items = val.items.unwrap_or([])
          let payload = match cases[tag].ty {
            None => {
              if items.length() != 0 {
                raise ParseError("variant case \{label} has no payload")
              }
              None
            }
            Some(payload_ty) => {
              if items.length() != 1 {
                raise ParseError("variant case \{label} requires one payload")
              }
              Some(parse_typed_component_value(items[0], payload_ty, types))
            }
          }
          Variant(tag, payload)
        }
        Enum(labels) => {
          if val.type_ != "enum" {
            raise ParseError("expected enum value")
          }
          guard val.value is Some(label) else {
            raise ParseError("enum value is missing its case")
          }
          let mut tag = -1
          for i, candidate in labels {
            if candidate == label {
              tag = i
              break
            }
          }
          if tag < 0 {
            tag = parse_enum_case_tag(label)
          }
          if tag < 0 || tag >= labels.length() {
            raise ParseError("unknown enum case \{label}")
          }
          U32(tag)
        }
        Flags(labels) => {
          if val.type_ != "flags" {
            raise ParseError("expected flags value")
          }
          let selected = val.labels.unwrap_or([])
          let mut bits = 0UL
          for label in selected {
            let mut index = -1
            for i, candidate in labels {
              if candidate == label {
                index = i
                break
              }
            }
            if index < 0 {
              raise ParseError("unknown flag \{label}")
            }
            bits = bits | (1UL << index)
          }
          if labels.length() <= 32 {
            U32(bits.to_uint().reinterpret_as_int())
          } else {
            U64(bits.reinterpret_as_int64())
          }
        }
        Option(payload_ty) => {
          if val.type_ != "option" {
            raise ParseError("expected option value")
          }
          let items = val.items.unwrap_or([])
          match val.value {
            Some("none") =>
              if items.length() == 0 {
                Variant(0, None)
              } else {
                raise ParseError("option.none has a payload")
              }
            Some("some") =>
              if items.length() == 1 {
                Variant(
                  1,
                  Some(parse_typed_component_value(items[0], payload_ty, types)),
                )
              } else {
                raise ParseError("option.some requires one payload")
              }
            _ => raise ParseError("unknown option case")
          }
        }
        Result(ok_ty, error_ty) => {
          if val.type_ != "result" {
            raise ParseError("expected result value")
          }
          let (tag, payload_ty) = match val.value {
            Some("ok") => (0, ok_ty)
            Some("err") => (1, error_ty)
            _ => raise ParseError("unknown result case")
          }
          let items = val.items.unwrap_or([])
          let payload = match payload_ty {
            None =>
              if items.length() == 0 {
                None
              } else {
                raise ParseError("result case has no payload")
              }
            Some(payload_ty) =>
              if items.length() == 1 {
                Some(parse_typed_component_value(items[0], payload_ty, types))
              } else {
                raise ParseError("result case requires one payload")
              }
          }
          Variant(tag, payload)
        }
        Own(_) | Borrow(_) | ResourceType(_, _, _, _) =>
          parse_component_value(val)
        Stream(_)
        | Future(_)
        | FuncType(_)
        | ComponentType(_)
        | InstanceTypeEmpty
        | InstanceType(_) =>
          raise ScriptError("unsupported component value type")
      }
    }
  }
}

///|
fn parse_typed_arguments(
  vals : Array[JsonValue]?,
  func_type : @component_types.FuncType,
  types : Array[@component_types.TypeDef?],
) -> Array[@runtime_impl.ComponentValue] raise ComponentTestError {
  let values = vals.unwrap_or([])
  if values.length() != func_type.params.length() {
    raise ParseError("argument count mismatch")
  }
  let result = []
  for i in 0..<values.length() {
    result.push(
      parse_typed_component_value(values[i], func_type.params[i].ty, types),
    )
  }
  result
}

///|
fn parse_typed_results(
  vals : Array[JsonValue]?,
  func_type : @component_types.FuncType,
  types : Array[@component_types.TypeDef?],
) -> Array[@runtime_impl.ComponentValue] raise ComponentTestError {
  let values = vals.unwrap_or([])
  match func_type.result {
    None =>
      if values.length() == 0 {
        []
      } else {
        raise ParseError("result count mismatch")
      }
    Some(result_ty) =>
      if values.length() == 1 {
        [parse_typed_component_value(values[0], result_ty, types)]
      } else {
        raise ParseError("result count mismatch")
      }
  }
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
) -> @component_types.Component raise ComponentTestError {
  let bytes = @fs.read_file_to_bytes(path) catch {
    IOError(e) => raise ParseError(e)
  }
  @component_types.parse_component(bytes) catch {
    e => raise ParseError(e.to_string())
  }
}

///|
/// Produce the validation evidence `ComponentLinker::add_component` requires.
fn component_import_evidence(
  component : @component_types.Component,
) -> Result[@component_model.ValidatedComponent, String] {
  try
    @component_model.validate_component_for_instantiation_with_config(
      component,
      ComponentValidationConfig(false),
    )
  catch {
    e => Err(e.to_string())
  } noraise {
    value => Ok(value)
  }
}

///|
fn instantiate_component(
  linker : @runtime_impl.ComponentLinker,
  name : String,
  component : @component_types.Component,
) -> Result[@runtime_impl.ComponentInstance, String] {
  let validated = try
    @component_model.validate_component_for_instantiation_with_config(
      component,
      ComponentValidationConfig(false),
    )
  catch {
    e => return Err(e.to_string())
  } noraise {
    value => value
  }
  try linker.instantiate(name, validated) catch {
    e => Err(e.to_string())
  } noraise {
    instance => Ok(instance)
  }
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
  try instance.call_exported_func(field, args) catch {
    e => Err(e)
  } noraise {
    values => Ok(values)
  }
}

///|
fn make_const_u32_func(value : Int) -> @runtime_impl.ComponentFunc {
  let func_type : @component_types.FuncType = {
    is_async: false,
    params: [],
    result: Some(Prim(U32)),
  }
  let func = fn(
    _args : Array[@runtime_impl.ComponentValue],
  ) -> Array[@runtime_impl.ComponentValue] raise @runtime_impl.ComponentRuntimeError {
    if false {
      raise HostCallError("unreachable")
    }
    [U32(value)]
  }
  Host(func_type, [], fn(
    args : Array[@runtime_impl.ComponentValue],
    _table : @runtime_impl.ResourceTable,
  ) -> Array[@runtime_impl.ComponentValue] raise @runtime_impl.ComponentRuntimeError {
    func(args)
  })
}

///|
fn make_echo_u32_func() -> @runtime_impl.ComponentFunc {
  let func_type : @component_types.FuncType = {
    is_async: false,
    params: [{ label: "p1", ty: Prim(U32), }],
    result: Some(Prim(U32)),
  }
  Host(func_type, [], fn(
    args : Array[@runtime_impl.ComponentValue],
    _table : @runtime_impl.ResourceTable,
  ) -> Array[@runtime_impl.ComponentValue] raise @runtime_impl.ComponentRuntimeError {
    match args {
      [U32(v)] => [U32(v)]
      _ => raise HostCallError("argument type mismatch")
    }
  })
}

///|
fn make_instance(
  name : String,
  store : @runtime.Store,
  exports : Map[String, @runtime_impl.ComponentExtern],
  host_runtime : @runtime_impl.HostRuntimeState,
) -> @runtime_impl.ComponentInstance {
  {
    name,
    types: [],
    funcs: [],
    values: [],
    components: [],
    instances: [],
    resource_table: host_runtime.resource_table(),
    stream_table: host_runtime.stream_table(),
    async_state: host_runtime.async_state(),
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
fn run_component_script_impl(
  path : String,
  error_format : ComponentTestOutputFormat,
  print_output : Bool,
  use_jit : Bool,
) -> Int {
  let contents = @fs.read_file_to_string(path) catch {
    IOError(e) => {
      if print_output {
        if error_format is Json {
          println(
            component_test_json(
              false,
              Some(CompTestScriptError),
              "load-script",
              e,
              None,
            ),
          )
        } else {
          println("component-test error: \{e}")
        }
      }
      return 1
    }
  }
  let json = @json.parse(contents) catch {
    e => {
      if print_output {
        if error_format is Json {
          println(
            component_test_json(
              false,
              Some(CompTestScriptError),
              "parse-json",
              e.to_string(),
              None,
            ),
          )
        } else {
          println("component-test error: \{e}")
        }
      }
      return 1
    }
  }
  let script : ScriptFile = @json.from_json(json) catch {
    e => {
      if print_output {
        if error_format is Json {
          println(
            component_test_json(
              false,
              Some(CompTestScriptError),
              "decode-json",
              e.to_string(),
              None,
            ),
          )
        } else {
          println("component-test error: \{e}")
        }
      }
      return 1
    }
  }
  let result = ScriptResult::ScriptResult()
  let runtime = ComponentScriptRuntime::new(use_jit)
  defer runtime.close()
  let components = runtime.definitions
  let instances = runtime.instances
  let mut last_component : @component_types.Component? = None
  let mut last_component_name : String? = None
  let mut last_instance : @runtime_impl.ComponentInstance? = None
  let mut anon_count = 0
  let mut has_unsupported_command = false
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
        match component_import_evidence(component) {
          Ok(_) => {
            components.set(name, component)
            result.add_passed()
          }
          Err(e) =>
            result.add_failed("component_definition validation failed: \{e}")
        }
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
          Some(n) => components.set(n, component)
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
          match runtime.instantiate(inst_name, component) {
            Ok(instance) => {
              last_instance = Some(instance)
              match cmd.name {
                Some(n) => instances.set(n, instance)
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
            anon_count += 1
            // Script identifiers may be rebound. Keep the linker-facing
            // instantiation name unique so a later `(component instance $i …)`
            // creates fresh runtime state instead of resolving through the
            // previous `$i` binding.
            let inst_name = "\{strip_identifier(name)}-\{anon_count}"
            match runtime.instantiate(inst_name, component) {
              Ok(instance) => {
                instances.set(name, instance)
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
        match runtime.instantiate(name, component) {
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
                    match runtime.instantiate(inst_name, c) {
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
        let (func_type, func_types) = component_func_contract(instance, field) catch {
          e => {
            result.add_failed("\{cmd.type_} invalid function: \{e}")
            continue
          }
        }
        let args = parse_typed_arguments(cmd.args, func_type, func_types) catch {
          e => {
            result.add_failed("\{cmd.type_} invalid args: \{e}")
            continue
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
            let expected = parse_typed_results(
              cmd.expected,
              func_type,
              func_types,
            ) catch {
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
                    "assert_return \{field} mismatch expected=\{Repr(expected)} got=\{Repr(vals)}",
                  )
                }
              Err(e) => result.add_failed("assert_return trapped: \{e}")
            }
          }
          "assert_trap" =>
            match call_result {
              Ok(_vals) =>
                result.add_failed("assert_trap \{field} unexpectedly returned")
              Err(e) =>
                match cmd.text {
                  Some(msg) =>
                    if component_trap_matches(e.to_string(), msg) {
                      result.add_passed()
                    } else {
                      result.add_failed("assert_trap \{field} wrong trap: \{e}")
                    }
                  None => result.add_passed()
                }
            }
          _ => ()
        }
      }
      _ => {
        has_unsupported_command = true
        result.add_failed("unsupported command type: \{cmd.type_}")
      }
    }
  }
  if print_output {
    if error_format is Json {
      let ok = result.failed == 0 && result.skipped == 0
      println(
        component_test_json(
          ok,
          if ok {
            None
          } else if has_unsupported_command || result.skipped > 0 {
            Some(CompTestUnsupportedCommand)
          } else {
            Some(CompTestAssertFailed)
          },
          "execute",
          if ok {
            "component-test finished successfully"
          } else if has_unsupported_command || result.skipped > 0 {
            "component-test has unsupported commands"
          } else {
            "component-test has failing commands"
          },
          Some(result),
        ),
      )
    } else {
      println(
        "RESULT passed=\{result.passed} failed=\{result.failed} skipped=\{result.skipped}",
      )
      for f in result.failures {
        println("FAIL \{f}")
      }
    }
  }
  if result.failed > 0 || result.skipped > 0 {
    1
  } else {
    0
  }
}

///|
pub fn run_component_script(
  path : String,
  error_format : ComponentTestOutputFormat,
  use_jit? : Bool = true,
) -> Int {
  run_component_script_impl(path, error_format, false, use_jit)
}

///|
pub fn run_component_script_cli(
  path : String,
  error_format : ComponentTestOutputFormat,
  use_jit? : Bool = true,
) -> Int {
  run_component_script_impl(path, error_format, true, use_jit)
}
