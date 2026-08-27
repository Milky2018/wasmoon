///|
fn native_continuation_test_context() -> NativeJITContext {
  match NativeJITContext::try_alloc(1) {
    Some(context) => context
    None => abort("failed to allocate native JIT test context")
  }
}

///|
fn synchronous_call_for_test(
  context : NativeJITContext,
  trampoline_ptr : Int64,
  func_ptr : Int64,
  values : FixedArray[Int64],
  values_len : Int,
) -> Int raise NativeFiberError {
  context.call_trampoline(trampoline_ptr, func_ptr, values, values_len, true)
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
    @native_test_support.hostcall_probe_trampoline(),
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
    @native_test_support.hostcall_probe_trampoline(),
    1L,
    FixedArray::from_array([0L]),
    1,
    stack_size=64L * 1024L,
  )
  ready.cancel()

  context.set_hostcall_callback(fn() { HostcallCompleted })
  let returned = context.start_continuation(
    @native_test_support.hostcall_probe_trampoline(),
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
      #|  NativeJITCompleted,
      #|  Some(Returned),
      #|)
    ),
  )
  context.clear_hostcall_callback()
}

///|
test "interleaved native continuations complete and cancel exactly" {
  let context = native_continuation_test_context()
  context.set_hostcall_callback(fn() { HostcallSuspended })
  let completed = Ref(0)
  let cancelled = Ref(0)
  for _round in 0..<16 {
    let parked : Array[NativeJITContinuation] = []
    for index in 0..<32 {
      let continuation = context.start_continuation(
        @native_test_support.hostcall_probe_trampoline(),
        1L,
        FixedArray::from_array([0L]),
        1,
        stack_size=64L * 1024L,
      )
      let event = continuation.continue_with()
      guard event is NativeHostcallSuspended else {
        return fail("continuation \{index} did not suspend: \{Repr(event)}")
      }
      parked.push(continuation)
    }
    for offset in 0..<parked.length() {
      let index = parked.length() - 1 - offset
      if index % 2 == 0 {
        parked[index].cancel()
        cancelled.val = cancelled.val + 1
      } else {
        guard parked[index].continue_with() is NativeJITCompleted else {
          return fail("continuation did not return")
        }
        completed.val = completed.val + 1
      }
    }
  }
  debug_inspect((completed.val, cancelled.val), content="(256, 256)")
  context.clear_hostcall_callback()
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
    @native_test_support.hostcall_probe_trampoline(),
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
    content="(NativeJITCompleted, 11, 1, Returned)",
  )
  context.clear_hostcall_callback()
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
    @native_test_support.hostcall_probe_trampoline(),
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
    content="(NativeJITCompleted, 11, 2)",
  )
  context.clear_hostcall_callback()
}

///|
test "native hostcall accepts slots on the active fiber stack" {
  let context = native_continuation_test_context()
  guard context.configure_native_fiber_stack_size(64L * 1024L) else {
    fail("failed to configure native fiber stack size")
  }
  context.set_hostcall_callback(fn() { HostcallCompleted })
  let values = FixedArray::from_array([99L])
  let continuation = context.start_continuation(
    @native_test_support.fiber_stack_hostcall_probe_trampoline(),
    1L,
    values,
    values.length(),
  )
  debug_inspect(
    (continuation.continue_with(), values[0]),
    content="(NativeJITCompleted, 0)",
  )
  context.clear_hostcall_callback()
}

///|
test "synchronous calls use the configured native fiber" {
  let context = native_continuation_test_context()
  let requested_stack_size = 128L * 1024L
  guard context.configure_native_fiber_stack_size(requested_stack_size) else {
    fail("failed to configure native fiber stack size")
  }
  let values = FixedArray::from_array([0L, 0L])
  let trap = context.call_trampoline(
    @native_test_support.active_fiber_stack_probe_trampoline(),
    1L,
    values,
    values.length(),
    true,
  )
  inspect(
    (trap, values[0], values[1] >= requested_stack_size),
    content="(0, 1, true)",
  )
}

