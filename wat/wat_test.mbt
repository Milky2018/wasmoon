// WAT Parser Tests

///|
test "parse empty module" {
  let wat = "(module)"
  let mod_ = parse(wat)
  inspect(mod_.funcs.length(), content="0")
  inspect(mod_.types.length(), content="0")
}

///|
test "parse module with type" {
  let wat =
    #|(module
    #|  (type (func (param i32 i32) (result i32)))
    #|)
  let mod_ = parse(wat)
  inspect(mod_.types.length(), content="1")
  inspect(mod_.types[0].params.length(), content="2")
  inspect(mod_.types[0].results.length(), content="1")
}

///|
test "parse simple function" {
  let wat =
    #|(module
    #|  (func (param i32 i32) (result i32)
    #|    local.get 0
    #|    local.get 1
    #|    i32.add
    #|  )
    #|)
  let mod_ = parse(wat)
  inspect(mod_.funcs.length(), content="1")
  inspect(mod_.codes.length(), content="1")
  inspect(mod_.codes[0].body.length(), content="3")
}

///|
test "parse function with export" {
  let wat =
    #|(module
    #|  (func (export "add") (param i32 i32) (result i32)
    #|    local.get 0
    #|    local.get 1
    #|    i32.add
    #|  )
    #|)
  let mod_ = parse(wat)
  inspect(mod_.exports.length(), content="1")
  inspect(mod_.exports[0].name, content="add")
}

///|
test "parse function with locals" {
  let wat =
    #|(module
    #|  (func (param i32) (result i32)
    #|    (local i32 i64)
    #|    local.get 0
    #|  )
    #|)
  let mod_ = parse(wat)
  inspect(mod_.codes[0].locals.length(), content="2")
}

///|
test "parse memory" {
  let wat =
    #|(module
    #|  (memory 1)
    #|)
  let mod_ = parse(wat)
  inspect(mod_.memories.length(), content="1")
  inspect(mod_.memories[0].limits.min, content="1")
}

///|
test "parse memory with max" {
  let wat =
    #|(module
    #|  (memory 1 16)
    #|)
  let mod_ = parse(wat)
  inspect(mod_.memories[0].limits.max, content="Some(16)")
}

///|
test "parse global" {
  let wat =
    #|(module
    #|  (global i32 (i32.const 42))
    #|)
  let mod_ = parse(wat)
  inspect(mod_.globals.length(), content="1")
  inspect(mod_.globals[0].type_.mutable, content="false")
}

///|
test "parse mutable global" {
  let wat =
    #|(module
    #|  (global (mut i32) (i32.const 0))
    #|)
  let mod_ = parse(wat)
  inspect(mod_.globals[0].type_.mutable, content="true")
}

///|
test "parse block instruction" {
  let wat =
    #|(module
    #|  (func (result i32)
    #|    block (result i32)
    #|      i32.const 1
    #|    end
    #|  )
    #|)
  let mod_ = parse(wat)
  inspect(mod_.codes[0].body.length(), content="1")
}

///|
test "parse if-else instruction" {
  let wat =
    #|(module
    #|  (func (param i32) (result i32)
    #|    local.get 0
    #|    if (result i32)
    #|      i32.const 1
    #|    else
    #|      i32.const 0
    #|    end
    #|  )
    #|)
  let mod_ = parse(wat)
  inspect(mod_.codes[0].body.length(), content="2")
}

///|
test "parse import" {
  let wat =
    #|(module
    #|  (type (func (param i32)))
    #|  (import "console" "log" (func (type 0)))
    #|)
  let mod_ = parse(wat)
  inspect(mod_.imports.length(), content="1")
  inspect(mod_.imports[0].mod_name, content="console")
  inspect(mod_.imports[0].name, content="log")
}

///|
test "parse hex number" {
  let wat =
    #|(module
    #|  (func (result i32)
    #|    i32.const 0xFF
    #|  )
    #|)
  let mod_ = parse(wat)
  match mod_.codes[0].body[0] {
    I32Const(n) => inspect(n, content="255")
    _ => panic()
  }
}

///|
test "parse comment" {
  let wat =
    #|(module
    #|  ;; This is a line comment
    #|  (func (result i32)
    #|    i32.const 42 ;; inline comment
    #|  )
    #|)
  let mod_ = parse(wat)
  inspect(mod_.funcs.length(), content="1")
}

///|
test "parse import with inline signature" {
  let wat =
    #|(module
    #|  (import "wasi" "fd_write" (func $fd_write (param i32 i32 i32 i32) (result i32)))
    #|)
  let mod_ = parse(wat)
  inspect(mod_.imports.length(), content="1")
  inspect(mod_.imports[0].mod_name, content="wasi")
  inspect(mod_.imports[0].name, content="fd_write")
  // The inline signature should be added to types
  inspect(mod_.types.length(), content="1")
  inspect(mod_.types[0].params.length(), content="4")
  inspect(mod_.types[0].results.length(), content="1")
}

