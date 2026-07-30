# Component Conformance Harness

This package is an unstable, test-only adapter for the upstream Component Model
JSON script suites. It intentionally constructs low-level component runtime
values, resources, imports, and partially valid fixtures that ordinary
applications must not create.

Stable embedding code and normal CLI component execution must use
`Milky2018/wasmoon/component` and its `ComponentRuntime` facade. This package
does not define a supported application API and may change with the pinned
upstream conformance snapshot.
