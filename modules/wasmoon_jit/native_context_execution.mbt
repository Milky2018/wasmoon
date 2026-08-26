/// Execution, callback, exception, fiber-stack, and GC operations for managed JIT contexts.

///|
fn throw_exception_tag(context : JITContext, tag_addr : Int) -> Unit {
  c_jit_exception_throw_tag_managed(context, tag_addr)
}

///|
fn throw_exception_values(
  context : JITContext,
  tag_addr : Int,
  values : Array[Int64],
) -> Unit {
  let payload = FixedArray::makei(values.length(), fn(i) { values[i] })
  c_jit_exception_throw_values_managed(
    context,
    tag_addr,
    payload,
    values.length(),
  )
}

///|
fn setup_segments(
  context : JITContext,
  datas : Array[@types.Data],
  elem_segments : Array[Array[Int64]],
  data_dropped? : Array[Bool] = [],
  elem_dropped? : Array[Bool] = [],
) -> Unit {
  c_jit_ctx_init_data_segments_managed(context, datas.length())
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
    c_jit_ctx_add_data_segment_managed(context, i, buf, size, dropped)
  }

  c_jit_ctx_init_elem_segments_managed(context, elem_segments.length())
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
    c_jit_ctx_add_elem_segment_managed(context, i, buf, nslots / 2, dropped)
  }
}

///|
fn clear_segments(context : JITContext) -> Unit {
  c_jit_ctx_clear_segments_managed(context)
}

///|
pub fn NativeJITContext::func_count(self : NativeJITContext) -> Int {
  context_func_count(self.handle)
}

///|
pub fn NativeJITContext::throw_exception_tag(
  self : NativeJITContext,
  tag_addr : Int,
) -> Unit {
  throw_exception_tag(self.handle, tag_addr)
}

///|
pub fn NativeJITContext::throw_exception_values(
  self : NativeJITContext,
  tag_addr : Int,
  values : Array[Int64],
) -> Unit {
  throw_exception_values(self.handle, tag_addr, values)
}

///|
pub fn NativeJITContext::setup_segments(
  self : NativeJITContext,
  datas : Array[@types.Data],
  elem_segments : Array[Array[Int64]],
  data_dropped? : Array[Bool] = [],
  elem_dropped? : Array[Bool] = [],
) -> Unit {
  setup_segments(
    self.handle,
    datas,
    elem_segments,
    data_dropped~,
    elem_dropped~,
  )
}

///|
pub fn NativeJITContext::clear_segments(self : NativeJITContext) -> Unit {
  clear_segments(self.handle)
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
  c_jit_ctx_set_func_managed(self.handle, idx, func_ptr)
}

///|
pub fn NativeJITContext::alloc_indirect_table(
  self : NativeJITContext,
  count : Int,
) -> Bool {
  c_jit_ctx_alloc_indirect_table_managed(self.handle, count) != 0
}

///|
pub fn NativeJITContext::set_indirect(
  self : NativeJITContext,
  table_idx : Int,
  func_idx : Int,
  type_idx : Int,
) -> Unit {
  c_jit_ctx_set_indirect_managed(self.handle, table_idx, func_idx, type_idx)
}

///|
pub fn NativeJITContext::set_globals(
  self : NativeJITContext,
  globals_ptr : Int64,
) -> Unit {
  c_jit_ctx_set_globals_managed(self.handle, globals_ptr)
}

///|
/// Configure the guarded stack size used by future native JIT continuations.
/// The stack mapping is allocated only when a continuation starts.
#alias(alloc_wasm_stack, deprecated="Use configure_native_fiber_stack_size instead")
pub fn NativeJITContext::configure_native_fiber_stack_size(
  self : NativeJITContext,
  stack_size : Int64,
) -> Bool {
  if stack_size <= 0L {
    false
  } else {
    self.configured_native_fiber_stack_size = stack_size
    true
  }
}

///|
/// Check whether a native-fiber stack size override has been configured.
#alias(has_wasm_stack, deprecated="Use has_configured_native_fiber_stack_size instead")
pub fn NativeJITContext::has_configured_native_fiber_stack_size(
  self : NativeJITContext,
) -> Bool {
  self.configured_native_fiber_stack_size > 0L
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
  c_jit_set_hostcall_callback_managed(self.handle, call_closure, encoded)
}

///|
pub fn NativeJITContext::clear_hostcall_callback(
  self : NativeJITContext,
) -> Unit {
  c_jit_clear_hostcall_callback_managed(self.handle)
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
  c_jit_set_cancellation_callback_managed(self.handle, call_closure, callback)
}

///|
pub fn NativeJITContext::clear_cancellation_callback(
  self : NativeJITContext,
) -> Unit {
  c_jit_clear_cancellation_callback_managed(self.handle)
}

///|
pub fn NativeJITContext::call_trampoline(
  self : NativeJITContext,
  trampoline_ptr : Int64,
  func_ptr : Int64,
  values_vec : FixedArray[Int64],
  values_len : Int,
  use_native_fiber : Bool,
) -> Int raise NativeFiberError {
  if use_native_fiber {
    let continuation = self.start_continuation(
      trampoline_ptr, func_ptr, values_vec, values_len,
    )
    let event = {
      errdefer (continuation.cancel() catch { _ => () })
      continuation.continue_with()
    }
    match event {
      NativeJITCompleted => 0
      NativeJITTrapped(code) => code
      NativeHostcallSuspended => {
        continuation.cancel()
        raise UnexpectedYield(-1L)
      }
    }
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
