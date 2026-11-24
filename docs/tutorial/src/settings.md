# Settings and a secret

Anyone who can reach the server can now add and remove notes. Let's keep
reading open, but ask for a key to write: a client sends
`Authorization: Bearer <key>` with a `POST` or a `DELETE`, and without the
right key it gets a `401`.

The key mustn't be in the code. It is a **setting**: the server gets it from
its environment when it starts, so each place the server runs (your Mac, a
container, a unikernel) can have a key of its own. And it is a **secret**: it
must never end up in a log, an error message or a response.

The app after this page is
[`examples/tutorial/notes/Notes.punk`](https://github.com/eelcoh/punk/blob/main/examples/tutorial/notes/Notes.punk).

## The settings

Until now `main` said that the app needs no settings. Replace it, and the
`Settings` under it:

```elm
import Platform.Secret
```

```elm
{{#include ../../../examples/tutorial/notes/Notes.punk:settings}}
```

`Settings` is the type of the app's settings, and `settings` is a decoder
for them, in the style of Elm's `Json.Decode`: `Config.secret "API_KEY"`
reads the setting `API_KEY` as a `Secret`, and `Config.map` makes the
record. Other settings are `Config.text`, `Config.int` and `Config.bool`,
and `Config.withDefault` gives the value for one that is missing:

```elm
Config.int "PAGE_SIZE" |> Config.withDefault 50
```

With more settings, `Config.map2` to `Config.map6` combine them, as
`D.map2` does for JSON.

The server runs the decoder once, when it starts, before the first request.
A setting that is missing, or one that doesn't fit (`PAGE_SIZE=fifty`),
stops the server with a message for each one. So the app never runs with
half its settings, and `handle!` gets them as a value of its own type:
`config.apiKey` is a `Secret`, not a `Maybe` and not text that might be
empty.

## A secret stays secret

A `Secret` can't be turned into text. Try to log it:

```elm
    Log.info! "key: ${config.apiKey}"
```

and `punk check` says no:

```
── ✗ type mismatch ──────────────────────────────── Notes.punk:146:23

Log.info! "key: ${config.apiKey}"
                  ^^^^^^^^^^^^^

It has the type:

    Secret

But you are trying to use it as:

    Str
```

There is no function from `Secret` to `Str` at all. `Str.inspect` and `dbg`
show `<secret>`, and the server's message about a missing or empty setting
names it without its value. What the app *can* do with a secret is compare
a value with it.

## Check the key

`handle!` now passes the settings on to `route!` (in the app it is called
`config`, because `settings` is the decoder), and the two routes that write
ask first:

```elm
{{#include ../../../examples/tutorial/notes/Notes.punk:routes}}
```

`hasKey` reads the header with `Http.header`, and `Secret.matches` compares
the rest with the key:

```elm
{{#include ../../../examples/tutorial/notes/Notes.punk:has-key}}
```

`Secret.matches` looks at every byte, also after the first one that differs,
so the time it takes tells an attacker nothing about how much of a guess was
right.

`hasKey` does no effects, so the `expect`s test it with a key of their own:
`Secret.fromText` makes a secret in the code, which is fine for a test and
nowhere else. The last one tests the decoder itself: `Config.decode` runs
it on settings you give it.

```sh
punk test Notes.punk
```

## The server's side

The app says which settings it needs, but the server decides which ones it
gets: only the environment variables named in `SETTINGS`, in
`server/src/lib.rs`. Add the key:

```rust
pub const SETTINGS: &[&str] = &["API_KEY"];
```

This list is the one place to see what the app can read from its
environment; `DATABASE_URL` and the database password aren't on it, so the
app can't read them, whatever its code does. An agent that adds a setting to
`Notes.punk` has to add it here too, and you see that in the change.

## Run it

Start the server without a key:

```sh
cd server
cargo run
# notes: the settings don't fit the app: API_KEY is missing
```

It doesn't start. Make a key, and keep it out of the code and out of git
(a password manager, or a file that `.gitignore` names):

```sh
export API_KEY=$(openssl rand -hex 32)
cargo run
```

Reading needs nothing, writing needs the key:

```sh
curl -s localhost:8080/notes
curl -s localhost:8080/notes -d '{"title": "Locked", "body": "no key"}'
# {"error":"this needs the API key"}
curl -s localhost:8080/notes -H "Authorization: Bearer $API_KEY" \
    -d '{"title": "Opened", "body": "with the key"}'
```

## Test it

The tutorial's
[spec](https://github.com/eelcoh/punk/blob/main/examples/tutorial/notes/server/tests/spec.rs)
gives the app a key of its own (`Settings::new().set("API_KEY", KEY)`),
sends it with each request that writes, and has two new tests: a write
without the key, with a wrong one or with the key but without `Bearer` is a
`401` and changes nothing, and the app doesn't start without `API_KEY` or
with an empty one. Copy those, then:

```sh
cargo test
git add -A
git commit -m "Notes: writing needs the API key"
```

Next: [in a container](container.md), where the key comes from `docker run`.
