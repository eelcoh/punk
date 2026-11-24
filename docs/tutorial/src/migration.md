# A migration

Notes should come newest first, so each note needs the time it was made.
That is a new column, and the notes already in the database need a value
for it: a migration.

In punk you don't write the SQL of a migration. You change the table in the
program, say how an old row becomes a new one, and `punk check --schema`
writes the next version of `schema.sql`. The server applies it when it
starts.

The app after this page and the next is
[`examples/tutorial/notes/Notes.punk`](https://github.com/eelcoh/punk/blob/main/examples/tutorial/notes/Notes.punk).

## Change the table

Add `created` to the row: a `Posix`, a moment in time, as in Elm's `Time`.
Postgres stores it as `timestamptz`:

```elm
{{#include ../../../examples/tutorial/notes/Notes.punk:table}}
```

`punk check Notes.punk` now finds every place that has to change with it.
First it doesn't know `Posix`; import it with the rest of `Time`:

```elm
import Platform.Time exposing [Posix]
```

The note made in `create!` misses `created`, so give it the time, from the
clock:

```elm
            note =
                { id = Uuid.generate! ()
                , title = new.title
                , body = new.body
                , created = Time.now! ()
                }
```

Put it in the JSON, as ISO 8601 text in UTC (`"2026-11-24T12:14:20.123Z"`),
which is what clients of a JSON API expect:

```elm
encodeNote : Note -> Value
encodeNote = fn note ->
    E.object
        [ ("id", E.string (Uuid.toString note.id))
        , ("title", E.string note.title)
        , ("body", E.string note.body)
        , ("created", E.string (Time.toIso8601 note.created))
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
    fn old -> { old | created = Time.millisToPosix 0 }
```

The old notes get `Time.millisToPosix 0`: 1970, older than any note. A migration runs in
the database, like a query, so it can use the old row and constants, but
not the clock. Now write version 2:

```sh
punk check --schema Notes.punk
# ./schema.sql: version 2:
#   notes: created added, to_timestamp(0::double precision / 1000) for the rows there are
```

Read what it added to `schema.sql`:

```sql
-- punk version 2
-- table notes : id Uuid key, title Str, body Str, created Posix
...
ALTER TABLE notes ADD COLUMN created timestamptz;
UPDATE notes SET created = to_timestamp(0::double precision / 1000);
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
# [{"id":"019ab5d0-...","title":"Call Sam","body":"about Friday","created":"2026-11-24T12:20:00.000Z"},
#  {"id":"019ab5c4-...","title":"Shopping","body":"milk, bread","created":"1970-01-01T00:00:00.000Z"}]
```

The note from before the migration is still there, made in 1970, at the
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
adds a note, applies version 2, and reads the note back, made in 1970.
Replace the hello tests in yours with those, then:

```sh
cargo test
git add -A
git commit -m "Notes: newest first"
```

Next: [settings and a secret](settings.md).
