# Parked activation root sources

Tracking: [ISS-720](../../issues/ISS-720.md).

Native fibers stop with their trap activation, function-frame chain, root scopes,
exception state, spilled locals and scratch storage still alive. Previously each
yield counted these roots, allocated a registration and root array, and copied
the roots before switching stacks. The original Core strconv module performs
about 1.887 million cooperative yields; independent sampling identifies root
enumeration and function-frame helpers as significant execution costs.

## Ownership and enumeration

An activation now embeds its parked-root registration. Linking it retains the
same heap, but does not allocate or enumerate roots. The native continuation
already retains its managed context and arguments; guest-continuation storage
keeps its fiber and owning execution state alive. Registration borrows these
stopped frames until the owner unregisters it.

The heap's existing registration list supports both owned arrays and activation
sources. Sources supply closed count/copy and conservative-mark callbacks. They
cannot run guest code, switch fibers or mutate root storage. GC seed snapshots,
transaction liveness and continuation tracing enumerate the same masks and
typed exception roots when needed. Copy counts and signed-size bounds remain
checked. Exception and continuation payload registrations still own their arrays;
owner identities continue to distinguish arena edges from independent roots.

Resume unregisters before attaching and running the stopped stack. Cancellation
and destruction unregister before abandoning the activation or releasing its
stack. Embedded registrations are reset on unlink; owned registrations and
buffers are freed. Popping or abandoning a still-registered activation aborts.
All operations remain on the fiber owner's thread. No root source survives the
storage that it borrows, and no collection runs between snapshot count and copy.

The generated function-frame ABI, heap layout, artifact revision, root masks,
barriers, quotas, cancellation callbacks and scheduling quantum are unchanged.
Only the internal representation of parked registrations changes. A performance
result must include both the ordinary root-frame traffic that remains and any
cost shifted into actual collections; avoiding eager copies alone is not a
whole-program speedup claim.

## Regression coverage

The native allocation-denial regression fails before this change: the first
parked-root allocation is rejected. Afterward the same pending failure remains
unconsumed, exact root snapshots retain only the live mask bit, collection keeps
that object and unregistering makes it reclaimable.

A shared ordinary/sanitizer public fixture keeps an object live through an
indirect call after the loop, preventing scalar replacement from making the
root assertion vacuous. At O0/O2/O3 it parks two calls on the same context,
mutates a detached snapshot, collects, cancels one call twice, and resumes the
other. Both objects are reclaimed at their corresponding lifetime boundaries.
Omitting source enumeration makes the regression fail; the implementation is
restored before acceptance. Existing exception graphs, transactional rollback,
continuation retirement, host reentry and native-fiber lifecycle suites remain
required.

## Matched measurements

The parent is `44d8d356`; both native embeddings use the same unchanged downstream
`ed848ac5` sources and MoonBit SDK 20261023. Original generated Core artifacts,
test selections, assertions, cancellation and scheduling quantum are unchanged.
Each process has a separate empty cache. One warmup pair per hot module is
retained separately; five measured pairs alternate engine order and rotate
module order. All 20 measured pairs improve, with identical output per pair.

| Original module | Parent median (s) | Source registration median (s) | Median paired change |
| --- | ---: | ---: | ---: |
| strconv | 8.162626 | 7.649178 | -6.40% |
| immut/vector whitebox | 7.727863 | 7.558746 | -2.29% |
| edit-distance | 5.909965 | 5.778816 | -1.89% |
| sorted-map | 5.991096 | 5.895687 | -1.42% |

Three full-suite rounds rotate official/parent/candidate process order and use
`moon test --target wasm-gc -j 1`. Every run passes all 7,971 original tests.
Median process wall time is 10.235260 s for official V8 moonrun, 138.355690 s for
the parent and 137.357672 s for this change. Candidate/parent paired changes are
-0.72%, +0.40% and -1.73%, all retained. The matched median ratio to official is
13.52x before and 13.42x after. These mixed, small full-suite changes do not
establish a material total-time improvement. The historical 13.28x result is a
separate measurement and must not be used as the paired baseline here.

These wall times include startup, compilation, execution, GC and teardown; they
do not isolate guest execution. `-j 1` serializes test executables and leaves
V8's internal compilation defaults unchanged. This change addresses repeated
root materialization, while eager optimized compilation and object-projection
helpers remain substantial independent costs. No universal speedup or peak-RSS
improvement is claimed.
