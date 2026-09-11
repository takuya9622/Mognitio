# Mognitio

Mognitio v0.1 is a small boolean language with a Common Lisp compiler.
It compiles one expression using SBCL and executes the resulting function
in the same process.

## Run

Install SBCL and make `sbcl` available on your PATH. No Quicklisp or
third-party Common Lisp libraries are required.

From this checkout:

```sh
./bin/mgn run examples/nested.mgn
```

Expected output:

```text
true
```

The launcher can be called by absolute path from another directory.
Relative source paths are resolved from the caller's working directory.
Pass filenames containing spaces or shell metacharacters as one quoted argument.

A program contains a single boolean expression. For example:

```mgn
if (true) {
    false
} else {
    true
}
```

Expressions may nest in the condition and either branch. This version does
not include variables, comments, operators, standalone grouping parentheses,
or optional `else` branches.

## Results

Successful execution prints `true` or `false` followed by one newline,
leaves stderr empty, and exits with status 0.

| Exit | Meaning |
|---|---|
| 1 | Source encoding, lexical, syntax, or semantic failure |
| 2 | Invalid invocation or unreadable source path |
| 3 | Internal compilation, execution, or bootstrap failure |

Diagnostics are written to stderr. Source diagnostics include a filename,
1-based line and column, and phase. Message wording is not a stable interface.

## Build and test

```sh
sbcl --noinform --script scripts/test.lisp
```

This calls `asdf:test-system "mognitio"`, builds the compiler, and runs unit
and subprocess tests. Any failed assertion causes a nonzero exit. Tests
require a non-root Unix environment for the file-permission cases and use
SBCL's bundled SB-POSIX facilities. Tests create and remove their own temporary
directories. Existing ASDF caches are preserved.

To load only the compiler from a Lisp session in this checkout:

```lisp
(require :asdf)
(asdf:load-asd (truename "mognitio.asd"))
(asdf:load-system "mognitio")
```

The production system does not load the test harness or fault-injection entry.
FASL files cache the compiler itself; there is no saved Mognitio program artifact.

## Verification

See [test coverage](tests/README.md) for the acceptance matrix and
[verification](verification/README.md) for reproducible checks.

## Contributing

See [contribution guidelines](CONTRIBUTING.md) for pull request and
public documentation conventions.
