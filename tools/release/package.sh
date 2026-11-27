#!/bin/sh
# Packs a built punk into dist/punk-<version>-<os>-<arch>.tar.gz, the archive
# a release carries and install.sh unpacks. Run from the repo root after
# `zig build` and `sh test/setup.sh`:
#
#     sh tools/release/package.sh v0.1.0
#
# The archive holds, under punk-<version>-<os>-<arch>/:
#
#   bin/punk                    the command launcher
#   libexec/punk                the compiler
#   libexec/punk-fmt            the formatter for editor buffers
#   platforms/cli/              the cli platform: its API and its prebuilt host
#                               (targets/<target>/), so cli apps need no Rust
#   platforms/server/, tui/     their API; their hosts still build with cargo,
#                               per app (see each platform's README)
#   packages/json/              Json.Decode / Json.Encode
#   share/punk/llms.txt         the language reference for agents
#   share/punk/skills/          agent skills per task (skills/), when there are
#   share/punk/templates/       an AGENTS.md per platform (templates/), when there are
#   share/punk/new/             `punk new` (tools/new/), with the ambit commit
#                               and Rust toolchain the platforms use
#   README.md, VERSION
set -eu

version=${1:?usage: sh tools/release/package.sh <version>}

case "$(uname -s)" in
    Linux) os=linux ;;
    Darwin) os=macos ;;
    *) echo "package.sh: no releases for $(uname -s)"; exit 1 ;;
esac
case "$(uname -m)" in
    x86_64 | amd64) arch=x86_64 ;;
    aarch64 | arm64) arch=aarch64 ;;
    *) echo "package.sh: no releases for $(uname -m)"; exit 1 ;;
esac

name="punk-$version-$os-$arch"
test -x zig-out/bin/punk || { echo "package.sh: run 'zig build' first"; exit 1; }
ls platforms/cli/targets/*/libhost.a > /dev/null 2>&1 || { echo "package.sh: run 'sh test/setup.sh' first"; exit 1; }

stage="dist/$name"
rm -rf "$stage" "dist/$name.tar.gz"
mkdir -p "$stage/bin" "$stage/libexec" "$stage/share/punk" "$stage/platforms" "$stage/packages"

cp zig-out/bin/punk "$stage/bin/punk"
cp zig-out/libexec/punk zig-out/libexec/punk-fmt "$stage/libexec/"
cp -R tools/new "$stage/share/punk/new"
sed -n 's/^ambit-caps = .*rev = "\([0-9a-f]*\)".*/\1/p' platforms/server/host/Cargo.toml > "$stage/share/punk/new/ambit-rev"
test -s "$stage/share/punk/new/ambit-rev" || { echo "package.sh: no ambit rev in platforms/server/host/Cargo.toml"; exit 1; }
cp platforms/server/host/rust-toolchain.toml "$stage/share/punk/new/rust-toolchain.toml"
cp src/punk/llms.txt "$stage/share/punk/llms.txt"
for d in skills templates; do
    if [ -d "$d" ]; then cp -R "$d" "$stage/share/punk/$d"; fi
done
cp README.md "$stage/README.md"
printf '%s\n' "$version" > "$stage/VERSION"

# The API files of a platform (and the cli platform's prebuilt host), not
# its Rust sources or build output.
copy_api() {
    mkdir -p "$stage/$1"
    for f in "$1"/*.roc "$1"/*.punk "$1"/README.md; do
        if [ -f "$f" ]; then cp "$f" "$stage/$1/"; fi
    done
}
copy_api platforms/cli
cp -R platforms/cli/targets "$stage/platforms/cli/targets"
copy_api platforms/server
copy_api platforms/tui
copy_api packages/json

tar -C dist -czf "dist/$name.tar.gz" "$name"
rm -rf "$stage"
echo "dist/$name.tar.gz"
