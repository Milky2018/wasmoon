(module
  (tag $e)
  (func (export "run") (result i32) (local $i i32) (local $saved exnref)
    (block $caught (result exnref)
      (try_table (catch_all_ref $caught) (throw $e)) unreachable)
    local.set $saved
    (loop $again
      (block $handled
        (try_table (catch_all $handled) (throw_ref (local.get $saved))))
      local.get $i i32.const 1 i32.add local.tee $i
      i32.const 200000 i32.lt_u br_if $again)
    local.get $i))
