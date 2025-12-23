///|
/// Unit tests for GC type definitions and helper functions

// ============================================================
// SubType creation tests
// ============================================================

///|
test "SubType::simple creates final type without supertypes" {
  let composite = CompositeType::Func({ params: [I32], results: [I64] })
  let subtype = SubType::simple(composite)
  inspect(subtype.final_, content="true")
  inspect(subtype.supertypes.length(), content="0")
  inspect(subtype.composite, content="Func({params: [I32], results: [I64]})")
}

///|
test "SubType::from_func wraps FuncType correctly" {
  let func_type : FuncType = { params: [F32, F64], results: [I32] }
  let subtype = SubType::from_func(func_type)
  inspect(subtype.final_, content="true")
  inspect(subtype.supertypes.length(), content="0")
  guard subtype.composite is Func(ft) else { return }
  inspect(ft.params, content="[F32, F64]")
  inspect(ft.results, content="[I32]")
}

///|
test "SubType::func convenience function" {
  let subtype = SubType::func([I32, I32], [I32])
  inspect(subtype.final_, content="true")
  guard subtype.composite is Func(ft) else { return }
  inspect(ft.params, content="[I32, I32]")
  inspect(ft.results, content="[I32]")
}

///|
test "SubType::func with empty params and results" {
  let subtype = SubType::func([], [])
  guard subtype.composite is Func(ft) else { return }
  inspect(ft.params.length(), content="0")
  inspect(ft.results.length(), content="0")
}

// ============================================================
// StructType tests
// ============================================================

///|
test "StructType with immutable i32 field" {
  let field : FieldType = { storage_type: Val(I32), mutable: false }
  let struct_type : StructType = { fields: [field] }
  inspect(struct_type.fields.length(), content="1")
  inspect(struct_type.fields[0].mutable, content="false")
  inspect(struct_type.fields[0].storage_type, content="Val(I32)")
}

///|
test "StructType with mutable fields" {
  let field1 : FieldType = { storage_type: Val(I32), mutable: true }
  let field2 : FieldType = { storage_type: Val(I64), mutable: false }
  let struct_type : StructType = { fields: [field1, field2] }
  inspect(struct_type.fields.length(), content="2")
  inspect(struct_type.fields[0].mutable, content="true")
  inspect(struct_type.fields[1].mutable, content="false")
}

///|
test "StructType with packed i8 field" {
  let field : FieldType = { storage_type: Packed(I8), mutable: true }
  let struct_type : StructType = { fields: [field] }
  inspect(struct_type.fields[0].storage_type, content="Packed(I8)")
}

///|
test "StructType with packed i16 field" {
  let field : FieldType = { storage_type: Packed(I16), mutable: false }
  let struct_type : StructType = { fields: [field] }
  inspect(struct_type.fields[0].storage_type, content="Packed(I16)")
}

///|
test "StructType with mixed field types" {
  let fields : Array[FieldType] = [
    { storage_type: Val(I32), mutable: false },
    { storage_type: Packed(I8), mutable: true },
    { storage_type: Val(F64), mutable: false },
    { storage_type: Packed(I16), mutable: true },
  ]
  let struct_type : StructType = { fields, }
  inspect(struct_type.fields.length(), content="4")
}

///|
test "StructType with reference field" {
  let field : FieldType = { storage_type: Val(RefNullStruct(0)), mutable: true }
  let struct_type : StructType = { fields: [field] }
  inspect(struct_type.fields[0].storage_type, content="Val(RefNullStruct(0))")
}

// ============================================================
// ArrayType tests
// ============================================================

///|
test "ArrayType with i32 element" {
  let elem : FieldType = { storage_type: Val(I32), mutable: true }
  let array_type : ArrayType = { element: elem }
  inspect(array_type.element.storage_type, content="Val(I32)")
  inspect(array_type.element.mutable, content="true")
}

///|
test "ArrayType with packed i8 element" {
  let elem : FieldType = { storage_type: Packed(I8), mutable: true }
  let array_type : ArrayType = { element: elem }
  inspect(array_type.element.storage_type, content="Packed(I8)")
}

