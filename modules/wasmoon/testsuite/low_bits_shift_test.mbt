///|
test "low-bit shift selection preserves boundary values and shared intermediate uses" {
  for width in [32, 64] {
    let mask = if width == 32 { "16382" } else { "8589934590" }
    let source =
      $|(module
      $| (func (export "single") (param $x i\{width}) (result i\{width})
      $|   local.get $x i\{width}.const 1 i\{width}.shl i\{width}.const \{mask} i\{width}.and)
      $| (func (export "commuted") (param $x i\{width}) (result i\{width})
      $|   i\{width}.const \{mask} local.get $x i\{width}.const \{width + 1} i\{width}.shl i\{width}.and)
      $| (func (export "shared") (param $x i\{width}) (result i\{width} i\{width}) (local $s i\{width})
      $|   local.get $x i\{width}.const 1 i\{width}.shl local.tee $s
      $|   i\{width}.const 0x55555555 i\{width}.and local.get $s)
      $| (func (export "top") (param $x i\{width}) (result i\{width})
      $|   local.get $x i\{width}.const \{width - 1} i\{width}.shl
      $|   i\{width}.const \{if width == 32 { "0x80000000" } else { "0x8000000000000000" }} i\{width}.and)
      $| (func (export "full") (param $x i\{width}) (result i\{width})
      $|   local.get $x i\{width}.const 1 i\{width}.shl i\{width}.const -1 i\{width}.and)
      $| (func (export "zero") (param $x i\{width}) (result i\{width})
      $|   local.get $x i\{width}.const 1 i\{width}.shl i\{width}.const 0 i\{width}.and))
    for opt_level in [0, 2] {
      for
        value in [
          0L, 1L, -1L, -2147483648L, 2147483647L, -9223372036854775808L, 9223372036854775807L,
          1311768467750121217L,
        ] {
        let args : Array[@types.Value] = if width == 32 {
          [I32(value.to_int())]
        } else {
          [I64(value)]
        }
        for
          export_name in ["single", "commuted", "shared", "top", "full", "zero"] {
          inspect(
            @testsuite.compare_jit_interp_with_opt_level(
              source, export_name, args, opt_level,
            ),
            content="matched",
          )
        }
      }
    }
  }
}
