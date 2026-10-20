///|
test "text limits preserve u64 values before address-width validation" {
  for
    size in ["0x1_0000_0000", "0x8000_0000_0000_0000", "0xffff_ffff_ffff_ffff"] {
    for
      declaration in [
        "(memory " + size + ")",
        "(memory 0 " + size + ")",
        "(import \"m\" \"m\" (memory " + size + " " + size + "))",
        "(memory (import \"m\" \"m\") " + size + " " + size + ")",
        "(table " + size + " funcref)",
        "(table 0 " + size + " funcref)",
        "(import \"m\" \"t\" (table " + size + " " + size + " funcref))",
        "(table (import \"m\" \"t\") " + size + " " + size + " funcref)",
      ] {
      let module_ = @wat.parse("(module " + declaration + ")")
      try @validator.validate_module(module_) catch {
        _ => ()
      } noraise {
        _ => fail("out-of-range limit passed validation: " + declaration)
      }
    }
  }
  // The same limits remain valid for table64; they must not be narrowed.
  let table64 = @wat.parse(
    "(module (table i64 0 0xffff_ffff_ffff_ffff funcref))",
  )
  @validator.validate_module(table64)
  assert_eq(table64.tables[0].type_.limits.max, Some(-1L))
  for size in ["-1", "0x1_0000_0000_0000_0000"] {
    try @wat.parse("(module (memory " + size + "))") catch {
      _ => ()
    } noraise {
      _ => fail("invalid u64 limit syntax was accepted")
    }
  }
}
