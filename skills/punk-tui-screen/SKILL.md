---
name: punk-tui-screen
description: Use when adding a screen, a key binding, a timer or a background effect to a punk terminal app (platform "tui", the Elm architecture with Model, Msg, update, view, subscriptions and Cmd).
---

# Add a screen or a key to a terminal app

A terminal app is the Elm architecture:
`main = { init = init, update = update, view = view, subscriptions = subscriptions }`,
with `update : Msg -> Model -> (Model, Cmd Msg)`, `view : Model -> View` and
`subscriptions : Model -> Sub Msg`. The app does no effects itself: it
returns `Cmd`s, and the platform answers with a `Msg`. Keys, pastes, the
terminal's size and timers reach `update` only through `subscriptions`.
`examples/library/Library.punk` and `examples/counter/Counter.punk` are the
models.

## Steps

1. **Model.** Add what the screen needs to `Model`. For a new screen, add
   a field like `screen : Screen` with `type Screen = List | Detail Str`,
   and start it in `init` (a value, not a function).
2. **Msg.** Add a variant for each new input: `Pressed Tui.Key` for keys,
   `Loaded (Result Str Str)` for the result of an effect, `Tick Int` for a
   timer.
3. **subscriptions.** Listen for what the screen needs: `Sub.onKey Pressed`,
   `Sub.onPaste`, `Sub.onResize`, `Clock.every 1000 Tick`, combined with
   `Sub.batch [...]`. It is asked again after every update, so it can depend
   on the model (a timer only on the screen that shows it). A key that
   nothing listens to never reaches `update`.
4. **update.** Add branches:
   - keys: `Pressed (Char "d") -> ...`, `Pressed Enter`, `Pressed Esc`, `Pressed Up`, ...
   - results: `Loaded (Ok text) -> ...` and the `Err` case too
   - an effect: return it as the command, `(model, File.read path Loaded)`,
     or `Cmd.batch [...]`; `Cmd.after ms msg` for a one-off delay
   Each branch returns `(newModel, cmd)`, with `Cmd.none` when there is
   nothing to do.
5. **view.** Draw from the model only: `View.column`, `View.row`,
   `View.block "Title" ...`, `View.list selected lines`,
   `View.span [View.bold] "text"`. Pick the screen with `case model.screen of`.
6. **Check.** Run the skill `punk-check-loop` until it is clean.
7. **Test.** In the app's Rust crate (`tui/tests/`), drive it on ambit's sim
   terminal: send the keys, then assert on the rendered screen text. Run
   `cargo test --locked` in `tui/`.

## Rules

- `update`, `view` and `subscriptions` are pure: no `!` functions in a
  terminal app.
- `File.read` and `File.list` reach only the app's folder.
- `compare` does not take `Str`. Sort by `Str.toUtf8` bytes.
