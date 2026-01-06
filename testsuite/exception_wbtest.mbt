// Tests for WebAssembly Exception Handling
// These tests cover throw, try_table, catch, catch_ref, catch_all, catch_all_ref, and throw_ref

///|
/// Create a module with a simple throw instruction
fn create_throw_module() -> @types.Module {
  // tag $e0 (no params)
  let tag0 : @types.TagType = { type_idx: 0 }
  // Function type for tag (no params, no results)
  let tag_type : @types.FuncType = { params: [], results: [] }
  // Function type for throw_it: () -> ()
  let func_type : @types.FuncType = { params: [], results: [] }
  // Function: throw_it() { throw $e0 }
  let throw_func : @types.FunctionCode = { locals: [], body: [Throw(0)] }
  {
    types: [
      @types.SubType::from_func(tag_type),
      @types.SubType::from_func(func_type),
    ],
    type_rec_groups: [0, 1],
    imports: [],
    funcs: [1],
    tables: [],
    memories: [],
    globals: [],
    exports: [{ name: "throw_it", desc: @types.ExportDesc::Func(0) }],
    start: None,
    elems: [],
    codes: [throw_func],
    datas: [],
    tags: [tag0],
    func_names: {},
  }
}

///|
test "exception: basic throw raises exception" {
  let mod = create_throw_module()
  let (store, instance) = @executor.instantiate_module(mod)
  // Calling throw_it should raise an exception
  let result = try? @executor.call_exported_func(store, instance, "throw_it", [])
  inspect(result is Err(_), content="true")
}

///|
/// Create a module with try_table and catch
fn create_catch_module() -> @types.Module {
  // tag $e0 (no params)
  let tag0 : @types.TagType = { type_idx: 0 }
  let tag_type : @types.FuncType = { params: [], results: [] }
  // Function type: () -> i32
  let func_type : @types.FuncType = {
    params: [],
    results: [@types.ValueType::I32],
  }
  // Function: catch_it() {
  //   block $handler (result)
  //     try_table (catch $e0 $handler)
  //       throw $e0
  //     end
  //     return (i32.const 0)  // not caught - shouldn't reach here
  //   end
  //   i32.const 1  // caught
  // }
  let catch_func : @types.FunctionCode = {
    locals: [],
    body: [
      Block(@types.BlockType::Empty, [
        TryTable(@types.BlockType::Empty, [@types.CatchHandler::Catch(0, 0)], [
          Throw(0),
        ]),
        I32Const(0),
        Return,
      ]),
      I32Const(1),
    ],
  }
  {
    types: [
      @types.SubType::from_func(tag_type),
      @types.SubType::from_func(func_type),
    ],
    type_rec_groups: [0, 1],
    imports: [],
    funcs: [1],
    tables: [],
    memories: [],
    globals: [],
    exports: [{ name: "catch_it", desc: @types.ExportDesc::Func(0) }],
    start: None,
    elems: [],
    codes: [catch_func],
    datas: [],
    tags: [tag0],
    func_names: {},
  }
}

///|
test "exception: try_table with catch handles exception" {
  let mod = create_catch_module()
  let (store, instance) = @executor.instantiate_module(mod)
  let result = @executor.call_exported_func(store, instance, "catch_it", [])
  inspect(result[0], content="I32(1)")
}

///|
/// Create a module with throw that passes i32 parameter
fn create_throw_param_module() -> @types.Module {
  // tag $e-i32 (param i32)
  let tag0 : @types.TagType = { type_idx: 0 }
  let tag_type : @types.FuncType = {
    params: [@types.ValueType::I32],
    results: [],
  }
  // Function type: (i32) -> i32
  let func_type : @types.FuncType = {
    params: [@types.ValueType::I32],
    results: [@types.ValueType::I32],
  }
  // Function: catch_param(n) {
  //   block $handler (result i32)
  //     try_table (catch $e-i32 $handler)
  //       local.get 0
  //       throw $e-i32
  //     end
  //     i32.const 0
  //   end
  // }
  let catch_func : @types.FunctionCode = {
    locals: [],
    body: [
      Block(@types.BlockType::Value(@types.ValueType::I32), [
        TryTable(@types.BlockType::Empty, [@types.CatchHandler::Catch(0, 0)], [
          LocalGet(0),
          Throw(0),
        ]),
        I32Const(0),
      ]),
    ],
  }
  {
    types: [
      @types.SubType::from_func(tag_type),
      @types.SubType::from_func(func_type),
    ],
    type_rec_groups: [0, 1],
    imports: [],
    funcs: [1],
    tables: [],
    memories: [],
    globals: [],
    exports: [{ name: "catch_param", desc: @types.ExportDesc::Func(0) }],
    start: None,
    elems: [],
    codes: [catch_func],
    datas: [],
    tags: [tag0],
    func_names: {},
  }
}

