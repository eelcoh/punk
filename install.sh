#!/bin/sh
# Installs punk-lang (the `punk` command) on macOS or Linux, from a release of
# github.com/eelcoh/punk. No Zig, Rust or zvm needed.
#
#     curl -fsSL https://raw.githubusercontent.com/eelcoh/punk/main/install.sh | sh
#
# Settings, as environment variables:
#
#   PUNK_VERSION   the release to install, e.g. v0.1.0 (default: the latest)
#   PUNK_HOME      where releases go (default: ~/.punk); each version in
#                  $PUNK_HOME/versions/<version>, the active one linked as
#                  $PUNK_HOME/current
#   PUNK_BIN_DIR   where the `punk` command is linked (default: ~/.local/bin)
#   PUNK_ARCHIVE   install this local archive instead of downloading one
#                  (made by tools/release/package.sh); no checksum check
#
# The archive is checked against the release's SHA256SUMS before it is
# unpacked. Running the script again installs another version next to the
# old ones and makes it current; nothing outside PUNK_HOME and PUNK_BIN_DIR
# is touched.
set -eu

repo="eelcoh/punk"
home=${PUNK_HOME:-"$HOME/.punk"}
bin_dir=${PUNK_BIN_DIR:-"$HOME/.local/bin"}

say() { printf 'punk-lang: %s\n' "$*"; }
die() { printf 'punk-lang: %s\n' "$*" >&2; exit 1; }

case "$(uname -s)" in
    Linux) os=linux ;;
    Darwin) os=macos ;;
    *) die "there are no releases for $(uname -s) (only macOS and Linux)" ;;
esac
case "$(uname -m)" in
    x86_64 | amd64) arch=x86_64 ;;
    aarch64 | arm64) arch=aarch64 ;;
    *) die "there are no releases for $(uname -m) (only x86_64 and aarch64)" ;;
esac
# A shell under Rosetta reports x86_64 on an Apple silicon Mac.
if [ "$os-$arch" = "macos-x86_64" ] && [ "$(sysctl -n sysctl.proc_translated 2>/dev/null || echo 0)" = "1" ]; then
    arch=aarch64
fi

download() {
    if command -v curl > /dev/null; then
        curl --proto '=https' --tlsv1.2 -fsSL -o "$2" "$1"
    elif command -v wget > /dev/null; then
        wget -q --https-only -O "$2" "$1"
    else
        die "needs curl or wget"
    fi
}

sha256() {
    if command -v sha256sum > /dev/null; then
        sha256sum "$1" | cut -d' ' -f1
    elif command -v shasum > /dev/null; then
        shasum -a 256 "$1" | cut -d' ' -f1
    else
        die "needs sha256sum or shasum to check the download"
    fi
}

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT INT TERM

if [ -n "${PUNK_ARCHIVE:-}" ]; then
    archive=$PUNK_ARCHIVE
    [ -f "$archive" ] || die "no archive at $archive"
    say "installing $archive (local, not checked)"
else
    version=${PUNK_VERSION:-}
    if [ -z "$version" ]; then
        # The latest release, from where github.com/<repo>/releases/latest
        # redirects to (no API call, so no rate limit).
        if command -v curl > /dev/null; then
            url=$(curl --proto '=https' -fsSLI -o /dev/null -w '%{url_effective}' "https://github.com/$repo/releases/latest")
        else
            url=$(wget -q --https-only --max-redirect=5 -S --spider "https://github.com/$repo/releases/latest" 2>&1 | sed -n 's/^ *Location: *//p' | tail -1)
        fi
        version=${url##*/}
        case "$version" in
            v*) ;;
            *) die "found no release of $repo; set PUNK_VERSION" ;;
        esac
    fi
    name="punk-$version-$os-$arch"
    base="https://github.com/$repo/releases/download/$version"
    say "downloading $name"
    download "$base/$name.tar.gz" "$tmp/$name.tar.gz" || die "release $version has no $name.tar.gz"
    download "$base/SHA256SUMS" "$tmp/SHA256SUMS" || die "release $version has no SHA256SUMS"
    want=$(awk -v f="$name.tar.gz" '$2 == f || $2 == "*" f { print $1 }' "$tmp/SHA256SUMS")
    [ -n "$want" ] || die "SHA256SUMS of $version does not list $name.tar.gz"
    have=$(sha256 "$tmp/$name.tar.gz")
    [ "$want" = "$have" ] || die "checksum mismatch for $name.tar.gz (expected $want, got $have); not installed"
    archive="$tmp/$name.tar.gz"
fi

mkdir -p "$tmp/unpacked"
tar -xzf "$archive" -C "$tmp/unpacked"
top=$(ls "$tmp/unpacked")
[ "$(printf '%s\n' "$top" | wc -l | tr -d ' ')" = "1" ] && [ -x "$tmp/unpacked/$top/bin/punk" ] || die "unexpected archive layout"
version=$(cat "$tmp/unpacked/$top/VERSION" 2>/dev/null || echo "$top")

mkdir -p "$home/versions" "$bin_dir"
rm -rf "$home/versions/$version"
mv "$tmp/unpacked/$top" "$home/versions/$version"
ln -sfn "versions/$version" "$home/current"
ln -sf "$home/current/bin/punk" "$bin_dir/punk"

say "installed $version in $home/versions/$version"
say "the command: $bin_dir/punk"
case ":$PATH:" in
    *":$bin_dir:"*) ;;
    *) say "add $bin_dir to your PATH, e.g. in ~/.zshrc or ~/.bashrc:"
       # shellcheck disable=SC2016 # $PATH is meant literally here
       printf '\n    export PATH="%s:$PATH"\n\n' "$bin_dir" ;;
esac
say "platforms and packages: $home/current/platforms, $home/current/packages"
say "the reference for agents: $home/current/share/punk/llms.txt"
