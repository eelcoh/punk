#!/bin/sh
# Tries a packed release as a user would: installs it with install.sh into a
# fresh folder, makes an app per platform with `punk new`, runs the cli app
# and checks the others. Run after package.sh:
#
#     sh tools/release/try.sh dist/punk-v0.1.0-linux-x86_64.tar.gz
set -eu

archive=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
root=$(pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT INT TERM

PUNK_ARCHIVE=$archive PUNK_HOME="$work/punk" PUNK_BIN_DIR="$work/bin" sh "$root/install.sh"
punk="$work/bin/punk"

cd "$work"
"$punk" new cli hello
out=$("$punk" hello/Hello.punk)
[ "$out" = "Hello, world!" ] || { echo "try.sh: hello says \"$out\""; exit 1; }
"$punk" test hello/Hello.punk

"$punk" new server my-notes
"$punk" check my-notes/MyNotes.punk
grep -q 'punk-server = { git = "https://github.com/eelcoh/punk", tag = "' my-notes/server/Cargo.toml
test -f my-notes/.claude/skills/punk-check-loop/SKILL.md
test -f my-notes/AGENTS.md

"$punk" new tui counter
"$punk" check counter/Counter.punk
echo "try.sh: $(basename "$archive") installs, and its apps check"
