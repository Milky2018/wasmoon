///|
pub(all) enum AllocatorStrategy {
  LinearScan
} derive(Eq, Debug)

///|
pub struct RegallocConfig {
  strategy : AllocatorStrategy
  verify : Bool
} derive(Eq, Debug)

///|
pub fn RegallocConfig::RegallocConfig(
  strategy? : AllocatorStrategy = LinearScan,
  verify? : Bool = true,
) -> RegallocConfig {
  { strategy, verify }
}

///|
pub fn RegallocConfig::strategy(self : RegallocConfig) -> AllocatorStrategy {
  self.strategy
}

///|
pub fn RegallocConfig::verify(self : RegallocConfig) -> Bool {
  self.verify
}

///|
pub fn allocate(
  program : Program,
  config? : RegallocConfig = RegallocConfig(),
) -> Allocation raise VerifyError {
  let allocation = match config.strategy {
    LinearScan => allocate_linear_scan(program)
  }
  if config.verify {
    verify_allocation(program, allocation)
  }
  allocation
}
