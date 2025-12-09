// Tests for JIT profiler

///|
test "call counter: basic operations" {
  let counter = CallCounter::new()
  inspect(counter.get_count(0), content="0")
  inspect(counter.total(), content="0")

  // Increment
  let count = counter.increment(0)
  inspect(count, content="1")
  inspect(counter.get_count(0), content="1")
  inspect(counter.total(), content="1")

  // Multiple increments
  counter.increment(0) |> ignore
  counter.increment(0) |> ignore
  inspect(counter.get_count(0), content="3")
  inspect(counter.total(), content="3")
}

///|
test "call counter: multiple functions" {
  let counter = CallCounter::new()
  counter.increment(0) |> ignore
  counter.increment(1) |> ignore
  counter.increment(0) |> ignore
  counter.increment(2) |> ignore
  inspect(counter.get_count(0), content="2")
  inspect(counter.get_count(1), content="1")
  inspect(counter.get_count(2), content="1")
  inspect(counter.unique_functions(), content="3")
  inspect(counter.total(), content="4")
}

///|
test "call counter: reset and clear" {
  let counter = CallCounter::new()
  counter.increment(0) |> ignore
  counter.increment(1) |> ignore
  counter.reset(0)
  inspect(counter.get_count(0), content="0")
  inspect(counter.get_count(1), content="1")
  counter.clear()
  inspect(counter.get_count(0), content="0")
  inspect(counter.get_count(1), content="0")
  inspect(counter.total(), content="0")
}

///|
test "hot threshold: temperature detection" {
  let threshold = HotThreshold::default()
  inspect(get_temperature(0, threshold).to_string(), content="cold")
  inspect(get_temperature(5, threshold).to_string(), content="cold")
  inspect(get_temperature(10, threshold).to_string(), content="warm")
  inspect(get_temperature(50, threshold).to_string(), content="warm")
  inspect(get_temperature(100, threshold).to_string(), content="hot")
  inspect(get_temperature(1000, threshold).to_string(), content="hot")
}

///|
test "profiler: record calls and detect hot" {
  let threshold = HotThreshold::{ warm_threshold: 5, hot_threshold: 10 }
  let profiler = Profiler::new(threshold)

  // Cold function
  for _ in 0..<9 {
    let (_, should_compile) = profiler.record_call(0)
    inspect(should_compile, content="false")
  }

  // 10th call should trigger compilation
  let (count, should_compile) = profiler.record_call(0)
  inspect(count, content="10")
  inspect(should_compile, content="true")

  // Subsequent calls should not re-trigger
  let (_, should_compile2) = profiler.record_call(0)
  inspect(should_compile2, content="false")
}

///|
test "profiler: mark compiled" {
  let threshold = HotThreshold::{ warm_threshold: 5, hot_threshold: 10 }
  let profiler = Profiler::new(threshold)
  inspect(profiler.is_compiled(0), content="false")
  profiler.mark_compiled(0)
  inspect(profiler.is_compiled(0), content="true")
  inspect(profiler.should_use_jit(0), content="true")
}

///|
test "profiler: pending compilation" {
  let threshold = HotThreshold::{ warm_threshold: 5, hot_threshold: 10 }
  let profiler = Profiler::new(threshold)

  // Trigger compilation for function 0
  for _ in 0..<10 {
    profiler.record_call(0) |> ignore
  }
  let pending = profiler.get_pending()
  inspect(pending.length(), content="1")
  inspect(pending[0], content="0")

  // Mark as compiled
  profiler.mark_compiled(0)
  let pending2 = profiler.get_pending()
  inspect(pending2.length(), content="0")
}

///|
test "profiler: stats" {
  let threshold = HotThreshold::{ warm_threshold: 5, hot_threshold: 10 }
  let profiler = Profiler::new(threshold)
  for _ in 0..<15 {
    profiler.record_call(0) |> ignore
  }
  for _ in 0..<5 {
    profiler.record_call(1) |> ignore
  }
  profiler.mark_compiled(0)
  let (total, unique, hot, compiled) = profiler.stats()
  inspect(total, content="20")
  inspect(unique, content="2")
  inspect(hot, content="1")
  inspect(compiled, content="1")
}
