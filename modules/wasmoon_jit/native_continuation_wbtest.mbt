///|
extern "c" fn c_native_hostcall_probe_trampoline() -> Int64 = "wasmoon_native_hostcall_probe_trampoline"

///|
extern "c" fn c_native_fiber_stack_hostcall_probe_trampoline() -> Int64 = "wasmoon_native_fiber_stack_hostcall_probe_trampoline"

///|
extern "c" fn c_native_nested_hostcall_tls_probe_trampoline() -> Int64 = "wasmoon_native_nested_hostcall_tls_probe_trampoline"

///|
extern "c" fn c_native_nested_trap_probe() -> Int64 = "wasmoon_native_nested_trap_probe"

///|
extern "c" fn c_native_parked_gc_root_probe() -> Int64 = "wasmoon_native_parked_gc_root_probe"

///|
extern "c" fn c_native_fiber_live_count() -> Int64 = "wasmoon_native_fiber_live_count"

///|
extern "c" fn c_native_fiber_mapped_stack_bytes() -> Int64 = "wasmoon_native_fiber_mapped_stack_bytes"

///|
extern "c" fn c_native_fiber_parked_root_registration_count() -> Int64 = "wasmoon_native_fiber_parked_root_registration_count"

///|
fn native_fiber_lifecycle_counts() -> (Int64, Int64, Int64) {
  (
    c_native_fiber_live_count(),
    c_native_fiber_mapped_stack_bytes(),
    c_native_fiber_parked_root_registration_count(),
  )
}

///|
fn native_continuation_test_context() -> NativeJITContext {
  match NativeJITContext::try_alloc(1) {
    Some(context) => context
    None => abort("failed to allocate native JIT test context")
  }
}

///|
test "native continuation cancellation has explicit phase boundaries" {
  let context = native_continuation_test_context()
  let running : Array[NativeJITContinuation?] = [None]
  let running_cancel_phase : Array[NativeFiberPhase?] = [None]
  context.set_hostcall_callback(fn() {
    if running[0] is Some(continuation) {
      continuation.cancel() catch {
        InvalidTransition(phase) => running_cancel_phase[0] = Some(phase)
        _ => ()
      }
    }
    HostcallSuspended
  })
  let active = context.start_continuation(
    c_native_hostcall_probe_trampoline(),
    1L,
    FixedArray::from_array([0L]),
    1,
    stack_size=64L * 1024L,
  )
  running[0] = Some(active)
  let suspended = active.continue_with()
  running[0] = None
  let suspended_phase = active.phase()
  active.cancel()
  let cancelled_phase = active.phase()
  let repeated_cancel_phase : Array[NativeFiberPhase?] = [None]
  active.cancel() catch {
    InvalidTransition(phase) => repeated_cancel_phase[0] = Some(phase)
    _ => ()
  }

  let ready = context.start_continuation(
    c_native_hostcall_probe_trampoline(),
    1L,
    FixedArray::from_array([0L]),
    1,
    stack_size=64L * 1024L,
  )
  ready.cancel()

  context.set_hostcall_callback(fn() { HostcallCompleted })
  let returned = context.start_continuation(
    c_native_hostcall_probe_trampoline(),
    1L,
    FixedArray::from_array([0L]),
    1,
    stack_size=64L * 1024L,
  )
  let returned_event = returned.continue_with()
  let returned_cancel_phase : Array[NativeFiberPhase?] = [None]
  returned.cancel() catch {
    InvalidTransition(phase) => returned_cancel_phase[0] = Some(phase)
    _ => ()
  }
  debug_inspect(
    (
      suspended,
      running_cancel_phase[0],
      suspended_phase,
      cancelled_phase,
      repeated_cancel_phase[0],
      ready.phase(),
      returned_event,
      returned_cancel_phase[0],
    ),
    content=(
      #|(
      #|  NativeHostcallSuspended,
      #|  Some(Running),
      #|  Suspended,
      #|  Cancelled,
      #|  Some(Cancelled),
      #|  Cancelled,
      #|  NativeJITReturned(0),
      #|  Some(Returned),
      #|)
    ),
  )
}

