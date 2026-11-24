# As a unikernel

A container still has an operating system under it: a Linux kernel with
hundreds of system calls, file systems, users and processes, of which the
server uses a handful. A **unikernel** leaves all of that out. The app, its
server and a small kernel ([Hermit](https://hermit-os.org)) are linked into
one image of a few MB, which boots as a virtual machine and does nothing else.
There is no shell, no other program and no file in it: the only way in is the
port.

The notes API runs that way without changes to `Notes.punk`: only the
wiring in Rust is different.

## What you need

punk-lang v0.1.3 or later (`punk version`; to update, run the installer of
[Install punk](install.md) again), and QEMU, which runs the virtual machine:

```sh
brew install qemu
```

Hermit runs on x86-64, so on a Mac with Apple silicon QEMU emulates an Intel
processor. That's slower than a real one, but plenty for trying it out.

The rest comes by itself: the first time, the script below adds Rust's
standard library for Hermit to the Rust the server uses (from
[hermit-os/rust-std-hermit](https://github.com/hermit-os/rust-std-hermit)).

An app made with an older `punk new` has no `unikernel.sh`: make a new app
next to it (`punk new server notes2`) and copy its `server/unikernel.sh`,
`server/src/hermit.rs`, `server/build.rs` and the parts of
`server/Cargo.toml` that mention Hermit.

## Boot it

Postgres is still running on your Mac from the chapters before. In the
folder of the server:

```sh
cd server
sh unikernel.sh
```

(with `API_KEY` still set from [Settings and a secret](settings.md): the
script gives the app the settings that `SETTINGS` in `src/lib.rs` names).
The first build takes a few minutes: it also compiles the kernel. Then QEMU
starts, the loader and the kernel say a few things, and then the app:

```
INFO notes::hermit: applied version 1 of schema.sql
INFO notes::hermit: applied version 2 of schema.sql
INFO notes::hermit: notes listens on http://0.0.0.0:8080
```

(or nothing about `schema.sql`, if the database already has both versions).
From another terminal, the same API as before:

```sh
curl -s localhost:8080/notes -H "Authorization: Bearer $API_KEY" \
    -d '{"title": "Unikernel", "body": "it boots"}'
curl -s localhost:8080/notes
```

The notes you made with `cargo run` are there too: it is the same database.
Stop the virtual machine with Ctrl-C.

The image itself is `target/x86_64-unknown-hermit/release/notes`, about 4 MB.

## How it reaches the database

The virtual machine has a network of its own, which QEMU connects to your
Mac: inside it, your Mac is `10.0.2.2`. So without settings `unikernel.sh`
gives the app these URLs:

```
DATABASE_URL=postgres://notes_app@10.0.2.2/notes?sslmode=disable
DATABASE_OWNER_URL=postgres://<you>@10.0.2.2/notes?sslmode=disable
```

To Postgres the connections come from your Mac itself, so it lets them in
as it does for `cargo run`. `sslmode=disable` is needed here: `10.0.2.2` is
not `localhost` to the server, so without it the server would ask for TLS
(see [In a container](container.md#tls)), and the traffic never leaves your
Mac anyway.

A unikernel has no environment variables of its own, so `unikernel.sh`
passes them on the kernel's command line (`env=DATABASE_URL=...`, and
`env=API_KEY=...` for the app's own settings), and `src/hermit.rs` reads them
with `std::env::var`, as `main.rs` does. A value there can't contain a space. Set
`DATABASE_URL` and `DATABASE_OWNER_URL` yourself for another database:

```sh
DATABASE_OWNER_URL='postgres://notes_owner:...@203.0.113.7/notes' \
DATABASE_URL='postgres://notes_app:...@203.0.113.7/notes' \
    sh unikernel.sh
```

TLS works as in the container, with one difference: a unikernel has no files,
so `sslrootcert=<file>` can't be used, and the database's certificate has to
be signed by an authority browsers trust. Give an IP address in the URL for
now: names of hosts go through Hermit's DNS, which isn't tested yet.

## What is different from the container

`src/main.rs` (on your Mac and in the container) and `src/hermit.rs` (in
the unikernel) give the app the same capabilities: the database, the clock,
random numbers and the log. What differs is around it:

- **No lockdown.** On Linux, `main.rs` locks the process to its ports with
  Landlock and seccomp. A unikernel has nothing to lock: no other files, no
  other programs, no other users.
- **One app per machine.** The image boots as a whole virtual machine, so it
  runs where virtual machines run, not where containers run.
- **Tests stay the same.** `cargo test` and `punk test` run on your Mac; the
  unikernel is only another way to run the same server.

Under the hood the Postgres driver needs a few small changes to run on
Hermit; punk keeps those in
[`platforms/server/hermit`](https://github.com/eelcoh/punk/tree/main/platforms/server/hermit),
and `server/Cargo.toml` uses them (`[patch.crates-io]`). Elsewhere they are
the same as on crates.io.

Next: [next steps](next.md).
