///|
test "AArch64 rejects an internal ABI that reuses the context register" {
  try
    InternalAbi::new(0, 8, [0, 1, 2], [0, 1], [0, 1], [0, 1]) |> ignore
  catch {
    error => inspect(error, content="ContextRegisterReused(index=0)")
  } noraise {
    _ => fail("expected the internal ABI contract to be rejected")
  }
}

///|
test "AArch64 reserves the internal result-area register" {
  try InternalAbi::new(0, 1, [1, 2], [0, 1], [0, 1], [0, 1]) |> ignore catch {
    error => inspect(error, content="ResultAreaRegisterReused(index=1)")
  } noraise {
    _ => fail("expected the result-area ABI register to be reserved")
  }
}