///|
test "interleaved native continuations release all lifecycle state" {
  let before = native_fiber_lifecycle_counts()
  let context = native_continuation_test_context()
  context.set_hostcall_callback(fn() { HostcallSuspended })
  let completed = Ref(0)
  let cancelled = Ref(0)
  for _round in 0..<16 {
    let parked : Array[NativeJITContinuation] = []
    for index in 0..<32 {
      let continuation = context.start_continuation(
        c_native_hostcall_probe_trampoline(),
        1L,
        FixedArray::from_array([0L]),
        1,
        stack_size=64L * 1024L,
      )
      let event = continuation.continue_with()
      guard event is NativeHostcallSuspended else {
        return fail("continuation \{index} did not suspend: \{to_repr(event)}")
      }
      parked.push(continuation)
    }
    for offset in 0..<parked.length() {
      let index = parked.length() - 1 - offset
      if index % 2 == 0 {
        parked[index].cancel()
        cancelled.val = cancelled.val + 1
      } else {
        guard parked[index].continue_with() is NativeJITReturned(0) else {
          return fail("continuation did not return")
        }
        completed.val = completed.val + 1
      }
    }
  }
  let after = native_fiber_lifecycle_counts()
  debug_inspect(
    (
      completed.val,
      cancelled.val,
      after.0 - before.0,
      after.1 - before.1,
      after.2 - before.2,
    ),
    content="(256, 256, 0, 0, 0)",
  )
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
test "native hostcall suspension can retry only the suspended hostcall" {
  let context = native_continuation_test_context()
  let callback_count = [0]
  context.set_hostcall_callback(fn() {
    callback_count[0] = callback_count[0] + 1
    if callback_count[0] == 1 {
      HostcallSuspended
    } else {
      HostcallCompleted
    }
  })
  let values = FixedArray::from_array([0L])
  let continuation = context.start_continuation(
    c_native_hostcall_probe_trampoline(),
    1L,
    values,
    values.length(),
  )
  debug_inspect(
    (continuation.continue_with(), callback_count[0]),
    content="(NativeHostcallSuspended, 1)",
  )
  debug_inspect(
    (
      continuation.continue_after_hostcall(retry=true),
      values[0],
      callback_count[0],
    ),
    content="(NativeJITReturned(0), 11, 2)",
  )
}

///|
test "native hostcall accepts slots on the active fiber stack" {
  let context = native_continuation_test_context()
  guard context.alloc_wasm_stack(64L * 1024L) else {
    fail("failed to allocate ordinary Wasm stack")
  }
  context.set_hostcall_callback(fn() { HostcallCompleted })
  let values = FixedArray::from_array([99L])
  let continuation = context.start_continuation(
    c_native_fiber_stack_hostcall_probe_trampoline(),
    1L,
    values,
    values.length(),
  )
  debug_inspect(
    (continuation.continue_with(), values[0]),
    content="(NativeJITReturned(0), 0)",
  )
}

///|
test "suspended nested hostcall restores the outer hostcall slots" {
  let context = native_continuation_test_context()
  let nested : Array[NativeJITContinuation?] = [None]
  context.set_hostcall_callback(fn() {
    match get_hostcall_func_addr() {
      46 => {
        let continuation = context.start_continuation(
          c_native_fiber_stack_hostcall_probe_trampoline(),
          1L,
          FixedArray::from_array([0L]),
          1,
        ) catch {
          _ => return HostcallTrap(8)
        }
        let event = continuation.continue_with() catch {
          _ => return HostcallTrap(8)
        }
        guard event is NativeHostcallSuspended else { return HostcallTrap(8) }
        nested[0] = Some(continuation)
        hostcall_value_slot_write(0, 77L)
        HostcallCompleted
      }
      44 => HostcallSuspended
      _ => HostcallTrap(8)
    }
  })
  let values = FixedArray::from_array([0L])
  let outer = context.start_continuation(
    c_native_nested_hostcall_tls_probe_trampoline(),
    1L,
    values,
    values.length(),
  )
  debug_inspect(
    (outer.continue_with(), values[0]),
    content="(NativeJITReturned(0), 77)",
  )
  if nested[0] is Some(continuation) {
    continuation.cancel()
  }
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

///|
test "parked native continuation keeps its precise GC root alive" {
  let heap = CHeap::CHeap(capacity=1024)
  let context = native_continuation_test_context()
  gc_set_heap(context.ptr(), heap)
  context.set_hostcall_callback(fn() { HostcallSuspended })
  let _garbage = heap.alloc_struct(0, [I32(11)])
  let rooted = heap.alloc_struct(0, [I32(22)])
  let values = FixedArray::from_array([value_to_i64(StructRef(rooted)), 0L])
  let continuation = context.start_continuation(
    c_native_parked_gc_root_probe(),
    1L,
    values,
    values.length(),
  )

  debug_inspect(continuation.continue_with(), content="NativeHostcallSuspended")
  inspect(heap.get_offset(rooted) > 0, content="true")
  inspect(heap.collect([]), content="1")
  inspect(heap.is_valid(rooted), content="true")
  inspect(heap.get_offset(rooted), content="0")
  debug_inspect(heap.struct_get(rooted, 0, I32), content="I32(22)")
  debug_inspect(continuation.continue_with(), content="NativeJITReturned(0)")
  inspect(values[1], content="1")
  inspect(heap.collect([]), content="1")
  inspect(heap.is_valid(rooted), content="false")
  gc_clear_heap(context.ptr())
}

///|
test "multiple parked continuations unregister GC roots independently" {
  let heap = CHeap::CHeap(capacity=1024)
  let first_context = native_continuation_test_context()
  let second_context = native_continuation_test_context()
  gc_set_heap(first_context.ptr(), heap)
  gc_set_heap(second_context.ptr(), heap)
  first_context.set_hostcall_callback(fn() { HostcallSuspended })
  second_context.set_hostcall_callback(fn() { HostcallSuspended })
  let first_root = heap.alloc_struct(0, [I32(1)])
  let second_root = heap.alloc_struct(0, [I32(3)])
  let first = first_context.start_continuation(
    c_native_parked_gc_root_probe(),
    1L,
    FixedArray::from_array([value_to_i64(StructRef(first_root)), 0L]),
    2,
  )
  let second = second_context.start_continuation(
    c_native_parked_gc_root_probe(),
    1L,
    FixedArray::from_array([value_to_i64(StructRef(second_root)), 0L]),
    2,
  )

  debug_inspect(
    (first.continue_with(), second.continue_with()),
    content="(NativeHostcallSuspended, NativeHostcallSuspended)",
  )
  inspect(heap.collect([]), content="0")
  first.cancel()
  inspect(heap.collect([]), content="1")
  debug_inspect(
    (heap.is_valid(first_root), heap.is_valid(second_root)),
    content="(false, true)",
  )
  debug_inspect(second.continue_with(), content="NativeJITReturned(0)")
  inspect(heap.collect([]), content="1")
  inspect(heap.is_valid(second_root), content="false")
  gc_clear_heap(first_context.ptr())
  gc_clear_heap(second_context.ptr())
}
