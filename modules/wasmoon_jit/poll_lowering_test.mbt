///|
test "native poll checks branch directly without boolean temporaries" {
  let b = @milkir.FunctionBuilder("direct_poll_checks")
  b.add_param(Ptr) |> ignore
  b.emit_void_ext_inst(@wasm_milkir.encode(SafepointPoll(-8, 0, 16, 24)), [])
  b.return_([])
  for target in [@wasmoon_jit.NativeTarget::AArch64, X64] {
    let diagnostics = @wasmoon_jit.compile_wasm_body_diagnostics_for_target(
      b.get_function(),
      @wasm_milkir.WasmValidationContext::empty(),
      target,
    )
    assert_true(diagnostics.code_object.contains("cancel_poll"))
    assert_false(diagnostics.target_vcode.contains("CompareSet"))
    assert_true(diagnostics.target_vcode.contains("BranchCompare"))
  }
}

///|
test "x64 comparison branches preserve predicate widths and edge arguments" {
  let comparisons : Array[@milkir.IntCC] = [
    Eq,
    Ne,
    Slt,
    Sle,
    Sgt,
    Sge,
    Ult,
    Ule,
    Ugt,
    Uge,
  ]
  for ty in [@milkir.Type::I32, I64] {
    for comparison in comparisons {
      let b = @milkir.FunctionBuilder("comparison_edge_arguments")
      b.add_param(Ptr) |> ignore
      let left = b.add_param(ty)
      let right = b.add_param(ty)
      b.add_result(ty)
      let join = b.create_block()
      let first = b.add_block_param(join, ty)
      let second = b.add_block_param(join, ty)
      b.branch(b.icmp(comparison, left, right), join, [left, right], join, [
        right, left,
      ])
      b.switch_to_block(join)
      b.return_([b.isub(first, second)])
      let diagnostics = @wasmoon_jit.compile_wasm_body_diagnostics_for_target(
        b.get_function(),
        @wasm_milkir.WasmValidationContext::empty(),
        X64,
      )
      assert_false(diagnostics.target_vcode.contains("CompareSet"))
      assert_true(diagnostics.target_vcode.contains("BranchCompare"))
    }
  }
}
