fn main raise {
  let args = @env.args()
  let bad = args.length() > 1 && args[1] == "invalid"
  let plain = args.length() > 1 && args[1] == "plain"
  let memory_limit = args.length() > 1 && args[1] == "memory-limit"
  let text = if bad {
    "(module (type (func)) (func (type 99)))"
  } else if memory_limit {
    "(module (memory i64 281474976710656))"
  } else if plain {
    "(module (type $s (struct (field i32))) (func (export \"run\") (drop (struct.new $s (i32.const 1)))))"
  } else {
    "(module (type $s (struct (field i32))) (func (export \"run\") (drop (extern.convert_any (struct.new $s (i32.const 1))))))"
  }
  let mod_ = @wat.parse(text)
  @validator.validate_module(mod_) catch { error => println("validation_rejected=" + error.to_string()) } noraise { _ => println("validation_accepted=true") }
  let (store, instance) = @executor.instantiate_module_with_init(mod_) catch { error => { println("structured_instantiation_error=" + error.to_string()); return } }
  defer store.close()
  if !bad {
    for _ in 0..<1000 {
      @executor.call_exported_func(store, instance, "run", []) |> ignore
    }
    println("wrapped=" + store.wrapped_externs.length().to_string())
    println("roots=" + store.collect_roots([]).length().to_string())
    println("collected=" + store.collect_garbage().to_string())
    println("live_after_gc=" + store.heap.stats().live_objects.to_string())
  }
}