///|
test "synchronous stack allocation failure remains structured" {
  let context = native_continuation_test_context()
  let requested_stack_size = 9223372036854775807L
  guard context.configure_native_fiber_stack_size(requested_stack_size) else {
    fail("failed to configure native fiber stack size")
  }
  let values = FixedArray::from_array([0L])
  try
    synchronous_call_for_test(
      context,
      @native_test_support.active_fiber_stack_probe_trampoline(),
      1L,
      values,
      values.length(),
    )
  catch {
    StackAllocationFailed(stack_size) =>
      inspect(stack_size, content="9223372036854775807")
    error => fail("unexpected native fiber error: \{error}")
  } noraise {
    trap_code =>
      fail("expected stack allocation failure, got trap \{trap_code}")
  }
}

///|
test "synchronous calls cancel an unexpected hostcall suspension" {
  let context = native_continuation_test_context()
  guard context.configure_native_fiber_stack_size(64L * 1024L) else {
    fail("failed to configure native fiber stack size")
  }
  context.set_hostcall_callback(fn() { HostcallSuspended })
  let suspended_values = FixedArray::from_array([0L])
  try
    synchronous_call_for_test(
      context,
      @native_test_support.hostcall_probe_trampoline(),
      1L,
      suspended_values,
      suspended_values.length(),
    )
  catch {
    UnexpectedYield(event) => inspect(event, content="-1")
    error => fail("unexpected native fiber error: \{error}")
  } noraise {
    trap_code => fail("expected unexpected-yield error, got trap \{trap_code}")
  }
  context.set_hostcall_callback(fn() { HostcallCompleted })
  let completed_values = FixedArray::from_array([0L])
  inspect(
    (
      context.call_trampoline(
        @native_test_support.hostcall_probe_trampoline(),
        1L,
        completed_values,
        completed_values.length(),
        true,
      ),
      completed_values[0],
    ),
    content="(0, 11)",
  )
  context.clear_hostcall_callback()
}

///|
test "repeated synchronous traps release their native fibers" {
  let context = native_continuation_test_context()
  guard context.configure_native_fiber_stack_size(64L * 1024L) else {
    fail("failed to configure native fiber stack size")
  }
  for index in 0..<32 {
    let func_idx = index + 1
    let values = FixedArray::from_array([0L])
    let trap = context.call_trampoline(
      @native_test_support.nested_trap_probe(),
      func_idx.to_int64(),
      values,
      values.length(),
      true,
    )
    guard trap == 6 else { fail("trap \{index} returned \{trap}") }
    guard get_last_trap_details().func_idx == func_idx else {
      fail("trap \{index} published stale details")
    }
  }
}

///|
test "mismatched try end becomes an explicit JIT invariant trap" {
  let context = native_continuation_test_context()
  let first_values = FixedArray::from_array([0L])
  let second_values = FixedArray::from_array([0L])
  inspect(
    (
      context.call_trampoline(
        @native_test_support.mismatched_try_end_probe(),
        1L,
        first_values,
        first_values.length(),
        true,
      ),
      context.call_trampoline(
        @native_test_support.mismatched_try_end_probe(),
        1L,
        second_values,
        second_values.length(),
        true,
      ),
    ),
    content="(8, 8)",
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
          @native_test_support.fiber_stack_hostcall_probe_trampoline(),
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
    @native_test_support.nested_hostcall_tls_probe_trampoline(),
    1L,
    values,
    values.length(),
  )
  debug_inspect(
    (outer.continue_with(), values[0]),
    content="(NativeJITCompleted, 77)",
  )
  if nested[0] is Some(continuation) {
    continuation.cancel()
  }
  context.clear_hostcall_callback()
}

