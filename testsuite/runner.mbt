// Test Runner for WebAssembly official testsuite
// Parses JSON test format and runs tests against our runtime

///|
/// Test runner error types
pub suberror TestRunnerError {
  ParseError(String)
  ModuleLoadError(String)
} derive(Show)

///|
/// JSON test file structure
priv struct JsonTestFile {
  source_filename : String?
  commands : Array[JsonCommand]
} derive(FromJson)

///|
/// JSON command structure
priv struct JsonCommand {
  type_ : String
  line : Int?
  filename : String?
  name : String?
  as_ : String?
  action : JsonAction?
  expected : Array[JsonValue]?
  text : String?
} derive(FromJson(fields(type_(rename="type"), as_(rename="as"))))

///|
/// JSON action structure
priv struct JsonAction {
  type_ : String
  module_ : String?
  field : String?
  args : Array[JsonValue]?
} derive(FromJson(fields(type_(rename="type"), module_(rename="module"))))

///|
/// JSON value structure
pub(all) struct JsonValue {
  type_ : String
  value : String?
} derive(FromJson(fields(type_(rename="type"))), Show)

///|
/// Test command types from the JSON format
pub enum TestCommand {
  Module(String) // filename
  AssertReturn(TestAction, Array[TestValue])
  AssertTrap(TestAction, String) // action, expected trap message
  AssertInvalid(String, String) // filename, message
  AssertMalformed(String, String) // filename, message
  AssertUninstantiable(String, String) // filename, message
  Register(String, String?) // as, name
  Action(TestAction)
} derive(Show)

///|
/// Test command with line number information
pub struct TestCommandWithLine {
  line : Int?
  command : TestCommand
} derive(Show)

///|
/// Test action types
pub enum TestAction {
  Invoke(String?, String, Array[TestValue]) // module name, field, args
  Get(String?, String) // module name, field
} derive(Show)

///|
/// Test value representation
pub struct TestValue {
  type_ : String
  value : String?
} derive(Show)

///|
/// Test result
pub(all) struct TestResult {
  mut passed : Int
  mut failed : Int
  mut skipped : Int
  failures : Array[String]
  skip_reasons : Array[String]
  mut source_filename : String? // Source .wast filename for better error reporting
} derive(Show)

///|
pub fn TestResult::new() -> TestResult {
  {
    passed: 0,
    failed: 0,
    skipped: 0,
    failures: [],
    skip_reasons: [],
    source_filename: None,
  }
}

///|
/// Increment passed count
pub fn TestResult::add_passed(self : TestResult) -> Unit {
  self.passed += 1
}

///|
/// Increment failed count with source file context
pub fn TestResult::add_failed(self : TestResult, msg : String) -> Unit {
  self.failed += 1
  let full_msg = match self.source_filename {
    Some(filename) => "[\{filename}] \{msg}"
    None => msg
  }
  self.failures.push(full_msg)
}

///|
/// Increment skipped count with reason
pub fn TestResult::add_skipped(self : TestResult, reason : String) -> Unit {
  self.skipped += 1
  let full_reason = match self.source_filename {
    Some(filename) => "[\{filename}] \{reason}"
    None => reason
  }
  self.skip_reasons.push(full_reason)
}

///|
/// Convert Bytes to String (UTF-8)
fn bytes_to_string(bytes : Bytes) -> String {
  let buf = StringBuilder::new()
  for i in 0..<bytes.length() {
    buf.write_char(bytes[i].to_int().unsafe_to_char())
  }
  buf.to_string()
}

///|
/// Parse integer from string with error handling
/// Handles both signed and unsigned representations
fn parse_int_safe(s : String) -> Int {
  // First try parsing as unsigned (for values like 4294967295)
  let uint_result = @strconv.parse_uint(s) catch { _ => 0U }
  if uint_result != 0U {
    return uint_result.reinterpret_as_int()
  }
  // Then try parsing as signed (for negative values or zero)
  @strconv.parse_int(s) catch {
    _ => 0
  }
}

///|
/// Parse int64 from string with error handling
/// Handles both signed and unsigned representations
fn parse_int64_safe(s : String) -> Int64 {
  // First try parsing as unsigned (for large positive values)
  let uint_result = @strconv.parse_uint64(s) catch { _ => 0UL }
  if uint_result != 0UL {
    return uint_result.reinterpret_as_int64()
  }
  // Then try parsing as signed (for negative values or zero)
  @strconv.parse_int64(s) catch {
    _ => 0L
  }
}

///|
/// Convert JsonValue to TestValue
fn json_value_to_test_value(jv : JsonValue) -> TestValue {
  { type_: jv.type_, value: jv.value }
}