///|
test "ArrayType with immutable element" {
  let elem : FieldType = { storage_type: Val(F64), mutable: false }
  let array_type : ArrayType = { element: elem }
  inspect(array_type.element.mutable, content="false")
}

///|
test "ArrayType with reference element" {
  let elem : FieldType = { storage_type: Val(RefNullArray(1)), mutable: true }
  let array_type : ArrayType = { element: elem }
  inspect(array_type.element.storage_type, content="Val(RefNullArray(1))")
}

// ============================================================
// CompositeType tests
// ============================================================

///|
test "CompositeType::Func variant" {
  let ft : FuncType = { params: [I32], results: [I32] }
  let composite = CompositeType::Func(ft)
  guard composite is Func(f) else { return }
  inspect(f.params, content="[I32]")
}

///|
test "CompositeType::Struct variant" {
  let st : StructType = { fields: [] }
  let composite = CompositeType::Struct(st)
  guard composite is Struct(s) else { return }
  inspect(s.fields.length(), content="0")
}

///|
test "CompositeType::Array variant" {
  let at : ArrayType = { element: { storage_type: Val(I32), mutable: true } }
  let composite = CompositeType::Array(at)
  guard composite is Array(a) else { return }
  inspect(a.element.storage_type, content="Val(I32)")
}

// ============================================================
// func_types_to_subtypes tests
// ============================================================

///|
test "func_types_to_subtypes with empty array" {
  let func_types : Array[FuncType] = []
  let subtypes = func_types_to_subtypes(func_types)
  inspect(subtypes.length(), content="0")
}

///|
test "func_types_to_subtypes with single type" {
  let func_types : Array[FuncType] = [{ params: [I32], results: [I64] }]
  let subtypes = func_types_to_subtypes(func_types)
  inspect(subtypes.length(), content="1")
  inspect(subtypes[0].final_, content="true")
  guard subtypes[0].composite is Func(ft) else { return }
  inspect(ft.params, content="[I32]")
  inspect(ft.results, content="[I64]")
}

///|
test "func_types_to_subtypes with multiple types" {
  let func_types : Array[FuncType] = [
    { params: [], results: [] },
    { params: [I32, I32], results: [I32] },
    { params: [F64], results: [F64, F64] },
  ]
  let subtypes = func_types_to_subtypes(func_types)
  inspect(subtypes.length(), content="3")
  // Check each converted type
  for i, subtype in subtypes {
    inspect(subtype.final_, content="true")
    guard subtype.composite is Func(ft) else { continue }
    inspect(ft.params.length() == func_types[i].params.length(), content="true")
    inspect(
      ft.results.length() == func_types[i].results.length(),
      content="true",
    )
  }
}

// ============================================================
// extract_func_types tests
// ============================================================

///|
test "extract_func_types with empty array" {
  let subtypes : Array[SubType] = []
  let func_types = extract_func_types(subtypes)
  inspect(func_types.length(), content="0")
}

///|
test "extract_func_types with func subtypes" {
  let subtypes : Array[SubType] = [
    SubType::func([I32], [I32]),
    SubType::func([F64, F64], [F64]),
  ]
  let func_types = extract_func_types(subtypes)
  inspect(func_types.length(), content="2")
  inspect(func_types[0].params, content="[I32]")
  inspect(func_types[0].results, content="[I32]")
  inspect(func_types[1].params, content="[F64, F64]")
  inspect(func_types[1].results, content="[F64]")
}

///|
test "extract_func_types with struct subtype returns placeholder" {
  let struct_type : StructType = {
    fields: [{ storage_type: Val(I32), mutable: false }],
  }
  let subtypes : Array[SubType] = [
    SubType::simple(CompositeType::Struct(struct_type)),
  ]
  let func_types = extract_func_types(subtypes)
  inspect(func_types.length(), content="1")
  // Struct types get empty function placeholder
  inspect(func_types[0].params.length(), content="0")
  inspect(func_types[0].results.length(), content="0")
}

