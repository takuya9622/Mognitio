# Test coverage

Run all groups with `sbcl --noinform --script scripts/test.lisp`.
The suite is connected to `asdf:test-system "mognitio"`.

| Acceptance IDs | Coverage |
|---|---|
| V01–V02 | Both literals, eight conditional combinations, nested conditions and branches |
| V03–V04 | Whitespace, EOF, allowed BOM and invalid BOM placement |
| V05–V08 | Strict UTF-8 byte boundaries, invalid words/characters, source locations |
| V09–V12 | Empty input/blocks, missing delimiters/else, extra input, excluded grammar |
| V13–V14 | Full semantic traversal, malformed ASTs, checked boundary, generated form structure |
| V15–V16 | Compile flags/errors, canonical results, branch evaluation, host output isolation |
| V17–V19 | Arguments, literal paths, permissions, phase stopping, real process failure statuses |
| V20 | Other working directories, Unicode/spaced names, cold/warm compiler caches |
| V21 | Repeated executions, generated programs, grammar mutations, clean full-suite run |

The generated tests use independent test trees, a renderer, and a boolean
evaluator. They exhaust depth 0 and depth 1, then take 128 reproducible
samples with seed 9622 and maximum depth 5. Depth and sample index are
reported on a generated-case failure. This bound applies only to the tests.

Subprocesses use argument lists and separate stdout/stderr files, with a
20-second harness timeout and forced cleanup on timeout. Each suite run
owns a fresh temporary directory. Fault injection is confined to the test
system and test entry; there are no public CLI fault flags.

Valid v0.1 source cannot produce a non-boolean type. Semantic-failure
classification is therefore tested through injected compiler conditions;
malformed internal ASTs must produce internal failures instead.

The host result alone cannot show that an unselected pure branch was not
evaluated. Tests check generated CL:IF forms and observe evaluation with
test-only host effects. Production execution always calls the host compiler.

## Native compiler coverage

| Acceptance IDs | Coverage |
|---|---|
| N01–N08 | Both literals, every shallow conditional, nested/generated programs, source regression |
| N09–N11, N26–N28 | Required options, exact suffix, literal filenames and other working directories |
| N12–N14, N29 | Permissions, aliases, symlinks, safe replacement, cleanup and executable mode |
| N15–N17 | Silent build, phase stopping, native fault subprocesses, bootstrap failures |
| N21–N22 | ELF header/segment parsing, direct execution without source, clean environment |
| N23 | Actual executable under short writes, EINTR before/after a prefix, zero/error returns, broken stdout |
| N24 | Byte equality across relocated compiler/source paths and cold/warm caches |
| D01–D02 | SSA validity, dominance, edges, machine operands, fixups and integer/image bounds |
| D03, D05 | Hand-reviewed instruction goldens, branches for every if, no compile-time execution |
| D04 | Build with only launcher tools on PATH; process-launch traps during native compilation |
| D06–D08 | Publication faults, internal diagnostic positions, bootstrap and cache isolation |

The native generated suite executes both literals, all eight shallow if
combinations, and 128 fixed-seed trees. Every result is compared with both
the independent tree evaluator and the Common Lisp backend. Each source if
must have a corresponding SSA branch and machine conditional jump.
The golden fixtures include nested forward/backward branch displacements.

The runtime helper uses Python's standard library and Linux ptrace to control
write results in the actual executable. Short writes perform real kernel
writes. EINTR is injected both before output and after a partial prefix.
Zero and error returns must not report success. Missing ptrace permission
fails the test instead of silently skipping it. No fault option is exposed
by the compiler CLI.

## Integer and local-binding coverage

| Test group | Coverage |
|---|---|
| `v03-positive-kernel` | Precedence, signed comparisons, local values, assignment, scope, operand order and branch merges |
| `v03-rejection-kernel` | Token and grammar boundaries, types, names reserved during initialization, shadowing, literal range and output preservation |
| `v03-runtime-arithmetic` | Checked arithmetic, intermediate failures, unselected branches, unused results, host/runtime classification |
| `v03-integer-machine-goldens` | Independent instruction bytes, typed SSA edges, malformed operands, large entry frames |
| `v03-runtime-output-faults` | Actual executable stderr writes under short writes, interruptions, zero/error returns, retry exhaustion and broken streams |
| `v03-equal-incoming-values` | Shared incoming SSA values after branch assignments, int/bool, both conditions, nested and mixed merges, earlier operands |
| `v03-generated-oracle` | 128 fixed-seed integer trees with nested branches and mutation, compared against a separate mathematical evaluator |

The integer generator uses seed 314159265 and depth 3. The oracle operates on
test-only trees, computes truncating division from absolute magnitudes, and
checks each intermediate mathematical result. It does not call production
arithmetic or reuse the compiler's AST, symbol table, or SSA. Failures report
the seed, sample, and rendered input.

