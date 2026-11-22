# @app@

A terminal app in [punk-lang](https://github.com/eelcoh/punk): `@App@.punk` is the app, `tui/`
the Rust program that runs it. You need Rust (<https://rustup.rs>).

```
cd tui
cargo run                    # q quits
cargo test                   # the tests in tui/tests, on a simulated terminal
```

Change it with `punk fmt @App@.punk` and `punk check @App@.punk`.

`AGENTS.md` is for coding agents, and `.claude/skills/` has punk's skills.