///|
test "parse import with no params" {
  let wat =
    #|(module
    #|  (import "env" "exit" (func $exit (param i32)))
    #|)
  let mod_ = parse(wat)
  inspect(mod_.imports.length(), content="1")
  inspect(mod_.types.length(), content="1")
  inspect(mod_.types[0].params.length(), content="1")
  inspect(mod_.types[0].results.length(), content="0")
}

///|
test "parse import with only result" {
  let wat =
    #|(module
    #|  (import "env" "get_time" (func $get_time (result i64)))
    #|)
  let mod_ = parse(wat)
  inspect(mod_.imports.length(), content="1")
  inspect(mod_.types.length(), content="1")
  inspect(mod_.types[0].params.length(), content="0")
  inspect(mod_.types[0].results.length(), content="1")
}

///|
test "parse data segment" {
  let wat =
    #|(module
    #|  (memory 1)
    #|  (data (i32.const 8) "Hello, World!")
    #|)
  let mod_ = parse(wat)
  inspect(mod_.memories.length(), content="1")
  inspect(mod_.datas.length(), content="1")
  inspect(mod_.datas[0].memory_idx, content="0")
  inspect(mod_.datas[0].init.length(), content="13")
}

///|
test "parse data segment with offset keyword" {
  let wat =
    #|(module
    #|  (memory 1)
    #|  (data (offset (i32.const 100)) "test")
    #|)
  let mod_ = parse(wat)
  inspect(mod_.datas.length(), content="1")
  inspect(mod_.datas[0].init.length(), content="4")
}

// ============================================================
// Error Formatting Tests
// ============================================================

///|
test "format_wat_error shows source context" {
  let source =
    #|(module
    #|  (func (result i32)
    #|    invalid.instruction
    #|  )
    #|)
  let err = WatError::InvalidInstruction("invalid.instruction", SourceLoc::{
    line: 3,
    column: 5,
  })
  let formatted = format_wat_error(err, source)
  inspect(
    formatted,
    content=(
      #|error: invalid instruction: invalid.instruction
      #|  --> line 3, column 5
      #|   |
      #| 3 |     invalid.instruction
      #|   |     ^
      #|
    ),
  )
}

///|
test "format_wat_error with undefined identifier" {
  let source =
    #|(module
    #|  (func
    #|    call $undefined_func
    #|  )
    #|)
  let err = WatError::UndefinedIdentifier("func $undefined_func", SourceLoc::{
    line: 3,
    column: 10,
  })
  let formatted = format_wat_error(err, source)
  assert_true(formatted.contains("undefined identifier"))
  assert_true(formatted.contains("$undefined_func"))
}

///|
test "format_wat_error with unexpected token" {
  let source = "(module unexpected)"
  let err = WatError::UnexpectedToken("expected ')', got 'unexpected'", SourceLoc::{
    line: 1,
    column: 9,
  })
  let formatted = format_wat_error(err, source)
  assert_true(formatted.contains("unexpected token"))
  assert_true(formatted.contains("line 1"))
}

///|
test "parse inline table elem syntax" {
  let wat =
    #|(module
    #|  (table funcref (elem 0))
    #|)
  let mod_ = parse(wat)
  inspect(mod_.tables.length(), content="1")
  inspect(mod_.elems.length(), content="1")
}

///|
test "parse inline table elem with named function" {
  let wat =
    #|(module
    #|  (func $func (param i32 i32) (result i32) (local.get 0))
    #|  (type $check (func (param i32 i32) (result i32)))
    #|  (table funcref (elem $func))
    #|)
  let mod_ = parse(wat)
  inspect(mod_.tables.length(), content="1")
  inspect(mod_.elems.length(), content="1")
  // The element should contain the function index for $func (which is 0)
  inspect(mod_.elems[0].init.length(), content="1")
  inspect(mod_.elems[0].init[0], content="[RefFunc(0)]")
}

///|
test "parse inline table elem with named function - multiple funcs" {
  let wat =
    #|(module
    #|  (func $dummy)
    #|  (func $test1 (result i32) (i32.const 1))
    #|  (func $test2 (result i32) (i32.const 2))
    #|  (func $func (param i32 i32) (result i32) (local.get 0))
    #|  (table funcref (elem $func))
    #|)
  let mod_ = parse(wat)
  inspect(mod_.tables.length(), content="1")
  inspect(mod_.elems.length(), content="1")
  // $func is the 4th function (index 3)
  inspect(mod_.elems[0].init.length(), content="1")
  inspect(mod_.elems[0].init[0], content="[RefFunc(3)]")
}

