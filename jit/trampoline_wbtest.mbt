// Whitebox tests for JIT WASI trampolines

///|
test "trampoline pointers are valid" {
  // All 12 WASI trampolines should return non-zero function pointers
  assert_true(get_fd_write_ptr() != 0L)
  assert_true(get_fd_read_ptr() != 0L)
  assert_true(get_fd_close_ptr() != 0L)
  assert_true(get_fd_fdstat_get_ptr() != 0L)
  assert_true(get_fd_prestat_get_ptr() != 0L)
  assert_true(get_proc_exit_ptr() != 0L)
  assert_true(get_args_sizes_get_ptr() != 0L)
  assert_true(get_args_get_ptr() != 0L)
  assert_true(get_environ_sizes_get_ptr() != 0L)
  assert_true(get_environ_get_ptr() != 0L)
  assert_true(get_clock_time_get_ptr() != 0L)
  assert_true(get_random_get_ptr() != 0L)
}

///|
test "get_import_trampoline: supported functions" {
  let supported = [
    "fd_write", "fd_read", "fd_close", "fd_fdstat_get", "fd_prestat_get", "proc_exit",
    "args_sizes_get", "args_get", "environ_sizes_get", "environ_get", "clock_time_get",
    "random_get",
  ]
  for name in supported {
    assert_true(
      get_import_trampoline("wasi_snapshot_preview1", name) is Some(_),
    )
  }
}

///|
test "get_import_trampoline: unsupported modules" {
  // All WASI functions are now supported (some as stubs returning ENOSYS)
  // Only unknown modules should return None
  assert_true(get_import_trampoline("unknown_module", "unknown_func") is None)
}

///|
test "get_import_trampoline: spectest module" {
  let supported = [
    "print", "print_i32", "print_i64", "print_f32", "print_f64", "print_i32_f32",
    "print_f64_f64", "print_char",
  ]
  for name in supported {
    assert_true(get_import_trampoline("spectest", name) is Some(_))
  }
  // Unsupported spectest functions
  assert_true(get_import_trampoline("spectest", "unknown_func") is None)
}

///|
test "get_import_trampoline: unknown module" {
  assert_true(get_import_trampoline("env", "memory") is None)
  assert_true(get_import_trampoline("unknown_module", "some_func") is None)
}

///|
test "JITContext: allocation (GC-managed)" {
  let ctx = JITContext::new(10)
  assert_true(ctx is Some(_))
  if ctx is Some(c) {
    assert_true(c.ptr() != 0L)
    // No need to call free() - GC handles cleanup
  }
}

///|
test "memory allocation" {
  let mem = alloc_memory(65536L)
  assert_true(mem != 0L)
  free_memory(mem)
}

// ============ Entry Trampoline Tests ============

///|
test "entry trampoline: no params, i32 result" {
  // Generate trampoline for () -> i32
  let mc = @emit.emit_entry_trampoline([], [@emit.TYPE_I32])
  let bytes = mc.get_bytes()
  // Should generate non-empty code
  assert_true(bytes.length() > 0)
  // Code should be 4-byte aligned (ARM64 instructions)
  assert_true(bytes.length() % 4 == 0)
  // Key: values_vec (X1) is now saved to X20 (callee-saved) in prologue
  // and results are stored to [X20+offset] instead of [X1+offset]
  inspect(
    mc.dump_disasm(),
    content=(
      #|  0000: fd7bbfa9  stp x29, x30, [sp, #-16]!
      #|  0004: fd030091  add x29, sp, #0
      #|  0008: f30f1ff8  str x19, [sp, #-16]!
      #|  000c: f50300aa  mov x21, x0
      #|  0010: f30301aa  mov x19, x1
      #|block0:
      #|  0014: f10302aa  mov x17, x2
      #|  0018: 20023fd6  blr x17
      #|  001c: 600200b9  str w0, [x19, #0]
      #|  0020: 000080d2  movz x0, #0, lsl #0
      #|  0024: f30741f8  ldr x19, [sp], #16
      #|  0028: fd7bc1a8  ldp x29, x30, [sp], #16
      #|  002c: c0035fd6  ret
      #|
    ),
  )
}