///|
test "exception: catch receives exception parameter" {
  let mod = create_throw_param_module()
  let (store, instance) = @executor.instantiate_module(mod)
  // Pass 42, should catch and return 42
  let result = @executor.call_exported_func(store, instance, "catch_param", [
    I32(42),
  ])
  inspect(result[0], content="I32(42)")
  // Pass 100
  let result = @executor.call_exported_func(store, instance, "catch_param", [
    I32(100),
  ])
  inspect(result[0], content="I32(100)")
  // Pass -1
  let result = @executor.call_exported_func(store, instance, "catch_param", [
    I32(-1),
  ])
  inspect(result[0], content="I32(-1)")
}

///|
/// Create a module with catch_all
fn create_catch_all_module() -> @types.Module {
  // tag $e0 (no params)
  let tag0 : @types.TagType = { type_idx: 0 }
  let tag_type : @types.FuncType = { params: [], results: [] }
  // Function type: () -> i32
  let func_type : @types.FuncType = {
    params: [],
    results: [@types.ValueType::I32],
  }
  // Function: catch_all_test() {
  //   block $handler (result)
  //     try_table (catch_all $handler)
  //       throw $e0
  //     end
  //     i32.const 0
  //   end
  //   i32.const 1
  // }
  let catch_func : @types.FunctionCode = {
    locals: [],
    body: [
      Block(@types.BlockType::Empty, [
        TryTable(@types.BlockType::Empty, [@types.CatchHandler::CatchAll(0)], [
          Throw(0),
        ]),
        I32Const(0),
        Return,
      ]),
      I32Const(1),
    ],
  }
  {
    types: [
      @types.SubType::from_func(tag_type),
      @types.SubType::from_func(func_type),
    ],
    type_rec_groups: [0, 1],
    imports: [],
    funcs: [1],
    tables: [],
    memories: [],
    globals: [],
    exports: [{ name: "catch_all_test", desc: @types.ExportDesc::Func(0) }],
    start: None,
    elems: [],
    codes: [catch_func],
    datas: [],
    tags: [tag0],
    func_names: {},
  }
}

///|
test "exception: catch_all catches any exception" {
  let mod = create_catch_all_module()
  let (store, instance) = @executor.instantiate_module(mod)
  let result = @executor.call_exported_func(store, instance, "catch_all_test", [])
  inspect(result[0], content="I32(1)")
}

///|
/// Create a module with catch_ref that captures exnref
fn create_catch_ref_module() -> @types.Module {
  // tag $e-i32 (param i32)
  let tag0 : @types.TagType = { type_idx: 0 }
  let tag_type : @types.FuncType = {
    params: [@types.ValueType::I32],
    results: [],
  }
  // Function type: (i32) -> (i32, exnref)
  let func_type : @types.FuncType = {
    params: [@types.ValueType::I32],
    results: [@types.ValueType::I32, @types.ValueType::ExnRef],
  }
  // Function: catch_ref_test(n) {
  //   block $handler (result i32 exnref)
  //     try_table (catch_ref $e-i32 $handler)
  //       local.get 0
  //       throw $e-i32
  //     end
  //     unreachable
  //   end
  // }
  let catch_func : @types.FunctionCode = {
    locals: [],
    body: [
      Block(
        @types.BlockType::MultiValue([
          @types.ValueType::I32,
          @types.ValueType::ExnRef,
        ]),
        [
          TryTable(
            @types.BlockType::Empty,
            [@types.CatchHandler::CatchRef(0, 0)],
            [LocalGet(0), Throw(0)],
          ),
          Unreachable,
        ],
      ),
    ],
  }
  {
    types: [
      @types.SubType::from_func(tag_type),
      @types.SubType::from_func(func_type),
    ],
    type_rec_groups: [0, 1],
    imports: [],
    funcs: [1],
    tables: [],
    memories: [],
    globals: [],
    exports: [{ name: "catch_ref_test", desc: @types.ExportDesc::Func(0) }],
    start: None,
    elems: [],
    codes: [catch_func],
    datas: [],
    tags: [tag0],
    func_names: {},
  }
}

