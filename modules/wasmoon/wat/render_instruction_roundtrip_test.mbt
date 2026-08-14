///|
fn assert_instruction_roundtrip(body : String) -> Unit raise {
  let source = "(module\n" +
    "  (type (func))\n" +
    "  (type (struct (field (mut i32))))\n" +
    "  (type (array (mut i32)))\n" +
    "  (tag (type 0))\n" +
    "  (table 2 funcref)\n" +
    "  (table 2 funcref)\n" +
    "  (memory 1)\n" +
    "  (memory 1)\n" +
    "  (global (mut i32) (i32.const 0))\n" +
    "  (func (type 0)\n" +
    body +
    "\n  )\n" +
    "  (elem funcref)\n" +
    "  (data)\n" +
    ")"
  let expected = parse(source) catch {
    error => fail("instruction fixture did not parse: \{error}\n\{source}")
  }
  let rendered = @core_wat.render(expected)
  let actual = parse(rendered) catch {
    error =>
      fail("rendered instruction fixture did not parse: \{error}\n\{rendered}")
  }
  assert_eq(actual.codes, expected.codes)
}

///|
test "canonical renderer round-trips every no-immediate instruction" {
  assert_instruction_roundtrip(
    (
      #|
      #|    unreachable
      #|    nop
      #|    return
      #|    throw_ref
      #|    drop
      #|    select
      #|    ref.is_null
      #|    ref.as_non_null
      #|    ref.eq
      #|    i32.eqz
      #|    i32.eq
      #|    i32.ne
      #|    i32.lt_s
      #|    i32.lt_u
      #|    i32.gt_s
      #|    i32.gt_u
      #|    i32.le_s
      #|    i32.le_u
      #|    i32.ge_s
      #|    i32.ge_u
      #|    i32.clz
      #|    i32.ctz
      #|    i32.popcnt
      #|    i32.add
      #|    i32.sub
      #|    i32.mul
      #|    i32.div_s
      #|    i32.div_u
      #|    i32.rem_s
      #|    i32.rem_u
      #|    i32.and
      #|    i32.or
      #|    i32.xor
      #|    i32.shl
      #|    i32.shr_s
      #|    i32.shr_u
      #|    i32.rotl
      #|    i32.rotr
      #|    i32.extend8_s
      #|    i32.extend16_s
      #|    i64.eqz
      #|    i64.eq
      #|    i64.ne
      #|    i64.lt_s
      #|    i64.lt_u
      #|    i64.gt_s
      #|    i64.gt_u
      #|    i64.le_s
      #|    i64.le_u
      #|    i64.ge_s
      #|    i64.ge_u
      #|    i64.clz
      #|    i64.ctz
      #|    i64.popcnt
      #|    i64.add
      #|    i64.sub
      #|    i64.mul
      #|    i64.mul_wide_s
      #|    i64.mul_wide_u
      #|    i64.div_s
      #|    i64.div_u
      #|    i64.rem_s
      #|    i64.rem_u
      #|    i64.and
      #|    i64.or
      #|    i64.xor
      #|    i64.shl
      #|    i64.shr_s
      #|    i64.shr_u
      #|    i64.rotl
      #|    i64.rotr
      #|    i64.extend8_s
      #|    i64.extend16_s
      #|    i64.extend32_s
      #|    f32.eq
      #|    f32.ne
      #|    f32.lt
      #|    f32.gt
      #|    f32.le
      #|    f32.ge
      #|    f32.abs
      #|    f32.neg
      #|    f32.ceil
      #|    f32.floor
      #|    f32.trunc
      #|    f32.nearest
      #|    f32.sqrt
      #|    f32.add
      #|    f32.sub
      #|    f32.mul
      #|    f32.div
      #|    f32.min
      #|    f32.max
      #|    f32.copysign
      #|    f64.eq
      #|    f64.ne
      #|    f64.lt
      #|    f64.gt
      #|    f64.le
      #|    f64.ge
      #|    f64.abs
      #|    f64.neg
      #|    f64.ceil
      #|    f64.floor
      #|    f64.trunc
      #|    f64.nearest
      #|    f64.sqrt
      #|    f64.add
      #|    f64.sub
      #|    f64.mul
      #|    f64.div
      #|    f64.min
      #|    f64.max
      #|    f64.copysign
      #|    i32.wrap_i64
      #|    i32.trunc_f32_s
      #|    i32.trunc_f32_u
      #|    i32.trunc_f64_s
      #|    i32.trunc_f64_u
      #|    i64.extend_i32_s
      #|    i64.extend_i32_u
      #|    i64.trunc_f32_s
      #|    i64.trunc_f32_u
      #|    i64.trunc_f64_s
      #|    i64.trunc_f64_u
      #|    f32.convert_i32_s
      #|    f32.convert_i32_u
      #|    f32.convert_i64_s
      #|    f32.convert_i64_u
      #|    f32.demote_f64
      #|    f64.convert_i32_s
      #|    f64.convert_i32_u
      #|    f64.convert_i64_s
      #|    f64.convert_i64_u
      #|    f64.promote_f32
      #|    i32.reinterpret_f32
      #|    i64.reinterpret_f64
      #|    f32.reinterpret_i32
      #|    f64.reinterpret_i64
      #|    i32.trunc_sat_f32_s
      #|    i32.trunc_sat_f32_u
      #|    i32.trunc_sat_f64_s
      #|    i32.trunc_sat_f64_u
      #|    i64.trunc_sat_f32_s
      #|    i64.trunc_sat_f32_u
      #|    i64.trunc_sat_f64_s
      #|    i64.trunc_sat_f64_u
      #|    array.len
      #|    ref.i31
      #|    i31.get_s
      #|    i31.get_u
      #|    any.convert_extern
      #|    extern.convert_any
      #|    i8x16.swizzle
      #|    i8x16.splat
      #|    i16x8.splat
      #|    i32x4.splat
      #|    i64x2.splat
      #|    f32x4.splat
      #|    f64x2.splat
      #|    i8x16.eq
      #|    i8x16.ne
      #|    i8x16.lt_s
      #|    i8x16.lt_u
      #|    i8x16.gt_s
      #|    i8x16.gt_u
      #|    i8x16.le_s
      #|    i8x16.le_u
      #|    i8x16.ge_s
      #|    i8x16.ge_u
      #|    i16x8.eq
      #|    i16x8.ne
      #|    i16x8.lt_s
      #|    i16x8.lt_u
      #|    i16x8.gt_s
      #|    i16x8.gt_u
      #|    i16x8.le_s
      #|    i16x8.le_u
      #|    i16x8.ge_s
      #|    i16x8.ge_u
      #|    i32x4.eq
      #|    i32x4.ne
      #|    i32x4.lt_s
      #|    i32x4.lt_u
      #|    i32x4.gt_s
      #|    i32x4.gt_u
      #|    i32x4.le_s
      #|    i32x4.le_u
      #|    i32x4.ge_s
      #|    i32x4.ge_u
      #|    i64x2.eq
      #|    i64x2.ne
      #|    i64x2.lt_s
      #|    i64x2.gt_s
      #|    i64x2.le_s
      #|    i64x2.ge_s
      #|    f32x4.eq
      #|    f32x4.ne
      #|    f32x4.lt
      #|    f32x4.gt
      #|    f32x4.le
      #|    f32x4.ge
      #|    f64x2.eq
      #|    f64x2.ne
      #|    f64x2.lt
      #|    f64x2.gt
      #|    f64x2.le
      #|    f64x2.ge
      #|    v128.not
      #|    v128.and
      #|    v128.andnot
      #|    v128.or
      #|    v128.xor
      #|    v128.bitselect
      #|    v128.any_true
      #|    i8x16.abs
      #|    i8x16.neg
      #|    i8x16.popcnt
      #|    i8x16.all_true
      #|    i8x16.bitmask
      #|    i8x16.narrow_i16x8_s
      #|    i8x16.narrow_i16x8_u
      #|    i8x16.shl
      #|    i8x16.shr_s
      #|    i8x16.shr_u
      #|    i8x16.add
      #|    i8x16.add_sat_s
      #|    i8x16.add_sat_u
      #|    i8x16.sub
      #|    i8x16.sub_sat_s
      #|    i8x16.sub_sat_u
      #|    i8x16.min_s
      #|    i8x16.min_u
      #|    i8x16.max_s
      #|    i8x16.max_u
      #|    i8x16.avgr_u
      #|    i16x8.extadd_pairwise_i8x16_s
      #|    i16x8.extadd_pairwise_i8x16_u
      #|    i16x8.abs
      #|    i16x8.neg
      #|    i16x8.q15mulr_sat_s
      #|    i16x8.all_true
      #|    i16x8.bitmask
      #|    i16x8.narrow_i32x4_s
      #|    i16x8.narrow_i32x4_u
      #|    i16x8.extend_low_i8x16_s
      #|    i16x8.extend_high_i8x16_s
      #|    i16x8.extend_low_i8x16_u
      #|    i16x8.extend_high_i8x16_u
      #|    i16x8.shl
      #|    i16x8.shr_s
      #|    i16x8.shr_u
      #|    i16x8.add
      #|    i16x8.add_sat_s
      #|    i16x8.add_sat_u
      #|    i16x8.sub
      #|    i16x8.sub_sat_s
      #|    i16x8.sub_sat_u
      #|    i16x8.mul
      #|    i16x8.min_s
      #|    i16x8.min_u
      #|    i16x8.max_s
      #|    i16x8.max_u
      #|    i16x8.avgr_u
      #|    i16x8.extmul_low_i8x16_s
      #|    i16x8.extmul_high_i8x16_s
      #|    i16x8.extmul_low_i8x16_u
      #|    i16x8.extmul_high_i8x16_u
      #|    i32x4.extadd_pairwise_i16x8_s
      #|    i32x4.extadd_pairwise_i16x8_u
      #|    i32x4.abs
      #|    i32x4.neg
      #|    i32x4.all_true
      #|    i32x4.bitmask
      #|    i32x4.extend_low_i16x8_s
      #|    i32x4.extend_high_i16x8_s
      #|    i32x4.extend_low_i16x8_u
      #|    i32x4.extend_high_i16x8_u
      #|    i32x4.shl
      #|    i32x4.shr_s
      #|    i32x4.shr_u
      #|    i32x4.add
      #|    i32x4.sub
      #|    i32x4.mul
      #|    i32x4.min_s
      #|    i32x4.min_u
      #|    i32x4.max_s
      #|    i32x4.max_u
      #|    i32x4.dot_i16x8_s
      #|    i32x4.extmul_low_i16x8_s
      #|    i32x4.extmul_high_i16x8_s
      #|    i32x4.extmul_low_i16x8_u
      #|    i32x4.extmul_high_i16x8_u
      #|    i64x2.abs
      #|    i64x2.neg
      #|    i64x2.all_true
      #|    i64x2.bitmask
      #|    i64x2.extend_low_i32x4_s
      #|    i64x2.extend_high_i32x4_s
      #|    i64x2.extend_low_i32x4_u
      #|    i64x2.extend_high_i32x4_u
      #|    i64x2.shl
      #|    i64x2.shr_s
      #|    i64x2.shr_u
      #|    i64x2.add
      #|    i64x2.sub
      #|    i64x2.mul
      #|    i64x2.extmul_low_i32x4_s
      #|    i64x2.extmul_high_i32x4_s
      #|    i64x2.extmul_low_i32x4_u
      #|    i64x2.extmul_high_i32x4_u
      #|    f32x4.ceil
      #|    f32x4.floor
      #|    f32x4.trunc
      #|    f32x4.nearest
      #|    f32x4.abs
      #|    f32x4.neg
      #|    f32x4.sqrt
      #|    f32x4.add
      #|    f32x4.sub
      #|    f32x4.mul
      #|    f32x4.div
      #|    f32x4.min
      #|    f32x4.max
      #|    f32x4.pmin
      #|    f32x4.pmax
      #|    f64x2.ceil
      #|    f64x2.floor
      #|    f64x2.trunc
      #|    f64x2.nearest
      #|    f64x2.abs
      #|    f64x2.neg
      #|    f64x2.sqrt
      #|    f64x2.add
      #|    f64x2.sub
      #|    f64x2.mul
      #|    f64x2.div
      #|    f64x2.min
      #|    f64x2.max
      #|    f64x2.pmin
      #|    f64x2.pmax
      #|    i32x4.trunc_sat_f32x4_s
      #|    i32x4.trunc_sat_f32x4_u
      #|    f32x4.convert_i32x4_s
      #|    f32x4.convert_i32x4_u
      #|    i32x4.trunc_sat_f64x2_s_zero
      #|    i32x4.trunc_sat_f64x2_u_zero
      #|    f64x2.convert_low_i32x4_s
      #|    f64x2.convert_low_i32x4_u
      #|    f32x4.demote_f64x2_zero
      #|    f64x2.promote_low_f32x4
      #|    i8x16.relaxed_swizzle
      #|    i32x4.relaxed_trunc_f32x4_s
      #|    i32x4.relaxed_trunc_f32x4_u
      #|    i32x4.relaxed_trunc_f64x2_s_zero
      #|    i32x4.relaxed_trunc_f64x2_u_zero
      #|    f32x4.relaxed_madd
      #|    f32x4.relaxed_nmadd
      #|    f64x2.relaxed_madd
      #|    f64x2.relaxed_nmadd
      #|    i8x16.relaxed_laneselect
      #|    i16x8.relaxed_laneselect
      #|    i32x4.relaxed_laneselect
      #|    i64x2.relaxed_laneselect
      #|    f32x4.relaxed_min
      #|    f32x4.relaxed_max
      #|    f64x2.relaxed_min
      #|    f64x2.relaxed_max
      #|    i16x8.relaxed_q15mulr_s
      #|    i16x8.relaxed_dot_i8x16_i7x16_s
      #|    i32x4.relaxed_dot_i8x16_i7x16_add_s
    ),
  )
}

