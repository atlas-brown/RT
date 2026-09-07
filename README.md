# Rt: An overlay type system for shell pipelines

Jump to: [How it works](#how-it-works) | [Features](#features) | [Annotations](#annotations) | [Installation](#installation) | [Usage](#usage) | [Documentation](#documentation) | [Citing](#citing) | [Contributing](#contributing)

Rt catches data incompatibilities in shell pipelines before they run. Give it a
shell program and it tells you when one command produces data the next command
can't consume -- with a concrete counterexample showing exactly what breaks.

```
$ cat pipeline.sh
find . |
grep -E 'book[0-9]+\.txt' |
xargs cat
```

```
$ rt pipeline.sh
Error (ln. 1): grep → xargs
    grep produced '[^n]*' but xargs expects '([^[:blank:]]+|".+"|'.+')'
    Counterexample: " "
```

`grep -E 'book[0-9]+\.txt'` produces filenames -- including ones with spaces
or tabs. But `xargs` splits its input on whitespace, so a file named
`my book1.txt` would be split into two arguments: `my` and `book1.txt`.
Rt catches this mismatch and tells you exactly what triggers it.

## How it works

Rt gives each position in a pipeline a *regular type* -- a regular expression
describing the shape of every line that can appear at that point. For example,
after `grep -E '^[0-9]+$'`, the output type is lines consisting only of digits;
after `cut -d, -f1`, the output type is lines containing no commas.

Commands are modeled as transformations from input type to output type. Simple
commands like `echo` produce a fixed output regardless of input. Filtering
commands like `grep` produce output that is a subset of their input. Commands
that reshape data character-by-character -- `tr`, `cut`, `head` -- are modeled
with *finite-state transducers* that precisely describe how each input line is
rewritten into an output line.

To check a pipeline, Rt walks the commands left-to-right, composing these
transformations. At each step it verifies that the previous command's output
type is compatible with the next command's input type. If not, it reports a
counterexample: a concrete string that triggers the mismatch.

## Features

- **Pipeline type checking.** Verify that the output of each command in a
  pipeline is compatible with the input of the next.
- **Concrete counterexamples.** Every error includes a witness string that
  triggers the incompatibility, not just a vague warning.
- **Polymorphic command models.** Commands like `grep` and `cut` are modeled as
  input-dependent transformations, so the checker adapts to your pipeline's
  actual data.
- **User annotations.** Embed type expectations directly in shell comments to
  guide the checker or verify properties:

  ```sh
  # @assume "gen_books.sh" -> "^[A-Z][a-z]+ [0-9]+$"
  gen_books.sh |
  # @assert "[0-9]+" -> "grep -E '^[0-9]-[0-9]+-[0-9]+-[0-9A-Z]$'"
  grep -E '^[0-9]-[0-9]+-[0-9]+-[0-9A-Z]$'
  ```

- **Finite-state transducers.** Character-level transformations for commands
  like `tr`, `cut`, and `head`.
- **Interactive type inspection.** Use `rti` to query the type of any command
  invocation.

## Annotations

Annotations are user-provided type hints. They are shell comments placed on lines above a pipeline. They start
with `@` followed by a keyword and arguments:

```shell
# @assume_output some_invocation : [a-z0-9]+
# Or:
# @assume some_invocation -> [a-z0-9]+
```

Arguments can be quoted (single or double quotes), or unquoted (must not
contain whitespace). Quotes are stripped from the value. The invocation field
must be the full invocation including all flags and arguments (e.g.,
`"grep -E 'pattern'"`, not just `"grep"`).

Each pipeline can contain arbitrarily many annotations.
They can appear anywhere between two consecutive commands, even inbetween empty lines or other comments.
When two or more annotations are conflicting (same kind of annotation about the same invocation),
the one closest to the pipeline overwrites the rest.

### Invocation-level annotations

| Annotation | Syntax | Description |
|---|---|---|
| `@assume_input` | `# @assume_input <invocation> : <regex>` | Declare the invocation's input type |
| `@assume_output` | `# @assume_output <invocation> : <regex>` | Declare the invocation's output type |
| `@assert_input` | `# @assert_input <invocation> : <regex>` | Verify the invocation's input is a subset of the regex |
| `@assert_output` | `# @assert_output <invocation> : <regex>` | Verify the invocation's output is a subset of the regex |
| `@assert_input_contains` | `# @assert_input_contains <invocation> : <regex>` | Verify the invocation's input contains strings matching the regex (i.e., is a superset of the regex) |
| `@assert_output_contains` | `# @assert_output_contains <invocation> : <regex>` | Verify the invocation's output contains strings matching the regex (i.e., is a superset of the regex) |

#### Concise syntax

The above annotations can also be written using the more concise arrow syntax seen below:

| Annotation | Equivalent to |
|---|---|
| `@assume <invocation> -> <regex>` | `@assume_output` |
| `@assume <regex> -> <invocation>` | `@assume_input` |
| `@assert <invocation> -> <regex>` | `@assert_output` |
| `@assert <regex> -> <invocation>` | `@assert_input` |
| `@assert_contains <invocation> -> <regex>` | `@assert_output_contains` |
| `@assert_contains <regex> -> <invocation>` | `@assert_input_contains` |

If both sides match an invocation, or neither does, the annotation is ignored because it is ambiguous (which side is the invocation and which the regex?). In such cases the colon syntax should be used.

### Environment annotations

| Annotation | Syntax | Description |
|---|---|---|
| `@var` | `# @var <name> : <regex>` | Declare the type of a shell variable's contents |
| `@file` | `# @file <name> : <regex>` | Declare the type of a file operand's contents |
| `@concretize` | `# @concretize <name> : <path>` | Read a file at `path` and use its contents as the type of `name` |

### Examples

**Declaring unknown types.** Use `@assume_output` when you know exactly what an
invocation produces but the checker can't infer it:

```sh
# @assume_output "gen_books.sh" : "^[A-Z][a-z]+ [0-9]+$"
gen_books.sh | wc -l
```

**Verifying properties.** Use `@assert_output` to catch unexpected results:

```sh
# @assert_output "grep foo" : "[a-z]+"
cat data.txt | grep foo
```

If `grep foo` could produce digits or spaces, the checker reports a
counterexample.

**Describing variable contents.** Use `@var` when a shell variable holds a known
type. The checker substitutes the declared pattern into the invocation's argument
pattern:

```sh
# @var GREP_FILTER : "[0-9]+"
cat data.txt | grep -E "$GREP_FILTER"
```

**Snapshotting a file's shape.** Use `@concretize` to derive a type from an
actual file on disk:

```sh
# @concretize F : /path/to/example.txt
cat /path/to/example.txt | sort
```

At check time, the checker reads `/path/to/example.txt`, and uses the result as the type for `F`.
If the path cannot be resolved, the annotation is simply ignored.

**Using the arrow shorthand.** The arrow form is equivalent when unambiguous:

```sh
# These two are equivalent:
# @assume_output "gen_books.sh" : "[0-9]+"
# @assume "gen_books.sh" -> "[0-9]+"
gen_books.sh | wc -l

# Input assertions reverse the arrow direction:
# @assert_input "grep foo" : "[0-9]+"
# @assert "[0-9]+" -> "grep foo"
cat data.txt | grep foo
```

## Installation

The quickest way to get started:

```sh
curl -fsSL https://raw.githubusercontent.com/atlas-brown/rt/main/scripts/install.sh | sh
```

This downloads a thin `rt` wrapper to `~/.local/bin` that runs Rt in Docker.
Make sure `~/.local/bin` is on your `PATH`. Requires [Docker](https://docs.docker.com/get-docker/).

### brew

```sh
brew tap atlas-brown/tap
brew install rt
```

Requires [Docker](https://docs.docker.com/get-docker/).

### Ubuntu
```sh
curl -fsSLO https://github.com/atlas-brown/rt/releases/latest/download/rt_0.1.1_all.deb
sudo apt install ./rt_0.1.1_all.deb
```

with `dpkg`:
```sh
dpkg -i rt_0.1.1_all.deb
```

Requires [Docker](https://docs.docker.com/get-docker/).

### Fedora

rt is hosted on Fedora Copr. You can install from the official [repo](https://copr.fedorainfracloud.org/coprs/dvkofu/atlas-rt/):

```sh
dnf copr enable atlas-brown/atlas-rt 
sudo dnf install -y atlas-rt
```

You can also install the latest archive directly from GitHub:

```sh
curl -fsSLO https://github.com/atlas-brown/rt/releases/latest/download/rt-0.1.1.noarch.rpm
sudo dnf install -y ./rt-0.1.1.noarch.rpm
```

Requires [Docker](https://docs.docker.com/get-docker/).

### Build from source

If you'd rather run natively, Rt uses [uv](https://docs.astral.sh/uv/) for
dependency management. You will need a Java runtime -- the checker loads
automaton operations through JPype.

```sh
git clone https://github.com/atlas-brown/rt.git
cd rt
uv sync
uv run rt --help
```

Make sure `java` is on your `PATH` and `JAVA_HOME` is set before running.

## Usage

### `rt` -- check programs and pipelines

```sh
# Check a shell program file
rt program.sh

# Check a pipeline interactively (reads from stdin)
rt
```

Rt prints diagnostics for each type error it finds. If no errors are found,
nothing is printed and the exit status is `0`.

Output formats: `--compact` (single-line output) or `--json` (structured JSON).

### `rti` -- inspect invocation types

```sh
# Show the polymorphic type of an invocation
rti echo hello

# Show the input-to-output type of an invocation
rti -i hello grep o

# Register a custom type annotation for an invocation
rti --type '[0-9]+ -> [0-9]+' my_command --my-flag
```

`rti --type` persists the annotation as a YAML file under the signatures
directory, so subsequent `rt` runs will use it.

## Documentation

- [Architecture overview](docs/architecture.md) -- how the checker works under
  the hood: stream types, command types, transformations, stream transformers,
  and the automaton engine.
- [Command signatures](docs/command-signatures.md) -- how to define and
  register custom command types, including YAML format, output expressions,
  extended modules, and `rti --type` registration.

## Citing

If you use Rt in your research, please cite:

```bibtex
@inproceedings{rt:osdi:2026,
  title     = {Rt: Regular Types for the Streaming Shell},
  author    = {Li, Zekai and Lazarek, Lukas and Lamprou, Evangelos and Kapetanakis, George and Mamouras, Konstantinos and Vasilakis, Nikos},
  year      = {2026},
  booktitle = {20th USENIX Symposium on Operating Systems Design and Implementation (OSDI 26)},
  publisher = {USENIX Association},
  url       = {https://www.usenix.org/conference/osdi26/presentation/li-zekai},
  artifact  = {https://github.com/atlas-brown/rt},
  tags      = {correctness}
}
```

## Contributing

Rt is a research prototype from the [ATLAS Group](https://atlas.cs.brown.edu/). We welcome contributions. See [CONTRIBUTING.md](CONTRIBUTING.md) for development setup, project layout, and guidelines.
