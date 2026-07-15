// PROTOTYPE ONLY: terminal shell for inspecting the generic Target VCode sketch.

///|
priv enum Screen {
  Overview
  AArch64
  AMD64
  Projection
}

///|
priv enum Action {
  ShowOverview
  ShowAArch64
  ShowAMD64
  ShowProjection
  Quit
  Ignore
}

///|
priv struct PrototypeState {
  screen : Screen
}

///|
fn initial_state() -> PrototypeState {
  { screen: Overview }
}

///|
fn reduce(state : PrototypeState, action : Action) -> PrototypeState {
  match action {
    ShowOverview => { screen: Overview }
    ShowAArch64 => { screen: AArch64 }
    ShowAMD64 => { screen: AMD64 }
    ShowProjection => { screen: Projection }
    Quit | Ignore => state
  }
}

///|
fn parse_action(input : Int) -> Action {
  match input {
    111 => ShowOverview
    97 => ShowAArch64
    120 => ShowAMD64
    112 => ShowProjection
    113 | -1 => Quit
    _ => Ignore
  }
}

///|
fn render(state : PrototypeState) -> Unit {
  println("\u{001b}[2J\u{001b}[H")
  println("\u{001b}[1mTarget VCode shell prototype\u{001b}[0m")
  println(
    "\u{001b}[2mPROTOTYPE ONLY — not production compiler code\u{001b}[0m",
  )
  println("")
  match state.screen {
    Overview => {
      println("\u{001b}[1mCurrent state: overview\u{001b}[0m")
      println("VCodeFunction[Inst] and VCodeBlock[Inst] own shared CFG shape.")
      println("AArch64Inst and AMD64Inst are unrelated closed types.")
      println(
        "AllocatableInst projects either type into the same regalloc view.",
      )
      println("")
      println("Rejected by the type checker:")
      println(
        "  VCodeFunction[AArch64Inst] cannot contain AMD64Inst::SetParity.",
      )
    }
    AArch64 => {
      println("\u{001b}[1mCurrent state: VCodeFunction[AArch64Inst]\u{001b}[0m")
      println(render_function(aarch64_demo()))
    }
    AMD64 => {
      println("\u{001b}[1mCurrent state: VCodeFunction[AMD64Inst]\u{001b}[0m")
      println(render_function(amd64_demo()))
    }
    Projection => {
      println("\u{001b}[1mCurrent state: shared regalloc projection\u{001b}[0m")
      println(render_regalloc_view("aarch64", project_regalloc(aarch64_demo())))
      println(render_regalloc_view("amd64", project_regalloc(amd64_demo())))
    }
  }
  println(
    "\u{001b}[1mo\u{001b}[0m overview  \u{001b}[1ma\u{001b}[0m AArch64  \u{001b}[1mx\u{001b}[0m AMD64  \u{001b}[1mp\u{001b}[0m projection  \u{001b}[1mq\u{001b}[0m quit",
  )
  println("> ")
}

///|
extern "c" fn read_key() -> Int = "target_vcode_prototype_read_key"

///|
fn main {
  let mut state = initial_state()
  for ;; {
    render(state)
    let action = parse_action(read_key())
    if action is Quit {
      return
    }
    state = reduce(state, action)
  }
}
