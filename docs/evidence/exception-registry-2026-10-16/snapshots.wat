(module
  (tag $e)
  (func (export "run") (result i32) (local $i i32)
    (loop $again
      (block $caught (result exnref)
        (try_table (catch_all_ref $caught) (throw $e))
        unreachable)
      drop
      local.get $i i32.const 1 i32.add local.tee $i
      i32.const 20000 i32.lt_u br_if $again)
    local.get $i))
