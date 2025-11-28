// Test Runner for WebAssembly official testsuite
// Parses JSON test format and runs tests against our runtime

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
pub struct TestResult {
  passed : Int
  failed : Int
  skipped : Int
  failures : Array[String]
} derive(Show)

///|
pub fn TestResult::new() -> TestResult {
  { passed: 0, failed: 0, skipped: 0, failures: [] }
}

///|
/// Parse integer from string with error handling
fn parse_int_safe(s : String) -> Int {
  try {
    @strconv.parse_int(s)
  } catch {
    _ => 0
  }
}

///|
/// Parse int64 from string with error handling
fn parse_int64_safe(s : String) -> Int64 {
  try {
    @strconv.parse_int64(s)
  } catch {
    _ => 0L
  }
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
    "f32" => {
      if val == "nan:canonical" || val == "nan:arithmetic" || val.has_prefix("nan:") {
        @types.Value::F32(0.0 / 0.0) // NaN
      } else {
        // Parse as bits representation
        let bits = parse_int_safe(val)
        @types.Value::F32(bits.reinterpret_as_float())
      }
    }
    "f64" => {
      if val == "nan:canonical" || val == "nan:arithmetic" || val.has_prefix("nan:") {
        @types.Value::F64(0.0 / 0.0) // NaN
      } else {
        // Parse as bits representation
        let bits = parse_int64_safe(val)
        @types.Value::F64(bits.reinterpret_as_double())
      }
    }
    "funcref" => {
      if val == "null" {
        @types.Value::Null
      } else {
        let idx = parse_int_safe(val)
        @types.Value::FuncRef(idx)
      }
    }
    "externref" => {
      if val == "null" {
        @types.Value::Null
      } else {
        let idx = parse_int_safe(val)
        @types.Value::ExternRef(idx)
      }
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
    (F32(a), F32(e)) => {
      // Handle NaN comparison
      if a.is_nan() && e.is_nan() {
        true
      } else {
        a.reinterpret_as_uint() == e.reinterpret_as_uint()
      }
    }
    (F64(a), F64(e)) => {
      // Handle NaN comparison
      if a.is_nan() && e.is_nan() {
        true
      } else {
        a.reinterpret_as_uint64() == e.reinterpret_as_uint64()
      }
    }
    (Null, Null) => true
    (FuncRef(a), FuncRef(e)) => a == e
    (ExternRef(a), ExternRef(e)) => a == e
    _ => false
  }
}
