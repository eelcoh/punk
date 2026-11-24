# A new app

Go to the folder where you keep your code, and make a server app called
`notes`:

```sh
punk new server notes
cd notes
```

`punk new` makes the folder `notes`, puts a working app in it, and makes it
a git repository:

```text
notes/
├── Notes.punk          the app: this is where you write punk
├── schema.sql          the database tables, written by punk (empty for now)
├── server/             the Rust program that runs the app
│   ├── Cargo.toml
│   ├── build.rs        compiles Notes.punk with `punk build`
│   ├── src/lib.rs      which capabilities the app gets
│   ├── src/main.rs     the settings: database, port
│   └── tests/spec.rs   tests that send HTTP requests to the app
├── Dockerfile          the app as a container image
├── AGENTS.md           instructions for coding agents
├── .claude/skills/     punk's skills for agents
├── README.md
└── .gitignore
```

You write `Notes.punk`, and you rarely touch `server/`. Open the folder in
VS Code:

```sh
code .
```

## The app

`Notes.punk` starts as a hello world:

```elm
app [Settings, main] { Platform: platform "server", Json: "json" }

import Platform.Http exposing [Request, Response]
import Platform.Config
import Platform.Log
import Json.Encode as E
import Json.Value

main =
    { settings = Config.succeed {}, handle! = handle! }

-- The app needs no settings.
type alias Settings =
    {}

handle! : Settings -> Request => Response
handle! = fn _, req ->
    Log.info! "${req.method} ${req.path}"
    case toRoute req of
        Just Hello -> json 200 (E.object [("hello", E.string "world")])
        Nothing -> problemJson 404 "not found"

-- What a request can ask for, one tag per route.
type Route
    = Hello

-- The route of a request, `Nothing` when there is no such route.
toRoute : Request -> Maybe Route
toRoute = fn req ->
    case (Http.method req, Http.segments req) of
        (Get, ["hello"]) -> Just Hello
        _ -> Nothing

expect toRoute (Http.request Get "/hello") == Just Hello

expect toRoute (Http.request Post "/hello") == Nothing
```

The first line says that this is an app for the `server` platform, that it
gives the platform its `Settings` and `main`, and that it uses the `json`
package that comes with punk. `main` holds two things: `settings`, which
says what the app needs from the server's settings (nothing yet:
`Config.succeed {}`, more on that in [Settings and a secret](settings.md)),
and `handle!`, which the server calls for each request, with the settings
and the request. The `!` says that it does effects: here it only writes to
the log.

`handle!` doesn't look at the text of the path itself. `toRoute` turns the
request into a `Route`, a type of your own with one tag per thing a client
can ask for, and `handle!` does a `case` on that. `Http.method` gives the
method as a tag (`Get`, `Post`, `Put`, `Delete`, ...), and `Http.segments`
the parts of the path (`/hello` is `["hello"]`). Because `case` must cover
every tag, a route you add to `Route` but forget in `handle!` is a compile
error.

`toRoute` does no effects, so you can test it right where it is: each
`expect` is a test, and `punk test Notes.punk` runs them.
`Http.request Get "/hello"` makes a request to try it on.

## Run it

The server needs a database, even though the app doesn't use one yet. Make
the database `notes`, and a role `notes_app` for the app to connect as:

```sh
createdb notes
createuser notes_app
```

The app never connects as you. Your role owns the tables, and makes them
when the server starts; `notes_app` may only use them, and only as far as
the tables' policies allow. The server won't connect the app as a superuser,
because the policies don't hold for one.

Now build and start the server:

```sh
cd server
cargo run
```

The first time this takes a few minutes: cargo downloads Rust and the
server's libraries, and `build.rs` runs `punk build` on `Notes.punk`. After
that it is quick. When it says `notes listens on http://127.0.0.1:8080`, try
it from another terminal:

```sh
curl localhost:8080/hello
# {"hello":"world"}
curl localhost:8080/bye
# {"error":"not found"}
```

Stop the server with Ctrl-C.

## Check, format, commit

Three commands do most of the work while you write punk:

```sh
punk check Notes.punk    # does it compile? the problems, with what to do
punk fmt Notes.punk      # the one layout (VS Code does this when you save)
punk test Notes.punk     # the expects in Notes.punk
cargo test               # in server/: the tests in server/tests/spec.rs
```

The tests need a database of their own to make tables in. Give them yours:

```sh
export PUNK_TEST_POSTGRES=postgres://localhost/notes
```

Without it the tests say that they skip, and pass.

The new app is a git repository with every file added. Make the first
commit:

```sh
git commit -m "A new punk server app"
```

## For agents

`AGENTS.md` tells a coding agent (Claude Code, Codex and others) what this
app is, which commands to run, and the rules: Elm style, no loops, formatted
code, the tables are the truth. `.claude/skills/` has punk's skills, one per
kind of task: the check loop, a new endpoint, a migration. The full
language reference is in `~/.punk/current/share/punk/llms.txt`.

Next: [a JSON API for notes](notes-api.md).
