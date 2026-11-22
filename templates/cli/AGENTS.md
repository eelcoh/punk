# For agents working on this app

This is a command-line app in [punk-lang](https://github.com/eelcoh/punk) on
the `cli` platform (`platform "cli"`). Read the language reference first:
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

## Work loop

```
punk fmt Main.punk
punk check --json Main.punk     # fix the first problem, repeat
punk test Main.punk             # the expect tests
punk Main.punk [args]           # run it
```

The skill `punk-check-loop` explains the error codes.

## What the app can do

Only what the `cli` platform gives: `Stdout`, `Stderr`, `Stdin`,
`File`, `Arg`, `Clock`, `Random`. There is no network.