///|
test "exception: catch_ref captures exception value and exnref" {
  let mod = create_catch_ref_module()
  let (store, instance) = @executor.instantiate_module(mod)
  let result = @executor.call_exported_func(store, instance, "catch_ref_test", [
    I32(42),
  ])
  // First result should be the exception value
  inspect(result[0], content="I32(42)")
  // Second result should be an exnref
  inspect(result[1] is ExnRef(_), content="true")
}

///|
test "exception: catch_ref with different values" {
  let mod = create_catch_ref_module()
  let (store, instance) = @executor.instantiate_module(mod)
  // Test with value 100
  let result = @executor.call_exported_func(store, instance, "catch_ref_test", [
    I32(100),
  ])
  inspect(result[0], content="I32(100)")
  // Test with value 0
  let result = @executor.call_exported_func(store, instance, "catch_ref_test", [
    I32(0),
  ])
  inspect(result[0], content="I32(0)")
  // Test with negative value
  let result = @executor.call_exported_func(store, instance, "catch_ref_test", [
    I32(-999),
  ])
  inspect(result[0], content="I32(-999)")
}

///|
/// Create a module with catch_all_ref
fn create_catch_all_ref_module() -> @types.Module {
  // tag $e0 (no params)
  let tag0 : @types.TagType = { type_idx: 0 }
  let tag_type : @types.FuncType = { params: [], results: [] }
  // Function type: () -> exnref
  let func_type : @types.FuncType = {
    params: [],
    results: [@types.ValueType::ExnRef],
  }
  // Function: catch_all_ref_test() {
  //   block $handler (result exnref)
  //     try_table (catch_all_ref $handler)
  //       throw $e0
  //     end
  //     unreachable
  //   end
  // }
  let catch_func : @types.FunctionCode = {
    locals: [],
    body: [
      Block(@types.BlockType::Value(@types.ValueType::ExnRef), [
        TryTable(
          @types.BlockType::Empty,
          [@types.CatchHandler::CatchAllRef(0)],
          [Throw(0)],
        ),
        Unreachable,
      ]),
    ],
  }
  {
    types: [
      @types.SubType::from_func(tag_type),
      @types.SubType::from_func(func_type),
    ],
    type_rec_groups: [0, 1],
    imports: [],
    funcs: [1],
    tables: [],
    memories: [],
    globals: [],
    exports: [{ name: "catch_all_ref_test", desc: @types.ExportDesc::Func(0) }],
    start: None,
    elems: [],
    codes: [catch_func],
    datas: [],
    tags: [tag0],
    func_names: {},
  }
}

///|
test "exception: catch_all_ref captures exnref" {
  let mod = create_catch_all_ref_module()
  let (store, instance) = @executor.instantiate_module(mod)
  let result = @executor.call_exported_func(
    store,
    instance,
    "catch_all_ref_test",
    [],
  )
  inspect(result[0] is ExnRef(_), content="true")
}

