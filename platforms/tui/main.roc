platform ""
    requires {
        [Model : model, Msg : msg] for main : {
            init : (model, Cmd(msg)),
            update : msg, model -> (model, Cmd(msg)),
            view : model -> View,
            subscriptions : model -> Sub(msg),
        }
    }
    exposes [Tui, Cmd, Sub, View, File, Clock]
    packages {}
    provides {
        "roc_tui_init": init_for_host,
        "roc_tui_update": update_for_host,
        "roc_tui_reply": reply_for_host,
        "roc_tui_tick": tick_for_host,
    }
    hosted {}
    targets: {
        inputs_dir: "targets/",
        x64glibc: { inputs: [app], output: Archive },
        arm64glibc: { inputs: [app], output: Archive },
        x64musl: { inputs: [app], output: Archive },
        arm64musl: { inputs: [app], output: Archive },
        x64mac: { inputs: [app], output: Archive },
        arm64mac: { inputs: [app], output: Archive },
    }

import Tui
import Cmd
import Sub
import View
import File
import Clock

## The app as the host holds it: its model, and the messages still to come
## for work the host is doing, under the ids the host was given.
State : {
    model : Model,
    waiting : List({ id : U64, reply : Cmd.Reply -> Msg }),
    next : U64,
}

## What the host gets back after each step: the work to do (one line each,
## see `Cmd.to_host`), the new state, the timers to run (see `Sub.to_host`)
## and the screen (see `View.to_host`).
Step : { cmds : Str, state : Box(State), subs : Str, view : Str }

init_for_host : {} -> Step
init_for_host = |{}| {
    (model, cmd) = main.init
    step({ model, waiting: [], next: 0 }, cmd)
}

## A key, a paste or a resize (see `Tui.event_from_host`), for what the
## app's `subscriptions` listen to.
update_for_host : Box(State), U8, Str, U32, U8, U16, U16 -> Step
update_for_host = |boxed, kind, text, code, mods, width, height| {
    state = Box.unbox(boxed)
    subs = (main.subscriptions)(state.model)
    msgs = match kind {
        1 => Sub.paste_msgs(subs, text)
        2 => Sub.resize_msgs(subs, width.to_i64(), height.to_i64())
        _ => Sub.key_msgs(subs, Tui.key_from_host(text, code, mods))
    }
    update_all(state, msgs)
}

## The timer of `ms` milliseconds went off at `now` (milliseconds since 1970).
tick_for_host : Box(State), I64, I64 -> Step
tick_for_host = |boxed, ms, now| {
    state = Box.unbox(boxed)
    update_all(state, Sub.tick_msgs((main.subscriptions)(state.model), ms, now))
}

## The host's answer to the work it was given under `id`.
reply_for_host : Box(State), U64, Bool, Str -> Step
reply_for_host = |boxed, id, ok, text| {
    state = Box.unbox(boxed)
    match List.find_first(state.waiting, |w| w.id == id) {
        Ok(w) => {
            waiting = List.keep_if(state.waiting, |other| other.id != id)
            update_all({ ..state, waiting }, [(w.reply)({ ok, text })])
        }
        # An answer nobody waits for: nothing changes.
        Err(_) => step(state, Cmd.none())
    }
}

## The app's update for each of these messages in turn, and all their work.
update_all : State, List(Msg) -> Step
update_all = |state, msgs| {
    (model, cmds) = List.fold(
        msgs,
        (state.model, []),
        |(m, cs), msg| {
            (next, cmd) = (main.update)(msg, m)
            (next, List.append(cs, cmd))
        },
    )
    step({ ..state, model }, Cmd.batch(cmds))
}

step : State, Cmd(Msg) -> Step
step = |state, cmd| {
    sent = Cmd.to_host(cmd, state.next)
    {
        cmds: Str.join_with(sent.lines, "\n"),
        state: Box.box({ ..state, waiting: List.concat(state.waiting, sent.waiting), next: sent.next }),
        subs: Sub.to_host((main.subscriptions)(state.model)),
        view: View.to_host((main.view)(state.model)),
    }
}
