#!/bin/sh
# `punk new` (tools/new/new.sh): checks the generated apps and a package
# with the compiler of this repository, and runs their tests. The server
# tests use PUNK_TEST_POSTGRES when set. Run from the repo root after
# `zig build` and `sh test/setup.sh`.
set -eu

root=$(pwd)
punk="$root/zig-out/bin/punk"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT INT TERM

cd "$work"
sh "$root/tools/new/new.sh" cli hello
out=$("$punk" hello/Hello.punk)
[ "$out" = "Hello, world!" ] || { echo "new.sh: hello says \"$out\""; exit 1; }
"$punk" test hello/Hello.punk

sh "$root/tools/new/new.sh" package my-library checkout/my-library
(
    cd checkout/my-library
    "$punk" fmt --check Greeting.punk test/PackageTest.punk
    "$punk" check --json test/PackageTest.punk
    "$punk" test test/PackageTest.punk
)
cat > Consumer.punk <<'EOF'
app [main!] { Platform: platform "cli", Library: "checkout/my-library/main.roc" }

import Library.Greeting
import Platform.Stdout

main! : () => {}
main! = fn () ->
    Stdout.line! (Greeting.forName "world")
EOF
out=$("$punk" Consumer.punk)
[ "$out" = "Hello, world!" ] || { echo "new.sh: the package consumer says \"$out\""; exit 1; }

sh "$root/tools/new/new.sh" server my-notes
"$punk" check my-notes/MyNotes.punk
"$punk" test my-notes/MyNotes.punk
grep -q '^FROM rust:[0-9.]*-slim-trixie AS build$' my-notes/Dockerfile
grep -q '"/my-notes"' my-notes/Dockerfile
test -f my-notes/.dockerignore
test -f my-notes/server/src/hermit.rs
grep -qF 'release/my-notes"' my-notes/server/unikernel.sh
grep -qF 'pub const SETTINGS: &[&str] = &[];' my-notes/server/src/lib.rs
(cd my-notes/server && PUNK="$punk" cargo test)

sh "$root/tools/new/new.sh" tui counter
"$punk" check counter/Counter.punk
(cd counter/tui && PUNK="$punk" cargo test)
echo "new.sh: the apps and package of punk new check, and their tests pass"