///|
/// Create a module with throw_ref
fn create_throw_ref_module() -> @types.Module {
  // tag $e-i32 (param i32)
  let tag0 : @types.TagType = { type_idx: 0 }
  let tag_type : @types.FuncType = {
    params: [@types.ValueType::I32],
    results: [],
  }
  // Function type: (i32) -> i32
  let func_type : @types.FuncType = {
    params: [@types.ValueType::I32],
    results: [@types.ValueType::I32],
  }
  // Function: throw_ref_test(n) {
  //   block $outer (result i32)
  //     block $inner (result i32 exnref)
  //       try_table (catch_ref $e-i32 $inner)
  //         local.get 0
  //         throw $e-i32
  //       end
  //       unreachable
  //     end
  //     ;; At this point we have: exception_value exnref on stack
  //     ;; Add 100 to the value
  //     i32.const 100
  //     i32.add
  //     local.set 0  ;; save modified value
  //     ;; Now re-throw the exnref
  //     try_table (catch $e-i32 $outer)
  //       throw_ref
  //     end
  //     unreachable
  //   end
  // }
  let throw_ref_func : @types.FunctionCode = {
    locals: [],
    body: [
      Block(@types.BlockType::Value(@types.ValueType::I32), [
        Block(
          @types.BlockType::MultiValue([
            @types.ValueType::I32,
            @types.ValueType::ExnRef,
          ]),
          [
            TryTable(
              @types.BlockType::Empty,
              [@types.CatchHandler::CatchRef(0, 0)],
              [LocalGet(0), Throw(0)],
            ),
            Unreachable,
          ],
        ),
        // Stack: i32 exnref
        // Save the exnref to local 0 temporarily
        // Actually we need another local for this
        // Let's simplify: just re-throw and catch the original value
        TryTable(@types.BlockType::Empty, [@types.CatchHandler::Catch(0, 1)], [
          ThrowRef,
        ]),
        Unreachable,
      ]),
    ],
  }
  {
    types: [
      @types.SubType::from_func(tag_type),
      @types.SubType::from_func(func_type),
    ],
    type_rec_groups: [0, 1],
    imports: [],
    funcs: [1],
    tables: [],
    memories: [],
    globals: [],
    exports: [{ name: "throw_ref_test", desc: @types.ExportDesc::Func(0) }],
    start: None,
    elems: [],
    codes: [throw_ref_func],
    datas: [],
    tags: [tag0],
    func_names: {},
  }
}

///|
test "exception: throw_ref re-throws captured exception" {
  let mod = create_throw_ref_module()
  let (store, instance) = @executor.instantiate_module(mod)
  // The original value should be preserved through throw_ref
  let result = @executor.call_exported_func(store, instance, "throw_ref_test", [
    I32(42),
  ])
  inspect(result[0], content="I32(42)")
}

///|
test "exception: throw_ref preserves different values" {
  let mod = create_throw_ref_module()
  let (store, instance) = @executor.instantiate_module(mod)
  let result = @executor.call_exported_func(store, instance, "throw_ref_test", [
    I32(999),
  ])
  inspect(result[0], content="I32(999)")
  let result = @executor.call_exported_func(store, instance, "throw_ref_test", [
    I32(-123),
  ])
  inspect(result[0], content="I32(-123)")
}

///|
/// Create a module with multiple tags and selective catch
fn create_multi_tag_module() -> @types.Module {
  // tag $e0 (no params)
  let tag0 : @types.TagType = { type_idx: 0 }
  // tag $e1 (param i32)
  let tag1 : @types.TagType = { type_idx: 1 }
  let tag0_type : @types.FuncType = { params: [], results: [] }
  let tag1_type : @types.FuncType = {
    params: [@types.ValueType::I32],
    results: [],
  }
  // Function type: (i32) -> i32
  let func_type : @types.FuncType = {
    params: [@types.ValueType::I32],
    results: [@types.ValueType::I32],
  }
  // Function: selective_catch(which) {
  //   block $h1 (result i32)
  //     block $h0 (result)
  //       try_table (catch $e0 $h0) (catch $e1 $h1)
  //         local.get 0
  //         if
  //           throw $e1 (i32.const 100)
  //         else
  //           throw $e0
  //         end
  //       end
  //       unreachable
  //     end
  //     i32.const 0  ;; caught $e0
  //   end
  // }
  let selective_func : @types.FunctionCode = {
    locals: [],
    body: [
      Block(@types.BlockType::Value(@types.ValueType::I32), [
        Block(@types.BlockType::Empty, [
          TryTable(
            @types.BlockType::Empty,
            [@types.CatchHandler::Catch(0, 0), @types.CatchHandler::Catch(1, 1)],
            [
              LocalGet(0),
              If(@types.BlockType::Empty, [I32Const(100), Throw(1)], [Throw(0)]),
            ],
          ),
          Unreachable,
        ]),
        I32Const(0),
      ]),
    ],
  }
  {
    types: [
      @types.SubType::from_func(tag0_type),
      @types.SubType::from_func(tag1_type),
      @types.SubType::from_func(func_type),
    ],
    type_rec_groups: [0, 1, 2],
    imports: [],
    funcs: [2],
    tables: [],
    memories: [],
    globals: [],
    exports: [{ name: "selective_catch", desc: @types.ExportDesc::Func(0) }],
    start: None,
    elems: [],
    codes: [selective_func],
    datas: [],
    tags: [tag0, tag1],
    func_names: {},
  }
}

