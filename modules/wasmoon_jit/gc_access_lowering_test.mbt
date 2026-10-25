///|
test "both targets select explicit heap GC word helper contracts" {
  let context = @wasm_milkir.WasmValidationContext::new({
    function_contract: fn(_) { None },
    defined_type_contract: fn(index) {
      match index {
        0 =>
          Some(
            Struct([{ storage: Packed8, mutable_: true, defaultable: true, }]),
          )
        1 =>
          Some(
            Array({ storage: Value(I32), mutable_: true, defaultable: true, }),
          )
        _ => None
      }
    },
    table_contract: fn(_) { None },
    tag_contract: fn(_) { None },
    memory_exists: fn(_) { false },
    data_segment_exists: fn(_) { false },
    element_segment_type: fn(_) { None },
  })
  let builder = @milkir.FunctionBuilder::FunctionBuilder("planned_gc_access")
  builder.add_param(Ptr) |> ignore
  let struct_ref = builder.add_param(Ref)
  let array_ref = builder.add_param(Ref)
  let index = builder.add_param(I32)
  let value = builder.add_param(I32)
  builder.add_result(I32)
  @wasm_milkir.struct_set(builder, 0, 0, struct_ref, value)
  @wasm_milkir.array_set(builder, 1, array_ref, index, value)
  let field = @wasm_milkir.struct_get_u(builder, 0, 0, struct_ref, 1)
  let element = @wasm_milkir.array_get(builder, 1, array_ref, index, I32)
  let length = @wasm_milkir.array_len(builder, array_ref)
  let sum = builder.iadd(field, element)
  builder.return_([builder.iadd(sum, length)])
  for target in [@wasmoon_jit.NativeTarget::X64, AArch64] {
    let diagnostics = @wasmoon_jit.compile_wasm_body_diagnostics_for_target(
      builder.get_function(),
      context,
      target,
    )
    assert_true(diagnostics.code_object.contains("gc.array_data_heap"))
    for
      suffix in [
        "gc.struct_data", "gc.struct_set_heap", "gc.array_get_heap", "gc.array_set_heap",
        "gc.array_len_heap",
      ] {
      assert_true(diagnostics.code_object.contains(suffix))
    }
  }
}

///|
test "both targets materialize one preheader view for an entire array loop" {
  let context = @wasm_milkir.WasmValidationContext::new({
    function_contract: fn(_) { None },
    defined_type_contract: fn(index) {
      match index {
        0 =>
          Some(
            Array({ storage: Value(I32), mutable_: true, defaultable: true, }),
          )
        1 =>
          Some(
            Struct([
              { storage: Value(Ref), mutable_: false, defaultable: true, },
            ]),
          )
        _ => None
      }
    },
    table_contract: fn(_) { None },
    tag_contract: fn(_) { None },
    memory_exists: fn(_) { false },
    data_segment_exists: fn(_) { false },
    element_segment_type: fn(_) { None },
  })
  for produced in [false, true] {
    let b = @milkir.FunctionBuilder::FunctionBuilder("borrowed_array_loop")
    b.add_param(Ptr) |> ignore
    let argument = b.add_param(Ref)
    b.add_result(I32)
    let a = if produced {
      @wasm_milkir.struct_get(b, 1, 0, argument, Ref)
    } else {
      argument
    }
    let length = if produced {
      b.iconst_i32(4)
    } else {
      @wasm_milkir.array_len(b, a)
    }
    let header = b.create_block()
    let i = b.add_block_param(header, I32)
    let body = b.create_block()
    let exit = b.create_block()
    b.jump(header, [b.iconst_i32(0)])
    b.switch_to_block(header)
    b.branch(b.icmp_ult(i, length), body, [], exit, [])
    b.switch_to_block(body)
    let old = @wasm_milkir.array_get(b, 0, a, i, I32)
    @wasm_milkir.array_set(b, 0, a, i, b.iadd(old, b.iconst_i32(1)))
    b.jump(header, [b.iadd(i, b.iconst_i32(1))])
    b.switch_to_block(exit)
    b.return_([length])
    for target in [@wasmoon_jit.NativeTarget::X64, AArch64] {
      let code = @wasmoon_jit.compile_wasm_body_artifact_function(
        b.get_function(),
        context,
        target,
        function_index=0,
        signature=@native.Signature::new([GcRef64], [I32]),
      )
      let views = code.relocations.filter(r => {
        r.target is External(symbol) &&
        symbol.name == "wasmoon.runtime.gc.array_data_heap"
      })
      assert_eq(views.length(), 1)
    }
  }
}

