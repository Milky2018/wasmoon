///|
fn remap_component_index(index : Int, aliases : Map[Int, Int]) -> Int {
  aliases.get(index).unwrap_or(index)
}

///|
fn component_alias_map(addresses : Array[Int]) -> Map[Int, Int] {
  let first_by_address : Map[Int, Int] = Map([])
  let aliases : Map[Int, Int] = Map([])
  for index, address in addresses {
    match first_by_address.get(address) {
      Some(first) => if first != index { aliases[index] = first }
      None => first_by_address[address] = index
    }
  }
  aliases
}

///|
fn rewrite_component_instr_indices(
  instructions : Array[@types.Instruction],
  global_aliases : Map[Int, Int],
  tag_aliases : Map[Int, Int],
) -> Array[@types.Instruction] {
  let rewritten : Array[@types.Instruction] = []
  for instruction in instructions {
    match instruction {
      GlobalGet(index) =>
        rewritten.push(GlobalGet(remap_component_index(index, global_aliases)))
      GlobalSet(index) =>
        rewritten.push(GlobalSet(remap_component_index(index, global_aliases)))
      Throw(index) =>
        rewritten.push(Throw(remap_component_index(index, tag_aliases)))
      TryTable(block_type, handlers, body) => {
        let rewritten_handlers : Array[@types.CatchHandler] = []
        for handler in handlers {
          rewritten_handlers.push(
            match handler {
              Catch(tag_index, label_index) =>
                Catch(
                  remap_component_index(tag_index, tag_aliases),
                  label_index,
                )
              CatchRef(tag_index, label_index) =>
                CatchRef(
                  remap_component_index(tag_index, tag_aliases),
                  label_index,
                )
              CatchAll(label_index) => CatchAll(label_index)
              CatchAllRef(label_index) => CatchAllRef(label_index)
            },
          )
        }
        rewritten.push(
          TryTable(
            block_type,
            rewritten_handlers,
            rewrite_component_instr_indices(body, global_aliases, tag_aliases),
          ),
        )
      }
      Block(block_type, body) =>
        rewritten.push(
          Block(
            block_type,
            rewrite_component_instr_indices(body, global_aliases, tag_aliases),
          ),
        )
      Loop(block_type, body) =>
        rewritten.push(
          Loop(
            block_type,
            rewrite_component_instr_indices(body, global_aliases, tag_aliases),
          ),
        )
      If(block_type, then_body, else_body) =>
        rewritten.push(
          If(
            block_type,
            rewrite_component_instr_indices(
              then_body, global_aliases, tag_aliases,
            ),
            rewrite_component_instr_indices(
              else_body, global_aliases, tag_aliases,
            ),
          ),
        )
      _ => rewritten.push(instruction)
    }
  }
  rewritten
}

///|
fn rewrite_component_alias_indices(
  module_ : @types.Module,
  instance : @runtime.ModuleInstance,
) -> @types.Module {
  let global_aliases = component_alias_map(instance.global_addrs)
  let tag_aliases = component_alias_map(instance.tag_addrs)
  if global_aliases.is_empty() && tag_aliases.is_empty() {
    return module_
  }
  let codes : Array[@types.FunctionCode] = []
  for code in module_.codes {
    codes.push({
      locals: code.locals,
      body: rewrite_component_instr_indices(
        code.body,
        global_aliases,
        tag_aliases,
      ),
    })
  }
  let globals : Array[@types.Global] = []
  for global in module_.globals {
    globals.push({
      type_: global.type_,
      init: rewrite_component_instr_indices(
        global.init,
        global_aliases,
        tag_aliases,
      ),
    })
  }
  let elements : Array[@types.Element] = []
  for element in module_.elems {
    let mode = match element.mode {
      Active(table_index, offset) =>
        @types.ElemMode::Active(
          table_index,
          rewrite_component_instr_indices(offset, global_aliases, tag_aliases),
        )
      Passive => Passive
      Declarative => Declarative
    }
    elements.push({
      mode,
      type_: element.type_,
      init: element.init.map(fn(expr) {
        rewrite_component_instr_indices(expr, global_aliases, tag_aliases)
      }),
    })
  }
  let data : Array[@types.Data] = []
  for segment in module_.datas {
    data.push({
      memory_idx: segment.memory_idx,
      offset: rewrite_component_instr_indices(
        segment.offset,
        global_aliases,
        tag_aliases,
      ),
      init: segment.init,
    })
  }
  {
    types: module_.types,
    type_rec_groups: module_.type_rec_groups,
    imports: module_.imports,
    funcs: module_.funcs,
    tables: module_.tables,
    memories: module_.memories,
    globals,
    exports: module_.exports,
    start: module_.start,
    elems: elements,
    codes,
    datas: data,
    tags: module_.tags,
    func_names: module_.func_names,
  }
}

