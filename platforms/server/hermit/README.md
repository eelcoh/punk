# Postgres on Hermit: patched crates

A server on punk's server platform with Postgres (`punk-server-postgres`)
also runs as a [Hermit](https://hermit-os.org) unikernel. The Postgres
driver (`postgres`, `tokio-postgres`) and TLS (`rustls` with `ring`) need four
crates that don't build for, or don't work on, `x86_64-unknown-hermit` as
they are on crates.io. `vendor/` has those four, each as on crates.io with
only what Hermit needs added. On other targets they are the same as on
crates.io.

An app's crate uses them with `[patch.crates-io]` (`punk new server` writes
that section):

```toml
[patch.crates-io]
ring = { path = ".../platforms/server/hermit/vendor/ring" }
socket2 = { path = ".../platforms/server/hermit/vendor/socket2" }
tokio = { path = ".../platforms/server/hermit/vendor/tokio" }
whoami = { path = ".../platforms/server/hermit/vendor/whoami" }
```

| crate   | version | what changed for Hermit |
|---------|---------|-------------------------|
| ring    | 0.17.14 | `build.rs`: x86-64 Hermit gets the ELF assembly, as Linux (same ABI); its C is built without `-fstack-protector` (Hermit has no `__stack_chk_fail`) |
| socket2 | 0.6.5   | Hermit is built like WASI preview 2: the `sys/unix.rs` code on Hermit's `libc`, without the options Hermit doesn't have; the types and constants its `libc` lacks are defined in `sys/unix.rs` (the kernel answers them with EINVAL); `fcntl` with its third argument |
| tokio   | 1.54.1  | the `std::os::fd` traits for `TcpStream`, `TcpListener` and `TcpSocket` on Hermit; `libc` on Hermit; a connect checks the peer instead of `SO_ERROR`, which Hermit's kernel doesn't have |
| whoami  | 2.1.3   | `OsStringExt` from `std::os::hermit` |

Besides these, `punk-server-postgres` turns TCP keepalive off on Hermit:
the kernel only knows `TCP_NODELAY`, and asking for keepalive would fail the
connection.

To see the changes: `diff -r` a crate here against the same version from
crates.io (`~/.cargo/registry/src/*/<crate>-<version>`).

## Updating

When the lock file of an app wants a newer version of one of these, copy the
new version from crates.io over the old one and apply the same changes; then
`sh test/hermit.sh` (the tutorial's notes API, booted in QEMU against
Postgres) and the server tests. Each change is small enough to offer
upstream; once a crate supports Hermit there, it leaves `vendor/`.

## What doesn't work yet on Hermit

- `sslrootcert`: a unikernel has no files, so a database's certificate has to
  be signed by an authority of Mozilla's list (`webpki-roots`), or the
  connection has no TLS (`sslmode=disable`, on a private network).
- Names of hosts are resolved with Hermit's DNS (the `dns` feature of the
  kernel), which isn't tested yet: an IP address in the URL always works.
- Mongo: its driver needs more of tokio than this.