///|
test "exception: multiple catch handlers select correct handler" {
  let mod = create_multi_tag_module()
  let (store, instance) = @executor.instantiate_module(mod)
  // which=0: throw $e0, caught by first handler, returns 0
  let result = @executor.call_exported_func(
    store,
    instance,
    "selective_catch",
    [I32(0)],
  )
  inspect(result[0], content="I32(0)")
  // which=1: throw $e1(100), caught by second handler, returns 100
  let result = @executor.call_exported_func(
    store,
    instance,
    "selective_catch",
    [I32(1)],
  )
  inspect(result[0], content="I32(100)")
}

///|
/// Create a module where exception propagates through nested try_tables
fn create_propagate_module() -> @types.Module {
  // tag $e-i32 (param i32)
  let tag0 : @types.TagType = { type_idx: 0 }
  // tag $e-other (no params) - won't match
  let tag1 : @types.TagType = { type_idx: 1 }
  let tag0_type : @types.FuncType = {
    params: [@types.ValueType::I32],
    results: [],
  }
  let tag1_type : @types.FuncType = { params: [], results: [] }
  // Function type: (i32) -> i32
  let func_type : @types.FuncType = {
    params: [@types.ValueType::I32],
    results: [@types.ValueType::I32],
  }
  // Function: propagate(n) {
  //   block $outer (result i32)
  //     try_table (catch $e-i32 $outer)
  //       try_table (catch $e-other 0)  ;; won't match
  //         local.get 0
  //         throw $e-i32
  //       end
  //       unreachable
  //     end
  //     unreachable
  //   end
  // }
  let propagate_func : @types.FunctionCode = {
    locals: [],
    body: [
      Block(@types.BlockType::Value(@types.ValueType::I32), [
        TryTable(@types.BlockType::Empty, [@types.CatchHandler::Catch(0, 0)], [
          Block(@types.BlockType::Empty, [
            TryTable(
              @types.BlockType::Empty,
              [@types.CatchHandler::Catch(1, 0)],
              [LocalGet(0), Throw(0)],
            ),
            Unreachable,
          ]),
          Unreachable,
        ]),
        Unreachable,
      ]),
    ],
  }
  {
    types: [
      @types.SubType::from_func(tag0_type),
      @types.SubType::from_func(tag1_type),
      @types.SubType::from_func(func_type),
    ],
    type_rec_groups: [0, 1, 2],
    imports: [],
    funcs: [2],
    tables: [],
    memories: [],
    globals: [],
    exports: [{ name: "propagate", desc: @types.ExportDesc::Func(0) }],
    start: None,
    elems: [],
    codes: [propagate_func],
    datas: [],
    tags: [tag0, tag1],
    func_names: {},
  }
}

///|
test "exception: exception propagates through non-matching handlers" {
  let mod = create_propagate_module()
  let (store, instance) = @executor.instantiate_module(mod)
  let result = @executor.call_exported_func(store, instance, "propagate", [
    I32(42),
  ])
  inspect(result[0], content="I32(42)")
  let result = @executor.call_exported_func(store, instance, "propagate", [
    I32(777),
  ])
  inspect(result[0], content="I32(777)")
}

