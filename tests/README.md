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