///|
test "extract_func_types with array subtype returns placeholder" {
  let array_type : ArrayType = {
    element: { storage_type: Val(I64), mutable: true },
  }
  let subtypes : Array[SubType] = [
    SubType::simple(CompositeType::Array(array_type)),
  ]
  let func_types = extract_func_types(subtypes)
  inspect(func_types.length(), content="1")
  // Array types get empty function placeholder
  inspect(func_types[0].params.length(), content="0")
  inspect(func_types[0].results.length(), content="0")
}

///|
test "extract_func_types with mixed types" {
  let struct_type : StructType = { fields: [] }
  let array_type : ArrayType = {
    element: { storage_type: Val(I32), mutable: true },
  }
  let subtypes : Array[SubType] = [
    SubType::func([I32], [I32]),
    SubType::simple(CompositeType::Struct(struct_type)),
    SubType::func([F64], [F64]),
    SubType::simple(CompositeType::Array(array_type)),
  ]
  let func_types = extract_func_types(subtypes)
  inspect(func_types.length(), content="4")
  // Index 0: actual func type
  inspect(func_types[0].params, content="[I32]")
  // Index 1: struct placeholder
  inspect(func_types[1].params.length(), content="0")
  // Index 2: actual func type
  inspect(func_types[2].params, content="[F64]")
  // Index 3: array placeholder
  inspect(func_types[3].params.length(), content="0")
}

// ============================================================
// roundtrip test: func_types_to_subtypes -> extract_func_types
// ============================================================

///|
test "roundtrip: func_types -> subtypes -> func_types" {
  let original : Array[FuncType] = [
    { params: [], results: [] },
    { params: [I32, I64], results: [F32] },
    { params: [F64], results: [I32, I64] },
  ]
  let subtypes = func_types_to_subtypes(original)
  let recovered = extract_func_types(subtypes)
  inspect(recovered.length(), content="3")
  for i in 0..<original.length() {
    inspect(recovered[i] == original[i], content="true")
  }
}

// ============================================================
// GC ValueType tests
// ============================================================

///|
test "ValueType::RefStruct equality" {
  let t1 : ValueType = RefStruct(0)
  let t2 : ValueType = RefStruct(0)
  let t3 : ValueType = RefStruct(1)
  inspect(t1 == t2, content="true")
  inspect(t1 == t3, content="false")
}

///|
test "ValueType::RefNullStruct equality" {
  let t1 : ValueType = RefNullStruct(0)
  let t2 : ValueType = RefNullStruct(0)
  let t3 : ValueType = RefNullStruct(1)
  inspect(t1 == t2, content="true")
  inspect(t1 == t3, content="false")
}

///|
test "ValueType::RefArray equality" {
  let t1 : ValueType = RefArray(0)
  let t2 : ValueType = RefArray(0)
  let t3 : ValueType = RefArray(1)
  inspect(t1 == t2, content="true")
  inspect(t1 == t3, content="false")
}

///|
test "ValueType::RefNullArray equality" {
  let t1 : ValueType = RefNullArray(0)
  let t2 : ValueType = RefNullArray(0)
  let t3 : ValueType = RefNullArray(1)
  inspect(t1 == t2, content="true")
  inspect(t1 == t3, content="false")
}

///|
test "ValueType GC abstract types" {
  let types : Array[ValueType] = [
    RefAny,
    RefEq,
    RefNullEq,
    RefI31,
    RefNullI31,
    RefNone,
  ]
  inspect(types.length(), content="6")
  // Each type is distinct
  inspect(RefAny == RefEq, content="false")
  inspect(ValueType::RefI31 == RefNullI31, content="false")
}

// ============================================================
// GC Value tests
// ============================================================

///|
test "Value::StructRef" {
  let v1 : Value = StructRef(42)
  let v2 : Value = StructRef(42)
  let v3 : Value = StructRef(0)
  inspect(v1 == v2, content="true")
  inspect(v1 == v3, content="false")
}