///|
/// Create a module with multi-value exception
fn create_multi_value_exception_module() -> @types.Module {
  // tag $e-multi (param i32 i32)
  let tag0 : @types.TagType = { type_idx: 0 }
  let tag_type : @types.FuncType = {
    params: [@types.ValueType::I32, @types.ValueType::I32],
    results: [],
  }
  // Function type: (i32, i32) -> (i32, i32)
  let func_type : @types.FuncType = {
    params: [@types.ValueType::I32, @types.ValueType::I32],
    results: [@types.ValueType::I32, @types.ValueType::I32],
  }
  // Function: multi_value_test(a, b) {
  //   block $h (result i32 i32)
  //     try_table (catch $e-multi $h)
  //       local.get 0
  //       local.get 1
  //       throw $e-multi
  //     end
  //     unreachable
  //   end
  // }
  let func : @types.FunctionCode = {
    locals: [],
    body: [
      Block(
        @types.BlockType::MultiValue([
          @types.ValueType::I32,
          @types.ValueType::I32,
        ]),
        [
          TryTable(
            @types.BlockType::Empty,
            [@types.CatchHandler::Catch(0, 0)],
            [LocalGet(0), LocalGet(1), Throw(0)],
          ),
          Unreachable,
        ],
      ),
    ],
  }
  {
    types: [
      @types.SubType::from_func(tag_type),
      @types.SubType::from_func(func_type),
    ],
    type_rec_groups: [0, 1],
    imports: [],
    funcs: [1],
    tables: [],
    memories: [],
    globals: [],
    exports: [{ name: "multi_value_test", desc: @types.ExportDesc::Func(0) }],
    start: None,
    elems: [],
    codes: [func],
    datas: [],
    tags: [tag0],
    func_names: {},
  }
}

///|
test "exception: multi-value exception passes all values" {
  let mod = create_multi_value_exception_module()
  let (store, instance) = @executor.instantiate_module(mod)
  let result = @executor.call_exported_func(
    store,
    instance,
    "multi_value_test",
    [I32(1), I32(2)],
  )
  inspect(result[0], content="I32(1)")
  inspect(result[1], content="I32(2)")
}

///|
test "exception: multi-value exception with various values" {
  let mod = create_multi_value_exception_module()
  let (store, instance) = @executor.instantiate_module(mod)
  let result = @executor.call_exported_func(
    store,
    instance,
    "multi_value_test",
    [I32(100), I32(200)],
  )
  inspect(result[0], content="I32(100)")
  inspect(result[1], content="I32(200)")
  let result = @executor.call_exported_func(
    store,
    instance,
    "multi_value_test",
    [I32(-1), I32(-2)],
  )
  inspect(result[0], content="I32(-1)")
  inspect(result[1], content="I32(-2)")
}

///|
/// Create a module that tests no exception case
fn create_no_exception_module() -> @types.Module {
  // tag $e0 (no params)
  let tag0 : @types.TagType = { type_idx: 0 }
  let tag_type : @types.FuncType = { params: [], results: [] }
  // Function type: () -> i32
  let func_type : @types.FuncType = {
    params: [],
    results: [@types.ValueType::I32],
  }
  // Function: no_throw() {
  //   try_table (catch $e0 ...)
  //     i32.const 42
  //   end
  // }
  let func : @types.FunctionCode = {
    locals: [],
    body: [
      TryTable(
        @types.BlockType::Value(@types.ValueType::I32),
        [@types.CatchHandler::Catch(0, 0)],
        [I32Const(42)],
      ),
    ],
  }
  {
    types: [
      @types.SubType::from_func(tag_type),
      @types.SubType::from_func(func_type),
    ],
    type_rec_groups: [0, 1],
    imports: [],
    funcs: [1],
    tables: [],
    memories: [],
    globals: [],
    exports: [{ name: "no_throw", desc: @types.ExportDesc::Func(0) }],
    start: None,
    elems: [],
    codes: [func],
    datas: [],
    tags: [tag0],
    func_names: {},
  }
}

///|
test "exception: try_table without exception returns normally" {
  let mod = create_no_exception_module()
  let (store, instance) = @executor.instantiate_module(mod)
  let result = @executor.call_exported_func(store, instance, "no_throw", [])
  inspect(result[0], content="I32(42)")
}

