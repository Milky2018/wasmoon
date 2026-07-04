// Tests for JIT compilation strategy

///|
test "compilation request: creation" {
  let req = CompilationRequest::new(0, Baseline)
  inspect(req.func_idx, content="0")
  inspect(req.priority, content="0")
  let req2 = CompilationRequest::with_priority(1, Optimized, 100)
  inspect(req2.func_idx, content="1")
  inspect(req2.priority, content="100")
}

///|
test "compilation queue: basic operations" {
  let queue = CompilationQueue::new(0) // Unlimited
  inspect(queue.is_empty(), content="true")
  inspect(queue.length(), content="0")
  let req1 = CompilationRequest::new(0, Baseline)
  let added = queue.enqueue(req1)
  inspect(added, content="true")
  inspect(queue.length(), content="1")
  inspect(queue.is_empty(), content="false")
}

///|
test "compilation queue: priority ordering" {
  let queue = CompilationQueue::new(0)
  queue.enqueue(CompilationRequest::with_priority(0, Baseline, 10)) |> ignore
  queue.enqueue(CompilationRequest::with_priority(1, Baseline, 50)) |> ignore
  queue.enqueue(CompilationRequest::with_priority(2, Baseline, 30)) |> ignore

  // Should dequeue in priority order: 1, 2, 0
  match queue.dequeue() {
    Some(req) => inspect(req.func_idx, content="1")
    None => panic()
  }
  match queue.dequeue() {
    Some(req) => inspect(req.func_idx, content="2")
    None => panic()
  }
  match queue.dequeue() {
    Some(req) => inspect(req.func_idx, content="0")
    None => panic()
  }
  inspect(queue.is_empty(), content="true")
}

///|
test "compilation queue: no duplicates" {
  let queue = CompilationQueue::new(0)
  queue.enqueue(CompilationRequest::new(0, Baseline)) |> ignore
  let added = queue.enqueue(CompilationRequest::new(0, Optimized))
  inspect(added, content="false")
  inspect(queue.length(), content="1")
}

///|
test "compilation queue: size limit" {
  let queue = CompilationQueue::new(2)
  queue.enqueue(CompilationRequest::new(0, Baseline)) |> ignore
  queue.enqueue(CompilationRequest::new(1, Baseline)) |> ignore
  let added = queue.enqueue(CompilationRequest::new(2, Baseline))
  inspect(added, content="false")
  inspect(queue.length(), content="2")
}

///|
test "compilation queue: contains" {
  let queue = CompilationQueue::new(0)
  queue.enqueue(CompilationRequest::new(5, Baseline)) |> ignore
  inspect(queue.contains(5), content="true")
  inspect(queue.contains(6), content="false")
}

///|
test "compilation queue: clear" {
  let queue = CompilationQueue::new(0)
  queue.enqueue(CompilationRequest::new(0, Baseline)) |> ignore
  queue.enqueue(CompilationRequest::new(1, Baseline)) |> ignore
  queue.clear()
  inspect(queue.is_empty(), content="true")
}

///|
test "tiered config: presets" {
  let def = TieredConfig::default()
  inspect(def.baseline_threshold, content="100")
  inspect(def.optimize_threshold, content="10000")
  let eager = TieredConfig::eager()
  inspect(eager.baseline_threshold, content="10")
  let deferred = TieredConfig::deferred()
  inspect(deferred.baseline_threshold, content="1000")
}

///|
test "compilation strategy: interpret cold functions" {
  let strategy = CompilationStrategy::new(TieredConfig::default())

  // First few calls should interpret
  for _ in 0..<10 {
    let decision = strategy.decide(0)
    match decision {
      Interpret => ()
      _ => panic()
    }
  }
}

///|
test "compilation strategy: compile hot functions" {
  let config = TieredConfig::{
    baseline_threshold: 10,
    optimize_threshold: 100,
    synchronous: true,
    max_concurrent: 1,
  }
  let strategy = CompilationStrategy::new(config)

  // Call up to threshold - 1
  for _ in 0..<9 {
    strategy.decide(0) |> ignore
  }

  // 10th call should trigger compilation
  let decision = strategy.decide(0)
  match decision {
    CompileAndExecute(Baseline) => ()
    _ => panic()
  }
}

///|
test "compilation strategy: mark compiled" {
  let strategy = CompilationStrategy::new(TieredConfig::default())
  inspect(strategy.is_compiled(0), content="false")
  strategy.mark_compiled(0)
  inspect(strategy.is_compiled(0), content="true")

  // Subsequent calls should use compiled code
  let decision = strategy.decide(0)
  match decision {
    ExecuteCompiled => ()
    _ => panic()
  }
}

///|
test "compilation strategy: schedule and retrieve" {
  let strategy = CompilationStrategy::new(TieredConfig::default())
  let scheduled = strategy.schedule_compilation(0, Baseline)
  inspect(scheduled, content="true")
  match strategy.next_to_compile() {
    Some(req) => inspect(req.func_idx, content="0")
    None => panic()
  }
}

///|
test "compilation strategy: stats" {
  let config = TieredConfig::{
    baseline_threshold: 5,
    optimize_threshold: 50,
    synchronous: true,
    max_concurrent: 1,
  }
  let strategy = CompilationStrategy::new(config)

  // Make some calls
  for _ in 0..<10 {
    strategy.decide(0) |> ignore
  }
  let (total, interp, compiled_calls, compilations, queue, hot) = strategy.stats()
  inspect(total, content="10")
  inspect(interp, content="9") // 9 interpreted
  inspect(compiled_calls, content="0") // Not yet executed as compiled
  inspect(compilations, content="0") // Not marked as compiled yet
  inspect(queue, content="0") // Not scheduled
  inspect(hot, content="1") // 1 hot function
}

///|
test "compilation mode: show" {
  inspect(CompilationMode::Baseline.to_string(), content="baseline")
  inspect(CompilationMode::Optimized.to_string(), content="optimized")
}

///|
test "compilation decision: show" {
  inspect(CompilationDecision::Interpret.to_string(), content="interpret")
  inspect(
    CompilationDecision::ExecuteCompiled.to_string(),
    content="execute_compiled",
  )
  inspect(
    CompilationDecision::CompileAndExecute(Baseline).to_string(),
    content="compile_and_execute(baseline)",
  )
}
