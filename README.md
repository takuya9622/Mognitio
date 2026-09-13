# Mognitio

Mognitio v0.3.0 adds integers and local bindings to a small expression-first language.
It can run an expression through SBCL or build a standalone Linux amd64 executable.

## Requirements

The supported compiler host is Linux with SBCL and its bundled ASDF, UIOP,
and SB-POSIX facilities. Put `sbcl` on your PATH. No Quicklisp, third-party
Common Lisp libraries, assembler, or linker is needed to compile a program.

## Run

From this checkout:

```sh
./bin/mgn run examples/nested.mgn
```

Expected output:

```text
true
```

`run` compiles the expression with SBCL and executes the resulting function once.

## Build a native executable

```sh
./bin/mgn build --target linux/amd64 --output example examples/nested.mgn
./example
```

A successful build is silent and exits with status 0. Running the executable
prints `true` followed by one newline. The static ELF64 executable needs no
SBCL, libc, dynamic loader, source file, or compiler cache at runtime.

Both `--target` and `--output` are required, each exactly once, before the source.
Their order may be reversed. The only target is the exact spelling
`linux/amd64`. Use separate option values, as shown above.

Both commands require an exact lowercase `.mgn` source suffix.
`foo.MGN`, `foo.txt`, `foo`, and source `-` are rejected.
The output filename has no required suffix; output `-` names a regular file.

The output parent directory must exist. A successful build replaces an
existing regular output file and makes the result executable by its owner.
A failed build preserves an existing output and leaves no incomplete new
artifact. Output symlinks, other non-regular files, and aliases of the source
file are rejected.

The launcher can be called by absolute path from another directory.
Relative paths use the caller's working directory. Quote filenames containing
spaces or shell metacharacters as one argument.

## Language

A program has local declarations and assignments followed by a boolean result.
Blocks also end in an expression; both branches of an `if` must produce the
same type.

```mgn
let unitPrice = 120;
var count = 2;
count = count + 1;
count * unitPrice == 360
```

`let` is immutable; `var` can be assigned a value of its original inferred
type. Names use ASCII letters, digits, and underscores, without a `$` prefix.
A local cannot redeclare a visible or currently initializing outer name.
Separate sibling scopes and scopes that have already ended may reuse names.

Integers are signed 64-bit values. Decimal literals, arithmetic
(`+ - * / %`), comparisons (`< <= > >= == !=`), and grouping are supported.
Division truncates toward zero; nonzero remainders have the dividend's sign.
Operands are evaluated left to right. Only the selected branch executes,
while both branches are checked before execution.

Arithmetic overflow and division or remainder by zero stop execution.
Even a constant arithmetic failure is detected when evaluated, not during
build. There are no comments, functions, loops, strings, or optional
`else` branches in this version.

## Results

Successful `run` and native execution print `true` or `false` followed by
one newline, leave stderr empty, and exit with status 0.
Native output failures terminate with a nonzero status.

Compiler exit statuses:

| Exit | Meaning |
|---|---|
| 0 | Successful run or build |
| 1 | Source encoding, lexical, syntax, or semantic failure |
| 2 | Invalid invocation, target, source path, or output I/O |
| 3 | Internal compilation, execution, or bootstrap failure |
| 4 | Integer arithmetic failure during execution |

Integer failures print a fixed runtime diagnostic to stderr, leave stdout
empty, and do not resume evaluation. Building such a program succeeds;
running it reports the failure.

Diagnostics go to stderr. Source diagnostics include a filename, 1-based
line and column, and phase. Message wording is not a stable interface.

## Build and test

```sh
sbcl --noinform --script scripts/test.lisp
```

This calls `asdf:test-system "mognitio"`, builds the compiler, and runs unit
and subprocess tests. The full suite requires a non-root Linux amd64 host,
Python 3, and permission to trace its own child processes with ptrace.
These additional requirements apply to tests, not compilation or generated
executables. Any failed assertion or unavailable required test facility
causes a nonzero exit.

Tests create and remove their own temporary directories and preserve existing
ASDF caches. See [test coverage](tests/README.md) and
[verification](verification/README.md) for reproducible checks.

To load the compiler from a Lisp session in this checkout:

```lisp
(require :asdf)
(asdf:load-asd (truename "mognitio.asd"))
(asdf:load-system "mognitio")
```

The production system does not load the test harness or fault-injection helpers.
FASL files cache the compiler itself; native output is a separate executable.

## Contributing

See [contribution guidelines](CONTRIBUTING.md) for pull request and
public documentation conventions.
