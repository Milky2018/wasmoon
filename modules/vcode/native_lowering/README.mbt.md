# Native lowering protocol

`Milky2018/vcode/native_lowering` is a streaming instruction-selection
protocol. It carries one target-neutral operation at a time from MilkIR
legalization into a native target. It does not own a function graph, duplicate
SSA, or retain an
intermediate program representation.
