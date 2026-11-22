# For agents working on punk

punk is Eelco's language: Elm-like syntax, compiled by the Roc compiler,
platforms with Rust hosts on ambit. Read `README.md` first, and
`src/punk/llms.txt` for the language itself.

## Rules

- Never push, open PRs, issues or comments on upstream Roc (roc-lang/roc).
  Roc changes go to eelcoh/roc's `punkroc` branch only.
- Default for language design questions: do what Elm does. Prefer pipelines
  (`List.map`, `fold ... into`) over loops; there are none.
- Keep `punk fmt` output: every `.punk` file in `examples/` must be
  formatted (the golden tests check it).
- Code that knows Roc's compiler belongs in `src/punk/roc/` only. The rest of
  `src/punk/` imports nothing but `std`.

## Build and test

```
zig build                  # compiler -> zig-out/bin/punk
zig build test             # translator unit tests (or: zig test src/punk/test.zig)
sh test/setup.sh           # build the platform hosts (once, and after changing one)
sh test/golden.sh          # golden tests; --update after an intended change
sh test/ci.sh              # everything CI runs (Postgres/Mongo tests need
                           # PUNK_TEST_POSTGRES / PUNK_TEST_MONGO)
```

- A new example needs a case in `test/golden/cases.txt`.
- After changing the stdlib tables, `src/punk/llms.in.md` or the examples,
  run `python3 src/punk/gen_llms.py` (it reads Roc's builtins from
  `zig-out/share/roc/Builtin.roc`, so `zig build` first).
- To try a local Roc checkout: `zig build --fork=../roc`.