///|
/// Convert test value string to runtime Value
pub fn parse_test_value(tv : TestValue) -> @types.Value {
  let val = tv.value.unwrap_or("")
  match tv.type_ {
    "i32" => {
      // Parse as unsigned then reinterpret as signed
      let n = parse_int_safe(val)
      @types.Value::I32(n)
    }
    "i64" => {
      let n = parse_int64_safe(val)
      @types.Value::I64(n)
    }
    "f32" =>
      if val == "nan:canonical" ||
        val == "nan:arithmetic" ||
        val.has_prefix("nan:") {
        @types.Value::F32(0.0 / 0.0) // NaN
      } else {
        // Parse as unsigned bits representation then reinterpret as float
        let bits = @strconv.parse_uint(val) catch { _ => 0U }
        @types.Value::F32(
          Float::reinterpret_from_int(bits.reinterpret_as_int()),
        )
      }
    "f64" =>
      if val == "nan:canonical" ||
        val == "nan:arithmetic" ||
        val.has_prefix("nan:") {
        @types.Value::F64(0.0 / 0.0) // NaN
      } else {
        // Parse as unsigned bits representation then reinterpret as double
        let bits = @strconv.parse_uint64(val) catch { _ => 0UL }
        @types.Value::F64(bits.reinterpret_as_int64().reinterpret_as_double())
      }
    "funcref" =>
      if val == "null" {
        @types.Value::Null
      } else {
        let idx = parse_int_safe(val)
        @types.Value::FuncRef(idx)
      }
    "externref" =>
      if val == "null" {
        @types.Value::Null
      } else {
        let idx = parse_int_safe(val)
        @types.Value::ExternRef(idx)
      }
    _ => @types.Value::I32(0) // fallback
  }
}

///|
/// Compare two runtime values for equality
pub fn values_equal(actual : @types.Value, expected : @types.Value) -> Bool {
  match (actual, expected) {
    (I32(a), I32(e)) => a == e
    (I64(a), I64(e)) => a == e
    (F32(a), F32(e)) =>
      // Handle NaN comparison
      if a.is_nan() && e.is_nan() {
        true
      } else {
        a.reinterpret_as_uint() == e.reinterpret_as_uint()
      }
    (F64(a), F64(e)) =>
      // Handle NaN comparison
      if a.is_nan() && e.is_nan() {
        true
      } else {
        a.reinterpret_as_uint64() == e.reinterpret_as_uint64()
      }
    (Null, Null) => true
    (FuncRef(a), FuncRef(e)) => a == e
    (ExternRef(a), ExternRef(e)) => a == e
    (V128(a), V128(e)) =>
      // Compare all 16 bytes
      if a.length() != e.length() || a.length() != 16 {
        false
      } else {
        let mut equal = true
        for i in 0..<16 {
          if a[i] != e[i] {
            equal = false
            break
          }
        }
        equal
      }
    _ => false
  }
}

///|
/// Convert JsonAction to TestAction
fn json_action_to_test_action(ja : JsonAction) -> TestAction {
  let args = ja.args
    .map(fn(arr) { arr.map(json_value_to_test_value) })
    .unwrap_or([])
  match ja.type_ {
    "invoke" => TestAction::Invoke(ja.module_, ja.field.unwrap_or(""), args)
    "get" => TestAction::Get(ja.module_, ja.field.unwrap_or(""))
    _ => TestAction::Invoke(None, "", [])
  }
}

///|
/// Convert JsonCommand to TestCommandWithLine
fn json_command_to_test_command(
  jc : JsonCommand,
) -> TestCommandWithLine raise TestRunnerError {
  let expected = jc.expected
    .map(fn(arr) { arr.map(json_value_to_test_value) })
    .unwrap_or([])
  let text = jc.text.unwrap_or("")
  let command = match jc.type_ {
    "module" => TestCommand::Module(jc.filename.unwrap_or(""))
    "assert_return" =>
      match jc.action {
        Some(action) =>
          TestCommand::AssertReturn(
            json_action_to_test_action(action),
            expected,
          )
        None => raise ParseError("assert_return missing action")
      }
    "assert_trap" =>
      match jc.action {
        Some(action) =>
          TestCommand::AssertTrap(json_action_to_test_action(action), text)
        None => raise ParseError("assert_trap missing action")
      }
    "assert_invalid" =>
      TestCommand::AssertInvalid(jc.filename.unwrap_or(""), text)
    "assert_malformed" =>
      TestCommand::AssertMalformed(jc.filename.unwrap_or(""), text)
    "assert_unlinkable" =>
      TestCommand::AssertInvalid(jc.filename.unwrap_or(""), text)
    "assert_uninstantiable" =>
      TestCommand::AssertUninstantiable(jc.filename.unwrap_or(""), text)
    "register" => TestCommand::Register(jc.as_.unwrap_or(""), jc.name)
    "action" =>
      match jc.action {
        Some(action) => TestCommand::Action(json_action_to_test_action(action))
        None => raise ParseError("action missing action")
      }
    "assert_exhaustion" =>
      match jc.action {
        Some(action) =>
          TestCommand::AssertTrap(json_action_to_test_action(action), text)
        None => raise ParseError("assert_exhaustion missing action")
      }
    _ => raise ParseError("Unknown command type: \{jc.type_}")
  }
  { line: jc.line, command }
}

