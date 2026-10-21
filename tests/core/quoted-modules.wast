(module quote "(module (func (export \"run\") (result i32) i32.const 7))")
(assert_return (invoke "run") (i32.const 7))

(thread $child
  (module quote "(module " "(func (export \"run\") (result i32) i32.const 9))")
  (assert_return (invoke "run") (i32.const 9)))
(wait $child)

(assert_invalid (module quote "(module (func (result i32)))") "type mismatch")
(assert_unlinkable (module (func (import "missing" "f"))) "unknown import")
;; The pinned WAST adapter includes start traps in instantiation failures.
(assert_unlinkable (module (func $start unreachable) (start $start)) "unreachable")

;; Quoted text may also omit the outer module form, including after annotations.
(module quote "(@annotation) (func (export \"run\") (result i32) i32.const 11) ;; trailing comment")
(assert_return (invoke "run") (i32.const 11))