///|
/// Create a module with uncaught exception
fn create_uncaught_module() -> @types.Module {
  // tag $e0 (no params)
  let tag0 : @types.TagType = { type_idx: 0 }
  // tag $e1 (no params) - different tag
  let tag1 : @types.TagType = { type_idx: 0 }
  let tag_type : @types.FuncType = { params: [], results: [] }
  // Function type: () -> i32
  let func_type : @types.FuncType = {
    params: [],
    results: [@types.ValueType::I32],
  }
  // Function: uncaught() {
  //   try_table (catch $e1 ...)  ;; catches $e1, not $e0
  //     throw $e0
  //   end
  //   i32.const 0
  // }
  let func : @types.FunctionCode = {
    locals: [],
    body: [
      Block(@types.BlockType::Empty, [
        TryTable(@types.BlockType::Empty, [@types.CatchHandler::Catch(1, 0)], [
          Throw(0),
        ]),
        I32Const(0),
        Return,
      ]),
      I32Const(1),
    ],
  }
  {
    types: [
      @types.SubType::from_func(tag_type),
      @types.SubType::from_func(func_type),
    ],
    type_rec_groups: [0, 1],
    imports: [],
    funcs: [1],
    tables: [],
    memories: [],
    globals: [],
    exports: [{ name: "uncaught", desc: @types.ExportDesc::Func(0) }],
    start: None,
    elems: [],
    codes: [func],
    datas: [],
    tags: [tag0, tag1],
    func_names: {},
  }
}

///|
test "exception: uncaught exception propagates out" {
  let mod = create_uncaught_module()
  let (store, instance) = @executor.instantiate_module(mod)
  let result = try? @executor.call_exported_func(store, instance, "uncaught", [])
  // Should raise an error because exception is uncaught
  inspect(result is Err(_), content="true")
}

///|
/// Create a module with f32 exception parameter
fn create_f32_exception_module() -> @types.Module {
  // tag $e-f32 (param f32)
  let tag0 : @types.TagType = { type_idx: 0 }
  let tag_type : @types.FuncType = {
    params: [@types.ValueType::F32],
    results: [],
  }
  // Function type: (f32) -> f32
  let func_type : @types.FuncType = {
    params: [@types.ValueType::F32],
    results: [@types.ValueType::F32],
  }
  // Function: f32_test(x) {
  //   block $h (result f32)
  //     try_table (catch $e-f32 $h)
  //       local.get 0
  //       throw $e-f32
  //     end
  //     unreachable
  //   end
  // }
  let func : @types.FunctionCode = {
    locals: [],
    body: [
      Block(@types.BlockType::Value(@types.ValueType::F32), [
        TryTable(@types.BlockType::Empty, [@types.CatchHandler::Catch(0, 0)], [
          LocalGet(0),
          Throw(0),
        ]),
        Unreachable,
      ]),
    ],
  }
  {
    types: [
      @types.SubType::from_func(tag_type),
      @types.SubType::from_func(func_type),
    ],
    type_rec_groups: [0, 1],
    imports: [],
    funcs: [1],
    tables: [],
    memories: [],
    globals: [],
    exports: [{ name: "f32_test", desc: @types.ExportDesc::Func(0) }],
    start: None,
    elems: [],
    codes: [func],
    datas: [],
    tags: [tag0],
    func_names: {},
  }
}

///|
test "exception: f32 exception parameter" {
  let mod = create_f32_exception_module()
  let (store, instance) = @executor.instantiate_module(mod)
  let result = @executor.call_exported_func(store, instance, "f32_test", [
    F32(3.14),
  ])
  // Check it's approximately 3.14
  match result[0] {
    F32(v) => inspect(v > 3.13 && v < 3.15, content="true")
    _ => inspect("wrong type", content="F32")
  }
}

