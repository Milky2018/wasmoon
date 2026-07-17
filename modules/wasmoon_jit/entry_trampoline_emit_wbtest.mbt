///|
test "entry trampoline IR verifies with i64 pointer carriers" {
  inspect(generate_trampoline_ir([], []).verify(), content="()")
}

///|
test "entry trampoline preserves mixed float classes in large signatures" {
  let params = [
    TYPE_I32,
    TYPE_I64,
    TYPE_F32,
    TYPE_F32,
    TYPE_I32,
    TYPE_F64,
    TYPE_F32,
    TYPE_I32,
    TYPE_I32,
    TYPE_I32,
    TYPE_F32,
    TYPE_F64,
    TYPE_F64,
    TYPE_F64,
    TYPE_I32,
    TYPE_I32,
    TYPE_F32,
  ]
  let results = [
    TYPE_F64,
    TYPE_F32,
    TYPE_I32,
    TYPE_I32,
    TYPE_I32,
    TYPE_I64,
    TYPE_F32,
    TYPE_I32,
    TYPE_I32,
    TYPE_F32,
    TYPE_F64,
    TYPE_F64,
    TYPE_I32,
    TYPE_F32,
    TYPE_I32,
    TYPE_F64,
  ]
  let ir = generate_trampoline_ir(params, results)
  let isa = @isa.ISA::AArch64
  let embedding_abi = @abi.EmbeddingABI::EmbeddingABI(
    wasm_calling_convention(isa~),
    reg_roles=wasm_embedding_reg_roles(isa~),
    context_layout=Some(embedding_context_layout()),
  )
  let function = @machv_regalloc.allocate_registers_backtracking_with_isa(
    lower_semantic_core_with_isa(ir, isa, embedding_abi),
    isa,
    embedding_abi=Some(embedding_abi),
  )
  inspect(
    function,
    content=(
      #|machv trampoline(v0:int, v1:int, v2:int) -> int {
      #|block0:
      #|    x3 = ldi 0
      #|    x4 = mov x19
      #|    x5 = add x4, x3
      #|    x6 = load_ptr.i32 +0 x5
      #|    x7 = ldi 8
      #|    x8 = mov x19
      #|    x9 = add x8, x7
      #|    x10 = load_ptr.i64 +0 x9
      #|    x11 = ldi 16
      #|    x12 = mov x19
      #|    x13 = add x12, x11
      #|    d24 = load_ptr.f32 +0 x13
      #|    x15 = ldi 24
      #|    x1 = mov x19
      #|    x1 = add x1, x15
      #|    d28 = load_ptr.f32 +0 x1
      #|    x3 = ldi 32
      #|    x4 = mov x19
      #|    x5 = add x4, x3
      #|    x7 = load_ptr.i32 +0 x5
      #|    x8 = ldi 40
      #|    x9 = mov x19
      #|    x9 = add x9, x8
      #|    d4 = load_ptr.f64 +0 x9
      #|    x11 = ldi 48
      #|    x12 = mov x19
      #|    x13 = add x12, x11
      #|    d18 = load_ptr.f32 +0 x13
      #|    x15 = ldi 56
      #|    x1 = mov x19
      #|    x1 = add x1, x15
      #|    x3 = load_ptr.i32 +0 x1
      #|    x4 = ldi 64
      #|    x5 = mov x19
      #|    x5 = add x5, x4
      #|    x8 = load_ptr.i32 +0 x5
      #|    x9 = ldi 72
      #|    x11 = mov x19
      #|    x9 = add x11, x9
      #|    x11 = load_ptr.i32 +0 x9
      #|    x12 = ldi 80
      #|    x13 = mov x19
      #|    x13 = add x13, x12
      #|    d2 = load_ptr.f32 +0 x13
      #|    x15 = ldi 88
      #|    x1 = mov x19
      #|    x1 = add x1, x15
      #|    d6 = load_ptr.f64 +0 x1
      #|    x4 = ldi 96
      #|    x5 = mov x19
      #|    x5 = add x5, x4
      #|    d20 = load_ptr.f64 +0 x5
      #|    x9 = ldi 104
      #|    x12 = mov x19
      #|    x9 = add x12, x9
      #|    d25 = load_ptr.f64 +0 x9
      #|    x12 = ldi 112
      #|    x13 = mov x19
      #|    x13 = add x13, x12
      #|    x14 = load_ptr.i32 +0 x13
      #|    x15 = ldi 120
      #|    x1 = mov x19
      #|    x1 = add x1, x15
      #|    x4 = load_ptr.i32 +0 x1
      #|    x5 = ldi 128
      #|    x9 = mov x19
      #|    x5 = add x9, x5
      #|    d5 = load_ptr.f32 +0 x5
      #|    x9 = mov x2
      #|    str [sp+0] x4
      #|    str [sp+8] d5
      #|    x17 = mov x9
      #|    x1 = mov x6
      #|    x2 = mov x10
      #|    x4 = mov x3
      #|    x3 = mov x7
      #|    x5 = mov x8
      #|    x6 = mov x11
      #|    x7 = mov x14
      #|    d0 = mov d24
      #|    d1 = mov d28
      #|    d3 = mov d18
      #|    d5 = mov d6
      #|    d6 = mov d20
      #|    d7 = mov d25
      #|    d16 = mov d2
      #|    d2 = mov d4
      #|    d4 = mov d16
      #|    d0, d1, x0, x1, x2, x3, d2, x4, x5, d3, d4, d5, x6, d6, x7, d7 = call_ptr[Internal](17) -> 16 results x17
      #|    x10 = mov x0
      #|    x11 = mov x1
      #|    x12 = mov x2
      #|    x13 = mov x3
      #|    x15 = mov x4
      #|    x0 = mov x5
      #|    x4 = mov x6
      #|    x6 = mov x7
      #|    d22 = mov d2
      #|    d25 = mov d3
      #|    d26 = mov d4
      #|    d27 = mov d5
      #|    d29 = mov d6
      #|    d6 = mov d0
      #|    d31 = mov d7
      #|    d7 = mov d1
      #|    x8 = ldi 136
      #|    x9 = mov x19
      #|    x14 = add x9, x8
      #|    store_ptr.f64 +0 x14, d6
      #|    x14 = ldi 144
      #|    x1 = mov x19
      #|    x14 = add x1, x14
      #|    store_ptr.f32 +0 x14, d7
      #|    x14 = ldi 152
      #|    x1 = mov x19
      #|    x1 = add x1, x14
      #|    store_ptr.i32 +0 x1, x10
      #|    x1 = ldi 160
      #|    x2 = mov x19
      #|    x3 = add x2, x1
      #|    store_ptr.i32 +0 x3, x11
      #|    x5 = ldi 168
      #|    x7 = mov x19
      #|    x7 = add x7, x5
      #|    store_ptr.i32 +0 x7, x12
      #|    x7 = ldi 176
      #|    x8 = mov x19
      #|    x9 = add x8, x7
      #|    store_ptr.i64 +0 x9, x13
      #|    x10 = ldi 184
      #|    x11 = mov x19
      #|    x12 = add x11, x10
      #|    store_ptr.f32 +0 x12, d22
      #|    x13 = ldi 192
      #|    x14 = mov x19
      #|    x1 = add x14, x13
      #|    store_ptr.i32 +0 x1, x15
      #|    x1 = ldi 200
      #|    x2 = mov x19
      #|    x2 = add x2, x1
      #|    store_ptr.i32 +0 x2, x0
      #|    x3 = ldi 208
      #|    x5 = mov x19
      #|    x5 = add x5, x3
      #|    store_ptr.f32 +0 x5, d25
      #|    x7 = ldi 216
      #|    x8 = mov x19
      #|    x8 = add x8, x7
      #|    store_ptr.f64 +0 x8, d26
      #|    x9 = ldi 224
      #|    x10 = mov x19
      #|    x11 = add x10, x9
      #|    store_ptr.f64 +0 x11, d27
      #|    x12 = ldi 232
      #|    x13 = mov x19
      #|    x14 = add x13, x12
      #|    store_ptr.i32 +0 x14, x4
      #|    x15 = ldi 240
      #|    x0 = mov x19
      #|    x1 = add x0, x15
      #|    store_ptr.f32 +0 x1, d29
      #|    x2 = ldi 248
      #|    x3 = mov x19
      #|    x4 = add x3, x2
      #|    store_ptr.i32 +0 x4, x6
      #|    x5 = ldi 256
      #|    x6 = mov x19
      #|    x7 = add x6, x5
      #|    store_ptr.f64 +0 x7, d31
      #|    x8 = ldi 0
      #|    ret x8
      #|}
      #|
    ),
  )
}
