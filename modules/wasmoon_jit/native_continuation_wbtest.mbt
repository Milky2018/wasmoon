///|
extern "c" fn c_native_hostcall_probe_trampoline() -> Int64 = "wasmoon_native_hostcall_probe_trampoline"

///|
extern "c" fn c_native_nested_trap_probe() -> Int64 = "wasmoon_native_nested_trap_probe"

///|
fn native_continuation_test_context() -> NativeJITContext {
  match NativeJITContext::try_alloc(1) {
    Some(context) => context
    None => abort("failed to allocate native JIT test context")
  }
}

///|
test "native hostcall suspension continues after the call without replay" {
  let context = native_continuation_test_context()
  let callback_count = [0]
  context.set_hostcall_callback(fn() {
    callback_count[0] = callback_count[0] + 1
    HostcallSuspended
  })
  let values = FixedArray::from_array([0L])
  let continuation = context.start_continuation(
    c_native_hostcall_probe_trampoline(),
    1L,
    values,
    values.length(),
  )
  debug_inspect(
    (
      continuation.continue_with(),
      values[0],
      callback_count[0],
      continuation.phase(),
    ),
    content="(NativeHostcallSuspended, 10, 1, Suspended)",
  )
  debug_inspect(
    (
      continuation.continue_with(),
      values[0],
      callback_count[0],
      continuation.phase(),
    ),
    content="(NativeJITReturned(0), 11, 1, Returned)",
  )
}

///|
test "trap activation survives a native hostcall suspension" {
  let context = native_continuation_test_context()
  context.set_hostcall_callback(fn() { HostcallSuspended })
  let values = FixedArray::from_array([0L])
  let continuation = context.start_continuation(
    c_native_hostcall_probe_trampoline(),
    73L,
    values,
    values.length(),
  )
  debug_inspect(continuation.continue_with(), content="NativeHostcallSuspended")
  debug_inspect(continuation.continue_with(), content="NativeJITReturned(6)")
  let details = get_last_trap_details()
  debug_inspect((details.func_idx, details.pc != 0L), content="(73, true)")
}

///|
test "fiber guard fault after resume becomes a structured stack trap" {
  let context = native_continuation_test_context()
  context.set_hostcall_callback(fn() { HostcallSuspended })
  let continuation = context.start_continuation(
    c_native_hostcall_probe_trampoline(),
    999L,
    FixedArray::from_array([0L]),
    1,
  )
  debug_inspect(continuation.continue_with(), content="NativeHostcallSuspended")
  debug_inspect(continuation.continue_with(), content="NativeJITReturned(2)")
  let details = get_last_trap_details()
  debug_inspect(
    (details.func_idx, details.signal != 0, details.fault_addr != 0L),
    content="(999, true, true)",
  )
}

///|
test "nested same-context activation preserves its suspended caller" {
  let context = native_continuation_test_context()
  let nested_function = [-1]
  context.set_hostcall_callback(fn() {
    let nested_values = FixedArray::from_array([0L])
    let trap = context.call_trampoline(
      c_native_nested_trap_probe(),
      321L,
      nested_values,
      nested_values.length(),
      false,
    )
    if trap != 6 {
      return HostcallTrap(8)
    }
    nested_function[0] = get_last_trap_details().func_idx
    HostcallSuspended
  })
  let continuation = context.start_continuation(
    c_native_hostcall_probe_trampoline(),
    73L,
    FixedArray::from_array([0L]),
    1,
  )
  debug_inspect(
    (continuation.continue_with(), nested_function[0]),
    content="(NativeHostcallSuspended, 321)",
  )
  debug_inspect(continuation.continue_with(), content="NativeJITReturned(6)")
  debug_inspect(get_last_trap_details().func_idx, content="73")
}

///|
test "parked native trap activations do not overwrite each other" {
  let context = native_continuation_test_context()
  context.set_hostcall_callback(fn() { HostcallSuspended })
  let first = context.start_continuation(
    c_native_hostcall_probe_trampoline(),
    111L,
    FixedArray::from_array([0L]),
    1,
  )
  let second = context.start_continuation(
    c_native_hostcall_probe_trampoline(),
    222L,
    FixedArray::from_array([0L]),
    1,
  )
  debug_inspect(
    (first.continue_with(), second.continue_with()),
    content="(NativeHostcallSuspended, NativeHostcallSuspended)",
  )
  debug_inspect(second.continue_with(), content="NativeJITReturned(6)")
  debug_inspect(get_last_trap_details().func_idx, content="222")
  debug_inspect(first.continue_with(), content="NativeJITReturned(6)")
  debug_inspect(get_last_trap_details().func_idx, content="111")
}
