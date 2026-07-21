///|
test "AArch64 code objects retain direct and tail branch fixups in cwasm v8" {
  let object = @code_object.build(
    AArch64,
    [b'\x00', b'\x00', b'\x00', b'\x94', b'\x00', b'\x00', b'\x00', b'\x14'],
    relocations=[
      @code_object.Relocation::new(
        0,
        AArch64Call26,
        Code(@semantic_machv.CodeSymbol::new("wasm.func.3")),
      ),
      @code_object.Relocation::new(
        4,
        AArch64Jump26,
        External(
          @semantic_machv.ExternalSymbol::new("wasmoon.runtime.cancel_poll"),
        ),
      ),
    ],
  )
  let plan = @aarch64_target.prepare_aarch64_link(object)
  let fixups = aarch64_cwasm_call_fixups(object, plan.veneer_offsets())
  debug_inspect(
    (
      plan.code().length(),
      fixups.map(fixup => (fixup.offset, fixup.func_idx, fixup.veneer_offset)),
    ),
    content="(40, [(0, 3, 8), (4, -21014, 24)])",
  )
}

///|
test "AArch64 code-object stack maps survive the cwasm v8 adapter" {
  let object = @code_object.build(
    AArch64,
    [b'\x1f', b'\x20', b'\x03', b'\xd5', b'\x1f', b'\x20', b'\x03', b'\xd5'],
    safepoints=[
      @code_object.SafepointSite::new(
        0,
        Gc,
        [],
        stack_map=@semantic_machv.StackMapMetadata::new(
          0,
          argument_root_count=2,
        ),
      ),
      @code_object.SafepointSite::new(4, Cancellation, []),
    ],
  )
  let (safepoints, root_counts) = aarch64_cwasm_gc_metadata(object)
  debug_inspect(
    (safepoints, root_counts),
    content=(
      #|(
      #|  [
      #|    { code_offset: 0, live_refs: [0, 1], metadata: 2 },
      #|    { code_offset: 4, live_refs: [], metadata: 0 },
      #|  ],
      #|  [2, 0],
      #|)
    ),
  )
}

///|
test "AArch64 cwasm adapter emits stackmap v2 for zero-root safepoints" {
  let safepoints = [@cwasm.GcSafepoint::GcSafepoint(4, [], 0L)]
  debug_inspect(
    aarch64_cwasm_stackmap_blob(safepoints, [0]).to_array(),
    content=(
      #|[
      #|  0x02,
      #|  0x00,
      #|  0x00,
      #|  0x00,
      #|  0x01,
      #|  0x00,
      #|  0x00,
      #|  0x00,
      #|  0x00,
      #|  0x00,
      #|  0x00,
      #|  0x00,
      #|  0x00,
      #|  0x00,
      #|  0x00,
      #|  0x00,
      #|]
    ),
  )
}

///|
test "AArch64 cwasm fixups preserve B and BL branch kinds" {
  guard ExecCode::try_alloc([0x00, 0x00, 0x00, 0x14, 0x00, 0x00, 0x00, 0x94])
    is Some(code) else {
    fail("failed to allocate branch-fixup test code")
  }
  patch_aarch64_direct_call(
    code.ptr(),
    { offset: 0, func_idx: 1, veneer_offset: -1 },
    code.ptr() + 4L,
  )
  patch_aarch64_direct_call(
    code.ptr(),
    { offset: 4, func_idx: 0, veneer_offset: -1 },
    code.ptr(),
  )
  debug_inspect(
    (c_jit_read_u32(code.ptr()), c_jit_read_u32(code.ptr() + 4L)),
    content="(335544321, 2550136831)",
  )
}