///|
test "entry trampoline: i32 param, i32 result" {
  // Generate trampoline for (i32) -> i32
  let mc = @emit.emit_entry_trampoline([@emit.TYPE_I32], [@emit.TYPE_I32])
  let bytes = mc.get_bytes()
  assert_true(bytes.length() > 0)
  assert_true(bytes.length() % 4 == 0)
  inspect(
    mc.dump_disasm(),
    content=(
      #|  0000: fd7bbfa9  stp x29, x30, [sp, #-16]!
      #|  0004: fd030091  add x29, sp, #0
      #|  0008: f30f1ff8  str x19, [sp, #-16]!
      #|  000c: f50300aa  mov x21, x0
      #|  0010: f30301aa  mov x19, x1
      #|block0:
      #|  0014: 610240b9  ldr w1, [x19, #0]
      #|  0018: f10302aa  mov x17, x2
      #|  001c: 20023fd6  blr x17
      #|  0020: 600a00b9  str w0, [x19, #8]
      #|  0024: 000080d2  movz x0, #0, lsl #0
      #|  0028: f30741f8  ldr x19, [sp], #16
      #|  002c: fd7bc1a8  ldp x29, x30, [sp], #16
      #|  0030: c0035fd6  ret
      #|
    ),
  )
}

///|
test "entry trampoline: no params, no result" {
  // Generate trampoline for () -> ()
  let mc = @emit.emit_entry_trampoline([], [])
  let bytes = mc.get_bytes()
  assert_true(bytes.length() > 0)
  assert_true(bytes.length() % 4 == 0)
  inspect(
    mc.dump_disasm(),
    content=(
      #|  0000: fd7bbfa9  stp x29, x30, [sp, #-16]!
      #|  0004: fd030091  add x29, sp, #0
      #|  0008: f50300aa  mov x21, x0
      #|block0:
      #|  000c: f10302aa  mov x17, x2
      #|  0010: 20023fd6  blr x17
      #|  0014: 000080d2  movz x0, #0, lsl #0
      #|  0018: fd7bc1a8  ldp x29, x30, [sp], #16
      #|  001c: c0035fd6  ret
      #|
    ),
  )
}

///|
test "entry trampoline: f64 param, f64 result" {
  // Generate trampoline for (f64) -> f64
  let mc = @emit.emit_entry_trampoline([@emit.TYPE_F64], [@emit.TYPE_F64])
  let bytes = mc.get_bytes()
  assert_true(bytes.length() > 0)
  inspect(
    mc.dump_disasm(),
    content=(
      #|  0000: fd7bbfa9  stp x29, x30, [sp, #-16]!
      #|  0004: fd030091  add x29, sp, #0
      #|  0008: f30f1ff8  str x19, [sp, #-16]!
      #|  000c: f50300aa  mov x21, x0
      #|  0010: f30301aa  mov x19, x1
      #|block0:
      #|  0014: 600240fd  ldr d0, [x19, #0]
      #|  0018: f10302aa  mov x17, x2
      #|  001c: 20023fd6  blr x17
      #|  0020: 600600fd  str d0, [x19, #8]
      #|  0024: 000080d2  movz x0, #0, lsl #0
      #|  0028: f30741f8  ldr x19, [sp], #16
      #|  002c: fd7bc1a8  ldp x29, x30, [sp], #16
      #|  0030: c0035fd6  ret
      #|
    ),
  )
}

