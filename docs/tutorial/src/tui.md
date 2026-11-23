# A shopping list in the terminal

This page makes a terminal app: a shopping list you add to, tick off and
clean up with the keyboard. It needs what you installed for the
[JSON API](install.md) except Postgres.

```sh
punk new tui shopping
cd shopping/tui
cargo run
```

The new app is a counter: it counts the keys you press and adds ten every
second. `p` pauses the clock and `q` quits. Like the server, it is a git
repository with `AGENTS.md` and the skills, and `tui/` is the Rust program
that runs it. You write `Shopping.punk`.

The whole app of this page is
[`examples/tutorial/shopping/Shopping.punk`](https://github.com/eelcoh/punk/blob/main/examples/tutorial/shopping/Shopping.punk).
Replace the counter with the parts below, in order.

## The Elm architecture

A terminal app is built the way Elm builds a web page:

- a **model**: everything the app knows, as one value;
- **messages**: what can happen, such as a key press;
- **`update`**: given a message and the model, the next model (and
  commands, such as quitting);
- **`view`**: given the model, what the screen shows;
- **`subscriptions`**: which events the app wants: keys, a timer, a paste.

The platform owns the loop. It draws the `view` of the model, waits for an
event the app subscribed to, calls `update`, and draws again. Nothing else
changes the model, so the screen is always the view of the current model.

## The model

```elm
{{#include ../../../examples/tutorial/shopping/Shopping.punk:model}}
```

The first line says which three things the app gives the `tui` platform:
the types `Model` and `Msg`, and `main`, a record of its four parts.

`Mode` is a custom type: either the app is browsing the list, or the user
is typing the name of a new item, and then the model holds what they typed
so far. There is no separate "is adding" flag that could disagree with the
name. The only message is a key press, `Pressed Tui.Key`: a character such
as `Char "a"`, or a key such as `Enter`, `Esc`, `Up`.

## Update

```elm
{{#include ../../../examples/tutorial/shopping/Shopping.punk:update}}
```

`update` first asks which mode the app is in, and gives the key to
`browse` or to `edit`. That is why `q` quits while browsing, but is just a
letter in the name while adding. `case` must cover every case: leave out
`_ -> (model, Cmd.none)` and the compiler says which keys are missing.

Each branch returns the next model and a command. `Cmd.none` does nothing;
`Cmd.quit` ends the app and gives the terminal back.

## Changing the list

```elm
{{#include ../../../examples/tutorial/shopping/Shopping.punk:changes}}
```

These are plain functions from a model to a model: no effects, so easy to
read and to test. `{ model | items = items }` is a copy of the model with
other items, as in Elm. `select` keeps the selection inside the list, so
`d` on the last item, or `↑` on the first, can't select nothing.

## The view

```elm
{{#include ../../../examples/tutorial/shopping/Shopping.punk:view}}
```

A view is a value: text, a list with one line highlighted, a frame with a
title around a view, and views above (`View.column`) or beside (`View.row`)
each other. `View.height 1` gives a view one row; the others share what is
left. A line is a list of spans, each with its own style: `View.bold`,
`View.dim`, `View.fg Green`.

The title of the frame counts what is left to get, and the bottom line
shows either the keys or what you are typing. Both come from the model, so
they can't go stale.

## Run it

```sh
punk check ../Shopping.punk
cargo run
```

Press `a`, type `milk`, Enter; `a`, `bread`, Enter. Space ticks off the
selected item, `d` deletes it, `↑` and `↓` move, `q` quits.

## Test it

The functions that change the list are pure, so they are tested right next
to them:

```elm
{{#include ../../../examples/tutorial/shopping/Shopping.punk:tests}}
```

```sh
punk test ../Shopping.punk
```

`empty` is the model `init` starts with. The keys and the screen are tested
by `tui/tests/`, which runs the app on a simulated terminal: keys go in, and the
screen comes out as text. The tutorial's
[tests](https://github.com/eelcoh/punk/blob/main/examples/tutorial/shopping/tui/tests/sim.rs)
add items, tick them off and delete them, for example:

```rust
#[test]
fn space_ticks_off_the_selected_item() {
    let mut sim = start();
    add(&mut sim, "milk");
    add(&mut sim, "bread");
    // The new item is selected; Up goes to milk.
    sim.key(KeyCode::Up).key(' ');
    assert_eq!(items(&sim), ["✓ milk", "  bread"]);
    assert!(sim.screen().contains("1 to get"));
}
```

Replace the counter's tests with those, then:

```sh
cargo test
git add -A
git commit -m "A shopping list"
```

## Next

- **Keep the list.** The platform can read and write files in one folder
  that the Rust program gives the app (`File` in the platform, and the
  folder in `tui/src/lib.rs`). [`examples/library`](https://github.com/eelcoh/punk/tree/main/examples/library)
  reads its books that way.
- **Search.** Add a mode `Searching Str`, and show only the items whose
  name contains it: one more case in `update`, one more filter in `view`.
