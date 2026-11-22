# @app@

A JSON API in [punk-lang](https://github.com/eelcoh/punk), with Postgres.
`@App@.punk` is the app, `schema.sql` its tables (made by `punk check --schema`),
and `server/` the Rust program that runs it.

## Run it

You need Rust (<https://rustup.rs>) and Postgres. On a Mac with Homebrew:

```
brew install postgresql@17
brew services start postgresql@17
export PATH="$(brew --prefix postgresql@17)/bin:$PATH"
createdb @app@               # the database
createuser @crate@_app       # the role the app connects as
cd server
cargo run
```

and in another terminal:

```
curl localhost:8080/hello
```

Without settings the server uses the database `@app@` on this computer, makes the tables as
you, and connects as `@crate@_app`. Elsewhere, set `DATABASE_OWNER_URL` (the role that owns the
tables), `DATABASE_URL` (the app's role, not a superuser) and `PORT`.

## In a container

`Dockerfile` builds the server as one static program on an image with nothing else in it
(distroless, as a user without rights). The database runs elsewhere: give the container its
URLs.

```
docker build -t @app@ .
docker run --rm -p 8080:8080 \
    -e DATABASE_OWNER_URL='postgres://owner:...@db.example.com/@app@' \
    -e DATABASE_URL='postgres://@crate@_app:...@db.example.com/@app@' \
    @app@
```

A database that isn't on the same computer gets TLS, and its certificate is checked against
the authorities browsers trust. Add `sslrootcert=/certs/ca.pem` to the URLs (and
`-v "$PWD/certs:/certs:ro"`) for a database with a certificate authority of its own, or
`sslmode=disable` for one on a private network without TLS.

## Change it

```
punk fmt @App@.punk
punk check @App@.punk                # fix the first problem, repeat
punk check --schema @App@.punk       # after changing a table: a new version in schema.sql
cd server && cargo test              # the tests in server/tests (with PUNK_TEST_POSTGRES)
```

The server applies new versions of `schema.sql` when it starts: that is the migration.

`AGENTS.md` is for coding agents, and `.claude/skills/` has punk's skills.