///|
test "entry trampoline: multiple params" {
  // Generate trampoline for (i32, i64, f32) -> i64
  let mc = @emit.emit_entry_trampoline(
    [@emit.TYPE_I32, @emit.TYPE_I64, @emit.TYPE_F32],
    [@emit.TYPE_I64],
  )
  let bytes = mc.get_bytes()
  assert_true(bytes.length() > 0)
  inspect(
    mc.dump_disasm(),
    content=(
      #|  0000: fd7bbfa9  stp x29, x30, [sp, #-16]!
      #|  0004: fd030091  add x29, sp, #0
      #|  0008: f30f1ff8  str x19, [sp, #-16]!
      #|  000c: f50300aa  mov x21, x0
      #|  0010: f30301aa  mov x19, x1
      #|block0:
      #|  0014: 630240b9  ldr w3, [x19, #0]
      #|  0018: 610640f9  ldr x1, [x19, #8]
      #|  001c: 601240bd  ldr s0, [x19, #16]
      #|  0020: f10302aa  mov x17, x2
      #|  0024: e20301aa  mov x2, x1
      #|  0028: e10303aa  mov x1, x3
      #|  002c: 20023fd6  blr x17
      #|  0030: 600e00f9  str x0, [x19, #24]
      #|  0034: 000080d2  movz x0, #0, lsl #0
      #|  0038: f30741f8  ldr x19, [sp], #16
      #|  003c: fd7bc1a8  ldp x29, x30, [sp], #16
      #|  0040: c0035fd6  ret
      #|
    ),
  )
}

///|
test "entry trampoline: 8 f64 params" {
  // Generate trampoline for 8 f64 params -> f64 result
  let param_types : Array[Int] = []
  for _i in 0..<8 {
    param_types.push(@emit.TYPE_F64)
  }
  let mc = @emit.emit_entry_trampoline(param_types, [@emit.TYPE_F64])
  let bytes = mc.get_bytes()
  assert_true(bytes.length() > 0)
  inspect(
    mc.dump_disasm(),
    content=(
      #|  0000: fd7bbfa9  stp x29, x30, [sp, #-16]!
      #|  0004: fd030091  add x29, sp, #0
      #|  0008: f30f1ff8  str x19, [sp, #-16]!
      #|  000c: f50300aa  mov x21, x0
      #|  0010: f30301aa  mov x19, x1
      #|block0:
      #|  0014: 600240fd  ldr d0, [x19, #0]
      #|  0018: 610640fd  ldr d1, [x19, #8]
      #|  001c: 620a40fd  ldr d2, [x19, #16]
      #|  0020: 630e40fd  ldr d3, [x19, #24]
      #|  0024: 641240fd  ldr d4, [x19, #32]
      #|  0028: 651640fd  ldr d5, [x19, #40]
      #|  002c: 661a40fd  ldr d6, [x19, #48]
      #|  0030: 671e40fd  ldr d7, [x19, #56]
      #|  0034: f10302aa  mov x17, x2
      #|  0038: 20023fd6  blr x17
      #|  003c: 602200fd  str d0, [x19, #64]
      #|  0040: 000080d2  movz x0, #0, lsl #0
      #|  0044: f30741f8  ldr x19, [sp], #16
      #|  0048: fd7bc1a8  ldp x29, x30, [sp], #16
      #|  004c: c0035fd6  ret
      #|
    ),
  )
}

