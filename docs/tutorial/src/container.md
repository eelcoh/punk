# In a container

The notes API runs on your Mac. On a server it runs as a container, and the
database runs elsewhere: a managed Postgres, a machine of its own, or a
container of its own. The app's container holds only the app.

## The Dockerfile

`punk new server` made a `Dockerfile` next to `Notes.punk`. It builds in
two steps:

1. **The build**, on an image with Rust: it installs punk-lang (the release
   of your `punk`, checked against its checksums) and runs `cargo build`
   for musl, so the result is one static program with the app in it.
2. **The image**: that program, on
   [distroless](https://github.com/GoogleContainerTools/distroless)'s
   `static` image, which has nothing else: no shell, no package manager.
   It runs as a user without rights, and listens on port 8080 of every
   address of the container (`HOST=0.0.0.0`).

Build it (with [Docker Desktop](https://www.docker.com/products/docker-desktop/)
on a Mac, or any Docker):

```sh
docker build -t notes .
```

The first time takes a few minutes, as with `cargo run`. The image is about
11 MB.

An app made with an older `punk new` has no `Dockerfile`: make a new app
next to it (`punk new server notes2`) and copy its `Dockerfile` and
`.dockerignore`.

## A database to try it with

To try it, start a Postgres in a container of its own, on a network with a
name, so that the app's container can reach it as `notes-db`:

```sh
docker network create notes
docker run -d --name notes-db --network notes \
    -e POSTGRES_USER=notes_owner -e POSTGRES_PASSWORD=owner-secret -e POSTGRES_DB=notes \
    postgres:17
docker exec notes-db psql -U notes_owner -d notes \
    -c "CREATE ROLE notes_app LOGIN PASSWORD 'app-secret'"
```

As on your Mac there are two roles: `notes_owner` owns the tables and makes
them when the server starts, and `notes_app` is the role the app connects
as, which only gets to use them, as far as the policies allow.

## Run it

The server reads the two URLs from the environment:

```sh
docker run --rm --name notes --network notes -p 8080:8080 \
    -e DATABASE_OWNER_URL='postgres://notes_owner:owner-secret@notes-db/notes?sslmode=disable' \
    -e DATABASE_URL='postgres://notes_app:app-secret@notes-db/notes?sslmode=disable' \
    notes
```

It applies `schema.sql` (both versions, the first time) and says that it
listens. From another terminal:

```sh
curl -s localhost:8080/notes -d '{"title": "Shopping", "body": "milk, bread"}'
curl -s localhost:8080/notes
```

Stop it with Ctrl-C; the notes stay in `notes-db`.

## TLS

What is `sslmode=disable` doing there? A database that isn't on the same
computer gets TLS: without `sslmode`, the server refuses to talk to
`notes-db` without it, because the passwords and the notes would cross the
network as plain text. The Postgres container has no TLS, and the two
containers share a private network, so the URLs say that's fine.

A real database has TLS, and then the server checks its certificate: that
it is for the host name in the URL, and signed by an authority it trusts.
Those are the authorities browsers trust, so for most managed databases
nothing needs to be added:

```sh
-e DATABASE_URL='postgres://notes_app:...@db.example.com/notes'
```

Some give their own authority, as a file to download (Amazon RDS, Google
Cloud SQL). Put it in a folder, give that folder to the container, and name
the file in the URLs:

```sh
docker run --rm -p 8080:8080 \
    -v "$PWD/certs:/certs:ro" \
    -e DATABASE_OWNER_URL='postgres://notes_owner:...@db.example.com/notes?sslrootcert=/certs/ca.pem' \
    -e DATABASE_URL='postgres://notes_app:...@db.example.com/notes?sslrootcert=/certs/ca.pem' \
    notes
```

`sslmode=verify-full`, as the database's documentation may say, is fine
too: the server always checks as `verify-full` does.

## Passwords

The passwords are in the URLs, so keep them out of the image and out of your
shell's history: put the settings in a file that isn't in git, and give the
file to `docker run`:

```sh
# notes.env
DATABASE_OWNER_URL=postgres://notes_owner:...@db.example.com/notes
DATABASE_URL=postgres://notes_app:...@db.example.com/notes
```

```sh
docker run --rm -p 8080:8080 --env-file notes.env notes
```

Where the container runs (Kubernetes, Fly.io, Cloud Run, ...), the same two
settings come from its secrets.

## What the container can do

Very little, on purpose. The app itself can only do what the platform gives
it: the database, the clock, random numbers, the log. Around it, the
server locks the process to its own port and the database's port (on Linux,
with Landlock and seccomp), the image has no shell to break into, and the
process has no rights in it.

Next: the same server [as a unikernel](unikernel.md).
