///|
// Binary Core guest: store/load the argument, call host.observe, then add one.
const GUEST : Bytes = b"\x00\x61\x73\x6d\x01\x00\x00\x00\x01\x06\x01\x60\x01\x7f\x01\x7f\x02\x10\x01\x04\x68\x6f\x73\x74\x07\x6f\x62\x73\x65\x72\x76\x65\x00\x00\x03\x02\x01\x00\x05\x04\x01\x01\x01\x02\x07\x10\x02\x06\x6d\x65\x6d\x6f\x72\x79\x02\x00\x03\x72\x75\x6e\x00\x01\x0a\x15\x01\x13\x00\x41\x00\x20\x00\x36\x02\x00\x41\x00\x28\x02\x00\x10\x00\x41\x01\x6a\x0b\x00\x11\x04\x6e\x61\x6d\x65\x01\x0a\x01\x00\x07\x6f\x62\x73\x65\x72\x76\x65"

///|
fn run() -> Unit raise {
  let observed = Ref(0)
  let budget = @runtime.ResourceBudget::new(memory_bytes=131072L, instances=2L)
  let store = @runtime.Store(resource_budget=Some(budget))
  defer store.close()
  let linker = @runtime.Linker::with_store(store)
  linker.add_host_func(
    "host",
    "observe",
    args => {
      guard args is [I32(value)] else { raise TypeMismatch }
      observed.val = value
      [I32(value * 2)]
    },
    func_type={ params: [I32], results: [I32], },
  )
  let module_ = store.decode_module(GUEST)
  let validated = @validator.ValidatedModule::new(module_)
  let instance = @executor.instantiate_with_linker(
    linker,
    "guest",
    validated.snapshot(),
  )
  let function = @executor.Function::from_export(store, instance, "run")
  defer function.close()
  let results = function.call([@runtime.RootedValue::i32(21)])
  defer (for value in results {
    value.close()
  })
  assert_eq(results[0].scalar(), I32(43))
  assert_eq(observed.val, 21)
  assert_eq(store.get_mem(instance.mem_addrs[0]).load_i32(0), 21)
  store.close()
  assert_eq(budget.used(MemoryBytes), 0L)
  assert_eq(budget.used(Instances), 0L)
  assert_eq(budget.used(CompilationUnits), 0L)
  println(
    "portable interpreter: result=43, host observed=21, memory=21, budget released",
  )
}

///|
fn main {
  run() catch {
    error => {
      println(error.to_string())
      abort("embedding failed")
    }
  }
}
