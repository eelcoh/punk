#!/bin/sh
# The `punk` command (bin/punk). It dispatches buffer formatting and release
# commands. The compiler in libexec/punk handles the other commands.
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
        if [ -f "$prefix/share/punk/new/new.sh" ]; then
            shift
            exec sh "$prefix/share/punk/new/new.sh" "$@"
        fi ;;
    version | --version)
        if [ -f "$prefix/VERSION" ]; then
            echo "punk-lang $(cat "$prefix/VERSION")"
            exit 0
        fi ;;
    fmt)
        for arg in "$@"; do
            case "$arg" in
                --path) exec "$prefix/libexec/punk-fmt" "$@" ;;
                --) break ;;
            esac
        done
        if [ "$#" -eq 2 ] && { [ "$2" = --help ] || [ "$2" = -h ]; }; then
            "$prefix/libexec/punk" "$@"
            printf '\nFormat a punk buffer with its import context:\n  punk fmt --stdin --path FILE.punk\n'
            exit 0
        fi ;;
esac
exec "$prefix/libexec/punk" "$@"