///|
test "canonical renderer round-trips immediate-bearing instructions" {
  assert_instruction_roundtrip(
    (
      #|    block
      #|      nop
      #|    end
      #|    block (result i32)
      #|    end
      #|    block (result i32 i64)
      #|    end
      #|    block (param i32) (result i64)
      #|    end
      #|    block (type 0)
      #|    end
      #|    loop
      #|      br 0
      #|      br_if 0
      #|      br_table 0 1 2
      #|    end
      #|    if
      #|      nop
      #|    else
      #|      nop
      #|    end
      #|    call 0
      #|    call_indirect (type 0)
      #|    call_indirect 1 (type 0)
      #|    call_ref 0
      #|    return_call 0
      #|    return_call_indirect (type 0)
      #|    return_call_indirect 1 (type 0)
      #|    return_call_ref 0
      #|    throw 0
      #|    select (result i32 i64)
      #|    local.get 1
      #|    local.set 1
      #|    local.tee 1
      #|    global.get 0
      #|    global.set 0
      #|    table.get 1
      #|    table.set 1
      #|    table.size 1
      #|    table.grow 1
      #|    table.fill 1
      #|    table.copy 1 0
      #|    table.init 1 0
      #|    i32.load 1 offset=7 align=2
      #|    i64.load 1 offset=7 align=4
      #|    f32.load 1 offset=7 align=2
      #|    f64.load 1 offset=7 align=4
      #|    i32.load8_s 1 offset=7 align=1
      #|    i32.load8_u 1 offset=7 align=1
      #|    i32.load16_s 1 offset=7 align=2
      #|    i32.load16_u 1 offset=7 align=2
      #|    i64.load8_s 1 offset=7 align=1
      #|    i64.load8_u 1 offset=7 align=1
      #|    i64.load16_s 1 offset=7 align=2
      #|    i64.load16_u 1 offset=7 align=2
      #|    i64.load32_s 1 offset=7 align=4
      #|    i64.load32_u 1 offset=7 align=4
      #|    i32.store 1 offset=7 align=2
      #|    i64.store 1 offset=7 align=4
      #|    f32.store 1 offset=7 align=2
      #|    f64.store 1 offset=7 align=4
      #|    i32.store8 1 offset=7 align=1
      #|    i32.store16 1 offset=7 align=2
      #|    i64.store8 1 offset=7 align=1
      #|    i64.store16 1 offset=7 align=2
      #|    i64.store32 1 offset=7 align=4
      #|    memory.size 1
      #|    memory.grow 1
      #|    memory.init 1 0
      #|    data.drop 0
      #|    memory.copy 1 0
      #|    memory.fill 1
      #|    elem.drop 0
      #|    i32.atomic.load 1 offset=7 align=2
      #|    ref.null func
      #|    ref.func 0
      #|    br_on_null 0
      #|    br_on_non_null 0
      #|    i32.const -2147483648
      #|    i64.const -9223372036854775808
      #|    f32.const -1.25
      #|    f64.const 1.25
      #|    struct.new 1
      #|    struct.new_default 1
      #|    struct.get 1 0
      #|    struct.get_s 1 0
      #|    struct.get_u 1 0
      #|    struct.set 1 0
      #|    array.new 2
      #|    array.new_default 2
      #|    array.new_fixed 2 3
      #|    array.new_data 2 0
      #|    array.new_elem 2 0
      #|    array.get 2
      #|    array.get_s 2
      #|    array.get_u 2
      #|    array.set 2
      #|    array.fill 2
      #|    array.copy 2 2
      #|    array.init_data 2 0
      #|    array.init_elem 2 0
      #|    ref.test (ref 1)
      #|    ref.test (ref null 1)
      #|    ref.cast (ref 1)
      #|    ref.cast (ref null 1)
      #|    br_on_cast 0 (ref null any) (ref 1)
      #|    br_on_cast_fail 0 (ref null any) (ref 1)
      #|    v128.const i8x16 0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15
      #|    v128.load 1 offset=7 align=8
      #|    v128.load8x8_s 1 offset=7 align=4
      #|    v128.load8x8_u 1 offset=7 align=4
      #|    v128.load16x4_s 1 offset=7 align=4
      #|    v128.load16x4_u 1 offset=7 align=4
      #|    v128.load32x2_s 1 offset=7 align=4
      #|    v128.load32x2_u 1 offset=7 align=4
      #|    v128.load8_splat 1 offset=7 align=1
      #|    v128.load16_splat 1 offset=7 align=2
      #|    v128.load32_splat 1 offset=7 align=4
      #|    v128.load64_splat 1 offset=7 align=8
      #|    v128.load32_zero 1 offset=7 align=4
      #|    v128.load64_zero 1 offset=7 align=8
      #|    v128.store 1 offset=7 align=8
      #|    v128.load8_lane 1 offset=7 align=1 15
      #|    v128.load16_lane 1 offset=7 align=2 7
      #|    v128.load32_lane 1 offset=7 align=4 3
      #|    v128.load64_lane 1 offset=7 align=8 1
      #|    v128.store8_lane 1 offset=7 align=1 15
      #|    v128.store16_lane 1 offset=7 align=2 7
      #|    v128.store32_lane 1 offset=7 align=4 3
      #|    v128.store64_lane 1 offset=7 align=8 1
      #|    i8x16.shuffle 0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 31
      #|    i8x16.extract_lane_s 15
      #|    i8x16.extract_lane_u 15
      #|    i16x8.extract_lane_s 7
      #|    i16x8.extract_lane_u 7
      #|    i32x4.extract_lane 3
      #|    i64x2.extract_lane 1
      #|    f32x4.extract_lane 3
      #|    f64x2.extract_lane 1
      #|    i8x16.replace_lane 15
      #|    i16x8.replace_lane 7
      #|    i32x4.replace_lane 3
      #|    i64x2.replace_lane 1
      #|    f32x4.replace_lane 3
      #|    f64x2.replace_lane 1
    ),
  )
}
