///|
test "DWARF lookup matches installed guest ranges through callable wrappers" {
  let module_ = @wat.parse(
    "(module (import \"h\" \"f\" (func)) (memory 1) (func (export \"leaf\") i32.const 65536 i32.load drop) (func (export \"run\") call 1))",
  )
  let store = @runtime.Store::with_c_heap()
  defer store.close()
  let imports = @runtime.Imports(store)
  imports.add_func("h", "f", store.alloc_host_func(_ => []))
  let instance = @executor.instantiate_module_with_imports(
    store, module_, imports,
  )
  let context = prepare_async_jit_context(
    module_,
    instance,
    store,
    cooperative=true,
  )
  defer context.close()
  let dwarf = context.jit_module.register_dwarf()
  defer dwarf.destroy()
  try context.call_core_func_resumable(store, instance, 2, []) catch {
    _ => ()
  } noraise {
    _ => fail("expected load trap")
  }
  guard context.jit_module.get_last_trap_report() is Some(report) else {
    fail("missing trap report")
  }
  guard context.jit_module.find_func_by_pc(report.pc)
    is Some((index, function_, offset)) else {
    fail("guest PC missing from installed ranges")
  }
  guard dwarf.lookup_address(report.pc) is Some(info) else {
    fail("DWARF registered a callable wrapper instead of guest code")
  }
  assert_eq(info.func_idx, index)
  assert_eq(info.name, function_.name)
  assert_eq(info.offset, offset.to_int64())
  let frames = dwarf.capture_backtrace()
  assert_true(frames.length() > 0)
  assert_eq(frames[0].pc, report.pc)
  assert_eq(frames[0].func_idx, index)
  assert_eq(frames[0].name, function_.name)
  // The imported callable wrapper is not an installed guest code range.
  let imported = context.jit_module.get_func_ptr(0)
  assert_true(context.jit_module.find_func_by_pc(imported) is None)
  assert_true(dwarf.lookup_address(imported) is None)
}
