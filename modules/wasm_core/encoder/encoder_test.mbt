///|
test "encode empty module" {
  debug_inspect(
    encode(@types.Module::empty()),
    content="[0, 97, 115, 109, 1, 0, 0, 0]",
  )
}

///|
test "encode UTF-8 export name" {
  let module_ = @types.Module::empty()
  module_.exports.push({ name: "é😀", desc: Func(0), })
  debug_inspect(
    encode(module_),
    content=(
      #|[
      #|  0,
      #|  97,
      #|  115,
      #|  109,
      #|  1,
      #|  0,
      #|  0,
      #|  0,
      #|  7,
      #|  10,
      #|  1,
      #|  6,
      #|  195,
      #|  169,
      #|  240,
      #|  159,
      #|  152,
      #|  128,
      #|  0,
      #|  0,
      #|]
    ),
  )
}
