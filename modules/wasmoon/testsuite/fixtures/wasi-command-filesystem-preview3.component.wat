(component
  (import "wasi:filesystem/types@0.3.0"
    (instance $filesystem-types
      (export "descriptor" (type (sub resource)))
    )
  )
  (alias export $filesystem-types "descriptor" (type $descriptor))
  (import "wasi:filesystem/preopens@0.3.0"
    (instance $filesystem-preopens
      (export "get-directories"
        (func (result (list (tuple (own $descriptor) string))))
      )
    )
  )

  (core module $memory
    (memory (export "memory") 1)
    (global $heap (mut i32) (i32.const 64))
    (func (export "realloc")
      (param $old i32)
      (param $old-size i32)
      (param $align i32)
      (param $new-size i32)
      (result i32)
      (local $result i32)
      global.get $heap
      local.get $align
      i32.const 1
      i32.sub
      i32.add
      local.get $align
      i32.const 1
      i32.sub
      i32.const -1
      i32.xor
      i32.and
      local.tee $result
      local.get $new-size
      i32.add
      global.set $heap
      local.get $result
    )
  )
  (core instance $memory (instantiate $memory))
  (core func $get-directories
    (canon lower (func $filesystem-preopens "get-directories")
      (memory (core memory $memory "memory"))
      (realloc (core func $memory "realloc"))
    )
  )
  (core module $command
    (import "memory" "memory" (memory 1))
    (import "filesystem" "get-directories" (func $get-directories (param i32)))
    (func (export "run") (result i32)
      i32.const 0
      call $get-directories
      i32.const 4
      i32.load
      i32.eqz
    )
  )
  (core instance $command
    (instantiate $command
      (with "memory" (instance $memory))
      (with "filesystem"
        (instance
          (export "get-directories" (func $get-directories))
        )
      )
    )
  )
  (type $run-result (result))
  (func $run async (result $run-result)
    (canon lift (core func $command "run"))
  )
  (instance $run-interface
    (export "run" (func $run))
  )
  (export "wasi:cli/run@0.3.0" (instance $run-interface))
)
