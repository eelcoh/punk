#!/bin/sh
# Builds the hosts of the platforms the punkroc examples use and puts them
# where `roc` looks for them, for this computer:
#
# - platforms/cli: punkroc's own platform. Its host is Rust, on ambit
#   (platforms/cli/host), built with cargo.
#
# Run from the repo root:
#
#     sh test/setup.sh
#
set -e

# The compiler needs exactly this Zig (see build.zig.zon); another version
# fails with errors such as "invalid builtin function: '@backingInt'".
want=$(sed -n 's/.*minimum_zig_version = "\(.*\)".*/\1/p' build.zig.zon)
have=$(zig version 2>/dev/null || echo none)
if [ "$have" != "$want" ]; then
    echo "punkroc needs Zig $want, but 'zig' here is $have ($(command -v zig || echo 'not found'))."
    echo "See 'Zig' in src/punk/README.md."
    exit 1
fi
if ! command -v cargo > /dev/null; then
    echo "punkroc's cli platform needs Rust (cargo), see https://rustup.rs."
    echo "platforms/cli/host/rust-toolchain.toml says which version."
    exit 1
fi

# This computer, as roc names it, and as Rust names it.
case "$(uname -s)-$(uname -m)" in
    Linux-x86_64) target=x64musl; triple=x86_64-unknown-linux-musl ;;
    Linux-aarch64 | Linux-arm64) target=arm64musl; triple=aarch64-unknown-linux-musl ;;
    Darwin-x86_64) target=x64mac; triple=x86_64-apple-darwin ;;
    Darwin-arm64) target=arm64mac; triple=aarch64-apple-darwin ;;
    *) echo "punkroc's platforms don't run on $(uname -s) $(uname -m) yet."; exit 1 ;;
esac

# punkroc's cli platform (Rust, on ambit). Built from its own folder, so that
# rustup uses the Rust of its rust-toolchain.toml. On Linux the program is
# static, with the C runtime and unwinder that Rust itself ships for musl.
mkdir -p "platforms/cli/targets/$target"
(
    cd platforms/cli/host
    if command -v rustup > /dev/null; then rustup target add "$triple" > /dev/null; fi
    cargo build --release --locked --target "$triple"
    cp "target/$triple/release/libpunk_cli_host.a" "../targets/$target/libhost.a"
    case $target in
        *musl)
            musl="$(rustc --print sysroot)/lib/rustlib/$triple/lib/self-contained"
            cp "$musl/rcrt1.o" "$musl/libc.a" "$musl/libunwind.a" "../targets/$target/"
            ;;
    esac
)
echo "cli platform ready for $target"
