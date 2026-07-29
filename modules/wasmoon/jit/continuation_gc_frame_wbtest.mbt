///|
extern "c" fn native_hostcall_probe_trampoline_for_gc_frame_test() -> Int64 = "wasmoon_native_hostcall_probe_trampoline"

///|
extern "c" fn gc_live_frame_count_for_test() -> Int64 = "wasmoon_jit_gc_live_frame_count"

///|
fn gc_frame_test_continuation(
  mode : Int64,
  callback : () -> @wasmoon_jit.NativeHostcallOutcome,
) -> (JITModule, JITCallContinuation) raise {
  let context = JITContext::try_alloc(1).unwrap()
  context.set_hostcall_callback(callback)
  let jit_module = JITModule::JITModule()
  jit_module.context = Some(context)
  jit_module.context_ptr = context.ptr()
  let values = FixedArray::from_array([0L])
  let raw = context.ctx.start_continuation(
    native_hostcall_probe_trampoline_for_gc_frame_test(),
    mode,
    values,
    values.length(),
    stack_size=64L * 1024L,
  )
  let call : JITContextContinuation = {
    raw,
    context_ptr: context.ptr(),
    values,
    num_arg_slots: 0,
    num_result_slots: 1,
    active: [true],
  }
  let continuation : JITCallContinuation = {
    jit_module,
    func: JITFunction(0, "gc-frame-test", mode, 0, [], []),
    call,
    entry_roots: [],
    first_entry: [true],
    gc_frame_active: [false],
    active: [true],
  }
  (jit_module, continuation)
}

///|
test "native continuation releases its GC frame on every terminal path" {
  let baseline = gc_live_frame_count_for_test()
  let trap_callback_count = [0]
  let (trap_module, trap_continuation) = gc_frame_test_continuation(73L, fn() {
    trap_callback_count[0] = trap_callback_count[0] + 1
    if trap_callback_count[0] == 1 {
      HostcallSuspended
    } else {
      HostcallCompleted
    }
  })
  guard trap_continuation.advance(false) is JITSuspended(_) else {
    return fail("native continuation did not suspend")
  }
  let trap_suspended = gc_live_frame_count_for_test() - baseline
  try trap_continuation.advance(true) catch {
    _ => ()
  } noraise {
    _ => fail("native continuation did not trap")
  }
  let trap_terminal = gc_live_frame_count_for_test() - baseline
  let retained_modules = [trap_module]
  let cancel_baseline = gc_live_frame_count_for_test()
  let (cancel_module, cancel_continuation) = gc_frame_test_continuation(1L, fn() {
    HostcallSuspended
  })
  guard cancel_continuation.advance(false) is JITSuspended(_) else {
    return fail("native continuation did not suspend")
  }
  retained_modules.push(cancel_module)
  let cancel_suspended = gc_live_frame_count_for_test() - cancel_baseline
  cancel_continuation.cancel()
  let cancel_terminal = gc_live_frame_count_for_test() - cancel_baseline
  cancel_module.gc_begin_frame(999L)
  let sentinel_active = gc_live_frame_count_for_test() - cancel_baseline
  cancel_continuation.cancel()
  let repeated_cancel = gc_live_frame_count_for_test() - cancel_baseline
  cancel_module.gc_end_frame()
  let final_count = gc_live_frame_count_for_test()
  debug_inspect(
    (
      trap_suspended,
      trap_terminal,
      cancel_suspended,
      cancel_terminal,
      sentinel_active,
      repeated_cancel,
      final_count - cancel_baseline,
    ),
    content="(1, 0, 1, 0, 1, 1, 0)",
  )
  for jit_module in retained_modules {
    jit_module.close()
  }
}