Earlier rejection fixtures were updated only where the language expanded:
ordinary words are now identifiers (unresolved names are semantic errors),
integer tokens and operators reach the parser, and grouping is accepted.
The semantic traversal test now checks the complete side table. Native
goldens reflect the entry frame, and generated-branch checks distinguish
source branches from runtime and frame-control branches. Relocation and
cold/warm-cache determinism now exercise integer values and mutation.

The production byte writer has a small write-chunk adapter for in-process
fault tests; no fault switch is exposed by the CLI. The same finite retry
budget is used by the host and native integer-failure paths.

## v0.3.0 acceptance traceability

| Acceptance IDs | Executable fixtures |
|---|---|
| V03-01, V03-20, V03-22 | Existing source/frontend, CLI and native regression groups |
| V03-02 through V03-17 | `v03-positive-kernel`, `v03-contract-boundaries`, `v03-equal-incoming-values`, existing source-format fixtures |
| V03-18, V03-21, V03-23 through V03-29, V03-38, V03-39 | `v03-rejection-kernel` |
| V03-30 through V03-37 | `v03-runtime-arithmetic`, mutable-value cases in `v03-contract-boundaries` |
| D03-01 through D03-05 | Frontend/semantic/backend groups and the positive/rejection kernels |
| D03-06 through D03-10 | SSA verifier, machine goldens, generated source branches, contract boundaries and equal-incoming-value regressions |
| D03-11 | `v03-runtime-output-faults` |
| D03-12 | Existing ELF and publication-fault groups |

The contract-boundary group also checks ordered edge arguments, duplicate SSA
definitions, typed jump rejection, adjacent overflow checks, division guards,
failure-artifact determinism, successful replacement before runtime failure,
and execution with the source removed and an empty environment.
Old word/grouping rejections changed under V03-15 and V03-21 through V03-23;
the corresponding native compatibility cases are N05 through N07.

## v0.4.0 functions and returns

| Acceptance IDs | Executable fixtures |
|---|---|
| V04-01 | All preceding boolean/integer groups, including equal incoming values |
| V04-02 through V04-07, V04-15 through V04-19 | `v04-typed-functions-and-order`, `v04-call-barriers-and-pressure`, `v04-name-type-and-flow-boundaries`, `v04-large-argument-frame-and-host-symbols` |
| V04-08 through V04-14 | `v04-return-paths`, `v04-name-type-and-flow-boundaries` |
| V04-20 through V04-29 | `v04-reserved-words-and-grammar`, `v04-static-errors-and-cycles`, `v04-name-type-and-flow-boundaries`, preceding source and integer rejection groups |
| V04-30 through V04-33 | `v04-call-runtime-order`, `v04-name-type-and-flow-boundaries`, `v04-return-paths` |
| V04-34, V04-37 | `v04-artifact-publication-and-output-faults`, preceding publication and ELF groups |
| V04-35, V04-36 | `v04-deterministic-standalone`, preceding standalone and relocation groups |
| V04-38 | `v04-generated-independent-oracle`, preceding boolean and integer oracles |
| D04-01 through D04-06 | Frontend/semantic cases and `v04-checked-and-ir-boundaries` |
| D04-07 through D04-11 | IR boundary cases, return paths, host symbol identity, runtime-order cases |
| D04-12 through D04-16 | Allocation intervals, independent map validator, symbolic parallel copies, call pressure, handwritten ABI, 600-argument frame |
| D04-17, D04-18 | Frame instruction and relocation goldens, ELF fields, all-functions IR checks |
| D04-19, D04-20 | Output/publication faults, relocation and independent generators |

The function generator uses seed 20260916, depth 3 and 128 programs, each
with four acyclic functions. Its own call frames and lexical return targets
model mutation, ordered arguments, nested calls, early exits and the first
arithmetic failure. It does not use production syntax, semantic, arithmetic
or IR data. Generated failures include seed, sample and complete source.

The native backend now uses linear scan with whole-interval call spills.
A separate pairwise checker validates allocation maps, and symbolic tuples
check parallel copies including register/memory cycles. The handwritten
machine caller/callee independently checks stack alignment, incoming offsets,
all allocatable register clobbers, and RSP/RBP restoration after two calls.
Fixed fixtures include mixed arguments, signed boundaries, 24-function chains,
600 simultaneous live values and 600 arguments. These are test bounds.

The v0.3 successful `int` identifier fixture now uses `intValue`; the exact
old `int` and `bool` names are covered by v0.4 parse rejections. All four
new keywords are tested at function, parameter, let and var name positions.
Historical validation records retain their original results.

## v0.4.1 parameter syntax

The parameter syntax correction uses `name: type` throughout fixed fixtures,
large-argument builders, and the independent generator. The
`v04-parameter-annotations` group checks both types, whitespace around colons,
parameter/token spans, and parse diagnostic locations. Old `type name`, mixed
syntax, and missing names, colons, or types are rejected by run and build,
including preservation of an existing output.

