# punkroc's tui platform

The platform for punk terminal apps. Its host is written in Rust, on
[ambit](https://github.com/eelcoh/ambit)'s `tui` platform: ambit owns the
terminal (raw mode, the alternate screen, restoring it on exit, error and
panic), the event loop and the worker threads, and draws with ratatui. The
punk app is the Elm architecture: a model, an `update` for every message, a
`view` that says what the screen shows, and `subscriptions` that say what the
app listens to.

```
app [Model, Msg, main] { Platform: platform "tui" }

import Platform.Tui
import Platform.Cmd
import Platform.Sub
import Platform.Clock
import Platform.View

type alias Model =
    { count : Int
    , paused : Bool
    }

type Msg
    = Pressed Tui.Key
    | Tick Int

main =
    { init = init, update = update, view = view, subscriptions = subscriptions }

init : (Model, Cmd Msg)
init =
    ({ count = 0, paused = False }, Cmd.none)

update : Msg -> Model -> (Model, Cmd Msg)
update = fn msg, model ->
    case msg of
        Pressed (Char "q") -> (model, Cmd.quit)
        Pressed (Char "p") -> ({ model | paused = not model.paused }, Cmd.none)
        Pressed _ -> ({ model | count = model.count + 1 }, Cmd.none)
        Tick _ -> ({ model | count = model.count + 10 }, Cmd.none)

subscriptions : Model -> Sub Msg
subscriptions = fn model ->
    if model.paused then
        Sub.onKey Pressed
    else
        Sub.batch [Sub.onKey Pressed, Clock.every 1000 Tick]

view : Model -> View
view = fn model ->
    View.column
        [ View.height 1 (View.text "Counter")
        , View.block "Count" (View.text (String.fromInt model.count))
        ]
```

The app exposes its `Model` and `Msg` types and `main`, a record of its four
parts. As in Elm, `update` gets only the app's own messages: keys, pastes, the
terminal's size and time come in through `subscriptions`, which the platform
asks again after every update, so the model decides what the app listens to.

| Module | What it has |
|--------|-------------|
| `Sub` | `Sub.none`, `Sub.batch [..]`, `Sub.map f sub`, `Sub.onKey toMsg` (a `Tui.Key`), `Sub.onPaste toMsg` (a `Str`), `Sub.onResize toMsg` (columns, rows: once at the start, and again when the terminal changes) |
| `Tui` | `Tui.Key`: `Char "a"` (shift applied: `"A"`), `Ctrl "c"`, `Alt "x"`, `Enter`, `Esc`, `Backspace`, `Delete`, `Tab`, `BackTab`, `Up`, `Down`, `Left`, `Right`, `Home`, `End`, `PageUp`, `PageDown`, `Insert`, `F Int` |
| `Cmd` | `Cmd.none`, `Cmd.quit`, `Cmd.batch [..]`, `Cmd.after ms msg`, `Cmd.map f cmd` |
| `File` | `File.read path toMsg` (`Result Str Str`), `File.list path toMsg` (`Result (List Str) Str`, folders end in `/`) |
| `Clock` | `Clock.now toMsg` (a `Cmd`: milliseconds since 1970), `Clock.every ms toMsg` (a `Sub`: the time, every `ms` milliseconds) |
| `View` | `View.text`, `View.paragraph [lines]`, `View.list selected [lines]` (one line highlighted and kept in sight), `View.column [..]`, `View.row [..]`, `View.height n v`, `View.width n v`, `View.block title v` (a frame), `View.empty`. A line is a list of spans: `View.span [View.bold, View.fg Yellow] "text"`, `View.plain "text"`. Styles: `bold`, `dim`, `italic`, `underline`, `reversed`, `fg color`, `bg color`; the sixteen terminal colours `Black`, `Red`, ..., `LightCyan`, `White` |

In a `column`, a view with a `height` gets that many rows and the others
share what is left; in a `row` the same holds for `width`.

## Effects are commands

As in Elm, the app never does anything itself: `update` gives back a `Cmd`,
a value that describes work, and the platform does it and answers later with
a `Msg`. `File.read "library.json" Loaded` gives `Msg (Loaded (Ok text))` or
`Msg (Loaded (Err why))`. The host does that work on ambit's worker threads,
so the screen keeps responding; the punk app itself only ever runs on the
screen's thread, one event at a time.

The app reads files only in the folder its wiring gives it (ambit's `Dir`,
read-only, no `..`, no symlinks out). A path outside it, or any other effect,
isn't there to ask for.

## How an app is built and run

`punk build` makes an archive (`libapp.a`) that does no I/O. A small Rust
crate links it with the host library `punk-tui` (in `host/`) and picks the
capabilities and the backend:

```rust
// The app, with its capabilities: the folder that holds library.json, and the clock.
pub fn init(folder: impl Dir, clock: impl Clock) -> punk_tui::App {
    punk_tui::App::new(folder, clock)
}

// main.rs: on a real terminal.
ambit_tui_native::run(init(NativeDir::open(path)?, StdClock::new()), Default::default())?;

// tests: on ambit's sim, keys in and the screen out as text, with time under control.
let mut sim = Sim::new(init(folder, clock.clone()), clock, 60, 12);
sim.key('s').keys("/guin");
assert!(sim.screen().contains("Library · 2 of 6"));
```

Examples, each with such a crate in its `tui/` folder:

- `examples/counter/`: the counter above.
- `examples/library/`: the library view of
  [crossload](https://github.com/eelcoh/crossload) (sorting, marking,
  searching), with its tests on the sim.

```
zig build
cd examples/library/tui
cargo test                     # on ambit's sim
cargo run -- ..                # on your terminal: the books of ../library.json
```

## How the host and the app talk

`main.roc` keeps the app's model in a `Box`, together with the replies it
still waits for. Each entry point (`roc_tui_init`, `roc_tui_update` for a
key, paste or resize, `roc_tui_reply` for the answer to a command,
`roc_tui_tick` for a timer) gives the host four things back: the commands as
text (one line each, `quit` or `<id>\t<kind>\t<arg>`, see `Cmd.to_host`), the
new box, the timers the subscriptions ask for (one length in milliseconds
per line, see `Sub.to_host`), and the screen as text (one node per line, see
`View.to_host` and `host/src/view.rs`). Text, not Roc's memory layout, so the
contract is small and the host can't misread a tag union. The host can't be
made to fail by what the app draws: what it can't read it leaves out.

A key, a paste or a resize goes to the app's update once for each
subscription that listens to it, and not at all when none does. The host
starts a timer when a length appears in the subscriptions and stops it when
the length is gone; a timer that was stopped and started again begins anew.

## Not done yet

- Tables with columns (`View.list` takes lines; the app pads them), wrapping
  text, scrolling a paragraph, colours beyond the sixteen.
- Writing files, the network, `Cmd.serial` (ambit has it), progress from a
  running task.
- `compare` on `Str` (Roc's strings have no order; the library example has
  its own `compareText`).