///|
test "parse type index in call_indirect" {
  let wat =
    #|(module
    #|  (func $dummy)
    #|  (func $test1 (result i32) (i32.const 1))
    #|  (func $func (param i32 i32) (result i32) (local.get 0))
    #|  (type $check (func (param i32 i32) (result i32)))
    #|  (table funcref (elem $func))
    #|  (func (export "test") (result i32)
    #|    (call_indirect (type $check)
    #|      (i32.const 1) (i32.const 2) (i32.const 0)
    #|    )
    #|  )
    #|)
  let mod_ = parse(wat)
  // With explicit types parsed first:
  // Type 0: $check (i32, i32) -> i32 (explicit)
  // Type 1: () -> () ($dummy's implicit type)
  // Type 2: () -> i32 ($test1's and test's implicit type)
  // Note: $func reuses type 0 ($check) since it matches
  inspect(mod_.types.length(), content="3")
  // Check the call_indirect instruction - $check is type 0
  let test_func = mod_.codes[mod_.codes.length() - 1]
  inspect(
    test_func.body,
    content="[I32Const(1), I32Const(2), I32Const(0), CallIndirect(0, 0)]",
  )
}

///|
test "check type indices" {
  let wat =
    #|(module
    #|  (func $dummy)
    #|  (func $test1 (result i32) (i32.const 1))
    #|  (func $func (param i32 i32) (result i32) (local.get 0))
    #|  (type $check (func (param i32 i32) (result i32)))
    #|  (table funcref (elem $func))
    #|  (func (export "test") (result i32)
    #|    (call_indirect (type $check)
    #|      (i32.const 1) (i32.const 2) (i32.const 0)
    #|    )
    #|  )
    #|)
  let mod_ = parse(wat)
  // With explicit types parsed first:
  // Type 0: $check (i32, i32) -> i32 (explicit)
  // Type 1: () -> () ($dummy's implicit type)
  // Type 2: () -> i32 ($test1's and test's implicit type)
  // Note: $func reuses type 0 ($check) since it matches
  inspect(mod_.types.length(), content="3")
  inspect(mod_.types[0], content="{params: [I32, I32], results: [I32]}")
  inspect(mod_.types[1], content="{params: [], results: []}")
  inspect(mod_.types[2], content="{params: [], results: [I32]}")
}

///|
test "parse inline table elem - func index with dummy" {
  let wat =
    #|(module
    #|  (func $dummy)
    #|  (func $func (param i32 i32) (result i32) (local.get 0))
    #|  (type $check (func (param i32 i32) (result i32)))
    #|  (table funcref (elem $func))
    #|  (func (export "test") (result i32)
    #|    (call_indirect (type $check)
    #|      (i32.const 1) (i32.const 2) (i32.const 0)
    #|    )
    #|  )
    #|)
  let mod_ = parse(wat)
  // $func is the 2nd function (index 1)
  inspect(mod_.elems[0].init[0], content="[RefFunc(1)]")
  // With explicit types first, $check is type 0
  let test_func = mod_.codes[mod_.codes.length() - 1]
  inspect(
    test_func.body,
    content="[I32Const(1), I32Const(2), I32Const(0), CallIndirect(0, 0)]",
  )
}

///|
test "check funcs type indices" {
  let wat =
    #|(module
    #|  (func $dummy)
    #|  (func $func (param i32 i32) (result i32) (local.get 0))
    #|  (type $check (func (param i32 i32) (result i32)))
    #|  (table funcref (elem $func))
    #|  (func (export "test") (result i32)
    #|    (call_indirect (type $check)
    #|      (i32.const 1) (i32.const 2) (i32.const 0)
    #|    )
    #|  )
    #|)
  let mod_ = parse(wat)
  // With explicit types parsed first:
  // Type 0: $check (i32, i32) -> i32 (explicit)
  // Type 1: () -> () ($dummy's implicit type)
  // Type 2: () -> i32 (test's implicit type)
  // Function type indices:
  // func 0 ($dummy): type 1 = () -> ()
  // func 1 ($func): type 0 = (i32, i32) -> i32 (matches $check)
  // func 2 (test): type 2 = () -> i32
  inspect(mod_.funcs, content="[1, 0, 2]")
  // Types:
  inspect(mod_.types.length(), content="3")
  inspect(mod_.types[0], content="{params: [I32, I32], results: [I32]}")
  inspect(mod_.types[1], content="{params: [], results: []}")
  inspect(mod_.types[2], content="{params: [], results: [I32]}")
}

// ============================================================
// Float parsing precision tests (from const.wast failures)
// ============================================================

