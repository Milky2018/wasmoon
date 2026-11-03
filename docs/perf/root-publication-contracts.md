# Root publication contracts

Tracking: [ISS-726](../../issues/ISS-726.md).

The native adapter plans liveness at collecting/cooperative edges, then the
existing scoped or persistent frame owns each admitted root. Persistent slots
are assigned only to SSA values in the union of root sites. Definition stores,
precise masks, parked-stack leases and nonlocal-exit markers retain the existing
protocol.

Observability is a separate property. A budget charge must remain observable,
but it does not collect, suspend or reenter. Likewise, a direct call may acquire
a separately validated invocation proof that excludes those transitions. The
`root_free_extension` adapter contract distinguishes those operations from
actual root sites. Unknown extensions retain the conservative default. Physical
address stability alone does not establish this contract: a nonmoving collector
could still require roots.

Wasm native lowering admits only its canonical budget guard/charge operations
and independently proved direct calls. Their contextual validation, SSA token,
complete path credit, exclusive invocation controls and native call behavior
must all agree before root planning. Original callee polls and charges remain
in place. Collecting calls keep their complete live root sets.

A final-machine-location frame prototype was implemented and rejected before
commit. Three independent six-case trials retained all 216 fresh processes;
the geometric means of the six median wall ratios were 1.0368, 1.0114 and
1.0105 against the parent. Even the version retaining small scoped frames and
publishing only a map pointer did not meet the declared performance criterion.
The new instruction, decoder and frame mode were removed. Package versions,
reference encoding, runtime JIT ABI 8 and artifact format 12 remain unchanged.
Codegen revision 36 invalidates caches for the retained compiler changes.

On the same flate whitebox IR, the validated root-site rule reduces sites from
8,490 to 8,457 and live root occurrences from 29,931 to 29,888. The seven most
sampled functions keep the same root-site counts. The rule makes the ownership
boundary explicit, but the counts do not explain the measured hot-path gain
or establish a material reduction in root maintenance.

The detached-child regression exercises real reclamation at a collecting host
call. Deliberately misclassifying that call as root-free must fail its live-root
assertion. Callback, cancellation, fuel, quantum and parked-root tests remain
required alongside complete platform validation and matched measurements.
