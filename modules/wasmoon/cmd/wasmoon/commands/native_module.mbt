///|
/// Compile and bind a native module before it can be called or exported.
fn compile_native_module_context(
  mod_ : @types.Module,
  instance : @runtime.ModuleInstance,
  store : @runtime.Store,
  opt_level : Int32,
  on_loaded : (Int32) -> Unit,
  classify_suspension : (@runtime.RuntimeError) -> Bool,
) -> Result[@core_jit.JITModuleContext, String] {
  let lowered_mod = rewrite_module_alias_indices_for_jit(mod_, instance)
  let local_compile_mask = build_export_compile_mask(lowered_mod)
  let compiled_local_funcs = match local_compile_mask {
    Some(mask) => count_true(mask)
    None => lowered_mod.codes.length()
  }
  // Get actual memory max from the store (for imported memories)
  // This is crucial for memory.grow to enforce the correct max limit
  let actual_memory_max : Int32? = if instance.mem_addrs.length() > 0 {
    let mem = store.get_mem(instance.mem_addrs[0]) catch {
      _ => return Err("JIT strict mode: memory not found")
    }
    let (_, max) = mem.get_limits()
    max
  } else {
    None
  }
  // Compile module to JIT
  let mut compile_failure : String? = None
  let compiled = compile_module_to_jit(
    lowered_mod,
    false,
    false,
    actual_memory_max~,
    opt_level,
    false,
    on_progress=fn(event) {
      if event.stage is Failed {
        compile_failure = event.message
      }
      None
    },
    local_compile_mask~,
    force_subtype_indirect_check=Some(true),
    nan_canonicalization=store.nan_canonicalization,
    enable_cancellation=true,
    stack_switching=true,
  )
  match compiled {
    None =>
      return Err(
        "JIT strict mode: compile_module_to_jit failed: \{compile_failure.unwrap_or("unknown compilation error")}",
      )
    Some((artifact, _)) => {
      // Build func_signatures array for JIT module
      let func_signatures = @core_jit.build_func_signatures(lowered_mod)
      let external_imports = @core_jit.build_external_imports_for_jit(
        lowered_mod, instance, store,
      )
      // Load JIT module
      let loaded = verify_compiled_jit_artifact(artifact) catch {
        err =>
          return Err(
            "JIT strict mode: artifact verification failed: \{Repr(err)}",
          )
      }
      let jit_module_result : Result[@jit.JITModule, @jit.JITModuleLoadError] = try
        @jit.JITModule::load_artifact_with_imports(
          loaded,
          func_signatures,
          external_imports,
          function_names=build_jit_function_names(lowered_mod),
          resource_budget=store.resource_budget,
        )
      catch {
        e => Err(e)
      } noraise {
        jm => Ok(jm)
      }
      match jit_module_result {
        Err(err) =>
          return Err("JIT strict mode: failed to create JIT module: \{err}")
        Ok(jm) => {
          on_loaded(compiled_local_funcs)
          @core_jit.register_instance_funcrefs_for_jit(jm, instance, store) catch {
            error => {
              jm.close()
              return Err("JIT instance binding failed: \{error}")
            }
          }
          // Allocate independent WASM stack with guard page. Native JIT
          // execution and hostcall bridges use this stack, so keep it aligned
          // with `wasmoon run`.
          if !jm.configure_native_fiber_stack_size(16L * 1024L * 1024L) {
            jm.close()
            return Err("JIT native fiber stack configuration failed")
          }
          // Initialize all memories (multi-memory support)
          let _ = @core_jit.init_jit_memories_from_store(instance, store, jm) catch {
            error =>
              return Err(
                "JIT strict mode: memory initialization failed: \{error}",
              )
          }
          // Initialize globals (pass jm for tagged funcref pointers)
          let globals_ptr = @core_jit.init_jit_globals_from_store(
            instance, store, jm,
          ) catch {
            error => return Err("JIT reference transfer failed: \{error}")
          }
          // Linked modules may use different type-index spaces.
          let use_subtype_indirect_check = true
          // Initialize indirect table for call_indirect
          @core_jit.bind_instance_tables(instance, store, jm) catch {
            error => return Err("JIT table preparation failed: \{error}")
          }
          // Initialize per-context data/elem segments for bulk ops (memory.init/table.init/etc).
          @core_jit.init_bulk_segments(lowered_mod, jm, instance, store) catch {
            error => return Err("JIT reference transfer failed: \{error}")
          }
          let jit_ctx = @core_jit.JITModuleContext(
            jm,
            globals_ptr,
            instance.global_addrs,
            instance.table_addrs,
            instance.func_addrs,
            instance.func_type_indices,
            instance.canonical_type_indices,
            lowered_mod.types,
            lowered_mod.type_rec_groups,
            use_subtype_indirect_check,
          )
          jit_ctx.install_hostcall_dispatcher(
            store,
            instance,
            classify_suspension~,
          ) catch {
            error => {
              jit_ctx.close()
              return Err("JIT instance binding failed: \{error}")
            }
          }
          Ok(jit_ctx)
        }
      }
    }
  }
}
