///|
pub(all) enum AllocatorStrategy {
  Backtracking
  SinglePass
} derive(Eq, Debug)

///|
pub impl Show for AllocatorStrategy with fn output(self, logger) {
  match self {
    Backtracking => logger.write_string("Backtracking")
    SinglePass => logger.write_string("SinglePass")
  }
}

///|
pub struct RegallocConfig {
  strategy : AllocatorStrategy
  verify : Bool
} derive(Eq, Debug)

///|
pub fn RegallocConfig::RegallocConfig(
  strategy? : AllocatorStrategy = Backtracking,
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