///|
/// Parsed test file with source filename and commands
pub struct ParsedTestFile {
  source_filename : String?
  commands : Array[TestCommandWithLine]
}

///|
/// Parse a JSON test file into a list of commands
pub fn parse_json_test_file(
  json_content : String,
) -> ParsedTestFile raise TestRunnerError {
  let json = @json.parse(json_content) catch {
    e => raise ParseError("JSON parse error: \{e}")
  }
  let test_file : JsonTestFile = @json.from_json(json) catch {
    e => raise ParseError("JSON decode error: \{e}")
  }
  let commands : Array[TestCommandWithLine] = []
  for jc in test_file.commands {
    commands.push(json_command_to_test_command(jc))
  }
  { source_filename: test_file.source_filename, commands }
}

///|
/// Run a single test command with line number info and update results
pub fn run_test_command_with_line(
  ctx : TestContext,
  cmd_with_line : TestCommandWithLine,
  result : TestResult,
  base_dir : String,
  read_file_fn : (String) -> Bytes raise Error,
) -> Unit raise TestRunnerError {
  let line_prefix = match cmd_with_line.line {
    Some(n) => "[line \{n}] "
    None => ""
  }
  run_test_command_internal(
    ctx,
    cmd_with_line.command,
    result,
    base_dir,
    read_file_fn,
    line_prefix,
  )
}

///|
/// Run a single test command and update results (without line info)
pub fn run_test_command(
  ctx : TestContext,
  cmd : TestCommand,
  result : TestResult,
  base_dir : String,
  read_file_fn : (String) -> Bytes raise Error,
) -> Unit raise TestRunnerError {
  run_test_command_internal(ctx, cmd, result, base_dir, read_file_fn, "")
}

