;; Status check: WASI CLI imports are accepted by validation, but unresolved at link time.
(assert_unlinkable
  (component
    (import "wasi:cli/run@0.2.0" (instance
      (export "run" (func))
    ))
  )
  "was not found")
