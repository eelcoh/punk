#!/bin/sh
# The notes API of the tutorial (examples/tutorial/notes) as a Hermit
# unikernel: builds it with its unikernel.sh, boots it in QEMU against the
# Postgres of PUNK_TEST_POSTGRES (as its superuser, which owns the tables),
# and tries the API over HTTP. Run from the repo root after `zig build`; needs
# psql, QEMU and rustup.
set -eu

root=$(pwd)
punk="$root/zig-out/bin/punk"
: "${PUNK_TEST_POSTGRES:?set PUNK_TEST_POSTGRES to a Postgres superuser URL on this computer}"
# The same Postgres as the VM sees it: this computer is 10.0.2.2 in QEMU's network.
vm_url=$(printf '%s' "$PUNK_TEST_POSTGRES" | sed 's#@localhost#@10.0.2.2#; s#@127\.0\.0\.1#@10.0.2.2#')
port=8089
log=$(mktemp)

PGOPTIONS=--client-min-messages=warning psql -q "$PUNK_TEST_POSTGRES" -c "DROP DATABASE IF EXISTS notes_hermit" -c "CREATE DATABASE notes_hermit"
psql -q "$PUNK_TEST_POSTGRES" -c "DO \$\$ BEGIN CREATE ROLE notes_hermit_app LOGIN PASSWORD 'app-secret';
    EXCEPTION WHEN duplicate_object THEN NULL; END \$\$"

cd examples/tutorial/notes/server
PUNK="$punk" PORT=$port API_KEY=hermit-key \
    DATABASE_URL="postgres://notes_hermit_app:app-secret@10.0.2.2/notes_hermit?sslmode=disable" \
    DATABASE_OWNER_URL="${vm_url%/*}/notes_hermit?sslmode=disable" \
    sh unikernel.sh > "$log" 2>&1 &
pid=$!
trap 'kill $pid 2>/dev/null || true; pkill -f "hostfwd=tcp::$port-" 2>/dev/null || true; rm -f "$log"' EXIT

base=http://localhost:$port
# The build (the kernel too) takes minutes; then QEMU boots in seconds.
for _ in $(seq 900); do
    curl -s -o /dev/null -m 1 "$base/notes" && break
    kill -0 $pid 2>/dev/null || break
    sleep 1
done

failures=0
check() { # name, expected, actual
    if [ "$2" = "$3" ]; then echo "ok   $1"; else echo "FAIL $1: expected '$2', got '$3'"; failures=$((failures + 1)); fi
}
status() { curl -s -o /dev/null -w '%{http_code}' "$@"; }

key="Authorization: Bearer hermit-key"
check "the tables are made" 200 "$(status "$base/notes")"
check "writing needs the key" 401 "$(status -X POST "$base/notes" -d '{"title": "Milk", "body": "2 litres"}')"
created=$(curl -s -X POST -H "$key" "$base/notes" -d '{"title": "Milk", "body": "2 litres"}')
id=$(printf '%s' "$created" | sed -n 's/.*"id":"\([^"]*\)".*/\1/p')
check "a new note has an id" yes "$([ -n "$id" ] && echo yes || echo no)"
check "it can be read back" 200 "$(status "$base/notes/$id")"
check "it is in the list" 1 "$(curl -s "$base/notes" | grep -o "\"$id\"" | wc -l | tr -d ' ')"
check "a bad body" 400 "$(status -X POST -H "$key" "$base/notes" -d '{"title": "Milk"}')"
check "it can be deleted" 204 "$(status -X DELETE -H "$key" "$base/notes/$id")"
check "then it is gone" 404 "$(status "$base/notes/$id")"

if [ $failures -gt 0 ]; then
    echo "hermit: $failures failed"; echo "--- log"; tail -n 60 "$log"; exit 1
fi
echo "hermit: the notes API runs as a unikernel"
