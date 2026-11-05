///|
test "WAST invalid and unlinkable assertions reject failures from the wrong phase" {
  let sources = [
    "(assert_malformed (module quote \"(module)\") \"expected malformed\")", "(assert_invalid (module quote \"(module)\") \"\")",
    "(assert_unlinkable (module (func (result i32))) \"type mismatch\")", "(assert_unlinkable (module binary \"\\00asm\\01\\00\\00\\00\\01\\05\\01\\60\\00\\01\\7f\\03\\02\\01\\00\\0a\\04\\01\\02\\00\\0b\") \"type mismatch\")",
  ]
  for source in sources {
    let result = @wast.run_wast_commands(@wast.parse(source), false, false)
    debug_inspect((result.passed, result.failed), content="(0, 1)")
  }
}

///|
test "WAST quoted module text executes with its original module boundary" {
  let body =
    #|(module quote "(module (func (export \"run\") (result i32) i32.const 7))")
    #|(assert_return (invoke "run") (i32.const 7))
  let implicit_body =
    #|(module quote "(@annotation) (func (export \"run\") (result i32) i32.const 7) ;; trailing comment")
    #|(assert_return (invoke "run") (i32.const 7))
  for source in [body, implicit_body, "(module)(thread $child " + body + ")"] {
    for use_jit in [false, true] {
      let compiler = @wast.JITCompiler(fn(mod_, instance, store) {
        Ok(prepare_async_jit_context(mod_, instance, store, cooperative=true)) catch {
          error => Err("\{error}")
        }
      })
      let result = @wast.run_wast_commands(
        @wast.parse(source),
        use_jit,
        false,
        jit_compiler=Some(compiler),
      )
      debug_inspect((result.passed, result.failed), content="(1, 0)")
    }
  }
}

///|
test "WAST unlinkable assertions retain pinned start-trap behavior" {
  let source =
    #|(assert_invalid (module quote "(module (func (result i32)))") "type mismatch")
    #|(assert_unlinkable (module (func (import "missing" "f"))) "unknown import")
    #|(assert_unlinkable (module (func $start unreachable) (start $start)) "unreachable")
  let result = @wast.run_wast_commands(@wast.parse(source), false, false)
  debug_inspect((result.passed, result.failed), content="(3, 0)")
}

///|
test "quoted start traps are parsed and checked against the expected category" {
  let source =
    #|(assert_trap (module quote "(module (func $s unreachable) (start $s))") "unreachable")
    #|(assert_trap (module quote "(module (func $s unreachable) (start $s))") "integer divide by zero")
  for use_jit in [false, true] {
    let result = @wast.run_wast_commands(@wast.parse(source), use_jit, false)
    debug_inspect((result.passed, result.failed), content="(1, 1)")
  }
}

///|
test "assert_invalid requires successful decoding and a validation rejection" {
  let source =
    #|(assert_invalid (module quote "(module (func i32.const 0e))") "malformed number")
    #|(assert_invalid (module binary "\00asm") "truncated header")
    #|(assert_invalid (module (func i32.const 0e)) "malformed inline number")
    #|(assert_invalid (module (memory 1 1 shared)) "valid despite host restrictions")
    #|(assert_invalid (module (func (result i32))) "type mismatch")
  for use_jit in [false, true] {
    let result = @wast.run_wast_commands(@wast.parse(source), use_jit, false)
    assert_eq(result.passed, 1)
    assert_eq(result.failed, 4)
  }
}

///|
test "WAST resource imports compare types in their defining modules" {
  let source =
    #|(module
    #|  (type $record (struct (field i32)))
    #|  (global (export "g") (ref null $record) (ref.null $record))
    #|  (table (export "t") 1 (ref null $record)))
    #|(register "provider")
    #|(assert_unlinkable
    #|  (module
    #|    (type $record (struct (field i64)))
    #|    (import "provider" "g" (global (ref null $record))))
    #|  "incompatible import type")
    #|(assert_unlinkable
    #|  (module
    #|    (type $record (struct (field i64)))
    #|    (import "provider" "t" (table 1 (ref null $record))))
    #|  "incompatible import type")
    #|(module
    #|  (type $unused (func))
    #|  (type $record (struct (field i32)))
    #|  (import "provider" "g" (global (ref null $record)))
    #|  (import "provider" "t" (table 1 (ref null $record)))
    #|  (func (export "empty") (result i32)
    #|    global.get 0 ref.is_null
    #|    i32.const 0 table.get 0 ref.is_null
    #|    i32.and))
    #|(assert_return (invoke "empty") (i32.const 1))
    #|(module
    #|  (type $record (struct (field i32)))
    #|  (tag (export "t") (param (ref null $record))))
    #|(register "typed")
    #|(assert_unlinkable
    #|  (module
    #|    (type $record (struct (field i64)))
    #|    (import "typed" "t" (tag (param (ref null $record)))))
    #|  "incompatible import type")
    #|(module
    #|  (type $unused (func))
    #|  (type $record (struct (field i32)))
    #|  (import "typed" "t" (tag (param (ref null $record))))
    #|  (func (export "probe") (result i32) i32.const 7))
    #|(assert_return (invoke "probe") (i32.const 7))
    #|(module
    #|  (rec
    #|    (type $tag (func (param i32)))
    #|    (type $other (func)))
    #|  (tag (export "t") (type $tag)))
    #|(register "rec-group")
    #|(assert_unlinkable
    #|  (module (import "rec-group" "t" (tag (param i32))))
    #|  "incompatible import type")
    #|(module
    #|  (type $unrelated (struct))
    #|  (rec
    #|    (type $tag (func (param i32)))
    #|    (type $other (func)))
    #|  (import "rec-group" "t" (tag (type $tag)))
    #|  (func (export "probe") (result i32) i32.const 8))
    #|(assert_return (invoke "probe") (i32.const 8))
  let compiler = @wast.JITCompiler(fn(mod_, instance, store) {
    Ok(prepare_async_jit_context(mod_, instance, store)) catch {
      error => Err("\{error}")
    }
  })
  for use_jit in [false, true] {
    let result = @wast.run_wast_commands(
      @wast.parse(source),
      use_jit,
      false,
      jit_compiler=Some(compiler),
    )
    inspect(result.failures.join("\n"), content="")
    inspect(result.passed, content="7")
    inspect(result.failed, content="0")
    inspect(result.skipped, content="0")
  }
}
