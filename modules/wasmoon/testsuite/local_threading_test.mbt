///|
/// Locals across control merges (#486 item 1).
///
/// A merge block carries only the locals its region writes; every other local
/// keeps the value the translator already holds. That is a claim about which
/// value each local has after the merge, so these run each shape through both
/// the JIT and the interpreter and require them to agree -- a local that gets
/// dropped from a merge it actually needed shows up here as a disagreement,
/// not as a compile error.
///
/// Each case is driven by the function argument so both sides of every branch
/// are taken across the calls.

///|
/// Written in one arm only: the merge has to reconcile the arm that wrote with
/// the arm that did not.
test "local_threading_if_then_only" {
  let source =
    #|(module
    #|  (func (export "f") (param i32) (result i32)
    #|    (local $x i32)
    #|    (local.set $x (i32.const 5))
    #|    (if (local.get 0) (then (local.set $x (i32.const 10))))
    #|    (local.get $x)
    #|  )
    #|)
  for arg in [0, 1] {
    let result = compare_jit_interp(source, "f", [I32(arg)])
    inspect(result, content="matched")
  }
}

///|
/// Each arm writes a different local, so the merge carries both even though
/// neither arm writes both.
test "local_threading_if_either_arm" {
  let source =
    #|(module
    #|  (func (export "f") (param i32) (result i32)
    #|    (local $x i32) (local $y i32)
    #|    (local.set $x (i32.const 1))
    #|    (local.set $y (i32.const 2))
    #|    (if (local.get 0)
    #|      (then (local.set $x (i32.const 10)))
    #|      (else (local.set $y (i32.const 20))))
    #|    (i32.add (local.get $x) (local.get $y))
    #|  )
    #|)
  for arg in [0, 1] {
    let result = compare_jit_interp(source, "f", [I32(arg)])
    inspect(result, content="matched")
  }
}

///|
/// Neither arm writes the local, so it crosses the merge with no parameter at
/// all. Its value after the `if` still has to be the one set before it.
test "local_threading_if_untouched_local_survives" {
  let source =
    #|(module
    #|  (func (export "f") (param i32) (result i32)
    #|    (local $kept i32) (local $touched i32)
    #|    (local.set $kept (i32.const 7))
    #|    (if (local.get 0)
    #|      (then (local.set $touched (i32.const 1)))
    #|      (else (local.set $touched (i32.const 2))))
    #|    (i32.add (local.get $kept) (local.get $touched))
    #|  )
    #|)
  for arg in [0, 1] {
    let result = compare_jit_interp(source, "f", [I32(arg)])
    inspect(result, content="matched")
  }
}

///|
/// A write two regions deep still has to reach the code after the outer block.
test "local_threading_nested_block_write_escapes" {
  let source =
    #|(module
    #|  (func (export "f") (param i32) (result i32)
    #|    (local $x i32)
    #|    (local.set $x (i32.const 1))
    #|    (block
    #|      (block
    #|        (if (local.get 0) (then (local.set $x (i32.const 99))))
    #|      )
    #|    )
    #|    (local.get $x)
    #|  )
    #|)
  for arg in [0, 1] {
    let result = compare_jit_interp(source, "f", [I32(arg)])
    inspect(result, content="matched")
  }
}

///|
/// A loop-carried counter and a loop-invariant local in the same loop: one
/// needs a header parameter, the other must not lose its value to the absence
/// of one.
test "local_threading_loop_carried_and_invariant" {
  let source =
    #|(module
    #|  (func (export "f") (param i32) (result i32)
    #|    (local $i i32) (local $sum i32) (local $step i32)
    #|    (local.set $step (i32.const 3))
    #|    (block $done
    #|      (loop $again
    #|        (br_if $done (i32.ge_s (local.get $i) (local.get 0)))
    #|        (local.set $sum (i32.add (local.get $sum) (local.get $step)))
    #|        (local.set $i (i32.add (local.get $i) (i32.const 1)))
    #|        (br $again)
    #|      )
    #|    )
    #|    (i32.add (local.get $sum) (local.get $step))
    #|  )
    #|)
  for arg in [0, 1, 5] {
    let result = compare_jit_interp(source, "f", [I32(arg)])
    inspect(result, content="matched")
  }
}

///|
/// `br` out of a nested block carrying a local the outer region writes.
test "local_threading_br_out_of_nest" {
  let source =
    #|(module
    #|  (func (export "f") (param i32) (result i32)
    #|    (local $x i32)
    #|    (block $outer
    #|      (block $inner
    #|        (local.set $x (i32.const 11))
    #|        (br_if $outer (local.get 0))
    #|        (local.set $x (i32.const 22))
    #|      )
    #|      (local.set $x (i32.add (local.get $x) (i32.const 100)))
    #|    )
    #|    (local.get $x)
    #|  )
    #|)
  for arg in [0, 1] {
    let result = compare_jit_interp(source, "f", [I32(arg)])
    inspect(result, content="matched")
  }
}

