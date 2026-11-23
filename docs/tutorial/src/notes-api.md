# A JSON API for notes

Now the real app: notes, stored in Postgres, with JSON in and out.

| Request | Response |
|---|---|
| `GET /notes` | `200`, all notes as a JSON array, by title |
| `POST /notes` with `{"title": "Shopping", "body": "milk, bread"}` | `201`, the new note |
| `GET /notes/<id>` | `200` with the note, or `404` |
| `DELETE /notes/<id>` | `204`, or `404` |

A note looks like `{"id": "n8301...", "title": "Shopping", "body": "milk, bread"}`,
and every error is `{"error": "what went wrong"}`.

Replace everything in `Notes.punk` with the parts below, in order. The whole
file is
[`examples/tutorial/notes-v1/Notes.punk`](https://github.com/eelcoh/punk/blob/main/examples/tutorial/notes-v1/Notes.punk),
if you'd rather copy it at once.

## The header

```elm
app [handle!] { Platform: platform "server", Json: "json" }

import Platform.Http exposing [Request, Response]
import Platform.Db
import Platform.Random
import Platform.Log
import Json.Decode as D
import Json.Encode as E
import Json.Value
```

Each `import` of `Platform` is a capability: the database, random numbers
(for the ids), the log. They are the only effects the app can do. It cannot
open files or make other connections, because the platform gives it no way
to.

## The table

```elm
{{#include ../../../examples/tutorial/notes-v1/Notes.punk:table}}
```

A `table` says what a row is (a record type) and which field is the key.
The four lines after it are the table's security policy, and all four are
required: who may read, insert, update and delete rows. This API has no
users yet, so `everyone` may do everything. With users, a policy is a
function of the user and the row, such as `read fn user, note -> note.owner
== user.id`, and Postgres itself enforces it as row-level security.

Run `punk check` now:

```sh
punk check Notes.punk
```

It stops you with `P405`: the tables in the program differ from
`schema.sql`. The program is the truth, and `schema.sql` is its history,
which punk writes:

```sh
punk check --schema Notes.punk
```

`schema.sql` now has version 1: the table, with row-level security and its
policies.

```sql
-- punk version 1
-- table notes : id Str key, title Str, body Str
...
CREATE TABLE notes (
    id text PRIMARY KEY,
    title text NOT NULL,
    body text NOT NULL
);
ALTER TABLE notes ENABLE ROW LEVEL SECURITY;
...
```

Commit it with the program. The server applies each version once, when it
starts.

## Queries

```elm
{{#include ../../../examples/tutorial/notes-v1/Notes.punk:queries}}
```

A query is a pipeline that starts at a table, like a list pipeline in Elm:
`Db.filter`, `Db.sortBy`, `Db.map`, and at the end `Db.all` (a list),
`Db.first` (a `Maybe`), `Db.update` or `Db.delete` (the number of rows
changed). The compiler turns each pipeline into one SQL statement with
parameters, so `findNote` becomes
`SELECT id, title, body FROM notes WHERE id = $1 LIMIT 1`. There is no SQL in
strings to get wrong, and a field that isn't in the table, or a type that
doesn't match, is a compile error.

A query is a value of type `Db.Query a`. Nothing happens until it runs, with
`Db.run!`.

## JSON

```elm
{{#include ../../../examples/tutorial/notes-v1/Notes.punk:json}}
```

JSON in and out is written by hand, as in Elm. A decoder says which fields it
needs and what type they have: `newNote` needs a string `title` and a string
`body`, and fails with a clear message when the body of the request has
something else. An encoder builds the JSON from a value. Nothing is derived
from the type, so the JSON of the API is right there in the code, and
changing the type cannot change it by accident.

## Routes

```elm
{{#include ../../../examples/tutorial/notes-v1/Notes.punk:route-type}}
```

A `Route` is what a client can ask for, one tag per row of the table above.
`ShowNote Str` carries the id from the path. `toRoute` reads it from the
method and the parts of the path: a list pattern like `["notes", id]`
matches a path of exactly two parts, the first `notes`, and names the
second `id`. A method or path the API doesn't know is `Nothing`.

The `expect`s are tests, next to the code they test. Run them:

```sh
punk test Notes.punk
```

```elm
{{#include ../../../examples/tutorial/notes-v1/Notes.punk:routes}}
```

`route!` does a `case` on the route, and gives a `Result`: the response, or
an error from the database. Because `case` must cover every tag, adding a
route to `Route` without handling it here is a compile error.
`handle!` turns the errors into responses, so a client never sees a crash.
The `_` in `Result Response _` lets the compiler work out the error type:
here what the database can return, `PgErr` and `RowErr`. Forgetting one of
them is a compile error too.

## Handlers

```elm
{{#include ../../../examples/tutorial/notes-v1/Notes.punk:handlers}}
```

`try` runs an effect that returns a `Result`, and returns early with the
error when it fails, like `?` in Rust. So `try Db.run! allNotes` is the list
of notes, or `route!` stops there with the database's error.

## Helpers

```elm
{{#include ../../../examples/tutorial/notes-v1/Notes.punk:helpers}}
```

## Run it

```sh
punk check Notes.punk     # no problems
cd server
cargo run
```

The server makes the table (version 1 of `schema.sql`) as you, and then
connects as `notes_app`. In another terminal:

```sh
curl -s localhost:8080/notes -d '{"title": "Shopping", "body": "milk, bread"}'
# {"id":"n5049...","title":"Shopping","body":"milk, bread"}
curl -s localhost:8080/notes
# [{"id":"n5049...","title":"Shopping","body":"milk, bread"}]
curl -s localhost:8080/notes -d '{"title": "no body"}'
# {"error":"json: Expecting an OBJECT with a field named `body`, but got {\"title\":\"no body\"}"}
```

`psql notes` shows the same row: `SELECT * FROM notes;`.

Commit:

```sh
git add -A
git commit -m "Notes: a JSON API on Postgres"
```

Next: [a migration](migration.md).
