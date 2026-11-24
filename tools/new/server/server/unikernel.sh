#!/bin/sh
# Builds the server as a Hermit unikernel and boots it in QEMU: the app, its
# server and a small kernel in one image of a few MB, with no operating system
# around it. See src/hermit.rs.
#
#     sh unikernel.sh
#
# Needs QEMU (on a Mac: brew install qemu). The first time it adds Rust's
# standard library for Hermit to the Rust of rust-toolchain.toml.
#
# The database: DATABASE_URL and DATABASE_OWNER_URL, as for `cargo run`.
# Without them it is Postgres on this computer, which the VM reaches at
# 10.0.2.2. The server is on http://localhost:$PORT (8080). Ctrl-C stops it.
set -eu
cd "$(dirname "$0")"

target=x86_64-unknown-hermit
rust=@rust@
loader_version=v0.5.6 # the loader for kernel 0.13.2 (v0.5.7 isn't)
port=${PORT:-8080}
url=${DATABASE_URL:-postgres://@crate@_app@10.0.2.2/@app@?sslmode=disable}
owner_url=${DATABASE_OWNER_URL:-postgres://$(id -un)@10.0.2.2/@app@?sslmode=disable}

command -v qemu-system-x86_64 > /dev/null || {
    echo "unikernel.sh: QEMU is not installed (on a Mac: brew install qemu)" >&2
    exit 1
}

rustup toolchain list | grep -q "^$rust-" || rustup toolchain install "$rust" --profile minimal
sysroot=$(rustup run "$rust" rustc --print sysroot)
if [ ! -d "$sysroot/lib/rustlib/$target" ]; then
    echo "Adding Rust's standard library for Hermit to Rust $rust ..."
    std=rust-std-$rust-$target
    tmp=$(mktemp -d)
    curl -sSfL -o "$tmp/$std.tar.gz" \
        "https://github.com/hermit-os/rust-std-hermit/releases/download/$rust/$std.tar.gz"
    tar xzf "$tmp/$std.tar.gz" -C "$tmp"
    (cd "$tmp" && rustup run "$rust" "./$std/install.sh" > /dev/null)
    rm -rf "$tmp"
fi

cargo build --release --target "$target"

loader=target/hermit-loader-x86_64-$loader_version
[ -f "$loader" ] || curl -sSfL -o "$loader" \
    "https://github.com/hermit-os/loader/releases/download/$loader_version/hermit-loader-x86_64"

# Linux with KVM runs the VM at full speed; elsewhere QEMU emulates x86-64,
# which is slower but works the same (also on a Mac with Apple silicon).
accel=""
[ -w /dev/kvm ] && accel="-enable-kvm"

echo "@app@ as a unikernel: http://localhost:$port (Ctrl-C stops it)"
# shellcheck disable=SC2086 # $accel is one option or none
exec qemu-system-x86_64 $accel \
    -cpu qemu64,apic,fsgsbase,fxsr,rdrand,rdseed,rdtscp,xsave,xsaveopt \
    -smp 1 -m 256M -display none -serial stdio \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 \
    -kernel "$loader" -initrd "target/$target/release/@app@" \
    -append "env=DATABASE_URL=$url env=DATABASE_OWNER_URL=$owner_url env=PORT=$port" \
    -netdev "user,id=net0,hostfwd=tcp::$port-:$port" \
    -device virtio-net-pci,netdev=net0,disable-legacy=on