///|
fn component_function_name(module_ : @types.Module, index : Int) -> String {
  for export_ in module_.exports {
    if export_.desc is Func(exported) && exported == index {
      return export_.name
    }
  }
  "func_\{index}"
}

///|
fn component_artifact_optimization_level(
  level : Int,
) -> @artifact.OptimizationLevel {
  match level {
    0 => O0
    1 => O1
    2 => O2
    _ => O3
  }
}

///|
fn append_component_i64(bytes : Array[Byte], value : Int64) -> Unit {
  for shift in 0..<8 {
    bytes.push((value >> (shift * 8)).to_byte())
  }
}

///|
fn component_semantic_features(actual_memory_max : Int?) -> Bytes {
  let bytes : Array[Byte] = [1, 1]
  match actual_memory_max {
    Some(max) => {
      bytes.push(1)
      append_component_i64(bytes, max.to_int64())
    }
    None => bytes.push(0)
  }
  Bytes::from_array(bytes)
}

///|
fn encoded_component_module(module_ : @types.Module) -> Bytes {
  Bytes::from_array(
    @encoder.encode(module_).map(fn(value) { (value & 0xFF).to_byte() }),
  )
}

///|
fn compile_component_artifact(
  module_ : @types.Module,
  target : @wasmoon_jit.NativeTarget,
  actual_memory_max : Int?,
  opt_level : Int,
) -> @artifact.Artifact raise @runtime_impl.ComponentRuntimeError {
  @validator.validate_module(module_) catch {
    error =>
      raise NativeCompilationFailed("core module validation failed: \{error}")
  }
  let canonical_type_indices = @types.compute_canonical_type_indices(
    module_.types,
    type_rec_groups=module_.type_rec_groups,
  )
  let translation_context = @wasm_frontend.translation_context_from_module(
    module_,
    @wasmoon.wasm_frontend_embedding_environment(),
    memory_max_override=actual_memory_max,
  )
  let validation_context = @wasm_frontend.wasm_validation_context(
    translation_context,
  )
  let imports : Array[@artifact.ImportIdentity] = []
  let mut imported_function_index = 0
  for import_ in module_.imports {
    if import_.desc is Func(type_index) {
      imports.push(
        @wasmoon_jit.wasm_import_identity(
          imported_function_index,
          import_.mod_name,
          import_.name,
          module_.get_func_type(type_index),
        ),
      )
      imported_function_index = imported_function_index + 1
    }
  }
  let functions : Array[@artifact.FunctionCode] = []
  for local_index, code in module_.codes {
    let function_index = imported_function_index + local_index
    let function_type = module_.get_func_type(module_.funcs[local_index])
    let milkir = @wasm_frontend.translate_function_body(
      translation_context,
      component_function_name(module_, function_index),
      function_type,
      code.locals,
      code.body,
    )
    @milkir.optimize_with_level(milkir, @milkir.OptLevel::from_int(opt_level))
    |> ignore
    let compiled = @wasmoon_jit.compile_wasm_body_artifact_function(
      milkir,
      validation_context,
      target,
      function_index~,
      signature=@wasmoon_jit.wasm_function_signature(function_type),
      use_subtype_indirect_check=true,
      canonical_type_indices~,
    ) catch {
      error =>
        raise NativeCompilationFailed(
          "core function \{function_index} compilation failed: \{error}",
        )
    }
    functions.push(compiled)
  }
  let policy : @artifact.CompilationPolicy = {
    optimization_level: component_artifact_optimization_level(opt_level),
    code_model: Small,
    call_binding: DirectBody,
    cancellation_safepoints: false,
    debug_info: false,
  }
  let manifest = @wasmoon_jit.build_host_artifact_manifest(
    module_identity=@wasmoon_jit.artifact_module_identity(
      "component-core-module",
      encoded_component_module(module_),
      component_semantic_features(actual_memory_max),
    ),
    policy~,
  ) catch {
    error => raise NativeCompilationFailed("artifact manifest failed: \{error}")
  }
  { manifest, imports, functions }
}

