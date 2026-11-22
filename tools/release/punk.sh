#!/bin/sh
# The `punk` command of a release (bin/punk): `punk new` makes a new app
# (share/punk/new/new.sh), `punk version` says which release this is, and
# everything else goes to the compiler
# (libexec/punk), which finds the platforms and packages next to itself.
set -eu
self=$0
# Through links such as ~/.local/bin/punk to <prefix>/bin/punk.
while [ -L "$self" ]; do
    link=$(readlink "$self")
    case "$link" in
        /*) self=$link ;;
        *) self=$(dirname "$self")/$link ;;
    esac
done
prefix=$(cd "$(dirname "$self")/.." && pwd)
case "${1:-}" in
    new)
        shift
        exec sh "$prefix/share/punk/new/new.sh" "$@" ;;
    version | --version)
        echo "punk-lang $(cat "$prefix/VERSION")"
        exit 0 ;;
esac
exec "$prefix/libexec/punk" "$@"
