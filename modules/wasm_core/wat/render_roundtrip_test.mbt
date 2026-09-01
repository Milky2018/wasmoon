///|
fn assert_module_shape_eq(
  expected : @types.Module,
  actual : @types.Module,
) -> Unit raise {
  assert_eq(actual.types, expected.types)
  assert_eq(actual.type_rec_groups, expected.type_rec_groups)
  assert_eq(actual.imports, expected.imports)
  assert_eq(actual.funcs, expected.funcs)
  assert_eq(actual.tables, expected.tables)
  assert_eq(actual.memories, expected.memories)
  assert_eq(actual.globals, expected.globals)
  assert_eq(actual.exports, expected.exports)
  assert_eq(actual.start, expected.start)
  assert_eq(actual.elems, expected.elems)
  assert_eq(actual.codes, expected.codes)
  assert_eq(actual.datas, expected.datas)
  assert_eq(actual.tags, expected.tags)
}

///|
fn assert_render_roundtrip(source : String) -> Unit raise {
  let expected = parse(source)
  let rendered = render(expected)
  let actual = parse(rendered) catch {
    error => fail("rendered WAT did not parse: \{error}\n\{rendered}")
  }
  assert_module_shape_eq(expected, actual)
}

///|
test "canonical renderer round-trips every module section" {
  assert_render_roundtrip(
    (
      #|(module
      #|  (rec
      #|    (type (sub (struct (field (mut i32)))))
      #|    (type (array (mut (ref null 0))))
      #|  )
      #|  (type (func))
      #|  (type (func (param i32)))
      #|  (import "m" "f" (func (type 2)))
      #|  (import "m" "t" (table i64 1 2 funcref))
      #|  (import "m" "mem" (memory i64 1 2 (pagesize 1)))
      #|  (import "m" "g" (global (mut i32)))
      #|  (import "m" "e" (tag (type 3)))
      #|  (table i64 2 3 funcref (ref.null func))
      #|  (memory i64 1 2 (pagesize 256))
      #|  (global (mut i32) (i32.const 7))
      #|  (tag (type 3))
      #|  (func (type 2))
      #|  (export "f" (func 1))
      #|  (export "t" (table 1))
      #|  (export "m" (memory 1))
      #|  (export "g" (global 1))
      #|  (export "e" (tag 1))
      #|  (start 1)
      #|  (elem funcref (ref.func 1))
      #|  (elem declare funcref (ref.func 1))
      #|  (elem (table 1) (offset (i64.const 0)) funcref (ref.func 1))
      #|  (data "passive")
      #|  (data (memory 1) (offset (i64.const 0)) "active")
      #|)
    ),
  )
}

///|
test "canonical renderer preserves try_table catch handlers" {
  assert_render_roundtrip(
    (
      #|(module
      #|  (type (func))
      #|  (tag (type 0))
      #|  (func (type 0)
      #|    try_table
      #|      (catch 0 0)
      #|      (catch_ref 0 0)
      #|      (catch_all 0)
      #|      (catch_all_ref 0)
      #|      nop
      #|    end
      #|  )
      #|)
    ),
  )
}

///|
test "canonical renderer preserves floating-point bits" {
  let f32_bits : Array[UInt] = [
    0x00000001U, 0x007fffffU, 0x3f800001U, 0x7f7fffffU, 0x80000000U, 0xff800000U,
    0x7fc12345U, 0xff812345U,
  ]
  let f64_bits : Array[UInt64] = [
    0x0000000000000001UL, 0x000fffffffffffffUL, 0x3ff0000000000001UL, 0x7fefffffffffffffUL,
    0x8000000000000000UL, 0xfff0000000000000UL, 0x7ff8123456789abcUL, 0xfff0123456789abcUL,
  ]
  let body : Array[@types.Instruction] = []
  for bits in f32_bits {
    body.push(F32Const(Float::reinterpret_from_uint(bits)))
  }
  for bits in f64_bits {
    body.push(F64Const(bits.reinterpret_as_double()))
  }
  let expected = @types.Module::simple([], [], body, "float-bits")
  let rendered = render(expected)
  let actual = parse(rendered)
  for i, bits in f32_bits {
    guard actual.codes[0].body[i] is F32Const(value) else {
      fail("expected f32.const at instruction \{i}")
    }
    assert_eq(value.reinterpret_as_uint(), bits)
  }
  for i, bits in f64_bits {
    guard actual.codes[0].body[f32_bits.length() + i] is F64Const(value) else {
      fail("expected f64.const at instruction \{i}")
    }
    assert_eq(value.reinterpret_as_uint64(), bits)
  }
}
