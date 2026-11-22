---
name: punk-tui-screen
description: Use when adding a screen, a key binding or a background effect to a punk terminal app (platform "tui", the Elm architecture with Model, Msg, update, view and Cmd).
---

# Add a screen or a key to a terminal app

A terminal app is the Elm architecture: `main = { init, update, view }`,
with `update : Event Msg -> Model -> (Model, Cmd Msg)` and
`view : Model -> View`. The app does no effects itself. It returns `Cmd`s,
and the platform answers with a `Msg`. `examples/library/Library.punk` and
`examples/counter/Counter.punk` are the models.

## Steps

1. **Model.** Add what the screen needs to `Model`. For a new screen, add
   a field like `screen : Screen` with `type Screen = List | Detail Str`,
   and start it in `init`.
2. **Msg.** For each new result of an effect, add a variant to `Msg` with
   the data it carries: `Loaded (Result Str Str)`.
3. **update.** Add branches:
   - keys: `Key (Char "d") -> ...`, `Key Enter`, `Key Esc`, `Key Up`, ...
   - results: `Msg (Loaded (Ok text)) -> ...` and the `Err` case too
   - an effect: return it as the command, `(model, File.read path Loaded)`,
     or `Cmd.batch [...]`; `Cmd.after ms msg` for a timer
   Each branch returns `(newModel, cmd)`, with `Cmd.none` when there is
   nothing to do. Keep `_ -> (model, Cmd.none)` last.
4. **view.** Draw from the model only: `View.column`, `View.row`,
   `View.block "Title" ...`, `View.list selected lines`,
   `View.span [View.bold] "text"`. Pick the screen with `case model.screen of`.
5. **Check.** Run the skill `punk-check-loop` until it is clean.
6. **Test.** In the app's Rust crate (`tui/tests/`), drive it on ambit's sim
   terminal: send the keys, then assert on the rendered screen text. Run
   `cargo test --locked` in `tui/`.

## Rules

- `update` and `view` are pure: no `!` functions in a terminal app.
- `Resize` is always the first event. Keep the size in the model if the
  view depends on it.
- `File.read` and `File.list` reach only the app's folder.
- `compare` does not take `Str`. Sort by `Str.toUtf8` bytes.
