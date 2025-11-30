// Tests for JIT debug support

// ============ Source Location Tests ============

///|
test "source location: basic" {
  let loc = SourceLocation::new(0, 10)
  inspect(loc.func_idx, content="0")
  inspect(loc.offset, content="10")
  inspect(loc.file, content="None")
  inspect(loc.line, content="None")
}

///|
test "source location: with source" {
  let loc = SourceLocation::with_source(1, 20, "test.wat", 42, 5)
  inspect(loc.func_idx, content="1")
  inspect(loc.offset, content="20")
  inspect(loc.file, content="Some(\"test.wat\")")
  inspect(loc.line, content="Some(42)")
  inspect(loc.column, content="Some(5)")
}

///|
test "source location: to_string" {
  let loc1 = SourceLocation::new(0, 10)
  inspect(loc1.to_string(), content="func 0 @ 10")
  let loc2 = SourceLocation::with_source(1, 20, "test.wat", 42, 5)
  inspect(loc2.to_string(), content="test.wat:42:5 (func 1 @ 20)")
}

// ============ Source Map Tests ============

///|
test "source map: add and get mapping" {
  let sm = SourceMap::new()
  let loc = SourceLocation::with_source(0, 10, "main.wat", 1, 1)
  sm.add_mapping(0, 10, loc)
  match sm.get_location(0, 10) {
    Some(l) => inspect(l.offset, content="10")
    None => panic()
  }
}

///|
test "source map: function names" {
  let sm = SourceMap::new()
  sm.add_func_name(0, "main")
  sm.add_func_name(1, "helper")
  inspect(sm.get_func_name(0), content="main")
  inspect(sm.get_func_name(1), content="helper")
  inspect(sm.get_func_name(2), content="func_2")
}

///|
test "source map: find nearest" {
  let sm = SourceMap::new()
  sm.add_mapping(0, 0, SourceLocation::new(0, 0))
  sm.add_mapping(0, 10, SourceLocation::new(0, 10))
  sm.add_mapping(0, 20, SourceLocation::new(0, 20))

  // Exact match
  match sm.find_nearest(0, 10) {
    Some(l) => inspect(l.offset, content="10")
    None => panic()
  }

  // Between mappings
  match sm.find_nearest(0, 15) {
    Some(l) => inspect(l.offset, content="10")
    None => panic()
  }

  // Before all mappings
  match sm.find_nearest(0, 5) {
    Some(l) => inspect(l.offset, content="0")
    None => panic()
  }
}

///|
test "source map: mapping count" {
  let sm = SourceMap::new()
  inspect(sm.mapping_count(), content="0")
  sm.add_mapping(0, 0, SourceLocation::new(0, 0))
  sm.add_mapping(0, 10, SourceLocation::new(0, 10))
  sm.add_mapping(1, 0, SourceLocation::new(1, 0))
  inspect(sm.mapping_count(), content="3")
}

// ============ Breakpoint Tests ============

///|
test "breakpoint: creation" {
  let bp = Breakpoint::new(1, 0, 10)
  inspect(bp.id, content="1")
  inspect(bp.func_idx, content="0")
  inspect(bp.offset, content="10")
  inspect(bp.enabled, content="true")
  inspect(bp.hit_count, content="0")
}

///|
test "breakpoint: enable disable" {
  let bp = Breakpoint::new(1, 0, 10)
  inspect(bp.enabled, content="true")
  bp.disable()
  inspect(bp.enabled, content="false")
  bp.enable()
  inspect(bp.enabled, content="true")
}

///|
test "breakpoint: hit count" {
  let bp = Breakpoint::new(1, 0, 10)
  bp.hit()
  bp.hit()
  bp.hit()
  inspect(bp.hit_count, content="3")
}

///|
test "breakpoint: conditional" {
  let bp = Breakpoint::with_condition(1, 0, 10, "x > 5")
  inspect(bp.condition, content="Some(\"x > 5\")")
}

// ============ Breakpoint Manager Tests ============

///|
test "breakpoint manager: add" {
  let mgr = BreakpointManager::new()
  let bp = mgr.add(0, 10)
  inspect(bp.id, content="1")
  inspect(mgr.count(), content="1")
}

///|
test "breakpoint manager: remove" {
  let mgr = BreakpointManager::new()
  let bp = mgr.add(0, 10)
  inspect(mgr.count(), content="1")
  let removed = mgr.remove(bp.id)
  inspect(removed, content="true")
  inspect(mgr.count(), content="0")

  // Remove non-existent
  let removed2 = mgr.remove(999)
  inspect(removed2, content="false")
}

///|
test "breakpoint manager: at location" {
  let mgr = BreakpointManager::new()
  let _ = mgr.add(0, 10)
  let _ = mgr.add(0, 20)
  match mgr.at_location(0, 10) {
    Some(bp) => inspect(bp.offset, content="10")
    None => panic()
  }
  match mgr.at_location(0, 15) {
    Some(_) => panic()
    None => ()
  }
}

