///|
test "custom page size syntax is independent of engine-supported sizes" {
  for
    (size, exponent) in [
      ("2", 1),
      ("131072", 17),
      ("0x8000_0000_0000_0000", 63),
    ] {
    for
      declaration in [
        "(memory 0 (pagesize " + size + "))",
        "(memory (import \"m\" \"mem\") 0 (pagesize " + size + "))",
        "(import \"m\" \"mem\" (memory 0 (pagesize " + size + ")))",
      ] {
      let module_ = @wat.parse("(module " + declaration + ")")
      if !module_.memories.is_empty() {
        assert_eq(module_.memories[0].page_size_log2, exponent)
      }
      try @validator.validate_module(module_) catch {
        InvalidLimits("invalid custom page size") => ()
        error => fail(error.to_string())
      } noraise {
        _ => fail("unsupported page size passed validation")
      }
    }
  }
  for size in ["1", "65536"] {
    @validator.validate_module(
      @wat.parse("(module (memory 0 (pagesize " + size + ")))"),
    )
  }
  for size in ["0", "3", "-1", "0x1_0000_0000_0000_0000"] {
    try @wat.parse("(module (memory 0 (pagesize " + size + ")))") catch {
      _ => ()
    } noraise {
      _ => fail("malformed page size was accepted")
    }
  }
}