///|
/// Create a module with i64 exception parameter
fn create_i64_exception_module() -> @types.Module {
  // tag $e-i64 (param i64)
  let tag0 : @types.TagType = { type_idx: 0 }
  let tag_type : @types.FuncType = {
    params: [@types.ValueType::I64],
    results: [],
  }
  // Function type: (i64) -> i64
  let func_type : @types.FuncType = {
    params: [@types.ValueType::I64],
    results: [@types.ValueType::I64],
  }
  // Function: i64_test(x) {
  //   block $h (result i64)
  //     try_table (catch $e-i64 $h)
  //       local.get 0
  //       throw $e-i64
  //     end
  //     unreachable
  //   end
  // }
  let func : @types.FunctionCode = {
    locals: [],
    body: [
      Block(@types.BlockType::Value(@types.ValueType::I64), [
        TryTable(@types.BlockType::Empty, [@types.CatchHandler::Catch(0, 0)], [
          LocalGet(0),
          Throw(0),
        ]),
        Unreachable,
      ]),
    ],
  }
  {
    types: [
      @types.SubType::from_func(tag_type),
      @types.SubType::from_func(func_type),
    ],
    type_rec_groups: [0, 1],
    imports: [],
    funcs: [1],
    tables: [],
    memories: [],
    globals: [],
    exports: [{ name: "i64_test", desc: @types.ExportDesc::Func(0) }],
    start: None,
    elems: [],
    codes: [func],
    datas: [],
    tags: [tag0],
    func_names: {},
  }
}

///|
test "exception: i64 exception parameter" {
  let mod = create_i64_exception_module()
  let (store, instance) = @executor.instantiate_module(mod)
  let result = @executor.call_exported_func(store, instance, "i64_test", [
    I64(9999999999L),
  ])
  inspect(result[0], content="I64(9999999999)")
}

///|
test "exception: i64 exception with large values" {
  let mod = create_i64_exception_module()
  let (store, instance) = @executor.instantiate_module(mod)
  // Test with max i64
  let result = @executor.call_exported_func(store, instance, "i64_test", [
    I64(9223372036854775807L),
  ])
  inspect(result[0], content="I64(9223372036854775807)")
  // Test with min i64
  let result = @executor.call_exported_func(store, instance, "i64_test", [
    I64(-9223372036854775808L),
  ])
  inspect(result[0], content="I64(-9223372036854775808)")
}

///|
/// Create a module with f64 exception parameter
fn create_f64_exception_module() -> @types.Module {
  // tag $e-f64 (param f64)
  let tag0 : @types.TagType = { type_idx: 0 }
  let tag_type : @types.FuncType = {
    params: [@types.ValueType::F64],
    results: [],
  }
  // Function type: (f64) -> f64
  let func_type : @types.FuncType = {
    params: [@types.ValueType::F64],
    results: [@types.ValueType::F64],
  }
  // Function: f64_test(x) {
  //   block $h (result f64)
  //     try_table (catch $e-f64 $h)
  //       local.get 0
  //       throw $e-f64
  //     end
  //     unreachable
  //   end
  // }
  let func : @types.FunctionCode = {
    locals: [],
    body: [
      Block(@types.BlockType::Value(@types.ValueType::F64), [
        TryTable(@types.BlockType::Empty, [@types.CatchHandler::Catch(0, 0)], [
          LocalGet(0),
          Throw(0),
        ]),
        Unreachable,
      ]),
    ],
  }
  {
    types: [
      @types.SubType::from_func(tag_type),
      @types.SubType::from_func(func_type),
    ],
    type_rec_groups: [0, 1],
    imports: [],
    funcs: [1],
    tables: [],
    memories: [],
    globals: [],
    exports: [{ name: "f64_test", desc: @types.ExportDesc::Func(0) }],
    start: None,
    elems: [],
    codes: [func],
    datas: [],
    tags: [tag0],
    func_names: {},
  }
}

///|
test "exception: f64 exception parameter" {
  let mod = create_f64_exception_module()
  let (store, instance) = @executor.instantiate_module(mod)
  let result = @executor.call_exported_func(store, instance, "f64_test", [
    F64(2.718281828),
  ])
  match result[0] {
    F64(v) => inspect(v > 2.71 && v < 2.72, content="true")
    _ => inspect("wrong type", content="F64")
  }
}
