(module
  (import "spectest" "print_char" (func $print (param i32)))
  (func (export "run") (call $print (i32.const 65))))
(invoke "run")
