#!/bin/sh
# punk new: a new punk-lang app, ready to build, with its agent instructions.
#
#     punk new <cli|server|tui> <name> [<folder>]
#
# Makes <folder> (default: <name>) with:
#
#   <Name>.punk           the app: a hello world for its platform
#   schema.sql            (server) the tables, made by `punk check --schema`
#   server/ or tui/       (server, tui) the Rust crate that runs the app:
#                         `cargo run` builds the app with `punk build`
#   AGENTS.md             what an agent needs to know (templates/<platform>)
#   .claude/skills/       the punk skills (skills/), for Claude Code and others
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
usage: punk new <platform> <name> [<folder>]

  <platform>  cli     a command-line program (no Rust needed)
              server  an HTTP server with Postgres (needs Rust: rustup.rs)
              tui     a terminal app (needs Rust: rustup.rs)
  <name>      lowercase letters, digits and -, such as notes or my-notes
  <folder>    where to make it (default: <name>)
EOF
}

case "${1:-}" in
    -h | --help | help) usage; exit 0 ;;
esac
[ $# -ge 2 ] && [ $# -le 3 ] || { usage >&2; exit 2; }
platform=$1 app=$2 folder=${3:-$2}

case "$platform" in
    cli | server | tui) ;;
    *) die "no platform \"$platform\": give cli, server or tui" ;;
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
        -e "s|@platform@|$platform|g" \
        -e "s|App\.punk|$Name.punk|g" \
        "$1" > "$2"
}

mkdir -p "$folder"
fill "$here/$platform/App.punk" "$folder/$Name.punk"
fill "$share/templates/$platform/AGENTS.md" "$folder/AGENTS.md"
if [ "$platform" = server ]; then
    cp "$here/server/schema.sql" "$folder/schema.sql"
fi
if [ "$platform" != cli ]; then
    crate_dir="$folder/$platform"
    (cd "$here/$platform/$platform" && find . -type f) | while read -r f; do
        fill "$here/$platform/$platform/$f" "$crate_dir/$f"
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
fill "$here/$platform/README.md" "$folder/README.md"
cat > "$folder/.gitignore" <<'EOF'
target/
EOF

if command -v git > /dev/null && ! (cd "$folder" && git rev-parse --is-inside-work-tree > /dev/null 2>&1); then
    (cd "$folder" && git init -q && git add -A)
    made_git=" (a git repository, files added)"
else
    made_git=""
fi

echo "made $folder$made_git, a $platform app:"
case "$platform" in
    cli) echo "    cd $folder && punk $Name.punk" ;;
    server) echo "    cd $folder/server && cargo run      # see README.md for the database" ;;
    tui) echo "    cd $folder/tui && cargo run" ;;
esac
