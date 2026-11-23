#!/bin/sh
# `punk new` (tools/new/new.sh): makes an app per platform, checks each with
# the compiler of this repository, runs the cli app, and runs the tests of
# the server (on PUNK_TEST_POSTGRES, when set) and the terminal app. Run from
# the repo root after `zig build` and `sh test/setup.sh`.
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

sh "$root/tools/new/new.sh" server my-notes
"$punk" check my-notes/MyNotes.punk
grep -q '^FROM rust:[0-9.]*-slim-trixie AS build$' my-notes/Dockerfile
grep -q '"/my-notes"' my-notes/Dockerfile
test -f my-notes/.dockerignore
(cd my-notes/server && PUNK="$punk" cargo test)

sh "$root/tools/new/new.sh" tui counter
"$punk" check counter/Counter.punk
(cd counter/tui && PUNK="$punk" cargo test)
echo "new.sh: the apps of punk new check, and their tests pass"
