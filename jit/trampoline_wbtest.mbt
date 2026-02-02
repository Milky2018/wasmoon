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
      #|  001c: e30300aa  mov x3, x0
      #|  0020: 630200b9  str w3, [x19, #0]
      #|  0024: 060080d2  movz x6, #0, lsl #0
      #|  0028: e00306aa  mov x0, x6
      #|  002c: f30741f8  ldr x19, [sp], #16
      #|  0030: fd7bc1a8  ldp x29, x30, [sp], #16
      #|  0034: c0035fd6  ret
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
      #|  0014: 630240b9  ldr w3, [x19, #0]
      #|  0018: f10302aa  mov x17, x2
      #|  001c: e10303aa  mov x1, x3
      #|  0020: 20023fd6  blr x17
      #|  0024: e50300aa  mov x5, x0
      #|  0028: 650a00b9  str w5, [x19, #8]
      #|  002c: 080080d2  movz x8, #0, lsl #0
      #|  0030: e00308aa  mov x0, x8
      #|  0034: f30741f8  ldr x19, [sp], #16
      #|  0038: fd7bc1a8  ldp x29, x30, [sp], #16
      #|  003c: c0035fd6  ret
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
      #|  0014: 040080d2  movz x4, #0, lsl #0
      #|  0018: e00304aa  mov x0, x4
      #|  001c: fd7bc1a8  ldp x29, x30, [sp], #16
      #|  0020: c0035fd6  ret
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
      #|  0024: 080080d2  movz x8, #0, lsl #0
      #|  0028: e00308aa  mov x0, x8
      #|  002c: f30741f8  ldr x19, [sp], #16
      #|  0030: fd7bc1a8  ldp x29, x30, [sp], #16
      #|  0034: c0035fd6  ret
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
      #|  0018: 650640f9  ldr x5, [x19, #8]
      #|  001c: 601240bd  ldr s0, [x19, #16]
      #|  0020: f10302aa  mov x17, x2
      #|  0024: e10303aa  mov x1, x3
      #|  0028: e20305aa  mov x2, x5
      #|  002c: 20023fd6  blr x17
      #|  0030: e90300aa  mov x9, x0
      #|  0034: 690e00f9  str x9, [x19, #24]
      #|  0038: 0c0080d2  movz x12, #0, lsl #0
      #|  003c: e0030caa  mov x0, x12
      #|  0040: f30741f8  ldr x19, [sp], #16
      #|  0044: fd7bc1a8  ldp x29, x30, [sp], #16
      #|  0048: c0035fd6  ret
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
      #|  0008: f36bbfa9  stp x19, x26, [sp, #-16]!
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
      #|  0040: 1a0080d2  movz x26, #0, lsl #0
      #|  0044: e0031aaa  mov x0, x26
      #|  0048: f36bc1a8  ldp x19, x26, [sp], #16
      #|  004c: fd7bc1a8  ldp x29, x30, [sp], #16
      #|  0050: c0035fd6  ret
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
      #|  0008: fb0f1ff8  str x27, [sp, #-16]!
      #|  000c: f867bfa9  stp x24, x25, [sp, #-16]!
      #|  0010: f65fbfa9  stp x22, x23, [sp, #-16]!
      #|  0014: f353bfa9  stp x19, x20, [sp, #-16]!
      #|  0018: ffc301d1  sub sp, sp, #112
      #|  001c: ff0300f9  str x31, [x31, #0]
      #|  0020: f50300aa  mov x21, x0
      #|  0024: f30301aa  mov x19, x1
      #|block0:
      #|  0028: 630240f9  ldr x3, [x19, #0]
      #|  002c: 650640f9  ldr x5, [x19, #8]
      #|  0030: 670a40f9  ldr x7, [x19, #16]
      #|  0034: 690e40f9  ldr x9, [x19, #24]
      #|  0038: 6b1240f9  ldr x11, [x19, #32]
      #|  003c: 6d1640f9  ldr x13, [x19, #40]
      #|  0040: 6f1a40f9  ldr x15, [x19, #48]
      #|  0044: 781e40f9  ldr x24, [x19, #56]
      #|  0048: 772240f9  ldr x23, [x19, #64]
      #|  004c: 792640f9  ldr x25, [x19, #72]
      #|  0050: 7b2a40f9  ldr x27, [x19, #80]
      #|  0054: 612e40f9  ldr x1, [x19, #88]
      #|  0058: 643240f9  ldr x4, [x19, #96]
      #|  005c: 663640f9  ldr x6, [x19, #104]
      #|  0060: 683a40f9  ldr x8, [x19, #112]
      #|  0064: 6a3e40f9  ldr x10, [x19, #120]
      #|  0068: 6c4240f9  ldr x12, [x19, #128]
      #|  006c: 6e4640f9  ldr x14, [x19, #136]
      #|  0070: 744a40f9  ldr x20, [x19, #144]
      #|  0074: 764e40f9  ldr x22, [x19, #152]
      #|  0078: f80300f9  str x24, [x31, #0]
      #|  007c: f70700f9  str x23, [x31, #8]
      #|  0080: f90b00f9  str x25, [x31, #16]
      #|  0084: fb0f00f9  str x27, [x31, #24]
      #|  0088: e11300f9  str x1, [x31, #32]
      #|  008c: e41700f9  str x4, [x31, #40]
      #|  0090: e61b00f9  str x6, [x31, #48]
      #|  0094: e81f00f9  str x8, [x31, #56]
      #|  0098: ea2300f9  str x10, [x31, #64]
      #|  009c: ec2700f9  str x12, [x31, #72]
      #|  00a0: ee2b00f9  str x14, [x31, #80]
      #|  00a4: f42f00f9  str x20, [x31, #88]
      #|  00a8: f63300f9  str x22, [x31, #96]
      #|  00ac: f10302aa  mov x17, x2
      #|  00b0: e10303aa  mov x1, x3
      #|  00b4: e20305aa  mov x2, x5
      #|  00b8: e30307aa  mov x3, x7
      #|  00bc: e40309aa  mov x4, x9
      #|  00c0: e5030baa  mov x5, x11
      #|  00c4: e6030daa  mov x6, x13
      #|  00c8: e7030faa  mov x7, x15
      #|  00cc: 20023fd6  blr x17
      #|  00d0: e60300aa  mov x6, x0
      #|  00d4: 665200f9  str x6, [x19, #160]
      #|  00d8: 090080d2  movz x9, #0, lsl #0
      #|  00dc: e00309aa  mov x0, x9
      #|  00e0: ffc30191  add sp, sp, #112
      #|  00e4: f353c1a8  ldp x19, x20, [sp], #16
      #|  00e8: f65fc1a8  ldp x22, x23, [sp], #16
      #|  00ec: f867c1a8  ldp x24, x25, [sp], #16
      #|  00f0: fb0741f8  ldr x27, [sp], #16
      #|  00f4: fd7bc1a8  ldp x29, x30, [sp], #16
      #|  00f8: c0035fd6  ret
      #|

    ),
  )
}
