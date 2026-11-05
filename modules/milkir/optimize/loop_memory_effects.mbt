///|
priv struct LoopMemoryEffects {
  mut invalidates_addresses : Bool
  mut writes_all : Bool
  mut writes_for_unknown_reads : Bool
  writes : @hashset.HashSet[@milkir.AliasRegion]
}

///|
priv struct LoopMemoryFacts {
  pointers : Array[@milkir.AliasRegion?]
  readable : Array[Bool]
  mut effects : LoopMemoryEffects?
}

///|
fn LoopMemoryFacts::new(function : @milkir.Function) -> LoopMemoryFacts {
  let (pointers, readable) = @analysis.loop_pointer_facts(function)
  { pointers, readable, effects: None, }
}

///|
/// Loop placement can move pure instructions and verified reads. Neither
/// changes this write/epoch summary. A new guard or a different loop gets a
/// new snapshot.
fn LoopMemoryFacts::effects_in_loop(
  self : LoopMemoryFacts,
  function : @milkir.Function,
  loop_ : @milkir.Loop,
) -> LoopMemoryEffects {
  if self.effects is Some(effects) {
    return effects
  }
  let effects : LoopMemoryEffects = {
    invalidates_addresses: false,
    writes_all: false,
    writes_for_unknown_reads: false,
    writes: HashSet([]),
  }
  for block in function.blocks {
    if !loop_.contains(block.id) {
      continue
    }
    for id in function.block_instruction_ids(block) {
      let inst = function.instruction_by_id(id).unwrap()
      if @analysis.invalidates_addresses(inst) {
        effects.invalidates_addresses = true
      }
      if !effects.writes_all {
        match @analysis.region_write(inst, self.pointers) {
          NoWrite => ()
          AllRegions => effects.writes_all = true
          ExactRegion(region) => effects.writes.add(region)
          RegionOrUnknownRead(region) => {
            effects.writes.add(region)
            effects.writes_for_unknown_reads = true
          }
        }
      }
      if effects.writes_all && effects.invalidates_addresses {
        self.effects = Some(effects)
        return effects
      }
    }
  }
  self.effects = Some(effects)
  effects
}

///|
fn LoopMemoryEffects::blocks_read(
  self : LoopMemoryEffects,
  region : @milkir.AliasRegion,
) -> Bool {
  self.writes_all ||
  (region == Other && self.writes_for_unknown_reads) ||
  self.writes.contains(region)
}
