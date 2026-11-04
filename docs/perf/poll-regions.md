# Guarded poll regions

Native object projections expose checked addresses to the generic optimizer.
An ordinary safepoint invalidates those addresses because it can collect,
suspend, or reenter the runtime. Small numeric loops therefore repeat object
projection helpers after both loop-header polls and inlined leaf-entry polls.

## Contract

The Wasmoon embedding snapshots execution controls for each activation. Native
lowering opts into `exclusive_poll_controls` only for that ownership contract;
reusable compiler consumers default to the existing conservative behavior.
No callback, allocation, reentry, suspension or unclassified memory write may
occur in a versioned region. Reference writes and their barriers retain the
existing lowering. No physical address may escape through a block argument,
return, or stored value.

The versioner keeps the original loop, including every full safepoint, and
adds a bounded copy. Before each copied iteration a guard checks that the
captured callback is absent and the scheduling budget exceeds the maximum
number of polls on that iteration, or scheduling is disabled. Every original
poll position in the copy still charges the budget. A budget reaching its slow
boundary selects the original loop on the next guard, so cancellation, yield
counts, precise roots, and heap relocation retain their original boundaries.
The guard never batches or precharges polls across intervening traps.

Native budget charges have a runtime assertion: an unexpectedly exhausted
budget or changed callback traps rather than using an unproven object address.
No runtime helper ABI or collector policy changes are required.

## Independent verification

The planner accepts only innermost loops whose body is acyclic after removing
header backedges. It bounds source size, clone size and versions per function.
Empty exit forwarding blocks can be copied while final scalar/reference phis
remain shared. Original instructions and terminators retain source metadata.

A separate CFG must-analysis verifies matching guard layouts, fresh guard
results on their true edges, least credit at joins, and every individual
charge. Side entries, stale guards, excessive charges, cycles without a new
guard, opaque operations and mismatched layouts fail closed. The existing
all-path physical-borrow verifier remains mandatory after optimization.
The generic optimizer models control-state writes separately from object
metadata, while unknown writes invalidate every region.

Public runtime regressions compare unoptimized and optimized yield counts and
results at quanta 1, 2, 3, 5, 17 and 1024. Suspended callbacks replace arrays with
different lengths, collect, and verify the heap while an older array remains
live across an inlined leaf poll. A private negative control that forces a
declined guard to succeed triggers the charge assertion; restoring the guard
passes the same workload. Compiler tests reject malformed budget proofs.

## Measurement scope

The original import-free decimal-conversion probe and all assertions are
unchanged. Comparisons use the same October 23 SDK, downstream sources and
zero/one/ten-call inputs, alternating fresh processes with separate empty
caches. Process wall time includes startup, compilation, execution, GC and
cooperative switching. It is not isolated guest execution.

Two independent execution profiles of 1d183b2e attribute 48.93% and 48.86% of
main-thread leaf samples to struct and array projection helpers together.
Generated-code address mapping identifies Decimal left/right shifting as hot
loops. Collector leaf samples do not establish a complete collection-time
percentage; inclusive safepoint/root-maintenance samples overlap and must not
be added together.

The first prototype reduced the paired ten-call median by 17.7%, with unchanged
slow-poll and yield counts. Final-source measurements are recorded in PR #582.
The remaining gap against official moonrun is substantial; these results do
not establish universal workload, peak-memory, or pure guest-execution gains.
