# punk-lang

> punk-lang is a programming environment for building AI-generated
> applications that humans can understand, compilers can constrain, and
> infrastructure can safely operate.

Agents write most of the code; people read it, design it and review it. So
punk limits what an agent can do instead of asking it to behave: design rules
the compiler enforces (no `crash`, only literal SQL, a policy on every table
that becomes row-level security in Postgres), effects only through the
capabilities a platform hands out, and errors that `punk check --json` gives
to an agent with a code and a place.

Underneath is a small language for real applications: Elm's syntax and
habits (whitespace, `f a b`, `|>`, `case ... of`, `Maybe`, hand-written JSON
decoders), compiled by the Roc compiler, on platforms whose hosts are Rust
(on [ambit](https://github.com/eelcoh/ambit)). The aim: if it compiles, it
runs.

The language and its command are called `punk`, and its files end in
`.punk`. "punk-lang" is the name to search for. It started as "punkroc", a
name that points at Roc, the compiler it is built on, and was later cut short
to `punk`.

```elm
app [main!] { Platform: platform "cli" }

import Platform.Stdout

double : I64 -> I64
double = fn x ->
    x * 2

main! = fn () ->
    [1, 2, 3]
        |> List.map double
        |> List.map I64.toStr
        |> Str.joinWith ", "
        |> Stdout.line!
```

## Install

On macOS or Linux, without Zig or Rust:

```
curl -fsSL https://raw.githubusercontent.com/eelcoh/punk/main/install.sh | sh
```

This installs the latest release in `~/.punk` (the compiler, the platforms,
the packages and `llms.txt`), links `punk` into `~/.local/bin`, and checks
the download against the release's `SHA256SUMS` first. `PUNK_VERSION`,
`PUNK_HOME` and `PUNK_BIN_DIR` change what and where (see `install.sh`).
Releases are made by `.github/workflows/release.yml` on a `v*` tag.

Then make an app or a package with its `AGENTS.md` and punk's skills:

```
punk new server notes           # or cli, or tui
punk new package my-library     # a library with a public API test
```

From this repository, use `sh tools/new/new.sh` with the same arguments.
New apps use the platforms in the repository.

For VS Code there is an extension in `editors/vscode/`: highlighting,
`punk fmt` on save, and the problems of `punk check --json`.

## Build and run

You need Zig 0.17.1 and Rust (see `src/punk/README.md`, "Zig").

```
zig build                       # the compiler, as zig-out/bin/punk
sh test/setup.sh                # the hosts of the platforms, once
zig-out/bin/punk examples/elm.punk
zig-out/bin/punk check examples/elm.punk
zig-out/bin/punk fmt examples/elm.punk
```

## What is where

| | |
|---|---|
| `src/punk/` | the language: translator to Roc, `punk fmt`, the design rules, the query language, migrations ([README](src/punk/README.md)) |
| `src/punk/roc/` | the seam with the Roc compiler (the only code here that knows Roc's) |
| `src/punk/llms.txt` | the language reference for agents |
| `platforms/cli`, `server`, `tui` | the platforms: their API and their Rust host |
| `packages/json` | Elm-style `Json.Decode` / `Json.Encode` |
| `examples/` | example apps, and the golden tests' programs |
| `skills/`, `templates/` | agent skills per task (`SKILL.md`), and an `AGENTS.md` per platform for new apps |
| `docs/tutorial/` | the tutorial (mdBook; its code is included from `examples/`) |
| `editors/vscode/` | the VS Code extension ([README](editors/vscode/README.md)) |
| `install.sh`, `tools/release/` | installing a release, and packing one |
| `tools/new/` | `punk new`: the new app per platform |
| `test/` | golden tests, setup of the hosts, everything CI runs (`test/ci.sh`) |

## How it fits together

punk uses Zig for the compiler (Roc's compiler with punk's translator in
front), Roc inside it, and Rust (on ambit) for the platforms that run an app.
They meet only in the finished program, through the C ABI.
[How punk is built](docs/tutorial/src/architecture.md) explains why there are
three, where each one sits, and which of them you need.

## Roc

The compiler is Roc's, as a Zig dependency in `build.zig.zon`, pinned by
hash to a commit of [eelcoh/roc](https://github.com/eelcoh/roc)'s `punkroc`
branch: upstream Roc plus a few marked places where it calls punk's seam.
Twice a month CI merges upstream Roc into that branch, runs all of punk's
tests with it, and opens a PR here that moves the pin, only when they pass.
Nothing goes to upstream Roc (roc-lang/roc): no PRs, issues or comments.

## License

[UPL-1.0](LICENSE), the same as Roc's.
