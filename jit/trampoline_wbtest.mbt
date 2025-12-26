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
test "get_import_trampoline: unsupported functions" {
  let unsupported = ["fd_seek", "path_open", "fd_readdir", "fd_pread"]
  for name in unsupported {
    assert_true(get_import_trampoline("wasi_snapshot_preview1", name) is None)
  }
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
      #|  0004: fd031faa  mov x29, x31
      #|  0008: f353bfa9  stp x19, x20, [sp, #-16]!
      #|  000c: ff4300d1  sub sp, sp, #16
      #|  0010: f30300aa  mov x19, x0
      #|  0014: f40301aa  mov x20, x1
      #|block0:
      #|  0018: f10302aa  mov x17, x2
      #|  001c: e10300aa  mov x1, x0
      #|  0020: 20023fd6  blr x17
      #|  0024: e80300aa  mov x8, x0
      #|  0028: 880200b9  str w8, [x20, #0]
      #|  002c: 090080d2  movz x9, #0, lsl #0
      #|  0030: e00309aa  mov x0, x9
      #|  0034: ff430091  add sp, sp, #16
      #|  0038: f353c1a8  ldp x19, x20, [sp], #16
      #|  003c: fd7bc1a8  ldp x29, x30, [sp], #16
      #|  0040: c0035fd6  ret
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
      #|  0004: fd031faa  mov x29, x31
      #|  0008: f353bfa9  stp x19, x20, [sp, #-16]!
      #|  000c: ff4300d1  sub sp, sp, #16
      #|  0010: f30300aa  mov x19, x0
      #|  0014: f40301aa  mov x20, x1
      #|block0:
      #|  0018: 880240b9  ldr w8, [x20, #0]
      #|  001c: f10302aa  mov x17, x2
      #|  0020: e10300aa  mov x1, x0
      #|  0024: e20308aa  mov x2, x8
      #|  0028: 20023fd6  blr x17
      #|  002c: e90300aa  mov x9, x0
      #|  0030: 890a00b9  str w9, [x20, #8]
      #|  0034: 080080d2  movz x8, #0, lsl #0
      #|  0038: e00308aa  mov x0, x8
      #|  003c: ff430091  add sp, sp, #16
      #|  0040: f353c1a8  ldp x19, x20, [sp], #16
      #|  0044: fd7bc1a8  ldp x29, x30, [sp], #16
      #|  0048: c0035fd6  ret
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
      #|  0004: fd031faa  mov x29, x31
      #|  0008: f30f1ff8  str x19, [sp, #-16]!
      #|  000c: ff4300d1  sub sp, sp, #16
      #|  0010: f30300aa  mov x19, x0
      #|block0:
      #|  0014: f10302aa  mov x17, x2
      #|  0018: e10300aa  mov x1, x0
      #|  001c: 20023fd6  blr x17
      #|  0020: 080080d2  movz x8, #0, lsl #0
      #|  0024: e00308aa  mov x0, x8
      #|  0028: ff430091  add sp, sp, #16
      #|  002c: f30741f8  ldr x19, [sp], #16
      #|  0030: fd7bc1a8  ldp x29, x30, [sp], #16
      #|  0034: c0035fd6  ret
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
      #|  0004: fd031faa  mov x29, x31
      #|  0008: f353bfa9  stp x19, x20, [sp, #-16]!
      #|  000c: ff4300d1  sub sp, sp, #16
      #|  0010: f30300aa  mov x19, x0
      #|  0014: f40301aa  mov x20, x1
      #|block0:
      #|  0018: 810240fd  ldr d1, [x20, #0]
      #|  001c: f10302aa  mov x17, x2
      #|  0020: e10300aa  mov x1, x0
      #|  0024: 2040601e  fmov d0, d1
      #|  0028: 20023fd6  blr x17
      #|  002c: 800600fd  str d0, [x20, #8]
      #|  0030: 080080d2  movz x8, #0, lsl #0
      #|  0034: e00308aa  mov x0, x8
      #|  0038: ff430091  add sp, sp, #16
      #|  003c: f353c1a8  ldp x19, x20, [sp], #16
      #|  0040: fd7bc1a8  ldp x29, x30, [sp], #16
      #|  0044: c0035fd6  ret
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
      #|  0004: fd031faa  mov x29, x31
      #|  0008: f353bfa9  stp x19, x20, [sp, #-16]!
      #|  000c: ff4300d1  sub sp, sp, #16
      #|  0010: f30300aa  mov x19, x0
      #|  0014: f40301aa  mov x20, x1
      #|block0:
      #|  0018: 880240b9  ldr w8, [x20, #0]
      #|  001c: 890640f9  ldr x9, [x20, #8]
      #|  0020: 811240bd  ldr s1, [x20, #16]
      #|  0024: f10302aa  mov x17, x2
      #|  0028: e10300aa  mov x1, x0
      #|  002c: e20308aa  mov x2, x8
      #|  0030: e30309aa  mov x3, x9
      #|  0034: 2040201e  fmov s0, s1
      #|  0038: 20023fd6  blr x17
      #|  003c: ea0300aa  mov x10, x0
      #|  0040: 8a0e00f9  str x10, [x20, #24]
      #|  0044: 080080d2  movz x8, #0, lsl #0
      #|  0048: e00308aa  mov x0, x8
      #|  004c: ff430091  add sp, sp, #16
      #|  0050: f353c1a8  ldp x19, x20, [sp], #16
      #|  0054: fd7bc1a8  ldp x29, x30, [sp], #16
      #|  0058: c0035fd6  ret
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
      #|  0004: fd031faa  mov x29, x31
      #|  0008: f353bfa9  stp x19, x20, [sp, #-16]!
      #|  000c: ee3fbf6d  stp d14, d15, [sp, #-16]!
      #|  0010: ec37bf6d  stp d12, d13, [sp, #-16]!
      #|  0014: ea2fbf6d  stp d10, d11, [sp, #-16]!
      #|  0018: e827bf6d  stp d8, d9, [sp, #-16]!
      #|  001c: ff4300d1  sub sp, sp, #16
      #|  0020: f30300aa  mov x19, x0
      #|  0024: f40301aa  mov x20, x1
      #|block0:
      #|  0028: 880240fd  ldr d8, [x20, #0]
      #|  002c: 890640fd  ldr d9, [x20, #8]
      #|  0030: 8a0a40fd  ldr d10, [x20, #16]
      #|  0034: 8b0e40fd  ldr d11, [x20, #24]
      #|  0038: 8c1240fd  ldr d12, [x20, #32]
      #|  003c: 8d1640fd  ldr d13, [x20, #40]
      #|  0040: 8e1a40fd  ldr d14, [x20, #48]
      #|  0044: 8f1e40fd  ldr d15, [x20, #56]
      #|  0048: f10302aa  mov x17, x2
      #|  004c: e10300aa  mov x1, x0
      #|  0050: 0041601e  fmov d0, d8
      #|  0054: 2141601e  fmov d1, d9
      #|  0058: 4241601e  fmov d2, d10
      #|  005c: 6341601e  fmov d3, d11
      #|  0060: 8441601e  fmov d4, d12
      #|  0064: a541601e  fmov d5, d13
      #|  0068: c641601e  fmov d6, d14
      #|  006c: e741601e  fmov d7, d15
      #|  0070: 20023fd6  blr x17
      #|  0074: 802200fd  str d0, [x20, #64]
      #|  0078: 080080d2  movz x8, #0, lsl #0
      #|  007c: e00308aa  mov x0, x8
      #|  0080: ff430091  add sp, sp, #16
      #|  0084: e827c16c  ldp d8, d9, [sp], #16
      #|  0088: ea2fc16c  ldp d10, d11, [sp], #16
      #|  008c: ec37c16c  ldp d12, d13, [sp], #16
      #|  0090: ee3fc16c  ldp d14, d15, [sp], #16
      #|  0094: f353c1a8  ldp x19, x20, [sp], #16
      #|  0098: fd7bc1a8  ldp x29, x30, [sp], #16
      #|  009c: c0035fd6  ret
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
      #|  0004: fd031faa  mov x29, x31
      #|  0008: fb73bfa9  stp x27, x28, [sp, #-16]!
      #|  000c: f96bbfa9  stp x25, x26, [sp, #-16]!
      #|  0010: f763bfa9  stp x23, x24, [sp, #-16]!
      #|  0014: f55bbfa9  stp x21, x22, [sp, #-16]!
      #|  0018: f353bfa9  stp x19, x20, [sp, #-16]!
      #|  001c: ff4302d1  sub sp, sp, #144
      #|  0020: f30300aa  mov x19, x0
      #|  0024: f40301aa  mov x20, x1
      #|block0:
      #|  0028: 880240f9  ldr x8, [x20, #0]
      #|  002c: 890640f9  ldr x9, [x20, #8]
      #|  0030: 8a0a40f9  ldr x10, [x20, #16]
      #|  0034: 8b0e40f9  ldr x11, [x20, #24]
      #|  0038: 8c1240f9  ldr x12, [x20, #32]
      #|  003c: 8d1640f9  ldr x13, [x20, #40]
      #|  0040: 8e1a40f9  ldr x14, [x20, #48]
      #|  0044: 8f1e40f9  ldr x15, [x20, #56]
      #|  0048: 952240f9  ldr x21, [x20, #64]
      #|  004c: 962640f9  ldr x22, [x20, #72]
      #|  0050: 972a40f9  ldr x23, [x20, #80]
      #|  0054: 982e40f9  ldr x24, [x20, #88]
      #|  0058: 993240f9  ldr x25, [x20, #96]
      #|  005c: 9a3640f9  ldr x26, [x20, #104]
      #|  0060: 9b3a40f9  ldr x27, [x20, #112]
      #|  0064: 9c3e40f9  ldr x28, [x20, #120]
      #|  0068: 904240f9  ldr x16, [x20, #128]
      #|  006c: f03b00f9  str x16, [x31, #112]
      #|  0070: 914640f9  ldr x17, [x20, #136]
      #|  0074: f13f00f9  str x17, [x31, #120]
      #|  0078: 904a40f9  ldr x16, [x20, #144]
      #|  007c: f04300f9  str x16, [x31, #128]
      #|  0080: 914e40f9  ldr x17, [x20, #152]
      #|  0084: f14700f9  str x17, [x31, #136]
      #|  0088: ee0300f9  str x14, [x31, #0]
      #|  008c: ef0700f9  str x15, [x31, #8]
      #|  0090: f50b00f9  str x21, [x31, #16]
      #|  0094: f60f00f9  str x22, [x31, #24]
      #|  0098: f71300f9  str x23, [x31, #32]
      #|  009c: f81700f9  str x24, [x31, #40]
      #|  00a0: f91b00f9  str x25, [x31, #48]
      #|  00a4: fa1f00f9  str x26, [x31, #56]
      #|  00a8: fb2300f9  str x27, [x31, #64]
      #|  00ac: fc2700f9  str x28, [x31, #72]
      #|  00b0: f03b40f9  ldr x16, [x31, #112]
      #|  00b4: f02b00f9  str x16, [x31, #80]
      #|  00b8: f03f40f9  ldr x16, [x31, #120]
      #|  00bc: f02f00f9  str x16, [x31, #88]
      #|  00c0: f04340f9  ldr x16, [x31, #128]
      #|  00c4: f03300f9  str x16, [x31, #96]
      #|  00c8: f04740f9  ldr x16, [x31, #136]
      #|  00cc: f03700f9  str x16, [x31, #104]
      #|  00d0: f10302aa  mov x17, x2
      #|  00d4: e10300aa  mov x1, x0
      #|  00d8: e20308aa  mov x2, x8
      #|  00dc: e30309aa  mov x3, x9
      #|  00e0: e4030aaa  mov x4, x10
      #|  00e4: e5030baa  mov x5, x11
      #|  00e8: e6030caa  mov x6, x12
      #|  00ec: e7030daa  mov x7, x13
      #|  00f0: 20023fd6  blr x17
      #|  00f4: ee0300aa  mov x14, x0
      #|  00f8: 8e5200f9  str x14, [x20, #160]
      #|  00fc: 080080d2  movz x8, #0, lsl #0
      #|  0100: e00308aa  mov x0, x8
      #|  0104: ff430291  add sp, sp, #144
      #|  0108: f353c1a8  ldp x19, x20, [sp], #16
      #|  010c: f55bc1a8  ldp x21, x22, [sp], #16
      #|  0110: f763c1a8  ldp x23, x24, [sp], #16
      #|  0114: f96bc1a8  ldp x25, x26, [sp], #16
      #|  0118: fb73c1a8  ldp x27, x28, [sp], #16
      #|  011c: fd7bc1a8  ldp x29, x30, [sp], #16
      #|  0120: c0035fd6  ret
      #|
    ),
  )
}
