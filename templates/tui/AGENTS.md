# For agents working on this app

This is a terminal app in [punk-lang](https://github.com/eelcoh/punk) on the
`tui` platform (`platform "tui"`), in the Elm architecture:
`main = { init = init, update = update, view = view, subscriptions = subscriptions }`. Read the language reference first:
`~/.punk/current/share/punk/llms.txt` (or `src/punk/llms.txt` in the punk
repository).

## Rules

- punk is Elm-like: `f a b`, `fn x ->`, `case ... of`, `|>`, `Maybe`,
  `Result`. When in doubt, do what Elm does. There are no loops: use
  `List.*`, `fold`, or recursion.
- Every top-level function has a type annotation.
- No `crash` or `dbg` outside `expect` tests. Return `Result` with your own
  error tags.
- `punk fmt` decides the layout. Every `.punk` file is formatted.
- Before you say a change is done, the loop below is clean and the tests pass.
- `update`, `view` and `subscriptions` are pure. Effects are `Cmd`s that the
  platform runs, and they answer with a `Msg`. Keys and timers come in only
  through `subscriptions`.

## Work loop

```
punk fmt App.punk
punk check --json App.punk      # fix the first problem, repeat
cd tui && cargo test --locked   # the app on ambit's sim terminal
```

Skills: `punk-check-loop`, `punk-tui-screen` (a new screen, key or effect).

## What the app can do

Only what the `tui` platform gives: keys, paste and resize (`Sub`),
`File.read` and `File.list` in the app's folder, `Clock.now` and
`Clock.every`, and `Cmd.after`.
