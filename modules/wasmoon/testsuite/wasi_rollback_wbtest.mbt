///|
fn wasi_memory_selection_fixture() -> (@runtime.Linker, @runtime.ModuleInstance) raise {
  let linker = @runtime.Linker::Linker()
  let wasi_ctx = @wasi.WasiContextBuilder::WasiContextBuilder()
    .args(["wasmoon", "argument"])
    .build()
  @wasi.register_wasi(linker, wasi_ctx)
  @executor.instantiate_with_linker(
    linker,
    "foreign",
    @wat.parse(
      (
        #|(module (memory (export "memory") 1))
      ),
    ),
  )
  |> ignore
  let old_instance = @executor.instantiate_with_linker(
    linker,
    "old",
    @wat.parse(
      (
        #|(module
        #|  (import "wasi_snapshot_preview1" "args_sizes_get"
        #|    (func $args_sizes_get (param i32 i32) (result i32)))
        #|  (memory (export "memory") 1)
        #|  (func (export "probe") (result i32)
        #|    (i32.store (i32.const 0) (i32.const -1))
        #|    (i32.store (i32.const 4) (i32.const -1))
        #|    (drop (call $args_sizes_get (i32.const 0) (i32.const 4)))
        #|    (i32.load (i32.const 0))))
        #|
      ),
    ),
  )
  (linker, old_instance)
}

///|
fn assert_old_wasi_instance_usable_after_start_trap(
  failing_source : String,
  name : String,
) -> Unit raise {
  let (linker, old_instance) = wasi_memory_selection_fixture()
  let store = linker.get_store()
  debug_inspect(
    @executor.call_exported_func(store, old_instance, "probe", []),
    content="[I32(2)]",
  )
  let transaction = @runtime.InstantiationTransaction::new()
  linker.register_rollback(transaction.registrar())
  try
    @executor.instantiate_with_linker(linker, name, @wat.parse(failing_source))
  catch {
    _ => ()
  } noraise {
    _ => fail("expected start to trap")
  }
  transaction.rollback()
  debug_inspect(
    @executor.call_exported_func(store, old_instance, "probe", []),
    content="[I32(2)]",
  )
  linker.close()
}

///|
test "WASI memory selection survives owned-memory start trap rollback" {
  assert_old_wasi_instance_usable_after_start_trap(
    (
      #|(module
      #|  (memory 1)
      #|  (func $start unreachable)
      #|  (start $start))
      #|
    ),
    "owned-memory-trap",
  )
}

///|
test "WASI memory selection survives imported-memory start trap rollback" {
  assert_old_wasi_instance_usable_after_start_trap(
    (
      #|(module
      #|  (import "foreign" "memory" (memory 1))
      #|  (func $start unreachable)
      #|  (start $start))
      #|
    ),
    "imported-memory-trap",
  )
}