///|
test "Value::ArrayRef" {
  let v1 : Value = ArrayRef(10)
  let v2 : Value = ArrayRef(10)
  let v3 : Value = ArrayRef(20)
  inspect(v1 == v2, content="true")
  inspect(v1 == v3, content="false")
}

///|
test "Value::I31" {
  let v1 : Value = I31(100)
  let v2 : Value = I31(100)
  let v3 : Value = I31(-1)
  inspect(v1 == v2, content="true")
  inspect(v1 == v3, content="false")
}

///|
test "Value::I31 max value (2^30 - 1)" {
  let max_i31 = (1 << 30) - 1 // 1073741823
  let v : Value = I31(max_i31)
  guard v is I31(n) else { return }
  inspect(n, content="1073741823")
}

///|
test "Value GC types are distinct from other ref types" {
  let struct_ref : Value = StructRef(0)
  let array_ref : Value = ArrayRef(0)
  let func_ref : Value = FuncRef(0)
  let extern_ref : Value = ExternRef(0)
  inspect(struct_ref == array_ref, content="false")
  inspect(struct_ref == func_ref, content="false")
  inspect(array_ref == extern_ref, content="false")
}

// ============================================================
// SubType with inheritance tests
// ============================================================

///|
test "SubType with supertype" {
  let subtype : SubType = {
    final_: false,
    supertypes: [0], // extends type at index 0
    composite: CompositeType::Func({ params: [I32], results: [I32] }),
  }
  inspect(subtype.final_, content="false")
  inspect(subtype.supertypes.length(), content="1")
  inspect(subtype.supertypes[0], content="0")
}

///|
test "SubType final vs non-final" {
  let final_type = SubType::simple(
    CompositeType::Func({ params: [], results: [] }),
  )
  let open_type : SubType = {
    final_: false,
    supertypes: [],
    composite: CompositeType::Func({ params: [], results: [] }),
  }
  inspect(final_type.final_, content="true")
  inspect(open_type.final_, content="false")
}

// ============================================================
// FieldType equality tests
// ============================================================

///|
test "FieldType equality" {
  let f1 : FieldType = { storage_type: Val(I32), mutable: false }
  let f2 : FieldType = { storage_type: Val(I32), mutable: false }
  let f3 : FieldType = { storage_type: Val(I32), mutable: true }
  let f4 : FieldType = { storage_type: Val(I64), mutable: false }
  inspect(f1 == f2, content="true")
  inspect(f1 == f3, content="false") // different mutability
  inspect(f1 == f4, content="false") // different storage type
}

///|
test "StorageType equality" {
  let s1 : StorageType = Val(I32)
  let s2 : StorageType = Val(I32)
  let s3 : StorageType = Packed(I8)
  let s4 : StorageType = Packed(I8)
  inspect(s1 == s2, content="true")
  inspect(s3 == s4, content="true")
  inspect(s1 == s3, content="false")
}

///|
test "PackedType equality" {
  let p1 : PackedType = I8
  let p2 : PackedType = I8
  let p3 : PackedType = I16
  inspect(p1 == p2, content="true")
  inspect(p1 == p3, content="false")
}

// ============================================================
// Module type accessor tests
// ============================================================

///|
test "Module::get_func_type returns correct FuncType" {
  let mod_ = Module::new()
  mod_.types.push(SubType::func([I32, I32], [I32]))
  mod_.types.push(SubType::func([], [F64]))
  let ft0 = mod_.get_func_type(0)
  let ft1 = mod_.get_func_type(1)
  inspect(ft0.params, content="[I32, I32]")
  inspect(ft0.results, content="[I32]")
  inspect(ft1.params, content="[]")
  inspect(ft1.results, content="[F64]")
}

///|
test "Module::get_struct_type returns correct StructType" {
  let mod_ = Module::new()
  let struct_type : StructType = {
    fields: [
      { storage_type: Val(I32), mutable: false },
      { storage_type: Val(I64), mutable: true },
    ],
  }
  mod_.types.push(SubType::simple(CompositeType::Struct(struct_type)))
  let st = mod_.get_struct_type(0)
  inspect(st.fields.length(), content="2")
  inspect(st.fields[0].storage_type, content="Val(I32)")
  inspect(st.fields[1].mutable, content="true")
}

