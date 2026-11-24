import Secret

## The app's settings, typed. The wiring gives the app named settings as text
## (from environment variables it picks, say), and the app says with a
## decoder which ones it needs and what type each one is, as Elm's
## `Json.Decode` reads JSON:
##
##     type alias Settings =
##         { baseUrl : Str
##         , ttlSeconds : Int
##         , apiKey : Secret
##         }
##
##     settings : Config.Decoder Settings
##     settings =
##         Config.map3 (fn baseUrl, ttlSeconds, apiKey -> { baseUrl, ttlSeconds, apiKey })
##             (Config.text "BASE_URL")
##             (Config.int "TTL_SECONDS" |> Config.withDefault 3600)
##             (Config.secret "API_KEY")
##
## The platform runs the decoder when the server starts: a setting that is
## missing or doesn't fit stops the server with a message that names every
## such setting, before the first request. `handle!` then gets the settings
## as a value of the app's type.
##
## (In this file the arguments are in Roc's order: the decoder a function
## works on comes first. punk passes it last.)
Config := [].{
    ## Turns the settings (pairs of a name and its text) into an `a`, or says
    ## what is wrong with them: every setting that is missing or doesn't fit.
    Decoder(a) :: { run : List((Str, Str)) -> Try(a, List(Problem)) }

    ## A setting that is missing (its name), or one that is wrong (a message).
    Problem : [Missing(Str), Wrong(Str)]

    ## The setting as text, in punk `Config.text "BASE_URL"`.
    text : Str -> Decoder(Str)
    text = |name| {
        run: |settings| match lookup(settings, name) {
            Ok(value) => Ok(value)
            Err(NotFound) => Err([Missing(name)])
        },
    }

    ## The setting as a whole number: `3600`, `-1`.
    int : Str -> Decoder(I64)
    int = |name| {
        run: |settings| match lookup(settings, name) {
            Err(NotFound) => Err([Missing(name)])
            Ok(value) => match I64.from_str(Str.trim(value)) {
                Ok(n) => Ok(n)
                Err(_) => Err([Wrong("${name} should be a whole number, it is \"${value}\"")])
            }
        },
    }

    ## The setting as a bool: `true` or `false`.
    bool : Str -> Decoder(Bool)
    bool = |name| {
        run: |settings| match lookup(settings, name) {
            Err(NotFound) => Err([Missing(name)])
            Ok(value) => match Str.trim(value) {
                "true" => Ok(True)
                "false" => Ok(False)
                _ => Err([Wrong("${name} should be true or false, it is \"${value}\"")])
            }
        },
    }

    ## The setting as a `Secret`: a password, a key, a token. It may not be
    ## empty. A message about it never shows its value.
    secret : Str -> Decoder(Secret)
    secret = |name| {
        run: |settings| match lookup(settings, name) {
            Err(NotFound) => Err([Missing(name)])
            Ok(value) =>
                if Str.is_empty(value) {
                    Err([Wrong("${name} is empty")])
                } else {
                    Ok(Secret.from_text(value))
                }
        },
    }

    ## This value when the setting is missing, in punk
    ## `Config.int "PORT" |> Config.withDefault 8080`. A setting that is there
    ## but doesn't fit is still an error.
    ##
    ## (Made from `succeed`: a decoder whose closure captures `default` itself
    ## makes the Roc compiler of the pinned commit fail in `punk test`, with
    ## "a worker without a type table read an input-dependent recipe".)
    with_default : Decoder(a), a -> Decoder(a)
    with_default = |decoder, default| when_missing(decoder, succeed(default))

    ## A setting that may be missing: `Nothing` then, `Just x` otherwise.
    maybe : Decoder(a) -> Decoder([Just(a), Nothing])
    maybe = |decoder| when_missing(map(decoder, |value| Just(value)), succeed(Nothing))

    ## The first decoder, or the second when a setting the first needs is
    ## missing (and none is wrong).
    when_missing : Decoder(a), Decoder(a) -> Decoder(a)
    when_missing = |first, second| {
        run: |settings| match (first.run)(settings) {
            Ok(value) => Ok(value)
            Err(problems) =>
                if all_missing(problems, 0) {
                    (second.run)(settings)
                } else {
                    Err(problems)
                }
        },
    }

    all_missing : List(Problem), U64 -> Bool
    all_missing = |problems, i| match List.get(problems, i) {
        Err(_) => True
        Ok(Missing(_)) => all_missing(problems, i + 1)
        Ok(Wrong(_)) => False
    }

    describe : Problem -> Str
    describe = |problem| match problem {
        Missing(name) => "${name} is missing"
        Wrong(message) => message
    }

    lookup : List((Str, Str)), Str -> Try(Str, [NotFound])
    lookup = |settings, name| match List.find_first(settings, |(n, _)| n == name) {
        Ok((_, value)) => Ok(value)
        Err(_) => Err(NotFound)
    }

    ## Settings that give this value, whatever the wiring gives.
    succeed : a -> Decoder(a)
    succeed = |value| { run: |_| Ok(value) }

    ## Settings that are wrong, with this message.
    fail : Str -> Decoder(a)
    fail = |message| { run: |_| Err([Wrong(message)]) }

    ## In punk `Config.map f decoder`.
    map : Decoder(a), (a -> b) -> Decoder(b)
    map = |decoder, f| {
        run: |settings| match (decoder.run)(settings) {
            Ok(a) => Ok(f(a))
            Err(e) => Err(e)
        },
    }

    ## Both decoders, with the problems of both when they fail.
    both : Decoder(a), Decoder(b) -> Decoder((a, b))
    both = |da, db| {
        run: |settings| match ((da.run)(settings), (db.run)(settings)) {
            (Ok(a), Ok(b)) => Ok((a, b))
            (Err(e), Ok(_)) => Err(e)
            (Ok(_), Err(e)) => Err(e)
            (Err(e1), Err(e2)) => Err(List.concat(e1, e2))
        },
    }

    ## In punk `Config.map2 f da db`: the last decoder comes first here.
    map2 : Decoder(b), (a, b -> c), Decoder(a) -> Decoder(c)
    map2 = |db, f, da| map(both(da, db), |(a, b)| f(a, b))

    ## In punk `Config.map3 f da db dc`.
    map3 : Decoder(c), (a, b, c -> d), Decoder(a), Decoder(b) -> Decoder(d)
    map3 = |dc, f, da, db| map(both(both(da, db), dc), |((a, b), c)| f(a, b, c))

    ## In punk `Config.map4 f da db dc dd`.
    map4 : Decoder(d), (a, b, c, d -> e), Decoder(a), Decoder(b), Decoder(c) -> Decoder(e)
    map4 = |dd, f, da, db, dc| map(both(both(both(da, db), dc), dd), |(((a, b), c), d)| f(a, b, c, d))

    ## In punk `Config.map5 f da db dc dd de`.
    map5 : Decoder(e), (a, b, c, d, e -> g), Decoder(a), Decoder(b), Decoder(c), Decoder(d) -> Decoder(g)
    map5 = |de, f, da, db, dc, dd| map(both(both(both(both(da, db), dc), dd), de), |((((a, b), c), d), e)| f(a, b, c, d, e))

    ## In punk `Config.map6 f da db dc dd de dg`.
    map6 : Decoder(g), (a, b, c, d, e, g -> h), Decoder(a), Decoder(b), Decoder(c), Decoder(d), Decoder(e) -> Decoder(h)
    map6 = |dg, f, da, db, dc, dd, de| map(both(both(both(both(both(da, db), dc), dd), de), dg), |(((((a, b), c), d), e), g)| f(a, b, c, d, e, g))

    ## In punk `Config.andThen f decoder`: settings that depend on a setting
    ## read before.
    and_then : Decoder(a), (a -> Decoder(b)) -> Decoder(b)
    and_then = |decoder, f| {
        run: |settings| match (decoder.run)(settings) {
            Err(e) => Err(e)
            Ok(a) => (f(a).run)(settings)
        },
    }

    ## Runs the decoder on these settings, in punk
    ## `Config.decode decoder [("BASE_URL", "https://s.test")]`: for tests of
    ## a decoder. The error has one line per problem.
    decode : List((Str, Str)), Decoder(a) -> Try(a, Str)
    decode = |settings, decoder| match (decoder.run)(settings) {
        Ok(value) => Ok(value)
        Err(problems) => Err(Str.join_with(List.map(problems, describe), "\n"))
    }

    ## The settings as the wiring gave them.
    settings_host! : () => List((Str, Str))
}
