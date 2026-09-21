# Mognitio

Mognitio is a small language with typed function values and structured iteration.
The released baseline is v0.5.0. This development branch starts v0.6.0
with string parsing, static checks, the Common Lisp `run` backend,
Core text operations, and independently verified safepoint root plans.
Native ABI v3, root publication, and static literal objects are implemented.
Native text helpers and mark-and-sweep collection are implemented and tested.
This is development work toward v0.6.0; the released version remains v0.5.0.
See [development progress](verification/v0.6.0-progress.md).
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

A program ends in an expression. If it completes normally, its result must
be boolean; a tail with no normal completion is also valid.
Declarations and statements use semicolons. Blocks can have a final expression,
or produce `void` when they finish without one.

```mgn
let unitPrice = 120;
var count = 2;
count = count + 1;
count * unitPrice == 360
```

`let` is immutable. A `var` holds `int`, `bool`, `void`, or `string` and assignments
preserve its type. Visible names, including a binding being initialized,
cannot be redeclared in nested scopes. Sibling scopes may reuse names.

Integers are signed 64-bit values. Arithmetic (`+ - * / %`), comparisons
(`< <= > >= == !=`), and grouping are supported. Division truncates toward
zero; nonzero remainders have the dividend's sign. Overflow and division
or remainder by zero fail only when evaluated. Consecutive minus tokens
are rejected even across whitespace: write `-(-1)` or `10 - (-2)`.

### Strings

Strings are immutable sequences of Unicode scalar values, written in double
quotes with `\\`, `\"`, `\n`, `\r`, `\t`, and `\0` escapes. `+` concatenates
strings; `==` and `!=` compare their contents without Unicode normalization.
`text->length()` counts scalars and `text->slice(start, end)` copies a half-open
scalar range. The receiver and arguments are evaluated once, left to right.
Invalid bounds fail at runtime. String methods cannot be used as function values.

```mgn
let text = "A日😀";
text->length() == 3
```

### Function values

```mgn
let magnitude = function(value: int): int {
    if (value < 0) { return -value; };
    value
};
let twice = function(value: int): int { value * 2 };
twice(magnitude(-6)) == 12
```

Function expressions have explicit `name: type` parameters and a result
type (`int`, `bool`, `void`, or `string`). Bind them with `let`, alias them, choose
between matching signatures with `if`, or return a function value from
a block or a value-producing loop. A function cannot itself accept or
return a function value. Mutable function values and recursion are excluded.

Names become visible in source order. A function may refer to an earlier
direct function binding or its static aliases. It cannot capture outer
primitive values or functions selected by a block, `if`, or loop.
Nested functions use the same rule. There are no forward declarations.

The callee is evaluated once, before arguments. Arguments are evaluated
once from left to right. An early exit inside a callee or argument belongs
to that expression's enclosing function or loop. A called function has
its own local variables and return target.

### Void, blocks and exits

`void` is both a type name and its single value; `()` is not an expression.
A void function may have an empty body or use `return;` or `return void;`.
A value can be discarded as an expression statement only when its type is
void. Assignment and declaration remain statements.

An `if` requires a boolean condition. Its normally completing branches
must have identical types. An omitted `else` acts as a void branch.
A branch that returns or never finishes does not supply a normal type.
Statements or a tail after an unconditional exit are semantic errors.
Both branches, all arguments and unused functions are still checked.

### Loops

```mgn
var count = 0;
let result = loop {
    count = count + 1;
    if (count < 4) { continue; };
    break count * 10;
};
result == 40
```

`loop while (condition) { ... }` checks its condition before every round
and returns void when the condition is false or a plain `break;` is taken.
`continue;` restarts the condition, including when used inside a block in
the condition itself. A conditional loop does not allow a valued break.

`loop { ... }` runs until a break or an enclosing function return.
Its valued breaks must have matching types. Plain and valued breaks
cannot be mixed, including `break;` with `break void;`. A loop without
a normal exit may be used as a function or program tail.

A loop body must produce void when it completes normally. Body locals
are initialized each round; updates to outer variables survive.
Break and continue target the nearest loop in the same function.

The reserved words are `true false if else let var function return int bool
loop while break continue void string`. Names are ASCII and case-sensitive.
Comments, collections and a `never` source type are not supported.

v0.4.1 programs need explicit migration of named function declarations to
`let name = function(...) { ... };`, forward references to source order,
new keyword names, consecutive minus, and unreachable sequence elements.
See [test coverage](tests/README.md) for the retained regression cases.

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
| 4 | Detected arithmetic, string bounds, string size, or allocation failure during execution |

Runtime failures print a fixed runtime diagnostic to stderr, leave stdout
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
