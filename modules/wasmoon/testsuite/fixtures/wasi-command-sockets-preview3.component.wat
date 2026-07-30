(component
  (import "wasi:sockets/types@0.3.0"
    (instance $sockets
      (export "tcp-socket" (type $tcp-socket (sub resource)))
      (type $address-family' (enum "ipv4" "ipv6"))
      (export "ip-address-family"
        (type $address-family (eq $address-family'))
      )
      (type $error-code'
        (variant
          (case "access-denied")
          (case "not-supported")
          (case "invalid-argument")
          (case "out-of-memory")
          (case "timeout")
          (case "invalid-state")
          (case "address-not-bindable")
          (case "address-in-use")
          (case "remote-unreachable")
          (case "connection-refused")
          (case "connection-broken")
          (case "connection-reset")
          (case "connection-aborted")
          (case "datagram-too-large")
          (case "other" (option string))
        )
      )
      (export "error-code"
        (type $error-code (eq $error-code'))
      )
      (export "[static]tcp-socket.create"
        (func
          (param "address-family" $address-family)
          (result (result (own $tcp-socket) (error $error-code)))
        )
      )
    )
  )
  (alias export $sockets "tcp-socket" (type $tcp-socket))
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
  (core func $create
    (canon lower (func $sockets "[static]tcp-socket.create")
      (memory (core memory $memory "memory"))
      (realloc (core func $memory "realloc"))
    )
  )
  (core func $drop (canon resource.drop $tcp-socket))
  (core module $command
    (import "memory" "memory" (memory 1))
    (import "sockets" "create" (func $create (param i32 i32)))
    (import "sockets" "drop" (func $drop (param i32)))
    (func (export "run") (result i32)
      (local $discriminant i32)
      (local $handle i32)
      i32.const 0
      i32.const 0
      call $create
      i32.const 0
      i32.load
      local.set $discriminant
      i32.const 4
      i32.load
      local.set $handle
      local.get $discriminant
      if (result i32)
        i32.const 1
      else
        local.get $handle
        call $drop
        i32.const 0
      end
    )
  )
  (core instance $command
    (instantiate $command
      (with "memory" (instance $memory))
      (with "sockets"
        (instance
          (export "create" (func $create))
          (export "drop" (func $drop))
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
