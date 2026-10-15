///|
test "validation evidence owns section snapshots and immutable syntax values" {
  let body : Array[@types.Instruction] = [I32Const(11)]
  let module_ = @types.Module::simple(
    [],
    [I32],
    [Block(Value(I32), ReadOnlyArray::from_array(body))],
    "f",
  )
  let validated = @validator.ValidatedModule::new(module_)
  body[0] = Unreachable
  module_.funcs[0] = -1
  module_.types.clear()
  let snapshot = validated.snapshot()
  snapshot.funcs[0] = 99
  snapshot.codes.clear()
  let fresh = validated.snapshot()
  inspect(fresh.funcs[0], content="0")
  assert_true(fresh.codes[0].body[:] is [Block(Value(I32), [I32Const(11)])])
  @validator.validate_module(fresh)
}

///|
test "raw unsigned indices and fixed SIMD shapes cannot escape validation" {
  let instructions : Array[@types.Instruction] = [
    LocalGet(-1),
    LocalSet(-1),
    LocalTee(-1),
    GlobalGet(-1),
    GlobalSet(-1),
    Call(-1),
    ReturnCall(-1),
    RefFunc(-1),
    Br(-1),
    BrIf(-1),
    BrTable([-1], 0),
    BrTable([], -1),
    MemorySize(-1),
    MemoryGrow(-1),
    MemoryFill(-1),
    MemoryCopy(-1, 0),
    MemoryCopy(0, -1),
    MemoryInit(-1, 0),
    DataDrop(-1),
    TableGet(-1),
    TableSet(-1),
    TableSize(-1),
    TableGrow(-1),
    TableFill(-1),
    TableCopy(-1, 0),
    TableCopy(0, -1),
    TableInit(-1, 0),
    ElemDrop(-1),
    I32Load(0, -1, 0L),
    V128Load(0, -1, 0L),
    V128Const(b""),
    I8x16Shuffle([]),
    I8x16Shuffle([-1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]),
    I8x16ExtractLaneS(-1),
    V128Load8Lane(0, 0, 0L, -1),
  ]
  for instruction in instructions {
    let module_ = @types.Module::simple([], [], [Unreachable, instruction], "f")
    module_.memories.push({
      limits: { min: 0L, max: None, },
      is_memory64: false,
      is_shared: false,
      page_size_log2: 16,
    })
    for contextual in [false, true] {
      let rejected = try {
        if contextual {
          @validator.validate_module_with_context(module_)
        } else {
          @validator.validate_module(module_)
        }
        false
      } catch {
        _ => true
      }
      assert_true(rejected, msg="accepted invalid immediate: \{instruction}")
    }
  }
}

///|
test "raw type indices must name the declared reference and import kinds" {
  let base = @types.Module::simple([], [], [], "f")
  base.types.push(@types.SubType::simple(Struct({ fields: [], })))
  base.type_rec_groups.push(1)
  let import_ = base.snapshot()
  import_.imports.push({ mod_name: "host", name: "bad", desc: Func(1), })
  let local_module = base.snapshot()
  local_module.codes[0] = { locals: [RefNullFuncTyped(1)], body: [], }
  let global = base.snapshot()
  global.imports.push({
    mod_name: "host",
    name: "bad",
    desc: Global({ value_type: RefNullFuncTyped(1), mutable: false, }),
  })
  for module_ in [import_, local_module, global] {
    for contextual in [false, true] {
      let rejected = try {
        if contextual {
          @validator.validate_module_with_context(module_)
        } else {
          @validator.validate_module(module_)
        }
        false
      } catch {
        _ => true
      }
      assert_true(rejected)
    }
  }
}

///|
test "raw type graphs and passive data sentinels must be representable Wasm" {
  let root = { ..@types.SubType::func([], []), final_: false, }
  let self_parent = @types.Module::empty()
  self_parent.types.push({ ..root, supertypes: [0], })
  let forward_parent = @types.Module::empty()
  forward_parent.types.append([{ ..root, supertypes: [1], }, root])
  forward_parent.type_rec_groups.append([0, 0])
  let multiple_parents = @types.Module::empty()
  multiple_parents.types.append([root, { ..root, supertypes: [0, 0], }])
  let split_group = @types.Module::empty()
  split_group.types.append([root, root, root])
  split_group.type_rec_groups.append([0, 1, 0])
  let negative_group = @types.Module::empty()
  negative_group.types.push(root)
  negative_group.type_rec_groups.push(-1)
  let passive = @types.Module::empty()
  passive.datas.push({ memory_idx: -2, offset: [], init: b"", })
  for
    module_ in [
      self_parent, forward_parent, multiple_parents, split_group, negative_group,
      passive,
    ] {
    for contextual in [false, true] {
      let rejected = try {
        if contextual {
          @validator.validate_module_with_context(module_)
        } else {
          @validator.validate_module(module_)
        }
        false
      } catch {
        _ => true
      }
      assert_true(rejected)
    }
  }
}
