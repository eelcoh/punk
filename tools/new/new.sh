#!/bin/sh
# punk new: a new punk-lang app or package, with its agent instructions.
#
#     punk new <cli|server|tui|package> <name> [<folder>]
#
# Makes <folder> (default: <name>) with:
#
#   <Name>.punk           the app: a hello world for its platform
#   main.roc              (package) the manifest listing public modules
#   Greeting.punk         (package) a starter module
#   test/PackageTest.punk  (package) an app testing the public API
#   schema.sql            (server) the tables, made by `punk check --schema`
#   server/ or tui/       (server, tui) the Rust crate that runs the app:
#                         `cargo run` builds the app with `punk build`
#   AGENTS.md             what an agent needs to know (templates/<kind>)
#   .claude/skills/       the punk skills (skills/), for Claude Code and others
#   Dockerfile            (server) the app as a container image, for a
#                         database that runs elsewhere (.dockerignore too)
#   README.md, .gitignore
#
# and makes it a git repository, when git is there and the folder is not
# already in one.
#
# In an installed punk this is share/punk/new/new.sh, and the crate uses
# the platform of the same version from GitHub (tag v<version>). In the
# punk repository it is tools/new/new.sh, and the crate uses the platform
# in the repository (by path), so you can try a change to it.
set -eu

die() { echo "punk new: $*" >&2; exit 1; }

usage() {
    cat <<'EOF'
usage: punk new <kind> <name> [<folder>]

  <kind>      cli     a command-line program (no Rust needed)
              server  an HTTP server with Postgres (needs Rust: rustup.rs)
              tui     a terminal app (needs Rust: rustup.rs)
              package a library with a public API test (no Rust needed)
  <name>      lowercase letters, digits and -, such as notes or my-notes
  <folder>    where to make it (default: <name>)
EOF
}

case "${1:-}" in
    -h | --help | help) usage; exit 0 ;;
esac
[ $# -ge 2 ] && [ $# -le 3 ] || { usage >&2; exit 2; }
kind=$1 app=$2 folder=${3:-$2}

case "$kind" in
    cli | server | tui | package) ;;
    *) die "unknown kind \"$kind\": give cli, server, tui or package" ;;
esac
case "$app" in
    [a-z]*) ;;
    *) die "the name \"$app\" must start with a lowercase letter" ;;
esac
case "$app" in
    *[!a-z0-9-]*) die "the name \"$app\" may only have lowercase letters, digits and -" ;;
esac
[ ! -e "$folder" ] || die "$folder is already there"

# my-notes: the module MyNotes (MyNotes.punk), the Rust crate my_notes.
Name=$(printf '%s\n' "$app" | awk -F- '{ for (i = 1; i <= NF; i++) printf "%s%s", toupper(substr($i, 1, 1)), substr($i, 2) } END { print "" }')
crate=$(printf '%s\n' "$app" | tr - _)

here=$(cd "$(dirname "$0")" && pwd)
if [ -f "$here/../../build.zig" ]; then
    # The punk repository.
    root=$(cd "$here/../.." && pwd)
    share=$root
    ambit_rev=$(sed -n 's/^ambit-caps = .*rev = "\([0-9a-f]*\)".*/\1/p' "$root/platforms/server/host/Cargo.toml")
    toolchain="$root/platforms/server/host/rust-toolchain.toml"
    punk_dep() { printf 'path = "%s/%s"' "$root" "$1"; }
    # The crate's path dependencies aren't in a container's build: its
    # Dockerfile needs a release (or PUNK_ARCHIVE and a crate on git).
    version=$(git -C "$root" describe --tags --abbrev=0 2>/dev/null || echo v0.0.0)
else
    # An installed punk: <prefix>/share/punk/new/new.sh.
    prefix=$(cd "$here/../../.." && pwd)
    share="$prefix/share/punk"
    version=$(cat "$prefix/VERSION")
    ambit_rev=$(cat "$here/ambit-rev")
    toolchain="$here/rust-toolchain.toml"
    punk_dep() { printf 'git = "https://github.com/eelcoh/punk", tag = "%s"' "$version"; }