Instruction goldens use the [Intel instruction reference](https://www.intel.com/content/www/us/en/developer/articles/technical/intel-sdm.html),
including CALL rel32, REX.W/R/B, ModR/M and SIB addressing. Host lexical
function declarations follow [Common Lisp LABELS](https://www.lispworks.com/documentation/HyperSpec/Body/s_flet_.htm).

## v0.5.0 function values, void and loops

| Acceptance IDs | Executable groups |
|---|---|
| V05-01 through V05-08 | `v05-function-values-and-scope`, `v05-function-and-flow-contracts`, `v05-dispatch-call-loop-composite` |
| V05-09 through V05-13 | `v05-void-blocks-and-flow`, `v05-function-and-flow-contracts`, `v05-large-mixed-void-call` |
| V05-14 through V05-23 | `v05-unconditional-loops`, `v05-conditional-and-valued-loops`, `v05-function-and-flow-contracts` |
| V05-24 through V05-26 | `v05-function-and-flow-contracts`, `v05-unconditional-loops`, `v05-loop-completion-boundary` |
| V05-27 through V05-33 | `v05-keywords-and-source-shapes`, `v05-void-blocks-and-flow`, retained grammar and annotation groups |
| V05-34 through V05-44 | `v05-function-values-and-scope`, `v05-function-and-flow-contracts`, `v05-void-blocks-and-flow` |
| V05-45 through V05-52 | `v05-unconditional-loops`, `v05-conditional-and-valued-loops`, `v05-condition-termination-has-no-false-exit` |
| V05-53 through V05-56 | `v05-void-blocks-and-flow`, `v05-runtime-order-and-artifacts`, retained arithmetic/return groups |
| V05-57 | `v05-dispatch-call-loop-composite`, `v05-generated-control-oracle` |
| V05-58 through V05-60 | `v05-runtime-order-and-artifacts`, updated `v04-artifact-publication-and-output-faults`, retained native fault/standalone groups |
| V05-61 | All preceding boolean, integer, function, allocation and artifact groups |

| Internal IDs | Checks |
|---|---|
| D05-01, D05-02 | Keyword/token boundaries, spans, optional AST children, general callees and statement parsing |
| D05-03 through D05-07 | Source-order visibility, static aliases, signatures, early exits, loop targets and function candidates |
| D05-08 | `v05-checked-metadata-mutations` and retained checked-boundary corruption |
| D05-09, D05-10 | Typed constants/joins, call operands, loop entry/backedge/exit environments |
| D05-11 | `v05-cyclic-core-verifier`, `v05-independent-dominance`, no-exit CFG observations |
| D05-12 | `v05-core-function-candidates`, `v05-cyclic-function-candidate-fixed-point` |
| D05-13 through D05-15 | `v05-cyclic-allocation`, pressure/call composite, retained symbolic copy checks |
| D05-16, D05-17 | Host/native function dispatch, callee ordering, lexical exits, first/middle/last dispatch arms |
| D05-18 | `v05-handwritten-void-abi`, `v05-large-mixed-void-call`, retained handwritten call/frame tests |
| D05-19 through D05-21 | No-exit loops, branch fixups, runtime ordering, publication, relocated cold/warm builds and write faults |
| D05-22 | `v05-generated-control-oracle` plus the fixed acceptance cases above |

The new oracle uses seed 20260920 and 128 programs. Generated expressions
have maximum depth 4 inside fixed control-flow templates; loop bodies run
at most eight rounds. Separate test trees, mutable cells and explicit
normal/return/break/continue records model function selection, nested calls,
mutation and early exits. Arithmetic uses the independent mathematical
test helper, not production arithmetic. Failures report the seed, sample,
source and expected completion.

Cyclic Core tests independently check dominance by removing a proposed
dominator and testing reachability. Function candidate propagation starts
from constants and must reject unsupported cycles even with call metadata.
The allocation checker reconstructs live demands from instruction events;
a negative test truncates an interval while retaining its assigned location.
The dispatch/loop composite expects 305 and repeats with 32 and 600 live
values. Handwritten machine code checks void argument slots, zero results,
clobbers, alignment and frame preservation across repeated calls.

Nontermination observations first require a successful build, then inspect
separate host/native processes for one second, requiring no output and a
still-running process before forced cleanup. This is a bounded observation,
not a termination proof or a language timeout. No-exit CFG assertions supply
separate structural evidence. A million-round finite loop checks that
iteration does not consume a fresh call frame each round.

Compatibility fixtures now bind function expressions explicitly and place
dependencies before use. Former forward-reference success is separately
rejected. The old `void` identifier uses `Void` in positive fixtures.
Consecutive minus arithmetic uses explicit grouping; original token shapes
have parse-negative tests. Empty blocks, optional else and statements after
an exit now reach semantic checks. Function aliases and grouped calls are
positive cases; immutable reassignment and mutable function values remain
negative. Historical verification records are unchanged.

`v05-public-examples` executes every checked-in example and every README
language example through host execution, silent build and direct native
execution. The complete suite retains a single entry point.
