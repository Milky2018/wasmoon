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
  inspect(mod_.get_func_type(0).params.length(), content="2")
  inspect(mod_.get_func_type(0).results.length(), content="1")
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
  inspect(mod_.get_func_type(0).params.length(), content="4")
  inspect(mod_.get_func_type(0).results.length(), content="1")
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
  inspect(mod_.get_func_type(0).params.length(), content="1")
  inspect(mod_.get_func_type(0).results.length(), content="0")
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
  inspect(mod_.get_func_type(0).params.length(), content="0")
  inspect(mod_.get_func_type(0).results.length(), content="1")
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

///|
test "reject trailing tokens after module" {
  let wat = "(module))"
  let result = try? parse(wat)
  match result {
    Err(_) => ()
    Ok(_) => fail("expected parse error but parsing succeeded")
  }
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
  inspect(
    mod_.types[0],
    content="{final_: true, supertypes: [], composite: Func({params: [I32, I32], results: [I32]})}",
  )
  inspect(
    mod_.types[1],
    content="{final_: true, supertypes: [], composite: Func({params: [], results: []})}",
  )
  inspect(
    mod_.types[2],
    content="{final_: true, supertypes: [], composite: Func({params: [], results: [I32]})}",
  )
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
  inspect(
    mod_.types[0],
    content="{final_: true, supertypes: [], composite: Func({params: [I32, I32], results: [I32]})}",
  )
  inspect(
    mod_.types[1],
    content="{final_: true, supertypes: [], composite: Func({params: [], results: []})}",
  )
  inspect(
    mod_.types[2],
    content="{final_: true, supertypes: [], composite: Func({params: [], results: [I32]})}",
  )
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

// ============================================================
// GC Type Parsing Tests
// ============================================================

///|
test "parse simple struct type" {
  let wat =
    #|(module
    #|  (type $point (struct (field i32) (field i32)))
    #|)
  let mod_ = parse(wat)
  inspect(mod_.types.length(), content="1")
  inspect(mod_.is_struct_type(0), content="true")
  let st = mod_.get_struct_type(0)
  inspect(st.fields.length(), content="2")
  inspect(st.fields[0].storage_type, content="Val(I32)")
  inspect(st.fields[1].storage_type, content="Val(I32)")
}

///|
test "parse struct type with named fields" {
  let wat =
    #|(module
    #|  (type $point (struct (field $x i32) (field $y i32)))
    #|)
  let mod_ = parse(wat)
  inspect(mod_.types.length(), content="1")
  let st = mod_.get_struct_type(0)
  inspect(st.fields.length(), content="2")
}

///|
test "parse struct type with mutable fields" {
  let wat =
    #|(module
    #|  (type $point (struct (field (mut i32)) (field (mut f64))))
    #|)
  let mod_ = parse(wat)
  let st = mod_.get_struct_type(0)
  inspect(st.fields[0].mutable, content="true")
  inspect(st.fields[0].storage_type, content="Val(I32)")
  inspect(st.fields[1].mutable, content="true")
  inspect(st.fields[1].storage_type, content="Val(F64)")
}

///|
test "parse struct type with packed fields" {
  let wat =
    #|(module
    #|  (type $bytes (struct (field i8) (field i16)))
    #|)
  let mod_ = parse(wat)
  let st = mod_.get_struct_type(0)
  inspect(st.fields[0].storage_type, content="Packed(I8)")
  inspect(st.fields[1].storage_type, content="Packed(I16)")
}

///|
test "parse struct type with mutable packed fields" {
  let wat =
    #|(module
    #|  (type $buf (struct (field (mut i8)) (field (mut i16))))
    #|)
  let mod_ = parse(wat)
  let st = mod_.get_struct_type(0)
  inspect(st.fields[0].mutable, content="true")
  inspect(st.fields[0].storage_type, content="Packed(I8)")
  inspect(st.fields[1].mutable, content="true")
  inspect(st.fields[1].storage_type, content="Packed(I16)")
}

///|
test "parse simple array type" {
  let wat =
    #|(module
    #|  (type $vec (array f64))
    #|)
  let mod_ = parse(wat)
  inspect(mod_.types.length(), content="1")
  inspect(mod_.is_array_type(0), content="true")
  let at = mod_.get_array_type(0)
  inspect(at.element.storage_type, content="Val(F64)")
  inspect(at.element.mutable, content="false")
}

///|
test "parse mutable array type" {
  let wat =
    #|(module
    #|  (type $vec (array (mut f64)))
    #|)
  let mod_ = parse(wat)
  let at = mod_.get_array_type(0)
  inspect(at.element.storage_type, content="Val(F64)")
  inspect(at.element.mutable, content="true")
}

///|
test "parse array type with packed element" {
  let wat =
    #|(module
    #|  (type $bytes (array (mut i8)))
    #|)
  let mod_ = parse(wat)
  let at = mod_.get_array_type(0)
  inspect(at.element.storage_type, content="Packed(I8)")
  inspect(at.element.mutable, content="true")
}

///|
test "parse mixed func, struct, array types" {
  let wat =
    #|(module
    #|  (type $add (func (param i32 i32) (result i32)))
    #|  (type $point (struct (field $x i32) (field $y i32)))
    #|  (type $vec (array (mut f64)))
    #|)
  let mod_ = parse(wat)
  inspect(mod_.types.length(), content="3")
  inspect(mod_.is_func_type(0), content="true")
  inspect(mod_.is_struct_type(1), content="true")
  inspect(mod_.is_array_type(2), content="true")
  // Check func type
  let ft = mod_.get_func_type(0)
  inspect(ft.params, content="[I32, I32]")
  inspect(ft.results, content="[I32]")
  // Check struct type
  let st = mod_.get_struct_type(1)
  inspect(st.fields.length(), content="2")
  // Check array type
  let at = mod_.get_array_type(2)
  inspect(at.element.storage_type, content="Val(F64)")
}

///|
test "parse struct with reference field" {
  let wat =
    #|(module
    #|  (type $node (struct
    #|    (field $val i32)
    #|    (field $next (ref null $node))
    #|  ))
    #|)
  let mod_ = parse(wat)
  let st = mod_.get_struct_type(0)
  inspect(st.fields.length(), content="2")
  inspect(st.fields[0].storage_type, content="Val(I32)")
  // The second field is a nullable reference to type 0
  inspect(st.fields[1].storage_type, content="Val(RefNullFuncTyped(0))")
}

///|
test "parse array of references" {
  let wat =
    #|(module
    #|  (type $point (struct (field i32) (field i32)))
    #|  (type $points (array (mut (ref null $point))))
    #|)
  let mod_ = parse(wat)
  inspect(mod_.types.length(), content="2")
  let at = mod_.get_array_type(1)
  inspect(at.element.mutable, content="true")
  // Reference to struct at index 0
  inspect(at.element.storage_type, content="Val(RefNullStruct(0))")
}

///|
test "parse sub keyword for type inheritance" {
  let wat =
    #|(module
    #|  (type $t0 (sub (struct)))
    #|  (type $t1 (sub $t0 (struct (field i32))))
    #|  (type $t2 (sub $t1 (struct (field i32) (field i32))))
    #|)
  let mod_ = parse(wat)
  inspect(mod_.types.length(), content="3")
  // t0: non-final type without parent
  inspect(mod_.types[0].final_, content="false")
  inspect(mod_.types[0].supertypes.length(), content="0")
  // t1: non-final type with parent t0
  inspect(mod_.types[1].final_, content="false")
  inspect(mod_.types[1].supertypes.length(), content="1")
  inspect(mod_.types[1].supertypes[0], content="0")
  // t2: non-final type with parent t1
  inspect(mod_.types[2].final_, content="false")
  inspect(mod_.types[2].supertypes.length(), content="1")
  inspect(mod_.types[2].supertypes[0], content="1")
}

///|
test "parse sub final keyword" {
  let wat =
    #|(module
    #|  (type $t0 (sub (struct)))
    #|  (type $t1 (sub final $t0 (struct (field i32))))
    #|)
  let mod_ = parse(wat)
  inspect(mod_.types.length(), content="2")
  // t0: non-final
  inspect(mod_.types[0].final_, content="false")
  // t1: final with parent t0
  inspect(mod_.types[1].final_, content="true")
  inspect(mod_.types[1].supertypes.length(), content="1")
  inspect(mod_.types[1].supertypes[0], content="0")
}

///|
test "parse empty struct type" {
  let wat =
    #|(module
    #|  (type $empty (struct))
    #|)
  let mod_ = parse(wat)
  inspect(mod_.types.length(), content="1")
  inspect(mod_.is_struct_type(0), content="true")
  let st = mod_.get_struct_type(0)
  inspect(st.fields.length(), content="0")
}

///|
test "parse abbreviated field syntax with multiple types" {
  let wat =
    #|(module
    #|  (type $t (struct (field i32 i32)))
    #|)
  let mod_ = parse(wat)
  inspect(mod_.types.length(), content="1")
  let st = mod_.get_struct_type(0)
  inspect(st.fields.length(), content="2")
  inspect(st.fields[0].storage_type, content="Val(I32)")
  inspect(st.fields[1].storage_type, content="Val(I32)")
}

///|
test "parse struct.get with field name" {
  let wat =
    #|(module
    #|  (type $vec (struct (field f32) (field $y (mut f32)) (field $z f32)))
    #|  (func (param (ref $vec)) (result f32)
    #|    (struct.get $vec $y (local.get 0))
    #|  )
    #|)
  let mod_ = parse(wat)
  inspect(mod_.types.length(), content="2")
  // struct.get $vec $y should resolve $y to field index 1
  let body = mod_.codes[0].body
  inspect(body[0], content="LocalGet(0)")
  inspect(body[1], content="StructGet(0, 1)")
}

// ============================================================
// Memory64 Tests
// ============================================================

///|
test "parse memory64 basic" {
  // Memory64: (memory i64 min)
  let wat =
    #|(module
    #|  (memory i64 1)
    #|)
  let mod_ = parse(wat)
  inspect(mod_.memories.length(), content="1")
  inspect(mod_.memories[0].limits.min, content="1")
  inspect(mod_.memories[0].is_memory64, content="true")
}

///|
test "parse memory64 with max" {
  // Memory64: (memory i64 min max)
  let wat =
    #|(module
    #|  (memory i64 1 16)
    #|)
  let mod_ = parse(wat)
  inspect(mod_.memories[0].limits.min, content="1")
  inspect(mod_.memories[0].limits.max, content="Some(16)")
  inspect(mod_.memories[0].is_memory64, content="true")
}

///|
test "parse memory32 default" {
  // Default is memory32 (no i64 keyword)
  let wat =
    #|(module
    #|  (memory 1)
    #|)
  let mod_ = parse(wat)
  inspect(mod_.memories[0].is_memory64, content="false")
}

///|
test "parse memory64 with export" {
  let wat =
    #|(module
    #|  (memory (export "mem64") i64 1)
    #|)
  let mod_ = parse(wat)
  inspect(mod_.memories[0].is_memory64, content="true")
  inspect(mod_.exports.length(), content="1")
  inspect(mod_.exports[0].name, content="mem64")
}

///|
test "parse memory64 import" {
  let wat =
    #|(module
    #|  (import "env" "mem" (memory i64 1 2))
    #|)
  let mod_ = parse(wat)
  inspect(mod_.imports.length(), content="1")
  inspect(mod_.imports[0].mod_name, content="env")
  inspect(mod_.imports[0].name, content="mem")
  if mod_.imports[0].desc is @types.ImportDesc::Memory(mem_type) {
    inspect(mem_type.is_memory64, content="true")
    inspect(mem_type.limits.min, content="1")
    inspect(mem_type.limits.max, content="Some(2)")
  } else {
    panic()
  }
}

///|
test "parse memory64 data segment with i64 offset" {
  let wat =
    #|(module
    #|  (memory i64 1)
    #|  (data (i64.const 0x100) "test")
    #|)
  let mod_ = parse(wat)
  inspect(mod_.memories[0].is_memory64, content="true")
  inspect(mod_.datas.length(), content="1")
  // Offset should be i64.const
  inspect(mod_.datas[0].offset[0], content="I64Const(256)")
}

// ============================================================
// Table64 Tests
// ============================================================

///|
test "parse table64 basic" {
  // Table64: (table i64 min reftype)
  let wat =
    #|(module
    #|  (table i64 1 funcref)
    #|)
  let mod_ = parse(wat)
  inspect(mod_.tables.length(), content="1")
  inspect(mod_.tables[0].type_.limits.min, content="1")
  inspect(mod_.tables[0].type_.is_table64, content="true")
}

///|
test "parse table64 with max" {
  // Table64: (table i64 min max reftype)
  let wat =
    #|(module
    #|  (table i64 1 10 funcref)
    #|)
  let mod_ = parse(wat)
  inspect(mod_.tables[0].type_.limits.min, content="1")
  inspect(mod_.tables[0].type_.limits.max, content="Some(10)")
  inspect(mod_.tables[0].type_.is_table64, content="true")
}

///|
test "parse table32 default" {
  // Default is table32 (no i64 keyword)
  let wat =
    #|(module
    #|  (table 1 funcref)
    #|)
  let mod_ = parse(wat)
  inspect(mod_.tables[0].type_.is_table64, content="false")
}

///|
test "parse table64 with export" {
  let wat =
    #|(module
    #|  (table (export "tbl64") i64 1 funcref)
    #|)
  let mod_ = parse(wat)
  inspect(mod_.tables[0].type_.is_table64, content="true")
  inspect(mod_.exports.length(), content="1")
  inspect(mod_.exports[0].name, content="tbl64")
}

///|
test "parse table64 import" {
  let wat =
    #|(module
    #|  (import "env" "tbl" (table i64 1 10 funcref))
    #|)
  let mod_ = parse(wat)
  inspect(mod_.imports.length(), content="1")
  inspect(mod_.imports[0].mod_name, content="env")
  inspect(mod_.imports[0].name, content="tbl")
  if mod_.imports[0].desc is @types.ImportDesc::Table(tbl_type) {
    inspect(tbl_type.is_table64, content="true")
    inspect(tbl_type.limits.min, content="1")
    inspect(tbl_type.limits.max, content="Some(10)")
  } else {
    panic()
  }
}

///|
test "parse table64 elem segment with i64 offset" {
  let wat =
    #|(module
    #|  (table i64 10 funcref)
    #|  (func $f)
    #|  (elem (i64.const 0) $f)
    #|)
  let mod_ = parse(wat)
  inspect(mod_.tables[0].type_.is_table64, content="true")
  inspect(mod_.elems.length(), content="1")
  // Check elem mode offset expression
  if mod_.elems[0].mode is @types.ElemMode::Active(_, offset_expr) {
    inspect(offset_expr[0], content="I64Const(0)")
  } else {
    panic()
  }
}

///|
test "parse table64 externref" {
  let wat =
    #|(module
    #|  (table i64 5 externref)
    #|)
  let mod_ = parse(wat)
  inspect(mod_.tables[0].type_.is_table64, content="true")
  inspect(mod_.tables[0].type_.elem_type, content="ExternRef")
}

///|
test "parse multi-memory with memory64" {
  let wat =
    #|(module
    #|  (memory $m0 1)
    #|  (memory $m1 i64 2)
    #|)
  let mod_ = parse(wat)
  inspect(mod_.memories.length(), content="2")
  inspect(mod_.memories[0].is_memory64, content="false")
  inspect(mod_.memories[1].is_memory64, content="true")
}

///|
test "parse multi-table with table64" {
  let wat =
    #|(module
    #|  (table $t0 1 funcref)
    #|  (table $t1 i64 2 funcref)
    #|)
  let mod_ = parse(wat)
  inspect(mod_.tables.length(), content="2")
  inspect(mod_.tables[0].type_.is_table64, content="false")
  inspect(mod_.tables[1].type_.is_table64, content="true")
}

///|
test "parse table64 with large 64-bit limits" {
  // Regression test: table64 limits must use u64 parsing, not u32
  let wat =
    #|(module
    #|  (table i64 0xffff_ffff_ffff funcref)
    #|)
  let mod_ = parse(wat)
  inspect(mod_.tables.length(), content="1")
  inspect(mod_.tables[0].type_.is_table64, content="true")
  // 0xffffffffffff = 281474976710655
  inspect(mod_.tables[0].type_.limits.min, content="281474976710655")
  inspect(mod_.tables[0].type_.limits.max, content="None")
}

///|
test "parse table64 with large 64-bit min and max" {
  // Regression test: both min and max must use u64 parsing
  let wat =
    #|(module
    #|  (table i64 0x1_0000_0000 0x2_0000_0000 funcref)
    #|)
  let mod_ = parse(wat)
  inspect(mod_.tables[0].type_.is_table64, content="true")
  // 0x100000000 = 4294967296 (larger than u32 max)
  inspect(mod_.tables[0].type_.limits.min, content="4294967296")
  // 0x200000000 = 8589934592
  inspect(mod_.tables[0].type_.limits.max, content="Some(8589934592)")
}

///|
test "parse table64 import with large 64-bit limits" {
  // Regression test: imported table64 limits must use u64 parsing
  let wat =
    #|(module
    #|  (import "m" "t" (table i64 0xffff_ffff_ffff 0x1_0000_0000_0000 funcref))
    #|)
  let mod_ = parse(wat)
  guard mod_.imports[0].desc is @types.ImportDesc::Table(tbl_type) else {
    return
  }
  inspect(tbl_type.is_table64, content="true")
  // 0xffffffffffff = 281474976710655
  inspect(tbl_type.limits.min, content="281474976710655")
  // 0x1000000000000 = 281474976710656
  inspect(tbl_type.limits.max, content="Some(281474976710656)")
}