///|
test "entry trampoline: 20 i64 params (debug)" {
  // Generate trampoline for 20 i64 params -> i64 result
  let param_types : Array[Int] = []
  for _i in 0..<20 {
    param_types.push(@emit.TYPE_I64)
  }
  let mc = @emit.emit_entry_trampoline(param_types, [@emit.TYPE_I64])
  let bytes = mc.get_bytes()
  assert_true(bytes.length() > 0)
  inspect(
    mc.dump_disasm(),
    content=(
      #|  0000: fd7bbfa9  stp x29, x30, [sp, #-16]!
      #|  0004: fd030091  add x29, sp, #0
      #|  0008: fa0f1ff8  str x26, [sp, #-16]!
      #|  000c: f867bfa9  stp x24, x25, [sp, #-16]!
      #|  0010: f65fbfa9  stp x22, x23, [sp, #-16]!
      #|  0014: f353bfa9  stp x19, x20, [sp, #-16]!
      #|  0018: ffc301d1  sub sp, sp, #112
      #|  001c: ff0300f9  str x31, [x31, #0]
      #|  0020: f50300aa  mov x21, x0
      #|  0024: f30301aa  mov x19, x1
      #|block0:
      #|  0028: 680240f9  ldr x8, [x19, #0]
      #|  002c: 670640f9  ldr x7, [x19, #8]
      #|  0030: 660a40f9  ldr x6, [x19, #16]
      #|  0034: 650e40f9  ldr x5, [x19, #24]
      #|  0038: 641240f9  ldr x4, [x19, #32]
      #|  003c: 631640f9  ldr x3, [x19, #40]
      #|  0040: 611a40f9  ldr x1, [x19, #48]
      #|  0044: 7a1e40f9  ldr x26, [x19, #56]
      #|  0048: 692240f9  ldr x9, [x19, #64]
      #|  004c: 6a2640f9  ldr x10, [x19, #72]
      #|  0050: 6b2a40f9  ldr x11, [x19, #80]
      #|  0054: 6c2e40f9  ldr x12, [x19, #88]
      #|  0058: 6d3240f9  ldr x13, [x19, #96]
      #|  005c: 6e3640f9  ldr x14, [x19, #104]
      #|  0060: 6f3a40f9  ldr x15, [x19, #112]
      #|  0064: 743e40f9  ldr x20, [x19, #120]
      #|  0068: 764240f9  ldr x22, [x19, #128]
      #|  006c: 774640f9  ldr x23, [x19, #136]
      #|  0070: 784a40f9  ldr x24, [x19, #144]
      #|  0074: 794e40f9  ldr x25, [x19, #152]
      #|  0078: fa0300f9  str x26, [x31, #0]
      #|  007c: e90700f9  str x9, [x31, #8]
      #|  0080: ea0b00f9  str x10, [x31, #16]
      #|  0084: eb0f00f9  str x11, [x31, #24]
      #|  0088: ec1300f9  str x12, [x31, #32]
      #|  008c: ed1700f9  str x13, [x31, #40]
      #|  0090: ee1b00f9  str x14, [x31, #48]
      #|  0094: ef1f00f9  str x15, [x31, #56]
      #|  0098: f42300f9  str x20, [x31, #64]
      #|  009c: f62700f9  str x22, [x31, #72]
      #|  00a0: f72b00f9  str x23, [x31, #80]
      #|  00a4: f82f00f9  str x24, [x31, #88]
      #|  00a8: f93300f9  str x25, [x31, #96]
      #|  00ac: f10302aa  mov x17, x2
      #|  00b0: e20307aa  mov x2, x7
      #|  00b4: e70301aa  mov x7, x1
      #|  00b8: e10308aa  mov x1, x8
      #|  00bc: f00303aa  mov x16, x3
      #|  00c0: e30306aa  mov x3, x6
      #|  00c4: e60310aa  mov x6, x16
      #|  00c8: f00304aa  mov x16, x4
      #|  00cc: e40305aa  mov x4, x5
      #|  00d0: e50310aa  mov x5, x16
      #|  00d4: 20023fd6  blr x17
      #|  00d8: 605200f9  str x0, [x19, #160]
      #|  00dc: 000080d2  movz x0, #0, lsl #0
      #|  00e0: ffc30191  add sp, sp, #112
      #|  00e4: f353c1a8  ldp x19, x20, [sp], #16
      #|  00e8: f65fc1a8  ldp x22, x23, [sp], #16
      #|  00ec: f867c1a8  ldp x24, x25, [sp], #16
      #|  00f0: fa0741f8  ldr x26, [sp], #16
      #|  00f4: fd7bc1a8  ldp x29, x30, [sp], #16
      #|  00f8: c0035fd6  ret
      #|
    ),
  )
}
