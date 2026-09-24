# Mognitio

Mognitio is a small language with typed function values, structured iteration,
and immutable data. Version 0.7.0 adds nominal structs and enums,
type aliases, unified branch expressions, and interfaces with concrete methods
and dynamic dispatch. Both execution backends reclaim unreachable data.

It can run an expression through SBCL or build a standalone Linux amd64 executable.
See the [v0.7.0 release validation](verification/v0.7.0-release.md) for coverage,
compatibility, and verification boundaries.
The [follow-up review record](verification/v0.7.0-review.md) covers the current
interface requirement syntax and subsequent implementation corrections.

This development branch is preparing v0.8.0. Ordinary local `let` / `var`
bindings now require type annotations. Direct function signatures and static
function aliases remain explicit binding forms; selected function values can
be called directly. See [development progress](verification/v0.8.0-progress.md)
for implemented and pending work.

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
let unitPrice: int = 120;
var count: int = 2;
count = count + 1;
count * unitPrice == 360
```

`let` is immutable. A `var` holds a primitive, aggregate, or interface value;
assignments preserve its type. Visible names, including a binding being initialized,
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
let text: string = "A日😀";
text->length() == 3
```

### Function values

```mgn
let magnitude = function(value: int): int {
    branch when { value < 0 => { return -value; } };
    value
};
let twice = function(value: int): int { value * 2 };
twice(magnitude(-6)) == 12
```

Function expressions have explicit `name: type` parameters and a result
type (primitive, aggregate, or interface). Bind them with `let`, alias them, choose
between matching signatures with `branch`, or return a function value from
a block or a value-producing loop. A function cannot itself accept or
return a function value. Mutable function values and recursion are excluded.

Names become visible in source order. A function may refer to an earlier
direct function binding or its static aliases. It cannot capture outer
data or functions selected by a block, `branch`, or loop.
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

`branch when { condition => expression, else => expression }` tests boolean
conditions in source order and selects the first true arm. Normally completing
arms must have identical types. Omitting `else` requires void arms or arms
without normal completion; all-false conditions then produce void.
A returning or nonterminating arm does not supply a normal type.
Statements or a tail after an unconditional exit are semantic errors.
All arms, arguments, and unused functions are still checked.

### Loops

```mgn
var count: int = 0;
let result: int = loop {
    count = count + 1;
    branch when { count < 4 => { continue; } };
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

The reserved words are `true false if match else let var function return int bool
loop while break continue void string type struct enum interface implement against
this branch when on try panic`. Names are ASCII and case-sensitive.
Comments, collections and a `never` source type are not supported.

Old `if` / `match` syntax is rejected. Replace an `if` with `branch when`, keeping
the original condition and arm block scopes. Comma-separated lists permit one
trailing comma, but never empty elements.

v0.4.1 programs also need explicit migration of named function declarations to
`let name = function(...) { ... };`, forward references to source order,
new keyword names, consecutive minus, and unreachable sequence elements.
See [test coverage](tests/README.md) for the retained regression cases.

### Data and contracts

```mgn
type Item = struct { name: string; };
type State = enum { Empty; Ready(Item); };
interface Named { let nameText = function(): string; }
implement Item against Named {
    let nameText = function(): string { this->name };
}
let render = function(value: Named): string { value->nameText() };
branch on (State::Ready(Item { name: "example" })) {
    State::Empty => false,
    State::Ready(item) => render(item) == "example",
}
```

Each struct and enum declaration creates a distinct type; `type Alias = Item;`
preserves identity. Type names and value names occupy separate namespaces.
Type, interface, and implementation declarations appear only at program scope
and become visible in source order. Fields and payloads are immutable; rebinding
a variable does not change earlier values. Aggregate equality is unavailable.

`branch on` evaluates its enum subject once and must cover every variant,
explicitly or with a final `else`. Payload bindings exist only in their arm.
Duplicate patterns and a redundant `else` are rejected.

Interfaces contain method signatures only. `implement Type against Contract`
supplies every method with its exact signature. `implement Type` adds methods
without a contract. `this` is an immutable concrete value in the method body.
An explicitly conforming value can cross an interface parameter or return
boundary, and the interface keeps the concrete value alive. Different contracts
may define the same method name; calls through an interface select its contract,
while ambiguous calls through a concrete value are rejected. Method references,
downcasts, recursive data, and call cycles are unavailable in this version.

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
