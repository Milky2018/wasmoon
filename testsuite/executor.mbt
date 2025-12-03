// Test Executor for wasm-testsuite
// This file implements the test runner that reads JSON spec tests and runs them

///|
/// Test context maintains state across test commands
pub struct TestContext {
  store : @runtime.Store
  linker : @runtime.Linker
  mut current_module : @runtime.ModuleInstance?
  named_modules : Map[String, @runtime.ModuleInstance]
}

///|
pub fn TestContext::new() -> TestContext {
  let linker = @runtime.Linker::new()
  { store: linker.get_store(), linker, current_module: None, named_modules: {} }
}

///|
/// Set current module
pub fn TestContext::set_current_module(
  self : TestContext,
  instance : @runtime.ModuleInstance,
) -> Unit {
  self.current_module = Some(instance)
}

///|
/// Get current module
pub fn TestContext::get_current_module(
  self : TestContext,
) -> @runtime.ModuleInstance? {
  self.current_module
}

///|
/// Load a wasm module from bytes
pub fn TestContext::load_module(
  self : TestContext,
  bytes : Bytes,
  name : String?,
) -> @runtime.ModuleInstance raise Error {
  let mod = @parser.parse_module(bytes)
  let instance = @executor.instantiate_with_linker(
    self.linker,
    name.unwrap_or("$current"),
    mod,
  )
  instance
}

///|
/// Invoke a function on the current module
pub fn TestContext::invoke(
  self : TestContext,
  module_name : String?,
  func_name : String,
  args : Array[@types.Value],
) -> Array[@types.Value] raise Error {
  let instance = match module_name {
    Some(name) =>
      match self.named_modules.get(name) {
        Some(inst) => inst
        None =>
          match self.linker.get_module(name) {
            Some(inst) => inst
            None => fail("Module not found: \{name}")
          }
      }
    None =>
      match self.current_module {
        Some(inst) => inst
        None => fail("No current module")
      }
  }
  let results = @executor.call_exported_func(
    self.store,
    instance,
    func_name,
    args,
  )
  results
}

///|
/// Run a single assert_return test
pub fn run_assert_return(
  ctx : TestContext,
  module_name : String?,
  func_name : String,
  args : Array[TestValue],
  expected : Array[TestValue],
) -> Bool {
  // Convert test values to runtime values
  let runtime_args = args.map(parse_test_value)
  let expected_values = expected.map(parse_test_value)
  // Try to invoke
  let results = ctx.invoke(module_name, func_name, runtime_args) catch {
    e => {
      println("Error invoking \{func_name}: \{e}")
      return false
    }
  }
  // Check results
  if results.length() != expected_values.length() {
    println(
      "Result count mismatch: expected \{expected_values.length()}, got \{results.length()}",
    )
    return false
  }
  for i in 0..<results.length() {
    if !values_equal(results[i], expected_values[i]) {
      println(
        "Result \{i} mismatch: expected \{expected_values[i]}, got \{results[i]}",
      )
      return false
    }
  }
  true
}

///|
/// Run a single assert_trap test
pub fn run_assert_trap(
  ctx : TestContext,
  module_name : String?,
  func_name : String,
  args : Array[TestValue],
  _expected_msg : String,
) -> Bool {
  let runtime_args = args.map(parse_test_value)
  // Should trap
  (try? ctx.invoke(module_name, func_name, runtime_args)) is Err(_)
}

///|
/// Get an exported global value
pub fn TestContext::get_global(
  self : TestContext,
  module_name : String?,
  global_name : String,
) -> @types.Value raise Error {
  let instance = match module_name {
    Some(name) =>
      match self.named_modules.get(name) {
        Some(inst) => inst
        None =>
          match self.linker.get_module(name) {
            Some(inst) => inst
            None => fail("Module not found: \{name}")
          }
      }
    None =>
      match self.current_module {
        Some(inst) => inst
        None => fail("No current module")
      }
  }
  @executor.get_exported_global(self.store, instance, global_name)
}
