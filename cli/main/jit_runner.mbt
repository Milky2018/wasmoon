///|
/// JITRunner: Unified abstraction for JIT execution
/// Handles both run_wasm path (with interpreter state) and run_cwasm path (standalone)

///|
/// Configuration for JIT execution from precompiled module (cwasm path)
struct JITConfig {
  // WASI configuration
  wasi_args : Array[String]
  wasi_envs : Array[String]
  wasi_preopens : Array[(String, String)]
  // Memory configuration (from PrecompiledModule)
  memories : Array[@cwasm.MemoryDef]
  data_segments : Array[@cwasm.DataEntry]
  // Function signatures for proper result conversion
  func_signatures : Array[(Array[@types.ValueType], Array[@types.ValueType])]
  // Stack size (default 16MB)
  wasm_stack_size : Int64
}

///|
fn JITConfig::new() -> JITConfig {
  {
    wasi_args: [],
    wasi_envs: [],
    wasi_preopens: [],
    memories: [],
    data_segments: [],
    func_signatures: [],
    wasm_stack_size: 16L * 1024L * 1024L,
  }
}

///|
fn JITConfig::with_wasi(
  self : JITConfig,
  args : Array[String],
  envs : Array[String],
  preopens : Array[(String, String)],
) -> JITConfig {
  { ..self, wasi_args: args, wasi_envs: envs, wasi_preopens: preopens }
}

///|
fn JITConfig::with_memories(
  self : JITConfig,
  memories : Array[@cwasm.MemoryDef],
  data_segments : Array[@cwasm.DataEntry],
) -> JITConfig {
  { ..self, memories, data_segments }
}

///|
fn JITConfig::with_signatures(
  self : JITConfig,
  signatures : Array[(Array[@types.ValueType], Array[@types.ValueType])],
) -> JITConfig {
  { ..self, func_signatures: signatures }
}

///|
/// JITRunner encapsulates JIT module execution
struct JITRunner {
  jit_module : @jit.JITModule
  // Optional interpreter state (None for cwasm fast path)
  instance : @runtime.ModuleInstance?
  store : @runtime.Store?
  // Configuration for cwasm path
  config : JITConfig
}

///|
/// Create JITRunner from PrecompiledModule (cwasm path)
fn JITRunner::from_precompiled(
  precompiled : @cwasm.PrecompiledModule,
  config : JITConfig,
) -> JITRunner? {
  let jit_module = @jit.JITModule::load(precompiled, config.func_signatures)
  match jit_module {
    Some(jm) => Some({ jit_module: jm, instance: None, store: None, config })
    None => None
  }
}

///|
/// Create JITRunner from Module with interpreter state (wasm path)
fn JITRunner::from_module_with_instance(
  precompiled : @cwasm.PrecompiledModule,
  instance : @runtime.ModuleInstance,
  store : @runtime.Store,
  func_signatures : Array[(Array[@types.ValueType], Array[@types.ValueType])],
  debug_db : @jit.JITDebugDB?,
) -> JITRunner? {
  let jit_module = @jit.JITModule::load(precompiled, func_signatures, debug_db~)
  match jit_module {
    Some(jm) => {
      let config = JITConfig::new()
      Some({
        jit_module: jm,
        instance: Some(instance),
        store: Some(store),
        config,
      })
    }
    None => None
  }
}

///|
/// Allocate WASM stack with guard page
fn JITRunner::alloc_wasm_stack(self : JITRunner) -> Bool {
  self.jit_module.alloc_wasm_stack(self.config.wasm_stack_size)
}

///|
/// Initialize WASI context
fn JITRunner::init_wasi(
  self : JITRunner,
  args : Array[String],
  envs : Array[String],
  preopens : Array[(String, String)],
) -> Unit {
  self.jit_module.init_wasi(args, envs, preopens)
}

///|
/// Initialize memories from config (cwasm path)
fn JITRunner::init_memories_from_config(self : JITRunner) -> Bool {
  if self.config.memories.is_empty() {
    return true
  }
  let mem_def = self.config.memories[0]
  let mem_pages = mem_def.min_pages
  let max_pages = mem_def.max_pages
  let mem_size = mem_pages.to_int64() * 65536L
  // Use guarded allocation for bounds check elimination
  let mem_ptr = self.jit_module.alloc_guarded_memory(mem_pages, max_pages)
  if mem_ptr == 0L && mem_size > 0L {
    return false
  }
  self.jit_module.set_memory(mem_ptr, mem_size)
  // Initialize data segments
  for data in self.config.data_segments {
    let data_bytes = Bytes::from_iter(
      data.data.iter().map(fn(b) { b.to_byte() }),
    )
    if not(@jit.memory_init(mem_ptr, data.offset.to_int64(), data_bytes)) {
      return false
    }
  }
  true
}

///|
/// Initialize memories from interpreter state (wasm path)
fn JITRunner::init_memories_from_instance(self : JITRunner) -> Bool {
  let instance = match self.instance {
    Some(i) => i
    None => return false
  }
  let store = match self.store {
    Some(s) => s
    None => return false
  }
  if instance.mem_addrs.is_empty() {
    return true
  }
  let memories : Array[@jit.MemoryInfo] = []
  for i, mem_addr in instance.mem_addrs {
    let mem = store.get_mem(mem_addr) catch { _ => return false }
    let pages = mem.size_pages()
    let size = pages.to_int64() * 65536L
    let (_, max) = mem.get_limits()
    // Use guarded memory for memory 0 (memory32 only)
    let mem_ptr = if i == 0 && not(mem.is_memory64()) {
      self.jit_module.alloc_guarded_memory(pages, max)
    } else {
      @jit.alloc_memory(size)
    }
    if mem_ptr == 0L && size > 0L {
      return false
    }
    // Copy interpreter memory to JIT memory
    copy_memory_to_jit(store, mem_addr, mem_ptr)
    memories.push(@jit.MemoryInfo::new(mem_ptr, size, max))
  }
  self.jit_module.set_memory_pointers(memories)
  if memories.length() > 0 {
    self.jit_module.set_memory(memories[0].ptr, memories[0].size)
  }
  true
}

///|
/// Copy interpreter memory to JIT memory
fn copy_memory_to_jit(
  store : @runtime.Store,
  mem_addr : Int,
  jit_mem_ptr : Int64,
) -> Unit {
  let mem = store.get_memory(mem_addr)
  let size = mem.size_pages() * 65536
  if size > 0 {
    let data = mem.read_bytes(0, size)
    @jit.memory_init(jit_mem_ptr, 0L, data) |> ignore
  }
}

///|
/// Call a function by name and return results
/// Returns None if function not found, Some(results) on success
/// Raises JITTrap on execution errors
fn JITRunner::call(
  self : JITRunner,
  func_name : String,
  args : Array[@types.Value],
) -> Array[@types.Value]? raise @jit.JITTrap {
  let jit_func = self.jit_module.get_func_by_name(func_name)
  match jit_func {
    Some(f) => {
      let i64_args = convert_args_to_jit(args)
      let results = self.jit_module.call_with_context(f, i64_args) catch {
        trap => raise trap
      }
      Some(convert_jit_results(results, f.result_types))
    }
    None => None
  }
}

///|
/// Get the underlying JIT module (for advanced operations)
fn JITRunner::get_jit_module(self : JITRunner) -> @jit.JITModule {
  self.jit_module
}
