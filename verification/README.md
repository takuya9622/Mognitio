# Verification

Run these commands from the repository root. SBCL must be available on
`PATH`. The full suite requires a non-root Linux amd64 environment, bundled
SB-POSIX, Python 3, and permission to ptrace its own children.

## Automated tests

```sh
sbcl --noinform --script scripts/test.lisp
```

This invokes `asdf:test-system "mognitio"` and runs both unit and subprocess
tests. The summary reports test groups, assertions, child processes, and
failures. Any failure causes a nonzero exit.

The [test coverage matrix](../tests/README.md) describes the cases, including
strict source decoding, nested expressions, error classification, literal
paths, output isolation, and cold/warm compiler caches.

To repeat the complete suite with an isolated compiler cache:

```sh
(
    cache=$(mktemp -d) || exit 1
    trap 'rm -rf -- "$cache"' EXIT
    XDG_CACHE_HOME="$cache" ASDF_OUTPUT_TRANSLATIONS= CL_SOURCE_REGISTRY= \
        sbcl --noinform --script scripts/test.lisp
)
```

The temporary directory belongs to this invocation. Existing caches are
preserved.

## Command-line checks

```sh
./bin/mgn run examples/true.mgn
./bin/mgn run examples/false.mgn
./bin/mgn run examples/nested.mgn
```

The expected results are `true`, `false`, and `true`, respectively.
Each command must print exactly one result line, leave stderr empty, and
exit with status 0.

Subprocess tests independently capture stdout, stderr, and exit status for
source failures (1), invocation or I/O failures (2), internal failures (3), and evaluated integer failures (4).
Internal faults are injected through a test-only entry, not public CLI options.

## Native checks

```sh
./bin/mgn build --target linux/amd64 --output example examples/nested.mgn
./example
readelf -h -l example
```

Build must leave both output streams empty and exit 0. Execution prints
`true` and exits 0. `readelf` is an optional inspection tool, never part of
code generation. The automated suite checks the ELF fields independently.

Determinism is defined by source bytes, target, and compiler build/revision
identity. Matching semantic versions alone does not establish matching
identities. Record the revision, content manifest (including uncommitted
changes), SBCL/ASDF versions, and any code-generation configuration.
Paths, timestamps, process IDs, and cache contents are not embedded in the
executable. See the [v0.4.1 validation record](v0.4.1.md) and
original [v0.4.0 validation record](v0.4.0.md); the [v0.3.0 record](v0.3.0.md) remains historical.

## Repository checks

- Run `git diff --check` for whitespace errors.
- Include newly added files in the review; ordinary diffs omit untracked files.
- Check Markdown relative links and code fences.
- Keep source files UTF-8 with LF line endings and a final newline.
- Preserve the executable bit on `bin/mgn`.

The [checksum manifest](SHA256SUMS) identifies the current source snapshot,
excluding the manifest itself. Verify it from the repository root:

```sh
sha256sum -c verification/SHA256SUMS
```

Regenerate the manifest whenever a delivered file changes. Checksums identify
file contents; they do not independently prove that tests passed.

## Reporting results

Report the commands used, outcomes, and relevant unverified behavior in English.
Follow the [contribution guidelines](../CONTRIBUTING.md) when preparing public
logs and pull requests. Do not publish local setup details or session records.

Generated programs cover bounded samples, not every possible nesting depth.
The test bound is not a language limit. Operating-system termination,
uncatchable resource exhaustion, and simultaneous filesystem changes by other processes
are outside the guarantees established by the test suite. Native broken-output
handling is tested separately from successful delivery.