///|
test "Module::get_array_type returns correct ArrayType" {
  let mod_ = Module::new()
  let array_type : ArrayType = {
    element: { storage_type: Packed(I8), mutable: true },
  }
  mod_.types.push(SubType::simple(CompositeType::Array(array_type)))
  let at = mod_.get_array_type(0)
  inspect(at.element.storage_type, content="Packed(I8)")
  inspect(at.element.mutable, content="true")
}

///|
test "Module::is_func_type correctly identifies function types" {
  let mod_ = Module::new()
  let struct_type : StructType = { fields: [] }
  let array_type : ArrayType = {
    element: { storage_type: Val(I32), mutable: true },
  }
  mod_.types.push(SubType::func([I32], [I32])) // index 0: func
  mod_.types.push(SubType::simple(CompositeType::Struct(struct_type))) // index 1: struct
  mod_.types.push(SubType::simple(CompositeType::Array(array_type))) // index 2: array
  inspect(mod_.is_func_type(0), content="true")
  inspect(mod_.is_func_type(1), content="false")
  inspect(mod_.is_func_type(2), content="false")
}

///|
test "Module::is_struct_type correctly identifies struct types" {
  let mod_ = Module::new()
  let struct_type : StructType = { fields: [] }
  let array_type : ArrayType = {
    element: { storage_type: Val(I32), mutable: true },
  }
  mod_.types.push(SubType::func([I32], [I32])) // index 0: func
  mod_.types.push(SubType::simple(CompositeType::Struct(struct_type))) // index 1: struct
  mod_.types.push(SubType::simple(CompositeType::Array(array_type))) // index 2: array
  inspect(mod_.is_struct_type(0), content="false")
  inspect(mod_.is_struct_type(1), content="true")
  inspect(mod_.is_struct_type(2), content="false")
}

///|
test "Module::is_array_type correctly identifies array types" {
  let mod_ = Module::new()
  let struct_type : StructType = { fields: [] }
  let array_type : ArrayType = {
    element: { storage_type: Val(I32), mutable: true },
  }
  mod_.types.push(SubType::func([I32], [I32])) // index 0: func
  mod_.types.push(SubType::simple(CompositeType::Struct(struct_type))) // index 1: struct
  mod_.types.push(SubType::simple(CompositeType::Array(array_type))) // index 2: array
  inspect(mod_.is_array_type(0), content="false")
  inspect(mod_.is_array_type(1), content="false")
  inspect(mod_.is_array_type(2), content="true")
}

///|
test "Module with mixed type definitions" {
  let mod_ = Module::new()
  // Add various types
  mod_.types.push(SubType::func([], [])) // 0: void -> void
  mod_.types.push(SubType::func([I32, I32], [I32])) // 1: add signature
  mod_.types.push(
    SubType::simple(
      CompositeType::Struct({
        fields: [{ storage_type: Val(I32), mutable: true }],
      }),
    ),
  ) // 2: point struct
  mod_.types.push(
    SubType::simple(
      CompositeType::Array({
        element: { storage_type: Val(F64), mutable: true },
      }),
    ),
  ) // 3: f64 array
  mod_.types.push(SubType::func([RefNullStruct(2)], [I32])) // 4: func taking struct ref
  inspect(mod_.types.length(), content="5")
  // Verify type queries
  inspect(mod_.is_func_type(0), content="true")
  inspect(mod_.is_func_type(1), content="true")
  inspect(mod_.is_struct_type(2), content="true")
  inspect(mod_.is_array_type(3), content="true")
  inspect(mod_.is_func_type(4), content="true")
  // Get specific types
  let add_type = mod_.get_func_type(1)
  inspect(add_type.params, content="[I32, I32]")
  let point_type = mod_.get_struct_type(2)
  inspect(point_type.fields.length(), content="1")
  let arr_type = mod_.get_array_type(3)
  inspect(arr_type.element.storage_type, content="Val(F64)")
}
