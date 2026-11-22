import Cmd
import Sub

## The time, as Elm's `Time.now`: a command that answers with the
## milliseconds since 1970 on the platform's clock.
##
##     Clock.now GotTime
##     Clock.every 1000 Tick
Clock := [].{
    now : (I64 -> msg) -> Cmd(msg)
    now = |to_msg| Cmd.work(
        "now",
        "",
        |reply| to_msg(
            match I64.from_str(reply.text) {
                Ok(ms) => ms
                Err(_) => 0
            },
        ),
    )

    ## A message every this many milliseconds, with the time then, as Elm's
    ## `Time.every`: a subscription, so it runs while `subscriptions` gives it.
    every : (I64 -> msg), I64 -> Sub(msg)
    every = |to_msg, ms| Sub.every(ms, to_msg)
}
