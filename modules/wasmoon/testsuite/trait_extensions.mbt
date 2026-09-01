///|
pub extend CompareResult with Show::{output}

///|
pub extend JsonValue with @moonbitlang/core/json.FromJson::{from_json}

///|
pub extend JsonValue with Debug::{to_repr}

///|
pub extend TestAction with Debug::{to_repr}

///|
pub extend TestCommand with Debug::{to_repr}

///|
pub extend TestCommandWithLine with Debug::{to_repr}

///|
pub extend TestResult with Debug::{to_repr}

///|
pub extend TestRunnerError with Debug::{to_repr}

///|
pub extend TestValue with Debug::{to_repr}