///|
test "both targets reserve reference structs without removing the collecting fallback" {
  let context = @wasm_milkir.WasmValidationContext::new({
    function_contract: fn(_) { None },
    defined_type_contract: fn(index) {
      if index == 0 {
        Some(
          Struct([
            { storage: Packed8, mutable_: false, defaultable: true, },
            { storage: Value(Ref), mutable_: false, defaultable: true, },
            { storage: Value(I64), mutable_: false, defaultable: true, },
          ]),
        )
      } else {
        None
      }
    },
    table_contract: fn(_) { None },
    tag_contract: fn(_) { None },
    memory_exists: fn(_) { false },
    data_segment_exists: fn(_) { false },
    element_segment_type: fn(_) { None },
  })
  for (default_, copies) in [(false, 1), (true, 1), (false, 12), (true, 12)] {
    let b = @milkir.FunctionBuilder::FunctionBuilder(
      "reference_struct_allocation",
    )
    b.add_param(Ptr) |> ignore
    let child = b.add_param(Ref)
    b.add_result(Ref)
    for _ in 1..<copies {
      if default_ {
        @wasm_milkir.struct_new_default(b, 0) |> ignore
      } else {
        @wasm_milkir.struct_new(b, 0, [
          b.iconst_i32(257),
          child,
          b.iconst_i64(42L),
        ])
        |> ignore
      }
    }
    let object = if default_ {
      @wasm_milkir.struct_new_default(b, 0)
    } else {
      @wasm_milkir.struct_new(b, 0, [
        b.iconst_i32(257),
        child,
        b.iconst_i64(42L),
      ])
    }
    b.return_([object])
    for target in [@wasmoon_jit.NativeTarget::X64, AArch64] {
      let code = @wasmoon_jit.compile_wasm_body_artifact_function(
        b.get_function(),
        context,
        target,
        function_index=0,
        signature=@native.Signature::new([GcRef64], [GcRef64]),
      )
      for
        (name, count) in [
          (
            "wasmoon.runtime.gc.reserve_struct_fast",
            if copies == 1 {
              0
            } else {
              copies
            },
          ),
          ("wasmoon.runtime.gc.alloc_struct_slow", copies),
        ] {
        assert_eq(
          code.relocations
          .filter(r => r.target is External(symbol) && symbol.name == name)
          .length(),
          count,
        )
      }
    }
  }
}

///|
test "struct read layout offsets fold without losing write fallbacks" {
  let context = @wasm_milkir.WasmValidationContext::new({
    function_contract: fn(_) { None },
    defined_type_contract: fn(index) {
      match index {
        0 =>
          Some(
            Struct(
              Array::make(3, {
                storage: Value(I64),
                mutable_: true,
                defaultable: true,
              }),
            ),
          )
        1 =>
          Some(
            Struct([
              { storage: Value(I32), mutable_: true, defaultable: true, },
              { storage: Value(I32), mutable_: true, defaultable: true, },
              { storage: Value(I64), mutable_: true, defaultable: true, },
            ]),
          )
        _ => None
      }
    },
    table_contract: fn(_) { None },
    tag_contract: fn(_) { None },
    memory_exists: fn(_) { false },
    data_segment_exists: fn(_) { false },
    element_segment_type: fn(_) { None },
  })
  for target in [@wasmoon_jit.NativeTarget::X64, AArch64] {
    for
      (type_, field, selects) in [
        (0, 0, false),
        (0, 1, false),
        (0, 2, false),
        (1, 2, true),
      ] {
      for write in [false, true] {
        let b = @milkir.FunctionBuilder("equal_field_offsets")
        b.add_param(Ptr) |> ignore
        let object = b.add_param(Ref)
        b.add_result(I64)
        if write {
          @wasm_milkir.struct_set(b, type_, field, object, b.iconst_i64(42L))
        }
        b.return_([@wasm_milkir.struct_get(b, type_, field, object, I64)])
        let diagnostics = @wasmoon_jit.compile_wasm_body_diagnostics_for_target(
          b.get_function(),
          context,
          target,
        )
        assert_eq(
          diagnostics.target_vcode.contains("Select("),
          write || selects,
        )
        if write {
          assert_true(diagnostics.code_object.contains("gc.struct_set_heap"))
        }
      }
    }
  }
}

