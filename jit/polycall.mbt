///|
pub suberror PolycallError {
  InputNumber(Int, Int)
  OutputNumber(Int, Int)
  JIT(JITTrap)
}

///|
impl Show for PolycallError with output(self, logger) {
  let msg = match self {
    OutputNumber(expected, got) =>
      "output number error: expected \{expected}, got \{got}"
    InputNumber(expected, got) =>
      "input number error: expected \{expected}, got \{got}"
    JIT(e) => e.to_string()
  }
  logger.write_string(msg)
}

///|
pub(all) struct Single[A](A)

///|
pub trait DynamicArgs {
  to_int64_array(Self) -> Array[Int64]
}

///|
pub impl DynamicArgs for Unit with to_int64_array(_self) {
  []
}

///|
pub impl[A : @types.ToInt64] DynamicArgs for Single[A] with to_int64_array(self) {
  [self.0.to_int64_bits()]
}

///|
pub impl[A : @types.ToInt64, B : @types.ToInt64] DynamicArgs for (A, B) with to_int64_array(
  self,
) {
  [@types.ToInt64::to_int64_bits(self.0), @types.ToInt64::to_int64_bits(self.1)]
}

///|
pub impl[A : @types.ToInt64, B : @types.ToInt64, C : @types.ToInt64] DynamicArgs for (
  A,
  B,
  C,
) with to_int64_array(self) {
  [
    @types.ToInt64::to_int64_bits(self.0),
    @types.ToInt64::to_int64_bits(self.1),
    @types.ToInt64::to_int64_bits(self.2),
  ]
}

///|
pub impl[
  A : @types.ToInt64,
  B : @types.ToInt64,
  C : @types.ToInt64,
  D : @types.ToInt64,
] DynamicArgs for (A, B, C, D) with to_int64_array(self) {
  [
    @types.ToInt64::to_int64_bits(self.0),
    @types.ToInt64::to_int64_bits(self.1),
    @types.ToInt64::to_int64_bits(self.2),
    @types.ToInt64::to_int64_bits(self.3),
  ]
}

///|
pub trait DynamicReturn {
  from_int64_array(Array[Int64]) -> Self
}

///|
pub impl DynamicReturn for Unit with from_int64_array(_arr) {
  ()
}

///|
pub impl[A : @types.FromInt64] DynamicReturn for Single[A] with from_int64_array(
  arr,
) {
  Single(arr[0] |> A::from_int64_bits())
}

///|
pub impl[A : @types.FromInt64, B : @types.FromInt64] DynamicReturn for (A, B) with from_int64_array(
  arr,
) {
  (
    @types.FromInt64::from_int64_bits(arr[0]),
    @types.FromInt64::from_int64_bits(arr[1]),
  )
}

///|
pub impl[A : @types.FromInt64, B : @types.FromInt64, C : @types.FromInt64] DynamicReturn for (
  A,
  B,
  C,
) with from_int64_array(arr) {
  (
    @types.FromInt64::from_int64_bits(arr[0]),
    @types.FromInt64::from_int64_bits(arr[1]),
    @types.FromInt64::from_int64_bits(arr[2]),
  )
}

///|
pub impl[
  A : @types.FromInt64,
  B : @types.FromInt64,
  C : @types.FromInt64,
  D : @types.FromInt64,
] DynamicReturn for (A, B, C, D) with from_int64_array(arr) {
  (
    @types.FromInt64::from_int64_bits(arr[0]),
    @types.FromInt64::from_int64_bits(arr[1]),
    @types.FromInt64::from_int64_bits(arr[2]),
    @types.FromInt64::from_int64_bits(arr[3]),
  )
}

///|
pub fn[Arg : DynamicArgs, Ret : DynamicReturn] JITModule::call_with_context_poly(
  self : JITModule,
  func : JITFunction,
  args : Arg,
) -> Ret raise PolycallError {
  let args_array = DynamicArgs::to_int64_array(args)
  if args_array.length() != func.param_types.length() {
    raise InputNumber(func.param_types.length(), args_array.length())
  }
  let result_array = self.call_with_context(func, args_array) catch {
    e => raise JIT(e)
  }
  let expected_results = func.result_types.length()
  if result_array.length() != expected_results {
    raise OutputNumber(expected_results, result_array.length())
  }
  DynamicReturn::from_int64_array(result_array)
}