fi
[ -n "$ambit_rev" ] || die "can't tell which ambit the platforms use"
rust=$(sed -n 's/^channel = "\(.*\)"/\1/p' "$toolchain")
[ -n "$rust" ] || die "can't tell which Rust the platforms use"
ambit="git = \"https://github.com/eelcoh/ambit\", rev = \"$ambit_rev\""

# Copies a template, filling in the names.
fill() {
    mkdir -p "$(dirname "$2")"
    sed -e "s|@App@|$Name|g" \
        -e "s|@app@|$app|g" \
        -e "s|@crate@|$crate|g" \
        -e "s|@ambit@|$ambit|g" \
        -e "s|@punk:platforms/server/host@|$(punk_dep platforms/server/host)|g" \
        -e "s|@punk:platforms/server/postgres@|$(punk_dep platforms/server/postgres)|g" \
        -e "s|@punk:platforms/tui/host@|$(punk_dep platforms/tui/host)|g" \
        -e "s|@punk:platforms/server/hermit/vendor/ring@|$(punk_dep platforms/server/hermit/vendor/ring)|g" \
        -e "s|@punk:platforms/server/hermit/vendor/socket2@|$(punk_dep platforms/server/hermit/vendor/socket2)|g" \
        -e "s|@punk:platforms/server/hermit/vendor/tokio@|$(punk_dep platforms/server/hermit/vendor/tokio)|g" \
        -e "s|@punk:platforms/server/hermit/vendor/whoami@|$(punk_dep platforms/server/hermit/vendor/whoami)|g" \
        -e "s|@platform@|$kind|g" \
        -e "s|@rust@|$rust|g" \
        -e "s|@version@|$version|g" \
        -e "s|App\.punk|$Name.punk|g" \
        "$1" > "$2"
}

mkdir -p "$folder"
if [ "$kind" = package ]; then
    mkdir -p "$folder/test"
    cp "$here/package/main.roc" "$here/package/Greeting.punk" "$folder/"
    cp "$here/package/test/PackageTest.punk" "$folder/test/"
else
    fill "$here/$kind/App.punk" "$folder/$Name.punk"
fi
fill "$share/templates/$kind/AGENTS.md" "$folder/AGENTS.md"
if [ "$kind" = server ]; then
    cp "$here/server/schema.sql" "$folder/schema.sql"
    fill "$here/server/Dockerfile" "$folder/Dockerfile"
    cp "$here/server/dockerignore" "$folder/.dockerignore"
fi
if [ "$kind" = server ] || [ "$kind" = tui ]; then
    crate_dir="$folder/$kind"
    # Cargo.toml.in: a template named Cargo.toml would be read by cargo as a
    # package when an app depends on this repository.
    (cd "$here/$kind/$kind" && find . -type f) | while read -r f; do
        fill "$here/$kind/$kind/$f" "$crate_dir/${f%.in}"
    done
    fill "$here/build.rs" "$crate_dir/build.rs"
    cp "$toolchain" "$crate_dir/rust-toolchain.toml"
    # The names change the length of lines: let rustfmt lay them out.
    if command -v cargo > /dev/null; then
        (cd "$crate_dir" && cargo fmt > /dev/null 2>&1) || true
    fi
fi
mkdir -p "$folder/.claude/skills"
# Without the trailing /: BSD cp (macOS) copies a dir/ as its contents.
for skill in "$share"/skills/*/; do
    cp -R "${skill%/}" "$folder/.claude/skills/"
done
fill "$here/$kind/README.md" "$folder/README.md"
cat > "$folder/.gitignore" <<'EOF'
target/
EOF

if command -v git > /dev/null && ! (cd "$folder" && git rev-parse --is-inside-work-tree > /dev/null 2>&1); then
    (cd "$folder" && git init -q && git add -A)
    made_git=" (a git repository, files added)"
else
    made_git=""
fi

case "$kind" in
    package) echo "made $folder$made_git, a punk package:" ;;
    *) echo "made $folder$made_git, a $kind app:" ;;
esac
case "$kind" in
    cli) echo "    cd $folder && punk $Name.punk" ;;
    server) echo "    cd $folder/server && cargo run      # see README.md for the database" ;;
    tui) echo "    cd $folder/tui && cargo run" ;;
    package) echo "    cd $folder && punk test test/PackageTest.punk" ;;
esac
