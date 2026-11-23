# A migration

Notes should come newest first, so each note needs the time it was made.
That is a new column, and the notes already in the database need a value
for it: a migration.

In punk you don't write the SQL of a migration. You change the table in the
program, say how an old row becomes a new one, and `punk check --schema`
writes the next version of `schema.sql`. The server applies it when it
starts.

The app after this page is
[`examples/tutorial/notes/Notes.punk`](https://github.com/eelcoh/punk/blob/main/examples/tutorial/notes/Notes.punk).

## Change the table

Add `created` to the row, in milliseconds since 1970 (as Elm's
`Time.posixToMillis`):

```elm
{{#include ../../../examples/tutorial/notes/Notes.punk:table}}
```

`punk check Notes.punk` now finds every place that has to change with it. The
note made in `create!` misses `created`, so give it the time, from the clock:

```elm
import Platform.Clock
```

```elm
            note =
                { id = "n${U64.toStr (Random.u64! ())}"
                , title = new.title
                , body = new.body
                , created = Clock.now! ()
                }
```

Put it in the JSON:

```elm
encodeNote : Note -> Value
encodeNote = fn note ->
    E.object
        [ ("id", E.string note.id)
        , ("title", E.string note.title)
        , ("body", E.string note.body)
        , ("created", E.int note.created)
        ]
```

and sort on it, newest first:

```elm
allNotes : Db.Query (List Note)
allNotes =
    notes
        |> Db.sortByDescending (fn note -> note.created)
        |> Db.all
```

## The migration

`punk check` is left with one problem, `P405`: the table differs from
`schema.sql`. A new column that isn't a `Maybe` needs a value for the rows
that are there, so say how an old note becomes a new one. Add a `migrate`
to `Notes.punk`, right after the `table notes` block (after its `delete`
line), at the start of the line like `table` itself:

```elm
table notes : Note
    key id
    read everyone
    insert everyone
    update everyone
    delete everyone

migrate notes
    fn old -> { old | created = 0 }
```

The old notes get `created = 0`: the oldest possible. A migration runs in
the database, like a query, so it can use the old row and constants, but
not the clock. Now write version 2:

```sh
punk check --schema Notes.punk
# ./schema.sql: version 2:
#   notes: created added, 0 for the rows there are
```

Read what it added to `schema.sql`:

```sql
-- punk version 2
-- table notes : id Str key, title Str, body Str, created Int
...
ALTER TABLE notes ADD COLUMN created bigint;
UPDATE notes SET created = 0;
ALTER TABLE notes ALTER COLUMN created SET NOT NULL;
...
```

The `migrate` has done its job, so remove its two lines again. A `migrate` that is
already in `schema.sql` is itself a `P405`, so `punk check` reminds you.

```sh
punk check Notes.punk     # no problems
```

Never change a version that is in `schema.sql` already. The server keeps a
checksum of each version it applied, and refuses to start when one changed.

## Migrate the database

Start the server again:

```sh
cd server
cargo run
# ... applied version 2 of schema.sql
```

The server saw that the database had version 1, and applied version 2 in
one transaction. Two servers starting at once apply it only once.

```sh
curl -s localhost:8080/notes -d '{"title": "Call Sam", "body": "about Friday"}'
curl -s localhost:8080/notes
# [{"id":"n...","title":"Call Sam","body":"about Friday","created":1795377600000},
#  {"id":"n5049...","title":"Shopping","body":"milk, bread","created":0}]
```

The note from before the migration is still there, with `created` 0, at the
end.

## Test it

First the tests next to the code. The encoder now has `created`, so its
`expect` does too:

```sh
punk test Notes.punk
```

Then the tests of the whole app. `server/tests/spec.rs` sends requests to the app, on a fresh schema of
`PUNK_TEST_POSTGRES` for each test. The tutorial's own
[spec](https://github.com/eelcoh/punk/blob/main/examples/tutorial/notes/server/tests/spec.rs)
has a test for each route, and one for this migration: it applies version 1,
adds a note, applies version 2, and reads the note back with `created` 0.
Replace the hello tests in yours with those, then:

```sh
cargo test
git add -A
git commit -m "Notes: newest first"
```

Next: [in a container](container.md).