///|
test "breakpoint manager: should break" {
  let mgr = BreakpointManager::new()
  let bp = mgr.add(0, 10)
  inspect(mgr.should_break(0, 10), content="true")
  inspect(mgr.should_break(0, 20), content="false")
  bp.disable()
  inspect(mgr.should_break(0, 10), content="false")
}

///|
test "breakpoint manager: clear" {
  let mgr = BreakpointManager::new()
  let _ = mgr.add(0, 10)
  let _ = mgr.add(0, 20)
  let _ = mgr.add(1, 0)
  inspect(mgr.count(), content="3")
  mgr.clear()
  inspect(mgr.count(), content="0")
}

// ============ Stack Frame Tests ============

///|
test "stack frame: basic" {
  let frame = StackFrame::new(0, 5, 100, "my_func")
  inspect(frame.index, content="0")
  inspect(frame.func_idx, content="5")
  inspect(frame.ip, content="100")
  inspect(frame.func_name, content="my_func")
}

///|
test "stack frame: with location" {
  let loc = SourceLocation::with_source(5, 100, "test.wat", 10, 1)
  let frame = StackFrame::with_location(0, 5, 100, "my_func", loc)
  match frame.location {
    Some(l) => inspect(l.line, content="Some(10)")
    None => panic()
  }
}

///|
test "stack frame: to_string" {
  let frame = StackFrame::new(0, 5, 100, "my_func")
  inspect(frame.to_string(), content="#0 my_func (ip=100)")
}

// ============ Stack Trace Tests ============

///|
test "stack trace: empty" {
  let trace = StackTrace::new()
  inspect(trace.depth(), content="0")
}

///|
test "stack trace: push frames" {
  let trace = StackTrace::new()
  trace.push_frame(StackFrame::new(0, 0, 10, "main"))
  trace.push_frame(StackFrame::new(1, 1, 20, "helper"))
  inspect(trace.depth(), content="2")
}

///|
test "stack trace: with error" {
  let trace = StackTrace::with_error("divide by zero")
  trace.push_frame(StackFrame::new(0, 0, 10, "divide"))
  match trace.error {
    Some(e) => inspect(e, content="divide by zero")
    None => panic()
  }
}

// ============ Debug Context Tests ============

///|
test "debug context: creation" {
  let ctx = DebugContext::new()
  inspect(ctx.enabled, content="false")
  inspect(ctx.breakpoints.count(), content="0")
}

///|
test "debug context: enable disable" {
  let ctx = DebugContext::new()
  ctx.enable()
  inspect(ctx.enabled, content="true")
  ctx.disable()
  inspect(ctx.enabled, content="false")
}

///|
test "debug context: should pause on breakpoint" {
  let ctx = DebugContext::new()
  ctx.enable()
  let _ = ctx.breakpoints.add(0, 10)
  inspect(ctx.should_pause(0, 10), content="true")
  inspect(ctx.should_pause(0, 20), content="false")
}

///|
test "debug context: step into" {
  let ctx = DebugContext::new()
  ctx.enable()
  ctx.set_step_mode(StepInto)

  // Should pause on every instruction in step mode
  inspect(ctx.should_pause(0, 0), content="true")
  inspect(ctx.should_pause(0, 10), content="true")
}

///|
test "debug context: on pause records hit" {
  let ctx = DebugContext::new()
  ctx.enable()
  let bp = ctx.breakpoints.add(0, 10)
  ctx.on_pause(0, 10)
  inspect(bp.hit_count, content="1")
}

///|
test "debug context: location string" {
  let ctx = DebugContext::new()
  ctx.source_map.add_func_name(0, "main")
  ctx.source_map.add_mapping(
    0,
    10,
    SourceLocation::with_source(0, 10, "test.wat", 5, 1),
  )
  let s = ctx.location_string(0, 10)
  inspect(s.contains("main"), content="true")
  inspect(s.contains("test.wat"), content="true")
}

///|
test "debug context: show" {
  let ctx = DebugContext::new()
  let _ = ctx.breakpoints.add(0, 10)
  ctx.source_map.add_mapping(0, 10, SourceLocation::new(0, 10))
  let s = ctx.to_string()
  inspect(s.contains("breakpoints=1"), content="true")
  inspect(s.contains("mappings=1"), content="true")
}

// ============ Step Mode Tests ============

///|
test "step mode: to_string" {
  inspect(StepMode::Continue.to_string(), content="continue")
  inspect(StepMode::StepInto.to_string(), content="step_into")
  inspect(StepMode::StepOver.to_string(), content="step_over")
  inspect(StepMode::StepOut.to_string(), content="step_out")
}