///|
/// `br_table` targets sit at different depths, so they no longer carry the
/// same locals: `$inner` writes one, the regions above it write two. Each
/// intermediate block builds its own argument list.
test "local_threading_br_table_targets_differ" {
  let source =
    #|(module
    #|  (func (export "f") (param i32) (result i32)
    #|    (local $a i32) (local $b i32)
    #|    (block $outer
    #|      (block $mid
    #|        (block $inner
    #|          (local.set $a (i32.const 11))
    #|          (br_table $inner $mid $outer (local.get 0))
    #|        )
    #|        (local.set $b (i32.const 22))
    #|      )
    #|      (local.set $b (i32.add (local.get $b) (i32.const 3)))
    #|    )
    #|    (i32.add (local.get $a) (local.get $b))
    #|  )
    #|)
  for arg in [0, 1, 2, 7] {
    let result = compare_jit_interp(source, "f", [I32(arg)])
    inspect(result, content="matched")
  }
}

///|
/// A branch to function level goes through the return continuation, which
/// carries no locals at all -- it only returns the result values. The locals
/// written before the branch must not be needed on that edge.
test "local_threading_branch_to_function_level" {
  let source =
    #|(module
    #|  (func (export "f") (param i32) (result i32)
    #|    (local $x i32)
    #|    (local.set $x (i32.const 4))
    #|    (block (result i32)
    #|      (local.set $x (i32.const 8))
    #|      (br_if 1 (i32.const 77) (local.get 0))
    #|      (drop)
    #|      (local.set $x (i32.const 9))
    #|      (local.get $x)
    #|    )
    #|  )
    #|)
  for arg in [0, 1] {
    let result = compare_jit_interp(source, "f", [I32(arg)])
    inspect(result, content="matched")
  }
}

///|
/// `br_table` reaching function level alongside an in-function target: the
/// return continuation takes results only, the block target takes its locals.
test "local_threading_br_table_to_function_level" {
  let source =
    #|(module
    #|  (func (export "f") (param i32) (result i32)
    #|    (local $x i32)
    #|    (block $b (result i32)
    #|      (local.set $x (i32.const 6))
    #|      (br_table $b 1 (i32.const 55) (local.get 0))
    #|    )
    #|    (i32.add (local.get $x))
    #|  )
    #|)
  for arg in [0, 1, 3] {
    let result = compare_jit_interp(source, "f", [I32(arg)])
    inspect(result, content="matched")
  }
}

///|
/// A catch handler branches to a label outside the try, and has to supply that
/// label's locals from the values restored out of spill storage.
test "local_threading_catch_branch_carries_locals" {
  let source =
    #|(module
    #|  (tag $e)
    #|  (func (export "f") (param i32) (result i32)
    #|    (local $x i32)
    #|    (local.set $x (i32.const 3))
    #|    (block $h
    #|      (try_table (catch $e $h)
    #|        (local.set $x (i32.const 30))
    #|        (if (local.get 0) (then (throw $e)))
    #|        (local.set $x (i32.add (local.get $x) (i32.const 1)))
    #|      )
    #|    )
    #|    (local.get $x)
    #|  )
    #|)
  for arg in [0, 1] {
    let result = compare_jit_interp(source, "f", [I32(arg)])
    inspect(result, content="matched")
  }
}

///|
/// Many locals across many merges with only one of them written, which is the
/// shape #486 reports. Correctness here is what makes the parameter count in
/// `wasm_frontend/local_threading_test.mbt` meaningful.
test "local_threading_many_locals_sparse_writes" {
  let source =
    #|(module
    #|  (func (export "f") (param i32) (result i32)
    #|    (local $a i32) (local $b i32) (local $c i32) (local $d i32)
    #|    (local $e i32) (local $f i32) (local $g i32) (local $h i32)
    #|    (local.set $a (i32.const 1))
    #|    (local.set $b (i32.const 2))
    #|    (local.set $c (i32.const 3))
    #|    (local.set $d (i32.const 4))
    #|    (local.set $e (i32.const 5))
    #|    (local.set $f (i32.const 6))
    #|    (local.set $g (i32.const 7))
    #|    (if (local.get 0) (then (local.set $h (i32.const 10))))
    #|    (if (local.get 0) (then (local.set $h (i32.add (local.get $h) (i32.const 1)))))
    #|    (if (local.get 0) (then (local.set $h (i32.add (local.get $h) (i32.const 1)))))
    #|    (i32.add (local.get $h)
    #|      (i32.add (i32.add (local.get $a) (local.get $b))
    #|        (i32.add (i32.add (local.get $c) (local.get $d))
    #|          (i32.add (i32.add (local.get $e) (local.get $f)) (local.get $g)))))
    #|  )
    #|)
  for arg in [0, 1] {
    let result = compare_jit_interp(source, "f", [I32(arg)])
    inspect(result, content="matched")
  }
}
