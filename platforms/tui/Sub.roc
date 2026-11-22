import Tui

## What the app listens to, as Elm's `Sub`: the platform asks the app's
## `subscriptions` after every update and passes on what it listens to now.
##
##     subscriptions : Model -> Sub Msg
##     subscriptions = fn model ->
##         Sub.batch
##             [ Sub.onKey Pressed
##             , Sub.onResize Resized
##             , if model.running then Clock.every 1000 Tick else Sub.none
##             ]
##
## (In this file the arguments are in Roc's order, as in `Cmd.roc`.)
Sub(msg) := [None, Batch(List(Sub(msg))), OnKey(Tui.Key -> msg), OnPaste(Str -> msg), OnResize((I64, I64 -> msg)), Every(I64, (I64 -> msg))].{

    ## Nothing. (A function here, so that it can be a `Sub` of any message:
    ## punk writes `Sub.none`.)
    none : () -> Sub(msg)
    none = || None

    ## All of these.
    batch : List(Sub(msg)) -> Sub(msg)
    batch = |subs| Batch(subs)

    ## Every key press (releases and repeats are not reported).
    on_key : (Tui.Key -> msg) -> Sub(msg)
    on_key = |to_msg| OnKey(to_msg)

    ## Text pasted into the terminal in one piece.
    on_paste : (Str -> msg) -> Sub(msg)
    on_paste = |to_msg| OnPaste(to_msg)

    ## The terminal's size in columns and rows: once when the app starts, and
    ## again whenever it changes.
    on_resize : (I64, I64 -> msg) -> Sub(msg)
    on_resize = |to_msg| OnResize(to_msg)

    ## The same, its messages wrapped: for a part of the app with its own
    ## messages, as Elm's `Sub.map`.
    map : Sub(a), (a -> b) -> Sub(b)
    map = |sub, f| match sub {
        None => None
        Batch(subs) => Batch(List.map(subs, |s| map(s, f)))
        OnKey(g) => OnKey(|key| f(g(key)))
        OnPaste(g) => OnPaste(|text| f(g(text)))
        OnResize(g) => OnResize(|w, h| f(g(w, h)))
        Every(ms, g) => Every(ms, |now| f(g(now)))
    }

    ## A message every `ms` milliseconds, with the time then, for the
    ## platform's `Clock.every`.
    every : I64, (I64 -> msg) -> Sub(msg)
    every = |ms, to_msg| Every(if ms < 1 1 else ms, to_msg)

    ## The messages for a key.
    key_msgs : Sub(msg), Tui.Key -> List(msg)
    key_msgs = |sub, key| match sub {
        OnKey(f) => [f(key)]
        Batch(subs) => List.join(List.map(subs, |s| key_msgs(s, key)))
        _ => []
    }

    ## The messages for a paste.
    paste_msgs : Sub(msg), Str -> List(msg)
    paste_msgs = |sub, text| match sub {
        OnPaste(f) => [f(text)]
        Batch(subs) => List.join(List.map(subs, |s| paste_msgs(s, text)))
        _ => []
    }

    ## The messages for a new size.
    resize_msgs : Sub(msg), I64, I64 -> List(msg)
    resize_msgs = |sub, width, height| match sub {
        OnResize(f) => [f(width, height)]
        Batch(subs) => List.join(List.map(subs, |s| resize_msgs(s, width, height)))
        _ => []
    }

    ## The messages for the timer of `ms` milliseconds, at `now`.
    tick_msgs : Sub(msg), I64, I64 -> List(msg)
    tick_msgs = |sub, ms, now| match sub {
        Every(every_ms, f) => if every_ms == ms [f(now)] else []
        Batch(subs) => List.join(List.map(subs, |s| tick_msgs(s, ms, now)))
        _ => []
    }

    ## The timers the host runs, as it reads them: their intervals, one per
    ## line, each once.
    to_host : Sub(msg) -> Str
    to_host = |sub| Str.join_with(List.map(intervals(sub, []), |ms| ms.to_str()), "\n")

    intervals : Sub(msg), List(I64) -> List(I64)
    intervals = |sub, acc| match sub {
        Every(ms, _) => if List.contains(acc, ms) acc else List.append(acc, ms)
        Batch(subs) => List.fold(subs, acc, |a, s| intervals(s, a))
        _ => acc
    }
}
