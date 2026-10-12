///|
suberror ExpectedExploreCompileFailure

///|
test "explore keeps an earlier compile failure after a later success" {
  let stamp = @env.now()
  let wat_path = @test_fs.temp_dir() + "/wasmoon-explore-status-\{stamp}.wat"
  let html_path = @test_fs.temp_dir() + "/wasmoon-explore-status-\{stamp}.html"
  @fs.write_string_to_file(
    wat_path,
    (
      #|(module
      #|  (func (export "first") (result i32) (i32.const 1))
      #|  (func (export "second") (result i32) (i32.const 2)))
    ),
  )
  defer (@fs.remove_file(wat_path) catch { _ => () })
  defer (@fs.remove_file(html_path) catch { _ => () })
  let events : Array[String] = []
  let status = run_explore_with_compiler(
    wat_path,
    None,
    2,
    [],
    true,
    false,
    "x64",
    fn(compile) raise {
      if events.is_empty() {
        events.push("failed")
        raise ExpectedExploreCompileFailure
      }
      let diagnostics = compile()
      events.push("succeeded")
      diagnostics
    },
  )
  debug_inspect(events, content="[\"failed\", \"succeeded\"]")
  inspect(status, content="1")
}

///|
test "x64 exploration compiles spilled multi-result transfers" {
  for ty in ["i32", "f64", "v128"] {
    let results = Array::make(20, ty).join(" ")
    let constant = if ty == "v128" {
      "v128.const i32x4 0 1 2 3"
    } else {
      "\{ty}.const 0"
    }
    let values = Array::make(20, constant).join(" ")
    let path = @test_fs.temp_dir() +
      "/wasmoon-x64-result-spills-\{ty}-\{@env.now()}.wat"
    let html = path[:path.length() - 4].to_owned() + ".html"
    @fs.write_string_to_file(
      path,
      "(module (func $callee (result \{results}) \{values}) (func (export \"run\") (result \{results}) call $callee))",
    )
    defer (@fs.remove_file(path) catch { _ => () })
    defer (@fs.remove_file(html) catch { _ => () })
    inspect(
      run_explore(path, None, 2, [], true, false, target_name="x64"),
      content="0",
    )
  }
}

///|
test "explore matches production artifacts with compact context and imported function indices" {
  let path = @test_fs.temp_dir() + "/wasmoon-explore-parity-\{@env.now()}.wat"
  let html = path[:path.length() - 4].to_owned() + ".html"
  @fs.write_string_to_file(
    path,
    (
      #|(module
      #|  (type $cell (struct (field i32)))
      #|  (import "host" "id" (func (param i32) (result i32)))
      #|  (memory 1)
      #|  (global $g (mut i32) (i32.const 3))
      #|  (func $internal_first (export "first") (param i32) (result i32)
      #|    local.get 0 i32.load global.get $g i32.add call 0
      #|    struct.new $cell struct.get $cell 0)
      #|  (func $internal_second (export "second") (param i32) (result i32)
      #|    local.get 0 call 1))
    ),
  )
  defer (@fs.remove_file(path) catch { _ => () })
  defer (@fs.remove_file(html) catch { _ => () })
  let mod_ = load_module_from_path(path)
  inspect(@wasmoon_jit.context_shape(mod_) != Legacy, content="true")
  for target in [@wasmoon_jit.NativeTarget::X64, AArch64] {
    for level in [0, 2] {
      let expected_functions = if target == @wasmoon_jit.host_native_target() {
        // Compare against the complete production module compiler on this host.
        compile_module_to_jit(mod_, false, false, level, false).unwrap().0.functions
      } else {
        // Cross-compile through the production artifact entry on the other target.
        let shape = @wasmoon_jit.context_shape(mod_)
        let compiler = @wasmoon_jit.NativeCompiler::new(
          target,
          context_shape=shape,
        )
        let context = @wasm_frontend.translation_context_from_module(
          mod_,
          @wasmoon.wasm_frontend_embedding_environment(context_shape=shape),
        )
        let validation = @wasm_frontend.wasm_validation_context(context)
        let functions : Array[@artifact.FunctionCode] = []
        for i, code in mod_.codes {
          let index = i + count_func_imports(mod_.imports)
          let func_type = mod_.validated_func_type_at(mod_.funcs[i])
          let function = @wasm_frontend.translate_function_body(
            context,
            get_func_name(mod_, index),
            func_type,
            code.locals,
            code.body,
          )
          @optimize.optimize_with_level(
            function,
            @optimize.OptLevel::from_int(level),
          )
          |> ignore
          functions.push(
            compiler.compile_wasm_body_artifact_function(
              function,
              validation,
              function_index=index,
              signature=@wasmoon_jit.wasm_function_signature(func_type),
            ),
          )
        }
        functions
      }
      // Ensure this fixture protects metadata as well as machine bytes.
      inspect(expected_functions[0].safepoints.is_empty(), content="false")
      inspect(expected_functions[0].relocations.is_empty(), content="false")
      let mut index = 0
      let status = run_explore_with_compiler(
        path,
        None,
        level,
        [],
        true,
        false,
        if target is X64 {
          "x64"
        } else {
          "aarch64"
        },
        fn(compile) raise {
          let diagnostics = compile()
          let expected = expected_functions[index]
          let bytes = expected.code
            .map(byte => @types.to_hex_byte(byte.to_int()))
            .join(" ")
          assert_eq(diagnostics.machine_code, bytes)
          assert_true(
            diagnostics.code_object.contains(
              "relocations: \{Repr(expected.relocations)}",
            ),
          )
          assert_true(
            diagnostics.code_object.contains(
              "sources: \{Repr(expected.sources)}",
            ),
          )
          assert_true(
            diagnostics.code_object.contains("traps: \{Repr(expected.traps)}"),
          )
          assert_true(
            diagnostics.code_object.contains(
              "safepoints: \{Repr(expected.safepoints)}",
            ),
          )
          assert_true(
            diagnostics.code_object.contains("unwind: \{Repr(expected.unwind)}"),
          )
          index += 1
          diagnostics
        },
      )
      inspect(status, content="0")
      inspect(index, content="2")
    }
  }
}