///|
fn load_component_jit_context(
  module_ : @types.Module,
  instance : @runtime.ModuleInstance,
  store : @runtime.Store,
  target : @wasmoon_jit.NativeTarget,
  opt_level : Int,
  classify_suspension : (@runtime.RuntimeError) -> Bool,
) -> @wast.JITModuleContext raise @runtime_impl.ComponentRuntimeError {
  let lowered_module = rewrite_component_alias_indices(module_, instance)
  let actual_memory_max = if instance.mem_addrs.length() > 0 {
    let memory = store.get_mem(instance.mem_addrs[0]) catch {
      error =>
        raise NativeCompilationFailed(
          "cannot inspect component memory limits: \{error}",
        )
    }
    memory.get_limits().1
  } else {
    None
  }
  let artifact = compile_component_artifact(
    lowered_module, target, actual_memory_max, opt_level,
  )
  let compatibility = @wasmoon_jit.artifact_compatibility(
    artifact.manifest,
    available_cpu_features=[],
    runtime_symbols=@wasmoon_jit.wasmoon_runtime_external_symbols(),
    data_symbols=[],
  )
  let loaded = @wasmoon_jit.verify_artifact(artifact, compatibility) catch {
    error =>
      raise NativeCompilationFailed(
        "compiled artifact verification failed: \{Repr(error)}",
      )
  }
  let jit_module = @jit.JITModule::load_artifact_with_imports(
    loaded,
    @wast.build_func_signatures(lowered_module),
    @wast.build_external_imports_for_jit(lowered_module, instance, store),
    function_names=Array::makei(
      @wast.count_func_imports(lowered_module.imports) +
      lowered_module.funcs.length(),
      fn(index) { component_function_name(lowered_module, index) },
    ),
  ) catch {
    error =>
      raise NativeCompilationFailed("artifact installation failed: \{error}")
  }
  @wast.register_instance_funcrefs_for_jit(jit_module, instance)
  jit_module.alloc_wasm_stack(16L * 1024L * 1024L) |> ignore
  guard @wast.init_jit_memories_from_store(instance, store, jit_module)
    is Some(_) else {
    jit_module.close()
    raise NativeCompilationFailed(
      "failed to initialize component core memories",
    )
  }
  let globals_pointer = @wast.init_jit_globals_from_store(
    instance, store, jit_module,
  )
  @wast.init_elem_segments(
    lowered_module,
    jit_module,
    instance,
    store,
    use_subtype_indirect_check=true,
  )
  @wast.init_bulk_segments(
    lowered_module,
    jit_module,
    instance,
    store,
    use_subtype_indirect_check=true,
  ) catch {
    error => {
      jit_module.close()
      raise NativeCompilationFailed(
        "failed to initialize component core segments: \{error}",
      )
    }
  }
  @wast.sync_tables_to_jit(
    instance,
    store,
    jit_module,
    use_subtype_indirect_check=true,
  )
  let context = @wast.JITModuleContext(
    jit_module,
    globals_pointer,
    instance.global_addrs.copy(),
    instance.table_addrs.copy(),
    instance.func_addrs.copy(),
    instance.func_type_indices.copy(),
    instance.canonical_type_indices.copy(),
    lowered_module.types.copy(),
    lowered_module.type_rec_groups.copy(),
    true,
  )
  @wast.install_jit_hostcall_dispatcher(
    jit_module,
    store,
    instance,
    before_dispatch=fn() {
      @wast.sync_jit_globals_to_store(context, store)
      @wast.sync_jit_tables_to_store(context, store)
    },
    after_dispatch=fn() {
      @wast.sync_store_globals_to_jit(context, store)
      @wast.sync_tables_to_jit(
        instance,
        store,
        jit_module,
        use_subtype_indirect_check=true,
      )
    },
    classify_suspension~,
  )
  context
}
