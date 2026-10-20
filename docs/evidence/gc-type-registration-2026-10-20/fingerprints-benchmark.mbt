fn many_types_module(count : Int32, allocations : Int32) -> @types.Module {
  let types : Array[@types.SubType] = []
  let type_rec_groups : Array[Int32] = []
  for i in 0..<count {
    let params : Array[@types.ValueType] = if i < 13 {
      let scalars : Array[@types.ValueType] = []
      for _ in 0..<i {
        scalars.push(I32)
      }
      scalars
    } else {
      [RefNullFuncTyped(i - 13)]
    }
    types.push(
      @types.SubType::from_func({
        params: ReadOnlyArray::from_array(params),
        results: [],
      }),
    )
    type_rec_groups.push(i)
  }
  let struct_idx = count
  types.push(
    @types.SubType::simple(
      Struct({ fields: [{ storage_type: Val(I32), mutable: true, }], }),
    ),
  )
  type_rec_groups.push(struct_idx)
  {
    ..@types.Module::empty(),
    types,
    type_rec_groups,
    funcs: [0],
    codes: [{ locals: [], body: [], }],
    globals: Array::make(allocations,
      {
        type_: { value_type: RefNullStruct(struct_idx), mutable: false, },
        init: [StructNewDefault(struct_idx)],
      },
    ),
    exports: [{ name: "_start", desc: Func(0), }],
  }
}


///|
async fn main {
 for count in [1000, 2000, 5000] {
  for allocations in [0, 1] {
   let module_ = many_types_module(count, allocations)
   for trial in 0..<3 {
    let start = @async.now()
    let canonical = @types.compute_canonical_type_indices(module_.types, type_rec_groups=module_.type_rec_groups)
    let computed = @async.now()
    assert_eq(canonical[count], count)
    let (store, instance) = @executor.instantiate_module(module_)
    let instantiated = @async.now()
    assert_eq(instance.global_addrs.length(), allocations)
    store.close()
    println("types=\{count+1} globals=\{allocations} trial=\{trial} canonical_ms=\{computed-start} instantiate_ms=\{instantiated-computed} close_ms=\{@async.now()-instantiated}")
   }
  }
 }
}
