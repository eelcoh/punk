# punk-lang

punk-lang is a small language for real applications: Elm's syntax and habits
(whitespace, `f a b`, `|>`, `case ... of`, `Maybe`, hand-written JSON
decoders), compiled by the Roc compiler, on platforms whose hosts are Rust
(on [ambit](https://github.com/eelcoh/ambit)). It is written mostly by
agents and meant to be easy for a person to read: if it compiles, it runs.

The language and its command are called `punk`, and its files end in
`.punk`. "punk-lang" is the name to search for.

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

Once the first release is tagged, this installs the latest release in `~/.punk` (the compiler, the platforms,
the packages and `llms.txt`), links `punk` into `~/.local/bin`, and checks
the download against the release's `SHA256SUMS` first. `PUNK_VERSION`,
`PUNK_HOME` and `PUNK_BIN_DIR` change what and where (see `install.sh`).
Releases are made by `.github/workflows/release.yml` on a `v*` tag.

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
| `test/` | golden tests, setup of the hosts, everything CI runs (`test/ci.sh`) |

## Roc

The compiler is Roc's, as a Zig dependency in `build.zig.zon`, pinned by
hash to a commit of [eelcoh/roc](https://github.com/eelcoh/roc)'s `punkroc`
branch: upstream Roc plus a few marked places where it calls punk's seam.
Twice a month CI merges upstream Roc into that branch, runs all of punk's
tests with it, and opens a PR here that moves the pin, only when they pass.
Nothing goes to upstream Roc (roc-lang/roc): no PRs, issues or comments.

## License

[UPL-1.0](LICENSE), the same as Roc's.