///|
test "f32 decimal literal rounding - case 551" {
  // const.wast line 551: (f32.const +8.8817847263968443574e-16) should be 0x1.000002p-50
  let wat =
    #|(module
    #|  (func (export "f") (result f32) (f32.const +8.8817847263968443574e-16))
    #|)
  let mod_ = parse(wat)
  if mod_.codes[0].body[0] is F32Const(f) {
    // Expected: 0x1.000002p-50 = 8.881785255792436e-16
    // Bits: 0x26800001 = 645922817
    inspect(f.reinterpret_as_int(), content="645922817")
  } else {
    panic()
  }
}

///|
test "f32 decimal literal rounding - case 553" {
  // const.wast line 553: (f32.const -8.8817847263968443574e-16) should be -0x1.000002p-50
  let wat =
    #|(module
    #|  (func (export "f") (result f32) (f32.const -8.8817847263968443574e-16))
    #|)
  let mod_ = parse(wat)
  if mod_.codes[0].body[0] is F32Const(f) {
    // Expected: -0x1.000002p-50 = -8.881785255792436e-16
    // Bits: 0xa6800001 = -1501560831 as signed
    inspect(f.reinterpret_as_int(), content="-1501560831")
  } else {
    panic()
  }
}

///|
test "f32 decimal literal rounding - case 555" {
  // const.wast line 555: (f32.const +8.8817857851880284252e-16) should be 0x1.000002p-50
  let wat =
    #|(module
    #|  (func (export "f") (result f32) (f32.const +8.8817857851880284252e-16))
    #|)
  let mod_ = parse(wat)
  if mod_.codes[0].body[0] is F32Const(f) {
    // Expected: 0x1.000002p-50 = 8.881785255792436e-16
    // Bits: 0x26800001 = 645922817
    inspect(f.reinterpret_as_int(), content="645922817")
  } else {
    panic()
  }
}

///|
test "f32 decimal literal rounding - case 557" {
  // const.wast line 557: (f32.const -8.8817857851880284252e-16) should be -0x1.000002p-50
  let wat =
    #|(module
    #|  (func (export "f") (result f32) (f32.const -8.8817857851880284252e-16))
    #|)
  let mod_ = parse(wat)
  if mod_.codes[0].body[0] is F32Const(f) {
    // Expected: -0x1.000002p-50 = -8.881785255792436e-16
    // Bits: 0xa6800001 = -1501560831 as signed
    inspect(f.reinterpret_as_int(), content="-1501560831")
  } else {
    panic()
  }
}

// ============================================================
// Regression test: f32.const 3 should parse correctly
// ============================================================

///|
test "f32 simple integer constant - regression" {
  // br.wast line 22-23: (func (export "type-f32-value") (result f32)
  //   (block (result f32) (f32.neg (br 0 (f32.const 3)))))
  // Expected: f32.const 3 should be 3.0, not 2.0
  let wat =
    #|(module
    #|  (func (export "f") (result f32) (f32.const 3))
    #|)
  let mod_ = parse(wat)
  match mod_.codes[0].body[0] {
    F32Const(f) => {
      // f32 3.0 should be 0x40400000 = 1077936128
      inspect(f, content="3")
      inspect(f.reinterpret_as_int(), content="1077936128")
    }
    _ => panic()
  }
}

///|
test "type-rec parsing with struct" {
  let wat =
    #|(module
    #|  (rec (type $ft (func)) (type (struct)))
    #|  (func $f (type $ft))
    #|  (global (ref $ft) (ref.func $f))
    #|)
  let mod_ = try! parse(wat)
  // Should parse successfully:
  // - Type 0 ($ft): func type () -> ()
  // - Type 1: struct placeholder () -> ()
  // Both in same rec group (id=0)
  inspect(mod_.types.length(), content="2")
  inspect(mod_.type_rec_groups, content="[0, 0]")
  inspect(mod_.funcs.length(), content="1")
  inspect(mod_.globals.length(), content="1")
}

///|
test "parse two simple rec groups" {
  let wat =
    #|(module
    #|  (rec (type $f1 (func)))
    #|  (rec (type $f2 (func)))
    #|)
  let mod_ = try! parse(wat)
  // Should have 2 types: $f1 at 0, $f2 at 1
  inspect(mod_.types.length(), content="2")
  inspect(mod_.type_rec_groups, content="[0, 1]")
}

///|
test "parse multiple rec groups with struct" {
  let wat =
    #|(module
    #|  (rec (type $f1 (func)) (type (struct)))
    #|  (rec (type $f2 (func)) (type (struct)))
    #|  (func $f (type $f2))
    #|)
  let mod_ = try! parse(wat)
  // Should have 4 types total:
  // - rec group 0: $f1 (func), struct placeholder
  // - rec group 2: $f2 (func), struct placeholder
  inspect(mod_.types.length(), content="4")
  inspect(mod_.type_rec_groups, content="[0, 0, 2, 2]")
  // Function $f should have type $f2 = index 2
  inspect(mod_.funcs, content="[2]")
}