///|
test "both targets retain collecting array fallback beside the no-GC constructor" {
  let validation = @wasm_milkir.WasmValidationContext::new({
    function_contract: fn(_) { None },
    defined_type_contract: fn(index) {
      Some(
        Array({
          storage: Value(
            match index {
              0 => I32
              1 => Ref
              _ => V128
            },
          ),
          mutable_: true,
          defaultable: true,
        }),
      )
    },
    table_contract: fn(_) { None },
    tag_contract: fn(_) { None },
    memory_exists: fn(_) { false },
    data_segment_exists: fn(_) { false },
    element_segment_type: fn(_) { None },
  })
  for type_index in 0..<3 {
    for default_ in [false, true] {
      let b = @milkir.FunctionBuilder("prepared_array")
      b.add_param(Ptr) |> ignore
      let length = b.add_param(I32)
      let init = b.add_param(
        match type_index {
          0 => I32
          1 => Ref
          _ => V128
        },
      )
      b.add_result(Ref)
      b.return_([
        if default_ {
          @wasm_milkir.array_new_default(b, type_index, length)
        } else {
          @wasm_milkir.array_new(b, type_index, init, length)
        },
      ])
      let vector = type_index == 2 && !default_
      for target in [@wasmoon_jit.NativeTarget::X64, AArch64] {
        let code = @wasmoon_jit.compile_wasm_body_artifact_function(
          b.get_function(),
          validation,
          target,
          function_index=0,
          signature=@native.Signature::new(
            [
              I32,
              match type_index {
                0 => I32
                1 => GcRef64
                _ => V128
              },
            ],
            [GcRef64],
          ),
        )
        for
          name in [
            if vector {
              "wasmoon.runtime.gc.try_array_wide"
            } else {
              "wasmoon.runtime.gc.try_array"
            },
            if vector {
              "wasmoon.runtime.gc.alloc_array_wide_slow"
            } else {
              "wasmoon.runtime.gc.alloc_array_slow"
            },
          ] {
          assert_eq(
            code.relocations
            .filter(r => r.target is External(symbol) && symbol.name == name)
            .length(),
            1,
          )
        }
        // Only the collecting fallback owns a GC safepoint; the prepared
        // constructor must not stage roots or acquire a collecting contract.
        assert_eq(
          code.safepoints
          .filter(site => site.kind is Gc || site.kind is GcAndCancellation)
          .length(),
          1,
        )
        if type_index == 1 && !default_ {
          // Registered function slots own the reference initializer. The
          // collecting site keeps its identity without duplicating SSA roots.
          assert_true(code.safepoints.all(site => site.roots.is_empty()))
          for
            name in [
              "wasmoon.runtime.gc.function_frame_enter", "wasmoon.runtime.gc.function_frame_leave",
            ] {
            assert_eq(
              code.relocations
              .filter(r => r.target is External(symbol) && symbol.name == name)
              .length(),
              1,
            )
          }
        }
      }
    }
  }
}

///|
test "large straight-line array initializers keep the original shared allocation path" {
  let validation = @wasm_milkir.WasmValidationContext::new({
    function_contract: fn(_) { None },
    defined_type_contract: fn(_) {
      Some(Array({ storage: Value(I32), mutable_: true, defaultable: true, }))
    },
    table_contract: fn(_) { None },
    tag_contract: fn(_) { None },
    memory_exists: fn(_) { false },
    data_segment_exists: fn(_) { false },
    element_segment_type: fn(_) { None },
  })
  for copies in [16, 17, 100] {
    let b = @milkir.FunctionBuilder("bounded_prepared_arrays")
    b.add_param(Ptr) |> ignore
    let length = b.add_param(I32)
    for _ in 0..<copies {
      @wasm_milkir.array_new_default(b, 0, length) |> ignore
    }
    b.return_([])
    for target in [@wasmoon_jit.NativeTarget::X64, AArch64] {
      let code = @wasmoon_jit.compile_wasm_body_artifact_function(
        b.get_function(),
        validation,
        target,
        function_index=0,
        signature=@native.Signature::new([I32], []),
      )
      for
        (name, expected) in [
          (
            "wasmoon.runtime.gc.try_array",
            if copies <= 16 {
              copies
            } else {
              0
            },
          ),
          ("wasmoon.runtime.gc.alloc_array_slow", copies),
        ] {
        assert_eq(
          code.relocations
          .filter(r => r.target is External(symbol) && symbol.name == name)
          .length(),
          expected,
        )
      }
    }
  }
}
