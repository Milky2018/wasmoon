///|
fn workload(kind : String) -> String {
 let instruction = match kind {
  "memory" => "local.get $i i32.const 65535 i32.and local.get $i i32.store8 local.get $i i32.const 65535 i32.and i32.load8_u drop"
  "gc" => "local.get $i struct.new $s struct.get $s 0 drop"
  "exceptions" => "(block $caught (result exnref) (try_table (catch_all_ref $caught) (throw $e)) unreachable) drop"
  _ => abort("invalid workload")
 }
 "(module (memory 2) (type $s (struct (field i32))) (tag $e) (func (export \"run\") (result i32) (local $i i32) (loop $again " + instruction + " local.get $i i32.const 1 i32.add local.tee $i i32.const 1000000 i32.lt_u br_if $again) local.get $i))"
}
///|
fn run() -> Unit raise {
 let kind = @env.args()[1]
 let (store, instance) = @executor.instantiate_module(@wat.parse(workload(kind)))
 defer store.close()
 let start = @perf.instant_now()
 let values = @executor.call_exported_func(store, instance, "run", [])
 store.collect_garbage() |> ignore
 let seconds = @perf.instant_elapsed_as_secs_f64(start)
 assert_eq(values, [I32(1000000)])
 println(seconds)
}
///|
fn main { try run() catch { error => { println(error.to_string()); abort("benchmark failed") } } }
