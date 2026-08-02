/// Execution, callback, exception, fiber-stack, and GC operations for managed JIT contexts.

///|
fn throw_exception_tag(ctx_ptr : Int64, tag_addr : Int) -> Unit {
  c_jit_exception_throw_tag(ctx_ptr, tag_addr)
}

///|
fn throw_exception_values(
  ctx_ptr : Int64,
  tag_addr : Int,
  values : Array[Int64],
) -> Unit {
  let payload = FixedArray::makei(values.length(), fn(i) { values[i] })
  c_jit_exception_throw_values(ctx_ptr, tag_addr, payload, values.length())
}

///|
fn setup_segments(
  ctx_ptr : Int64,
  datas : Array[@types.Data],
  elem_segments : Array[Array[Int64]],
  data_dropped? : Array[Bool] = [],
  elem_dropped? : Array[Bool] = [],
) -> Unit {
  c_jit_ctx_init_data_segments(ctx_ptr, datas.length())
  for i, data in datas {
    let bytes = data.init
    let size = bytes.length()
    let dropped = if i < data_dropped.length() && data_dropped[i] {
      1
    } else {
      0
    }
    let buf = FixedArray::make(size.max(1), b'\x00')
    for j in 0..<size {
      buf[j] = bytes[j]
    }
    c_jit_ctx_add_data_segment(ctx_ptr, i, buf, size, dropped)
  }

  c_jit_ctx_init_elem_segments(ctx_ptr, elem_segments.length())
  for i, seg in elem_segments {
    let dropped = if i < elem_dropped.length() && elem_dropped[i] {
      1
    } else {
      0
    }
    let nslots = seg.length()
    let buf = FixedArray::make(nslots.max(1), 0L)
    for j in 0..<nslots {
      buf[j] = seg[j]
    }
    c_jit_ctx_add_elem_segment(ctx_ptr, i, buf, nslots / 2, dropped)
  }
}

///|
fn clear_segments(ctx_ptr : Int64) -> Unit {
  c_jit_ctx_clear_segments(ctx_ptr)
}

///|
pub fn NativeJITContext::func_count(self : NativeJITContext) -> Int {
  self.with_ptr(fn(ptr) { context_func_count(ptr) })
}

///|
pub fn NativeJITContext::throw_exception_tag(
  self : NativeJITContext,
  tag_addr : Int,
) -> Unit {
  self.with_ptr(fn(ptr) { throw_exception_tag(ptr, tag_addr) })
}

///|
pub fn NativeJITContext::throw_exception_values(
  self : NativeJITContext,
  tag_addr : Int,
  values : Array[Int64],
) -> Unit {
  self.with_ptr(fn(ptr) { throw_exception_values(ptr, tag_addr, values) })
}

///|
pub fn NativeJITContext::setup_segments(
  self : NativeJITContext,
  datas : Array[@types.Data],
  elem_segments : Array[Array[Int64]],
  data_dropped? : Array[Bool] = [],
  elem_dropped? : Array[Bool] = [],
) -> Unit {
  self.with_ptr(fn(ptr) {
    setup_segments(ptr, datas, elem_segments, data_dropped~, elem_dropped~)
  })
}

///|
pub fn NativeJITContext::clear_segments(self : NativeJITContext) -> Unit {
  self.with_ptr(fn(ptr) { clear_segments(ptr) })
}

///|
pub fn NativeJITContext::clear_gc_heap(self : NativeJITContext) -> Unit {
  c_jit_gc_clear_heap_managed(self.handle)
}

///|
pub fn NativeJITContext::set_func(
  self : NativeJITContext,
  idx : Int,
  func_ptr : Int64,
) -> Unit {
  self.with_ptr(fn(ptr) { c_jit_ctx_set_func(ptr, idx, func_ptr) })
}

///|
pub fn NativeJITContext::alloc_indirect_table(
  self : NativeJITContext,
  count : Int,
) -> Bool {
  self.with_ptr(fn(ptr) { c_jit_ctx_alloc_indirect_table(ptr, count) != 0 })
}

///|
pub fn NativeJITContext::set_indirect(
  self : NativeJITContext,
  table_idx : Int,
  func_idx : Int,
  type_idx : Int,
) -> Unit {
  self.with_ptr(fn(ptr) {
    c_jit_ctx_set_indirect(ptr, table_idx, func_idx, type_idx)
  })
}

///|
pub fn NativeJITContext::set_globals(
  self : NativeJITContext,
  globals_ptr : Int64,
) -> Unit {
  self.with_ptr(fn(ptr) { c_jit_ctx_set_globals(ptr, globals_ptr) })
}

///|
pub fn NativeJITContext::alloc_wasm_stack(
  self : NativeJITContext,
  stack_size : Int64,
) -> Bool {
  self.with_ptr(fn(ptr) { c_jit_alloc_wasm_stack(ptr, stack_size) == 0 })
}

///|
pub fn NativeJITContext::has_wasm_stack(self : NativeJITContext) -> Bool {
  self.with_ptr(fn(ptr) { c_jit_get_wasm_stack_top(ptr) != 0L })
}

///|
/// Typed result returned by a JIT hostcall dispatcher.
pub(all) enum NativeHostcallOutcome {
  HostcallCompleted
  HostcallTrap(Int)
  HostcallSuspended
} derive(Debug, Eq)

///|
pub fn NativeJITContext::set_hostcall_callback(
  self : NativeJITContext,
  callback : () -> NativeHostcallOutcome,
) -> Unit {
  let encoded = fn() {
    match callback() {
      HostcallCompleted => 0
      HostcallTrap(code) => if code > 0 { code } else { 8 }
      HostcallSuspended => -1
    }
  }
  let call_closure : FuncRef[(() -> Int) -> Int] = fn(f : () -> Int) { f() }
  self.with_ptr(fn(ptr) {
    c_jit_set_hostcall_callback(ptr, call_closure, encoded)
  })
}

///|
pub fn NativeJITContext::clear_hostcall_callback(
  self : NativeJITContext,
) -> Unit {
  self.with_ptr(fn(ptr) { c_jit_clear_hostcall_callback(ptr) })
}

///|
pub fn NativeJITContext::set_cancellation_callback(
  self : NativeJITContext,
  callback : () -> Bool,
) -> Unit {
  let call_closure : FuncRef[(() -> Bool) -> Int] = fn(f : () -> Bool) {
    if f() {
      1
    } else {
      0
    }
  }
  self.with_ptr(fn(ptr) {
    c_jit_set_cancellation_callback(ptr, call_closure, callback)
  })
}

///|
pub fn NativeJITContext::clear_cancellation_callback(
  self : NativeJITContext,
) -> Unit {
  self.with_ptr(fn(ptr) { c_jit_clear_cancellation_callback(ptr) })
}

///|
pub fn NativeJITContext::call_trampoline(
  self : NativeJITContext,
  trampoline_ptr : Int64,
  func_ptr : Int64,
  values_vec : FixedArray[Int64],
  values_len : Int,
  use_stack_switch : Bool,
) -> Int {
  if use_stack_switch {
    c_jit_call_with_stack_switch_managed(
      self.handle,
      trampoline_ptr,
      func_ptr,
      values_vec,
      values_len,
    )
  } else {
    c_jit_call_trampoline_managed(
      self.handle,
      trampoline_ptr,
      func_ptr,
      values_vec,
      values_len,
    )
  }
}
