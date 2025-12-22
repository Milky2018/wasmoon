///|
/// Tests for structural type equivalence functions

///|
test "func_types_structurally_equal: identical simple types" {
  let types : Array[@types.FuncType] = []
  let t1 : @types.FuncType = { params: [I32, I64], results: [F32] }
  let t2 : @types.FuncType = { params: [I32, I64], results: [F32] }
  let visited : Map[(Int, Int), Bool] = {}
  inspect(
    func_types_structurally_equal(types, t1, t2, 0, 0, visited),
    content="true",
  )
}

///|
test "func_types_structurally_equal: different param counts" {
  let types : Array[@types.FuncType] = []
  let t1 : @types.FuncType = { params: [I32], results: [] }
  let t2 : @types.FuncType = { params: [I32, I64], results: [] }
  let visited : Map[(Int, Int), Bool] = {}
  inspect(
    func_types_structurally_equal(types, t1, t2, 0, 0, visited),
    content="false",
  )
}

///|
test "func_types_structurally_equal: different result counts" {
  let types : Array[@types.FuncType] = []
  let t1 : @types.FuncType = { params: [], results: [I32] }
  let t2 : @types.FuncType = { params: [], results: [I32, I64] }
  let visited : Map[(Int, Int), Bool] = {}
  inspect(
    func_types_structurally_equal(types, t1, t2, 0, 0, visited),
    content="false",
  )
}

///|
test "func_types_structurally_equal: different param types" {
  let types : Array[@types.FuncType] = []
  let t1 : @types.FuncType = { params: [I32], results: [] }
  let t2 : @types.FuncType = { params: [I64], results: [] }
  let visited : Map[(Int, Int), Bool] = {}
  inspect(
    func_types_structurally_equal(types, t1, t2, 0, 0, visited),
    content="false",
  )
}

///|
test "func_types_structurally_equal: self-referential types are equal" {
  // (type $t1 (func (result (ref null $t1))))
  // (type $t2 (func (result (ref null $t2))))
  // These should be structurally equal because both reference "self"
  let t1 : @types.FuncType = { params: [], results: [RefNullFuncTyped(0)] }
  let t2 : @types.FuncType = { params: [], results: [RefNullFuncTyped(1)] }
  let types : Array[@types.FuncType] = [t1, t2]
  let visited : Map[(Int, Int), Bool] = {}
  // idx1=0 means t1 at index 0, idx2=1 means t2 at index 1
  // RefNullFuncTyped(0) in t1 is a self-ref (0 == idx1)
  // RefNullFuncTyped(1) in t2 is a self-ref (1 == idx2)
  inspect(
    func_types_structurally_equal(types, t1, t2, 0, 1, visited),
    content="true",
  )
}

///|
test "func_types_structurally_equal: indirect types with same referenced type" {
  // (type $s0 (func (param i32)))
  // (type $s1 (func (param i32 (ref $s0))))
  // (type $s2 (func (param i32 (ref $s0))))
  // $s1 and $s2 should be structurally equal
  let s0 : @types.FuncType = { params: [I32], results: [] }
  let s1 : @types.FuncType = { params: [I32, RefFuncTyped(0)], results: [] }
  let s2 : @types.FuncType = { params: [I32, RefFuncTyped(0)], results: [] }
  let types : Array[@types.FuncType] = [s0, s1, s2]
  let visited : Map[(Int, Int), Bool] = {}
  inspect(
    func_types_structurally_equal(types, s1, s2, 1, 2, visited),
    content="true",
  )
}

///|
test "func_types_structurally_equal: indirect types with structurally equal refs" {
  // (type $s0 (func (param i32)))
  // (type $s1 (func (param i32 (ref $s0))))  ; index 1
  // (type $s2 (func (param i32 (ref $s0))))  ; index 2
  // (type $t1 (func (param (ref $s1))))      ; index 3
  // (type $t2 (func (param (ref $s2))))      ; index 4
  // $t1 and $t2 should be structurally equal because $s1 == $s2
  let s0 : @types.FuncType = { params: [I32], results: [] }
  let s1 : @types.FuncType = { params: [I32, RefFuncTyped(0)], results: [] }
  let s2 : @types.FuncType = { params: [I32, RefFuncTyped(0)], results: [] }
  let t1 : @types.FuncType = { params: [RefFuncTyped(1)], results: [] }
  let t2 : @types.FuncType = { params: [RefFuncTyped(2)], results: [] }
  let types : Array[@types.FuncType] = [s0, s1, s2, t1, t2]
  let visited : Map[(Int, Int), Bool] = {}
  inspect(
    func_types_structurally_equal(types, t1, t2, 3, 4, visited),
    content="true",
  )
}

///|
test "func_types_structurally_equal: different referenced types" {
  // (type $s0 (func (param i32)))
  // (type $s1 (func (param i64)))  ; different from $s0
  // (type $t1 (func (param (ref $s0))))
  // (type $t2 (func (param (ref $s1))))
  // $t1 and $t2 should NOT be equal
  let s0 : @types.FuncType = { params: [I32], results: [] }
  let s1 : @types.FuncType = { params: [I64], results: [] }
  let t1 : @types.FuncType = { params: [RefFuncTyped(0)], results: [] }
  let t2 : @types.FuncType = { params: [RefFuncTyped(1)], results: [] }
  let types : Array[@types.FuncType] = [s0, s1, t1, t2]
  let visited : Map[(Int, Int), Bool] = {}
  inspect(
    func_types_structurally_equal(types, t1, t2, 2, 3, visited),
    content="false",
  )
}

///|
test "value_types_structurally_equal: basic types" {
  let types : Array[@types.FuncType] = []
  let visited : Map[(Int, Int), Bool] = {}
  inspect(
    value_types_structurally_equal(types, I32, I32, 0, 0, visited),
    content="true",
  )
  inspect(
    value_types_structurally_equal(types, I32, I64, 0, 0, visited),
    content="false",
  )
  inspect(
    value_types_structurally_equal(types, F32, F32, 0, 0, visited),
    content="true",
  )
  inspect(
    value_types_structurally_equal(types, FuncRef, FuncRef, 0, 0, visited),
    content="true",
  )
  inspect(
    value_types_structurally_equal(types, FuncRef, ExternRef, 0, 0, visited),
    content="false",
  )
}

///|
test "type_indices_structurally_equal: same index" {
  let types : Array[@types.FuncType] = [{ params: [I32], results: [] }]
  let visited : Map[(Int, Int), Bool] = {}
  inspect(type_indices_structurally_equal(types, 0, 0, visited), content="true")
}

///|
test "type_indices_structurally_equal: different but equivalent types" {
  let t1 : @types.FuncType = { params: [I32, F32], results: [I64] }
  let t2 : @types.FuncType = { params: [I32, F32], results: [I64] }
  let types : Array[@types.FuncType] = [t1, t2]
  let visited : Map[(Int, Int), Bool] = {}
  inspect(type_indices_structurally_equal(types, 0, 1, visited), content="true")
}

///|
test "type_indices_structurally_equal: out of bounds" {
  let types : Array[@types.FuncType] = [{ params: [], results: [] }]
  let visited : Map[(Int, Int), Bool] = {}
  inspect(
    type_indices_structurally_equal(types, 0, 5, visited),
    content="false",
  )
  let visited2 : Map[(Int, Int), Bool] = {}
  inspect(
    type_indices_structurally_equal(types, -1, 0, visited2),
    content="false",
  )
}