///|
/// Run a single test command and update results (internal helper with line prefix)
fn run_test_command_internal(
  ctx : TestContext,
  cmd : TestCommand,
  result : TestResult,
  base_dir : String,
  read_file_fn : (String) -> Bytes raise Error,
  line_prefix : String,
) -> Unit raise TestRunnerError {
  match cmd {
    Module(filename) => {
      let wasm_path = base_dir + "/" + filename
      let bytes = read_file_fn(wasm_path) catch {
        e =>
          raise ModuleLoadError(
            "\{line_prefix}Failed to read module \{filename}: \{e}",
          )
      }
      let instance = ctx.load_module(bytes, None) catch {
        e =>
          raise ModuleLoadError(
            "\{line_prefix}Failed to load module \{filename}: \{e}",
          )
      }
      ctx.set_current_module(instance)
    }
    AssertReturn(action, expected) =>
      match action {
        Invoke(module_name, func_name, args) => {
          let success = run_assert_return(
            ctx, module_name, func_name, args, expected,
          )
          if success {
            result.passed += 1
          } else {
            result.failed += 1
            result.failures.push(
              "\{line_prefix}assert_return failed: \{func_name}",
            )
          }
        }
        Get(module_name, field) => {
          // Get global value test
          let expected_values = expected.map(parse_test_value)
          let global_value = ctx.get_global(module_name, field) catch {
            e => {
              println("\{line_prefix}Error getting global \{field}: \{e}")
              result.failed += 1
              result.failures.push(
                "\{line_prefix}assert_return (get) failed: \{field}",
              )
              return
            }
          }
          // Check result
          if expected_values.length() != 1 {
            println(
              "\{line_prefix}Expected 1 value for global, got \{expected_values.length()}",
            )
            result.failed += 1
            result.failures.push(
              "\{line_prefix}assert_return (get) failed: \{field}",
            )
            return
          }
          if !values_equal(global_value, expected_values[0]) {
            println(
              "\{line_prefix}Global \{field} mismatch: expected \{expected_values[0]}, got \{global_value}",
            )
            result.failed += 1
            result.failures.push(
              "\{line_prefix}assert_return (get) failed: \{field}",
            )
          } else {
            result.passed += 1
          }
        }
      }
    AssertTrap(action, expected_msg) =>
      match action {
        Invoke(module_name, func_name, args) => {
          let success = run_assert_trap(
            ctx, module_name, func_name, args, expected_msg,
          )
          if success {
            result.passed += 1
          } else {
            result.failed += 1
            result.failures.push(
              "\{line_prefix}assert_trap failed: \{func_name}",
            )
          }
        }
        Get(_, field) => {
          // assert_trap with get is not used in WebAssembly spec tests
          // If this is triggered, the test file contains non-standard constructs
          result.failed += 1
          result.failures.push(
            "\{line_prefix}assert_trap (get \{field}) is not supported",
          )
        }
      }
    AssertInvalid(filename, _msg) => {
      // Should fail to validate (parse succeeds, but validation fails)
      let wasm_path = base_dir + "/" + filename
      let bytes = read_file_fn(wasm_path) catch {
        _ => {
          // File not found, skip
          result.add_skipped("assert_invalid: file not found: \{filename}")
          return
        }
      }
      if (try? {
          let mod = @parser.parse_module(bytes)
          @validator.validate_module(mod)
        })
        is Err(_) {
        result.passed += 1
      } else {
        result.failed += 1
        result.failures.push(
          "\{line_prefix}assert_invalid should have failed: \{filename}",
        )
      }
    }
    AssertMalformed(filename, _msg) => {
      // Should fail to parse
      let wasm_path = base_dir + "/" + filename
      // Check if it's a WAT file (text format)
      if filename.has_suffix(".wat") {
        // For WAT files, try to read as text and parse
        let bytes = read_file_fn(wasm_path) catch {
          _ => {
            // WAT files with module_type="text" are not generated by wast2json
            result.add_skipped(
              "assert_malformed: WAT file not generated by wast2json: \{filename}",
            )
            return
          }
        }
        // Convert bytes to string for WAT parsing
        let content = bytes_to_string(bytes)
        if (try? @wat.parse(content)) is Err(_) {
          result.passed += 1
        } else {
          result.failed += 1
          result.failures.push(
            "\{line_prefix}assert_malformed should have failed: \{filename}",
          )
        }
      } else {
        // For WASM files, parse as binary
        let bytes = read_file_fn(wasm_path) catch {
          _ => {
            result.add_skipped("assert_malformed: file not found: \{filename}")
            return
          }
        }
        if (try? @parser.parse_module(bytes)) is Err(_) {
          result.passed += 1
        } else {
          result.failed += 1
          result.failures.push(
            "\{line_prefix}assert_malformed should have failed: \{filename}",
          )
        }
      }
    }
    AssertUninstantiable(filename, _msg) => {
      // Should fail to instantiate
      let wasm_path = base_dir + "/" + filename
      let bytes = read_file_fn(wasm_path) catch {
        _ => {
          result.add_skipped(
            "assert_uninstantiable: file not found: \{filename}",
          )
          return
        }
      }
      if (try? ctx.load_module(bytes, None)) is Ok(_) {
        result.failed += 1
        result.failures.push(
          "\{line_prefix}assert_uninstantiable should have failed: \{filename}",
        )
      } else {
        result.passed += 1
      }
    }
    Register(as_, name) =>
      // Register current module with a name
      match ctx.get_current_module() {
        Some(inst) => {
          ctx.named_modules.set(as_, inst)
          if name is Some(n) {
            ctx.named_modules.set(n, inst)
          }
        }
        None =>
          println("\{line_prefix}Warning: Register without current module")
      }
    Action(action) =>
      match action {
        Invoke(module_name, func_name, args) => {
          // Just invoke without checking result
          let runtime_args = args.map(parse_test_value)
          try ctx.invoke(module_name, func_name, runtime_args) |> ignore catch {
            e => println("\{line_prefix}Action invoke error: \{e}")
          }
        }
        Get(_, _) => ()
      }
  }
}

///|
/// Run all tests from a JSON test file
pub fn run_json_tests(
  json_content : String,
  base_dir : String,
  read_file_fn : (String) -> Bytes raise Error,
) -> TestResult raise TestRunnerError {
  let parsed = parse_json_test_file(json_content)
  let result = TestResult::new()
  result.source_filename = parsed.source_filename
  let ctx = TestContext::new()
  for cmd in parsed.commands {
    run_test_command_with_line(ctx, cmd, result, base_dir, read_file_fn)
  }
  result
}
