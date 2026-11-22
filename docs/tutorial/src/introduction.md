# punk-lang

punk is a small language for real applications. It has Elm's syntax and
habits (whitespace, `f a b`, `|>`, `case ... of`, `Maybe`, hand-written JSON
decoders) and is compiled by the Roc compiler, on platforms whose hosts are
written in Rust. Most punk is written by agents and read by people, so it
aims for one thing: if it compiles, it runs.

## Install

On macOS or Linux:

```sh
curl -fsSL https://raw.githubusercontent.com/eelcoh/punk/main/install.sh | sh
```

This puts `punk` in `~/.local/bin` and its platforms next to it.

For VS Code, install the extension `punk-lang`: highlighting, `punk fmt` on
save, and the compiler's problems in the editor.

## Hello

```elm
app [main!] { Platform: platform "cli" }

import Platform.Stdout

main! = fn () ->
    Stdout.line! "Hello"
```

```sh
punk hello.punk          # build and run
punk fmt hello.punk      # lay it out
punk check hello.punk    # type-check only
```

`platform "cli"` picks one of the platforms that come with punk: `cli` for
command-line programs, `server` for HTTP servers, `tui` for terminal apps.

Every page of this tutorial is built from programs in the punk repository
that its tests run, so the code here compiles.
