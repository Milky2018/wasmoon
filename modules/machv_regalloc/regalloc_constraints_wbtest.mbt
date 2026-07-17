///|
test "parallel moves preserve the saved value class in a mixed float cycle" {
  let moves : Array[RegMove] = [
    {
      from: Reg({ index: 4, class: Float64 }),
      to: Reg({ index: 2, class: Float64 }),
      class: Float64,
    },
    {
      from: Reg({ index: 2, class: Float32 }),
      to: Reg({ index: 4, class: Float32 }),
      class: Float32,
    },
  ]
  let resolved = resolve_parallel_moves(moves, AArch64)
  fn describe_class(class : @abi.RegClass) -> String {
    match class {
      Int => "int"
      Float32 => "float"
      Float64 => "double"
      Vector => "vector"
    }
  }
  fn describe_loc(location : Loc) -> String {
    match location {
      Reg(preg) =>
        "reg(index=\{preg.index}, class=\{describe_class(preg.class)})"
      Spill(slot) => "spill(slot=\{slot})"
    }
  }
  inspect(
    resolved
    .map(item => {
      "\{describe_loc(item.from)} -> \{describe_loc(item.to)}, class=\{describe_class(item.class)}"
    })
    .join("\n"),
    content=(
      #|reg(index=2, class=float) -> reg(index=16, class=float), class=float
      #|reg(index=4, class=double) -> reg(index=2, class=double), class=double
      #|reg(index=16, class=float) -> reg(index=4, class=float), class=float
    ),
  )
}
