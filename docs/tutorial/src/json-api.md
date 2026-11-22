# A JSON API with Postgres

This page builds a small HTTP API for a todo list. The todos live in
Postgres, requests and responses are JSON:

| Request | Response |
|---|---|
| `GET /todos` | `200`, all todos as a JSON array, by title |
| `POST /todos` with `{"title": "buy milk"}` | `201`, the new todo |
| `GET /todos/<id>` | `200` with the todo, or `404` |
| `PUT /todos/<id>` with `{"title": "buy milk", "done": true}` | `200` with the changed todo, or `404` |
| `DELETE /todos/<id>` | `204`, or `404` |

A todo looks like `{"id": "t8301", "title": "buy milk", "done": false}`, and
every error is `{"error": "what went wrong"}`.

The whole program is
[`examples/todos/Todos.punk`](https://github.com/eelcoh/punk/blob/main/examples/todos/Todos.punk);
the code below is taken from it, and the repository's tests run it against a
real Postgres.

## The header

```elm
app [handle!] { Platform: platform "server", Json: "../../packages/json/main.roc" }

import Platform.Http exposing [Request, Response]
import Platform.Db
import Platform.Random
import Platform.Log
import Json.Decode as D
import Json.Encode as E
import Json.Value
```

A server app gives the `server` platform one function, `handle!`, which gets
a `Request` and returns a `Response`. The `!` says that it does effects: here
it talks to the database, makes random ids and writes to the log. Those are
the only effects it can do, because they are the only modules of the
platform it imports. It cannot open files or make other connections.

`Json` is the JSON package that comes with punk: decoders and encoders in
the style of Elm's `Json.Decode` and `Json.Encode`.

## The table

```elm
{{#include ../../../examples/todos/Todos.punk:table}}
```

A `table` says what a row is (a record type) and which field is the key.
The four lines after it are the table's security policy, and all four are
required: who may read, insert, update and delete rows. This API has no
users, so `everyone` may do everything. With users, a policy is a function
of the user and the row, such as `read fn user, note -> note.owner ==
user.id`, and Postgres itself enforces it as row-level security.

`punk check --schema Todos.punk` writes the table as SQL to `schema.sql`, next
to the app:

```sql
CREATE TABLE todos (
    id text PRIMARY KEY,
    title text NOT NULL,
    done boolean NOT NULL
);
ALTER TABLE todos ENABLE ROW LEVEL SECURITY;
...
```

You don't edit `schema.sql`. When the type changes, `punk check --schema` adds
a new version to it, with a migration you write in punk.

## Queries

```elm
{{#include ../../../examples/todos/Todos.punk:queries}}
```

A query is a pipeline that starts at a table, like a list pipeline in Elm:
`Db.filter`, `Db.sortBy`, `Db.map`, and at the end `Db.all` (a list),
`Db.first` (a `Maybe`), `Db.update` or `Db.delete` (the number of rows
changed). The compiler turns each pipeline into one SQL statement with
parameters, so `findTodo` becomes
`SELECT id, title, done FROM todos WHERE id = $1 LIMIT 1`. There is no SQL
in strings to get wrong, and a field that isn't in the table, or a type that
doesn't match, is a compile error.

A query is a value of type `Db.Query a`. Nothing happens until it runs, with
`Db.run!`.

## JSON

```elm
{{#include ../../../examples/todos/Todos.punk:json}}
```

JSON in and out is written by hand, as in Elm. A decoder says which fields it
needs and what type they have: `change` needs a string `title` and a bool
`done`, and fails with a clear message when the body has something else. An
encoder builds the JSON from a value. Nothing is derived from the type, so the
JSON format of the API is right there in the code, and changing a type cannot
change it by accident.

## Routes

```elm
{{#include ../../../examples/todos/Todos.punk:routes}}
```

`route!` matches on the method and the parts of the path, and gives a
`Result`: the response, or an error from the database. `handle!` turns the
errors into responses, so a client never sees a crash. `_` in the type
`Result Response _` lets the compiler work out the error type: here the
union of what the database can return, `PgErr` and `RowErr`. Because `case`
must cover every case, forgetting one of them is a compile error.

## Handlers

```elm
{{#include ../../../examples/todos/Todos.punk:handlers}}
```

`try` runs an effect that returns a `Result`, and returns early with the
error when it fails, as `?` does in Rust. So `try Db.run! allTodos` is the
list of todos, or `route!` stops there with the database's error.

## Helpers

```elm
{{#include ../../../examples/todos/Todos.punk:helpers}}
```

## Run it

The platform's host is a Rust program that serves HTTP, connects to
Postgres and calls `handle!` for each request. For this example it is
[`examples/todos/server`](https://github.com/eelcoh/punk/tree/main/examples/todos/server).
At startup it applies `schema.sql` as the owner of the table, and then
connects as a role that has to keep to the policies:

```sh
cd examples/todos/server
DATABASE_OWNER_URL=postgres://owner:secret@localhost/todos \
DATABASE_URL=postgres://todos_app:secret@localhost/todos \
cargo run --release
```

```sh
curl -s localhost:8080/todos -d '{"title": "buy milk"}'
# {"id":"t5049...","title":"buy milk","done":false}
curl -s localhost:8080/todos
# [{"id":"t5049...","title":"buy milk","done":false}]
```

Its tests (`cargo test` in the same folder, with `PUNK_TEST_POSTGRES` set to
a test database) send the requests from the table at the top of this page.

## Next

- [`examples/notes`](https://github.com/eelcoh/punk/tree/main/examples/notes):
  users, policies per user, joins and transactions.
- [`examples/shortener-postgres`](https://github.com/eelcoh/punk/tree/main/examples/shortener-postgres):
  configuration, a clock and expiring links.
