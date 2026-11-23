# How punk is built

punk uses three languages: **Zig** for the compiler, **Roc** inside the
compiler, and **Rust** for the platforms. You write none of them. You write
`.punk` files, and the release you install already holds everything else.
This page explains why there are three, and where each one sits.

## The layers

```
 you write             app.punk, its tests, its queries                 punk
 ──────────────────────────────────────────────────────────────────────────────
 the compiler          punk translator → Roc type checker → code        Zig
                       generator (between them: Roc source,
                       generated, nobody reads it)
 ──────────────────────────────────────────────────────────────────────────────
 compiled app          your app as machine code; it does no I/O itself
 ──────────────────────────────────────────────────────────────────────────────
 platform API          which effects an app may use (Http, Postgres,    .roc
                       Clock, ...): a thin file per platform
 platform host         main, the event loop, HTTP, Postgres,            Rust
                       the terminal; linked with the app                (on ambit)
```

### The compiler: Zig, with Roc in it

punk's compiler is the [Roc](https://www.roc-lang.org) compiler with punk's
translator in front of it. Roc is written in Zig, so the compiler is a Zig
program (`zig build` makes it).

When the compiler reads a `.punk` file, the translator (`src/punk/`) turns
it into ordinary Roc source in memory. From there Roc does the rest: type
checking, optimizing, and generating machine code. The translator is where
punk's own choices live: the Elm-like syntax, currying, Elm's argument
order, the design rules (no `crash`, no unchecked division), the query
language and the migrations.

Roc is pinned: `build.zig.zon` names one commit of
[eelcoh/roc](https://github.com/eelcoh/roc)'s `punkroc` branch, which is
upstream Roc plus a few marked places where it calls punk. Twice a month CI
tries a newer upstream Roc and moves the pin only when all of punk's tests
pass.

Why Roc: it has a type checker, fast code generation for many targets
(including WebAssembly and the Hermit unikernel), and a model where an app
does no I/O itself. punk gets all of that without writing a compiler
backend.

### The compiled app: no I/O

A compiled punk app is a library of machine code, not a program. It cannot
open a file, a socket or a database by itself. Everything it does to the
outside world goes through the platform: that is what makes it safe to let
agents write it. An app can only use the capabilities its platform hands it.

### The platforms: Rust, on ambit

A platform is the program around the app. It owns `main`, reads requests or
key presses, calls the app, and carries out the effects the app asks for.
punk has three: `cli`, `server` and `tui` (`platforms/`).

Each platform has two parts:

- **The API** (`platforms/<name>/*.roc`): the types and effects an app sees,
  such as `Http.Request` or `Postgres.rows!`. A thin file, written by agents.
- **The host** (`platforms/<name>/host/`): a Rust program, built on
  [ambit](https://github.com/eelcoh/ambit). ambit already has the platform
  model in Rust: capabilities (`Clock`, `Random`, `Kv`, `Http`, ...),
  platforms for command-line programs, servers and TUIs, a sandbox
  (Landlock and seccomp on Linux), deterministic simulation for tests, and a
  Hermit unikernel backend. The Postgres and Mongo drivers, HTTP and the
  terminal (ratatui) are Rust crates too.

Why Rust: all of that exists in Rust, and Hermit unikernels need it. Writing
the hosts in Zig would mean writing ambit again.

### Where Zig and Rust meet: nowhere

The compiler (Zig) and the hosts (Rust) never use each other's code. They
meet only in the finished program, through the C ABI: the compiler writes
the app as an object file, and the Rust host is linked with it.

- For `cli`, the host is built once as a static library (`libhost.a`), and
  `punk` links each app with it into one program.
- For `server` and `tui`, it goes the other way round: the app's Rust crate
  runs `punk build` from its `build.rs`, gets `libapp.a`, and `cargo build`
  links it into the program. That is why such an app has a `server/` or
  `tui/` folder with a `Cargo.toml`, and why the same server app can be
  built for Linux in a container or as a Hermit unikernel.

ambit is used as a Rust library, pinned to one commit in the hosts'
`Cargo.toml`. ambit does not know punk exists.

## What you need, and when

| you want to | you need |
|---|---|
| write and check `.punk` files | the punk release (compiler, platforms, packages) |
| run a `cli` app | the punk release |
| run a `server` or `tui` app | the punk release and Rust (`cargo`), because the program is a Rust crate with your app in it |
| work on punk itself | Zig 0.17.1 and Rust (see the repository's README) |

## The name

The language started as **punk**, a name that points at Roc, the
compiler it is built on. Later the name was cut short to **punk**. The language, the command and the `.punk` files
are `punk`; "punk-lang" is the name to search for. You will still meet
"punkroc" in one place: the branch of eelcoh/roc that holds the Roc punk is
built on.