///|
test "suspended nested continuation restores the outer exception handler" {
  let context = native_continuation_test_context()
  let nested : Array[NativeJITContinuation?] = [None]
  context.set_hostcall_callback(fn() {
    match get_hostcall_func_addr() {
      46 => {
        let continuation = context.start_continuation(
          @native_test_support.fiber_stack_hostcall_probe_trampoline(),
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
        HostcallCompleted
      }
      47 => {
        guard nested[0] is Some(continuation) else { return HostcallTrap(8) }
        let event = continuation.continue_with() catch {
          _ => return HostcallTrap(8)
        }
        guard event is NativeJITCompleted else { return HostcallTrap(8) }
        nested[0] = None
        HostcallCompleted
      }
      44 => HostcallSuspended
      _ => HostcallTrap(8)
    }
  })
  let values = FixedArray::from_array([0L])
  let outer = context.start_continuation(
    @native_test_support.nested_activation_exception_probe(),
    1L,
    values,
    values.length(),
  )
  debug_inspect(
    (outer.continue_with(), values[0]),
    content="(NativeJITCompleted, 17)",
  )
  inspect(nested[0] is None, content="true")
  context.clear_hostcall_callback()
}

///|
test "suspended nested continuation restores the outer precise GC roots" {
  let heap = CHeap::CHeap(capacity=1024)
  let context = native_continuation_test_context()
  context.set_gc_heap(heap)
  let nested : Array[NativeJITContinuation?] = [None]
  context.set_hostcall_callback(fn() {
    match get_hostcall_func_addr() {
      46 => {
        let continuation = context.start_continuation(
          @native_test_support.fiber_stack_hostcall_probe_trampoline(),
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
        HostcallCompleted
      }
      44 => HostcallSuspended
      _ => HostcallTrap(8)
    }
  })
  let rooted = heap.alloc_struct(0, [I32(22)])
  let values = FixedArray::from_array([value_to_i64(StructRef(rooted)), 0L])
  let outer = context.start_continuation(
    @native_test_support.nested_activation_gc_root_probe(),
    1L,
    values,
    values.length(),
  )
  debug_inspect(
    (outer.continue_with(), values[1]),
    content="(NativeJITCompleted, 1)",
  )
  inspect(heap.is_valid(rooted), content="true")
  if nested[0] is Some(continuation) {
    continuation.cancel()
  }
  inspect(heap.collect([]), content="1")
  inspect(heap.is_valid(rooted), content="false")
  context.clear_gc_heap()
  context.clear_hostcall_callback()
  heap.free()
}

///|
test "trap activation survives a native hostcall suspension" {
  let context = native_continuation_test_context()
  context.set_hostcall_callback(fn() { HostcallSuspended })
  let values = FixedArray::from_array([0L])
  let continuation = context.start_continuation(
    @native_test_support.hostcall_probe_trampoline(),
    73L,
    values,
    values.length(),
  )
  debug_inspect(continuation.continue_with(), content="NativeHostcallSuspended")
  debug_inspect(continuation.continue_with(), content="NativeJITTrapped(6)")
  let details = get_last_trap_details()
  debug_inspect((details.func_idx, details.pc != 0L), content="(73, true)")
  context.clear_hostcall_callback()
}

///|
test "fiber guard fault after resume becomes a structured stack trap" {
  let context = native_continuation_test_context()
  context.set_hostcall_callback(fn() { HostcallSuspended })
  let continuation = context.start_continuation(
    @native_test_support.hostcall_probe_trampoline(),
    999L,
    FixedArray::from_array([0L]),
    1,
  )
  debug_inspect(continuation.continue_with(), content="NativeHostcallSuspended")
  debug_inspect(continuation.continue_with(), content="NativeJITTrapped(2)")
  let details = get_last_trap_details()
  let dwarf = DWARFBuilder::DWARFBuilder()
  let frames = dwarf.capture_backtrace()
  dwarf.destroy()
  debug_inspect(
    (
      details.func_idx,
      details.signal != 0,
      details.fault_addr != 0L,
      frames.length() > 0,
    ),
    content="(999, true, true, true)",
  )
  context.clear_hostcall_callback()
}

///|
test "nested same-context activation preserves its suspended caller" {
  let context = native_continuation_test_context()
  let nested_function = [-1]
  context.set_hostcall_callback(fn() {
    let nested_values = FixedArray::from_array([0L])
    let trap = context.call_trampoline(
      @native_test_support.nested_trap_probe(),
      321L,
      nested_values,
      nested_values.length(),
      false,
    ) catch {
      _ => return HostcallTrap(8)
    }
    if trap != 6 {
      return HostcallTrap(8)
    }
    nested_function[0] = get_last_trap_details().func_idx
    HostcallSuspended
  })
  let continuation = context.start_continuation(
    @native_test_support.hostcall_probe_trampoline(),
    73L,
    FixedArray::from_array([0L]),
    1,
  )
  debug_inspect(
    (continuation.continue_with(), nested_function[0]),
    content="(NativeHostcallSuspended, 321)",
  )
  debug_inspect(continuation.continue_with(), content="NativeJITTrapped(6)")
  debug_inspect(get_last_trap_details().func_idx, content="73")
  context.clear_hostcall_callback()
}

///|
test "parked native trap activations do not overwrite each other" {
  let context = native_continuation_test_context()
  context.set_hostcall_callback(fn() { HostcallSuspended })
  let first = context.start_continuation(
    @native_test_support.hostcall_probe_trampoline(),
    111L,
    FixedArray::from_array([0L]),
    1,
  )
  let second = context.start_continuation(
    @native_test_support.hostcall_probe_trampoline(),
    222L,
    FixedArray::from_array([0L]),
    1,
  )
  debug_inspect(
    (first.continue_with(), second.continue_with()),
    content="(NativeHostcallSuspended, NativeHostcallSuspended)",
  )
  debug_inspect(second.continue_with(), content="NativeJITTrapped(6)")
  debug_inspect(get_last_trap_details().func_idx, content="222")
  debug_inspect(first.continue_with(), content="NativeJITTrapped(6)")
  debug_inspect(get_last_trap_details().func_idx, content="111")
  context.clear_hostcall_callback()
}

///|
test "parked native continuation keeps its precise GC root alive" {
  let heap = CHeap::CHeap(capacity=1024)
  let context = native_continuation_test_context()
  context.set_gc_heap(heap)
  context.set_hostcall_callback(fn() { HostcallSuspended })
  let _garbage = heap.alloc_struct(0, [I32(11)])
  let rooted = heap.alloc_struct(0, [I32(22)])
  let values = FixedArray::from_array([value_to_i64(StructRef(rooted)), 0L])
  let continuation = context.start_continuation(
    @native_test_support.parked_gc_root_probe(),
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
  debug_inspect(continuation.continue_with(), content="NativeJITCompleted")
  inspect(values[1], content="1")
  inspect(heap.collect([]), content="1")
  inspect(heap.is_valid(rooted), content="false")
  context.clear_gc_heap()
  context.clear_hostcall_callback()
  heap.free()
}

///|
test "multiple parked continuations unregister GC roots independently" {
  let heap = CHeap::CHeap(capacity=1024)
  let first_context = native_continuation_test_context()
  let second_context = native_continuation_test_context()
  first_context.set_gc_heap(heap)
  second_context.set_gc_heap(heap)
  first_context.set_hostcall_callback(fn() { HostcallSuspended })
  second_context.set_hostcall_callback(fn() { HostcallSuspended })
  let first_root = heap.alloc_struct(0, [I32(1)])
  let second_root = heap.alloc_struct(0, [I32(3)])
  let first = first_context.start_continuation(
    @native_test_support.parked_gc_root_probe(),
    1L,
    FixedArray::from_array([value_to_i64(StructRef(first_root)), 0L]),
    2,
  )
  let second = second_context.start_continuation(
    @native_test_support.parked_gc_root_probe(),
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
  debug_inspect(second.continue_with(), content="NativeJITCompleted")
  inspect(heap.collect([]), content="1")
  inspect(heap.is_valid(second_root), content="false")
  first_context.clear_gc_heap()
  second_context.clear_gc_heap()
  first_context.clear_hostcall_callback()
  second_context.clear_hostcall_callback()
  heap.free()
}
