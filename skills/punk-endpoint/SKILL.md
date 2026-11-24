---
name: punk-endpoint
description: Use when adding or changing an HTTP endpoint in a punk server app (platform "server"). Covers the route, decoding the JSON body, the query, the response, and the Rust spec test.
---

# Add an endpoint to a punk server app

A server app has one entry point, `handle! : Settings -> Request => Response`
(the app's settings, typed by its `Config` decoder, and the request), which
usually calls a `route! : Request => Result Response _` that does a `case`
on `toRoute req`: the app's own `type Route`, one tag per endpoint, read
from `(Http.method req, Http.segments req)`. Models to copy from are
`examples/todos/Todos.punk` (a JSON API) and `examples/notes/Notes.punk`
(users, policies, transactions).

## Steps

1. **Route.** Add a tag to `type Route` (`MarkDone Str`), a branch to
   `toRoute` before the catch-all `_ ->`:
   `(Post, ["todos", id, "done"]) -> Just (MarkDone id)`, and a branch to
   `route!`: `Just (MarkDone id) -> markDone! id` (the compiler says so if
   you forget it). A path part bound to a name (`id`) is a parameter. Add an
   `expect` next to `toRoute`:
   `expect toRoute (Http.request Post "/todos/t1/done") == Just (MarkDone "t1")`,
   and run `punk test App.punk`.
2. **Input.** For a JSON body, write a decoder next to the others, in Elm
   style (`D.field "title" D.string`, `D.map2 ...`). Decode with
   `D.decodeString decoder text`, and answer `400` with the decoder's error
   (`D.errorToString`) when it fails. Never trust a field you didn't decode.
3. **Database.** Write the query as a top-level `Db.Query` value or function
   (a pipeline from the table), and run it in the handler with
   `try Db.run! query`, or `try Db.runAs! user query` when the table's
   policies look at the user. Changes give the number of rows: `0` usually
   means `404`.
4. **Output.** Build the JSON with an encoder (`E.object [...]`) and a
   response record:
   `{ status = 200, headers = [("content-type", "application/json")], body = Str.toUtf8 (E.encode 0 value) }`.
   Use the app's existing helpers when it has them.
5. **Errors.** Database errors go up as the `Err` of `route!`, and `handle!`
   turns them into a 5xx. Don't catch them in the handler.
6. **Check.** Run the skill `punk-check-loop` until it is clean.
7. **Test.** Add a test to the app's Rust crate (`server/tests/spec.rs`)
   that sends the request and checks the status and the exact body. Run
   `cargo test --locked` in `server/`. Database tests need
   `PUNK_TEST_POSTGRES` (or `PUNK_TEST_MONGO`).
8. Update the list of endpoints in the app's doc comment and in
   `server/src/lib.rs`.

## Rules

- An effect (`!`) runs only in `handle!` and the functions it calls, never
  in a query or a decoder.
- The platform's modules an app imports are all it can do. Don't import one
  you don't need.
- Keep SQL out of strings. Use the query language, and `Sql.query` with
  parameters only for what it can't do (see `llms.txt`).
