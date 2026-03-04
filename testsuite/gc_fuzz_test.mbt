///|
/// Directed GC fuzz cases using deterministic pseudo-random generation.
/// Each generated module mixes struct/array/reference operations and compares
/// JIT against interpreter with compare_jit_interp.
fn fuzz_next_state(seed : Int) -> Int {
  ((seed.to_int64() * 1103515245L + 12345L) & 0x7FFFFFFFL).to_int()
}

///|
fn fuzz_next_in_range(seed : Int, bound : Int) -> (Int, Int) {
  let next_seed = fuzz_next_state(seed)
  if bound <= 0 {
    (next_seed, 0)
  } else {
    (next_seed, next_seed % bound)
  }
}

///|
fn generate_gc_fuzz_case(seed : Int) -> String {
  let lines : Array[String] = []
  lines.push("(module")
  lines.push(
    "  (type $node (struct (field (mut i32)) (field (mut (ref null $node)))))",
  )
  lines.push("  (type $arr (array (mut i32)))")
  lines.push("  (table $nodes 8 (ref null $node))")
  lines.push("  (func (export \"test\") (result i32)")
  lines.push("    (local $node (ref null $node))")
  lines.push("    (local $tmp (ref null $node))")
  lines.push("    (local $array (ref null $arr))")
  lines.push("    (local $sum i32)")

  let mut rng_state = seed
  let (rng_state0, first_value_raw) = fuzz_next_in_range(rng_state, 97)
  rng_state = rng_state0
  let first_value = first_value_raw - 48
  let (rng_state1, fill_value_raw) = fuzz_next_in_range(rng_state, 101)
  rng_state = rng_state1
  let fill_value = fill_value_raw - 50
  let (rng_state2, array_len_raw) = fuzz_next_in_range(rng_state, 8)
  rng_state = rng_state2
  let array_len = array_len_raw + 1

  lines.push(
    "    (local.set $node (struct.new $node (i32.const \{first_value}) (ref.null $node)))",
  )
  lines.push(
    "    (local.set $array (array.new $arr (i32.const \{fill_value}) (i32.const \{array_len})))",
  )
  lines.push("    (local.set $sum (i32.const 0))")

  for step in 0..<10 {
    let (rng_state3, index_raw) = fuzz_next_in_range(rng_state, array_len)
    rng_state = rng_state3
    let (rng_state4, write_value_raw) = fuzz_next_in_range(rng_state, 121)
    rng_state = rng_state4
    let write_value = write_value_raw - 60

    lines.push("    (local.get $array)")
    lines.push("    (i32.const \{index_raw})")
    lines.push("    (i32.const \{write_value})")
    lines.push("    (array.set $arr)")

    lines.push(
      "    (local.set $sum (i32.add (local.get $sum) (array.get $arr (local.get $array) (i32.const \{index_raw}))))",
    )

    if step % 2 == 0 {
      lines.push("    (local.get $node)")
      lines.push("    (local.get $sum)")
      lines.push("    (struct.set $node 0)")
    }
    if step % 3 == 0 {
      let (rng_state5, tmp_value_raw) = fuzz_next_in_range(rng_state, 89)
      rng_state = rng_state5
      let tmp_value = tmp_value_raw - 44
      lines.push(
        "    (local.set $tmp (struct.new $node (i32.const \{tmp_value}) (local.get $node)))",
      )
      lines.push("    (local.get $node)")
      lines.push("    (local.get $tmp)")
      lines.push("    (struct.set $node 1)")
    }
    if step % 4 == 0 {
      let (rng_state6, table_index_raw) = fuzz_next_in_range(rng_state, 8)
      rng_state = rng_state6
      lines.push(
        "    (table.set $nodes (i32.const \{table_index_raw}) (local.get $node))",
      )
      lines.push("    (drop (table.get $nodes (i32.const \{table_index_raw})))")
    }
  }

  lines.push(
    "    (i32.add (i32.add (struct.get $node 0 (local.get $node)) (array.len $arr (local.get $array))) (local.get $sum))",
  )
  lines.push("  )")
  lines.push(")")
  lines.join("\n")
}

///|
test "gc fuzz: directed jit/interpreter comparison" {
  for seed in 1..<65 {
    let source = generate_gc_fuzz_case(seed)
    let compared = compare_jit_interp(source, "test", [])
    if !compare_result_is_match(compared) {
      fail("gc fuzz mismatch (seed=\{seed}): \{compared}")
    }
  }
}

///|
fn generate_gc_deep_live_case(depth : Int) -> String {
  let lines : Array[String] = []
  lines.push("(module")
  lines.push(
    "  (type $node (struct (field (mut i32)) (field (mut (ref null $node)))))",
  )
  lines.push("  (func (export \"test\") (result i32)")
  lines.push("    (local $head (ref null $node))")
  lines.push("    (local $i i32)")
  lines.push("    (local.set $head (ref.null $node))")
  lines.push("    (local.set $i (i32.const 0))")
  lines.push("    (loop $grow")
  lines.push(
    "      (local.set $head (struct.new $node (local.get $i) (local.get $head)))",
  )
  lines.push("      (local.set $i (i32.add (local.get $i) (i32.const 1)))")
  lines.push(
    "      (br_if $grow (i32.lt_s (local.get $i) (i32.const \{depth})))",
  )
  lines.push("    )")
  lines.push("    (struct.get $node 0 (local.get $head))")
  lines.push("  )")
  lines.push(")")
  lines.join("\n")
}

///|
test "gc fuzz: deep live chain jit/interpreter comparison" {
  for depth in [16, 32, 64, 96] {
    let source = generate_gc_deep_live_case(depth)
    let compared = compare_jit_interp(source, "test", [])
    if !compare_result_is_match(compared) {
      fail("gc deep-live mismatch (depth=\{depth}): \{compared}")
    }
  }
}
