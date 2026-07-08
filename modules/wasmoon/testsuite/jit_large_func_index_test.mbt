///|
test "jit: large function index indirect call uses full offset" {
  let target_idx = 4096
  let lines : Array[String] = ["(module"]
  for i in 0..<(target_idx + 1) {
    lines.push("  (func $f\{i} (result i32) i32.const \{i})")
  }
  lines.push("  (func (export \"test\") (result i32) call $f\{target_idx})")
  lines.push(")")
  let source = lines.join("\n")
  let result = compare_jit_interp(source, "test", [])
  inspect(result, content="matched")
}

///|
test "jit: large function index ref.func uses full offset" {
  let target_idx = 4096
  let lines : Array[String] = ["(module", "  (type $t (func (result i32)))"]
  for i in 0..<(target_idx + 1) {
    lines.push("  (func $f\{i} (type $t) (result i32) i32.const \{i})")
  }
  lines.push("  (func (export \"test\") (result i32)")
  lines.push("    ref.func $f\{target_idx}")
  lines.push("    call_ref $t")
  lines.push("  )")
  lines.push(")")
  let source = lines.join("\n")
  let result = compare_jit_interp(source, "test", [])
  inspect(result, content="matched")
}
