///|
test "integer tokens preserve grammar and width before conversion" {
  for
    literal in [
      "_1", "1_", "1__0", "0X1", "0x", "0x_1", "-2147483649", "0x100000000", "18446744073709551616",
    ] {
    let rejected = try {
      let _ = parse_int(literal)
      false
    } catch {
      _ => true
    }
    inspect(rejected, content="true")
  }
  inspect(parse_int("0xffff_ffff"), content="-1")
  inspect(parse_int("-0x8000_0000"), content="-2147483648")
  inspect(parse_int("+4294967295"), content="-1")
  inspect(parse_int64("18_446_744_073_709_551_615"), content="-1")
}

///|
test "float tokens require complete syntax and nonzero bounded NaN payloads" {
  for
    literal in [
      "0e", "0e+", "0x", "0x.p0", "0x1p-", "1_", "+_100", "0x_1", "nan:0x0", "nan:0x800000",
      "1e1000",
    ] {
    let rejected = try {
      let _ = parse_float32(literal)
      false
    } catch {
      _ => true
    }
    inspect(rejected, content="true")
  }
  inspect(
    parse_float32("0x1_0.a_bp+1").reinterpret_as_int(),
    content="1107646464",
  )
  inspect(parse_float32("nan:0x1").reinterpret_as_int(), content="2139095041")
}

///|
test "UTF-8 names preserve bytes and Unicode while data permits nontext" {
  for name in ["é", "\u{1f4a9}", "\u{feff}"] {
    let module_ = parse("(module (func (export \"" + name + "\")))")
    inspect(module_.exports[0].name == name, content="true")
  }
  let escaped = parse(
    (
      #|(module (func (export "\f0\9f\92\a9")) (memory 1) (data "\ff\80"))
    ),
  )
  inspect(escaped.exports[0].name, content="💩")
  inspect(escaped.datas[0].init, content="b\"\\xff\\x80\"")
  for
    source in [
      (
        #|(module (func (export "\80")))
      ),
      (
        #|(module (import "\c0\af" "f" (func)))
      ),
      (
        #|(module (func $"\ed\a0\80"))
      ),
      (
        #|(module (func (export "\u{d800}")))
      ),
      (
        #|(module (func (export "\q")))
      ),
    ] {
    let rejected = try {
      let _ = parse(source)
      false
    } catch {
      _ => true
    }
    inspect(rejected, content="true")
  }
}

///|
test "module syntax shares strict ordering and names across both wrappers" {
  for
    fields in [
      "(func $f) (func $f)", "(global $g i32 (i32.const 0)) (global $g i32 (i32.const 1))",
      "(func) (import \"m\" \"f\" (func))", "(func) (start 0) (start 0)", "(type (struct (field $x i32) (field $x i64)))",
      "(func (param $x i32) (local $x i32))", "(func (result i32) (param i32) unreachable)",
      "(type (func)) (func (block (type 0) (result i32) unreachable))", "(func block $a end $b)",
      "(func i32.const 0 if $a else $b end)", "(func block (param $x i32) end)",
      "(func $\"\")", "(memory 1) (data\"a\")", "(@a \"\\q\")", "(@a", "(; unclosed comment",
    ] {
    for source in [fields, "(module " + fields + ")"] {
      let rejected = try {
        let _ = parse_wast(source)
        false
      } catch {
        _ => true
      }
      inspect(rejected, content="true")
    }
  }
  let valid = parse(
    (
      #|(module (type $t (func (param i32) (result i32)))
      #| (func (type $t) (param $x i32) (result i32)
      #|   block $a (type $t) (param i32) (result i32) end $a)
      #| (func $"é"))
    ),
  )
  inspect(valid.funcs.length(), content="2")
}
