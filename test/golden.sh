#!/bin/sh
# Golden tests: runs the punk examples listed in test/golden/cases.txt
# and compares their output (stdout, exit code and any file they write) with
# test/golden/expected/. Run from the repo root, after `zig build`
# and `sh test/setup.sh`:
#
#     sh test/golden.sh            check
#     sh test/golden.sh --update   write the expected output anew
#
# Server and terminal apps are only type-checked here (their crate's cargo test runs them).
# A schema.sql next to an app has to be up to date (`punk check --schema`).
# It fails as well when a program in examples/ has no case, so that a
# new example cannot be forgotten, when a .punk file there is not laid out
# as `punk fmt` would, and when src/punk/llms.txt is out of date.
set -u

root=$(pwd)
roc="$root/zig-out/bin/punk"
golden="$root/test/golden"
update=no
[ "${1:-}" = "--update" ] && update=yes

if [ ! -x "$roc" ]; then
    echo "no $roc: run 'zig build' first"
    exit 1
fi

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

failed=0
passed=0

# macOS has no timeout(1); Homebrew's coreutils call it gtimeout.
if command -v timeout > /dev/null; then limit="timeout 600"
elif command -v gtimeout > /dev/null; then limit="gtimeout 600"
else limit=""
fi

run_case() {
    name=$1 program=$2 stdin=${3:--}
    shift 2; [ $# -gt 0 ] && shift
    dir="$work/run"
    rm -rf "$dir"; mkdir -p "$dir"
    cp "$golden"/input/* "$dir/"
    ls "$dir" > "$work/before"
    actual="$work/actual"
    if [ "$stdin" = "-" ]; then input=/dev/null; else input="$golden/input/$stdin"; fi
    (cd "$dir" && $limit "$roc" "$root/examples/$program" "$@" < "$input" > "$actual" 2> "$work/stderr")
    code=$?
    echo "exit $code" >> "$actual"
    # Files the program wrote.
    for f in $(ls "$dir" | grep -vxF -f "$work/before"); do
        echo "--- $f" >> "$actual"
        cat "$dir/$f" >> "$actual"
        echo >> "$actual"
    done
    expected="$golden/expected/$name.out"
    if [ "$update" = yes ]; then
        mkdir -p "$(dirname "$expected")"
        cp "$actual" "$expected"
        echo "updated $name"
    elif [ ! -f "$expected" ]; then
        echo "FAIL $name: no expected output (run with --update)"
        failed=$((failed + 1))
    elif diff -u "$expected" "$actual" > "$work/diff"; then
        echo "ok   $name"
        passed=$((passed + 1))
    else
        echo "FAIL $name"
        sed 's/^/     /' "$work/diff"
        echo "     stderr:"
        sed 's/^/     /' "$work/stderr" | tail -n 30
        failed=$((failed + 1))
    fi
}

grep -v '^\s*#' "$golden/cases.txt" | grep -v '^\s*$' > "$work/cases"
while read -r line; do
    # shellcheck disable=SC2086
    set -- $line
    run_case "$@"
done < "$work/cases"

# A server app (on platforms/server) or a terminal app (platforms/tui) can't
# run here: it is an archive that its Rust crate links and tests (cargo test
# in its server/ or tui/ folder, on ambit's spec or sim). Here it only has to
# type-check.
server_apps=$(cd examples && grep -lE '^app.*platform "(server|tui)"' $(find . -name '*.punk') | sed 's|^\./||' | sort)
for f in $server_apps; do
    if "$roc" check "examples/$f" > "$work/check" 2>&1; then
        echo "ok   check $f"
        passed=$((passed + 1))
    else
        echo "FAIL check $f"
        sed 's/^/     /' "$work/check" | tail -n 30
        failed=$((failed + 1))
    fi
    # Its top-level `expect`s do run: they are pure.
    if grep -q '^expect' "examples/$f"; then
        if "$roc" test "examples/$f" > "$work/test" 2>&1; then
            echo "ok   test $f"
            passed=$((passed + 1))
        else
            echo "FAIL test $f"
            sed 's/^/     /' "$work/test" | tail -n 30
            failed=$((failed + 1))
        fi
    fi
done

# Copy the source tree for the schema check, which can write schema.sql.
# Keep import paths intact, including nested modules.
check_schema() {
    schema=$1
    dir=$(dirname "$schema")
    app=$(grep -l '^app ' "$dir"/*.punk 2>/dev/null | head -n 1)
    [ -z "$app" ] && app=$(grep -l '^table ' "$dir"/*.punk 2>/dev/null | head -n 1)
    copy="$work/schema/$dir"
    if [ -z "$app" ]; then
        echo "FAIL $schema: no .punk file next to it declares an app or table"
        failed=$((failed + 1))
    elif ! mkdir -p "$copy" || ! cp "$schema" "$copy/" ||
        ! find "$dir" \( -name target -o -name .git \) -prune -o \
            -type f \( -name '*.punk' -o -name '*.roc' \) -exec sh -c '
                source_dir=$1 dest=$2
                shift 2
                for file do
                    target="$dest/${file#"$source_dir"/}"
                    mkdir -p "$(dirname "$target")" && cp "$file" "$target" || exit 1
                done
            ' sh "$dir" "$copy" {} +; then
        echo "FAIL $schema: could not copy its source tree"
        failed=$((failed + 1))
    elif "$roc" check --schema "$copy/$(basename "$app")" > "$work/schema.out" 2>&1 && grep -q 'is up to date' "$work/schema.out"; then
        echo "ok   schema $schema"
        passed=$((passed + 1))
    else
        echo "FAIL schema $schema: run '$roc check --schema $app'"
        sed 's/^/     /' "$work/schema.out" | tail -n 30
        failed=$((failed + 1))
    fi
}

find examples -name schema.sql | sort > "$work/schemas"
while IFS= read -r schema; do
    check_schema "$schema"
done < "$work/schemas"

# A buffer can differ from the app on disk. Both modes need the nested
# module: the table row alias is defined there.
fmt_app="$golden/fmt/server/Server.punk"
check_schema test/golden/fmt/server/schema.sql
cp "$fmt_app" "$work/fmt.before"
sed 's/"ready"/"from the buffer"/' "$fmt_app" > "$work/fmt.expected"
sed 's/^handle! = /handle!   =   /' "$work/fmt.expected" > "$work/fmt.input"
if "$roc" fmt --stdin --path "$fmt_app" < "$work/fmt.input" > "$work/fmt.out" 2> "$work/fmt.err" &&
    cmp -s "$work/fmt.expected" "$work/fmt.out" && cmp -s "$work/fmt.before" "$fmt_app"; then
    echo "ok   punk fmt --stdin with nested imports"
    passed=$((passed + 1))
else
    echo "FAIL punk fmt --stdin with nested imports"
    diff -u "$work/fmt.expected" "$work/fmt.out"
    cat "$work/fmt.err"
    failed=$((failed + 1))
fi

if printf 'broken = (\n' | "$roc" fmt --stdin --path "$fmt_app" > "$work/fmt.out" 2> "$work/fmt.err"; then
    echo "FAIL punk fmt --stdin: accepted invalid input"
    failed=$((failed + 1))
elif [ -s "$work/fmt.out" ] || ! grep -qF "$fmt_app:" "$work/fmt.err"; then
    echo "FAIL punk fmt --stdin: expected a diagnostic on stderr with the app path"
    failed=$((failed + 1))
else
    echo "ok   punk fmt --stdin diagnostics"
    passed=$((passed + 1))
fi

# Every other app in examples/ needs at least one case.
for f in $(cd examples && grep -l '^app' $(find . -name '*.punk') | sed 's|^\./||' | grep -vxF "$server_apps" | sort); do
    if ! awk '{print $2}' "$work/cases" | grep -qxF "$f"; then
        echo "FAIL examples/$f has no case in test/golden/cases.txt"
        failed=$((failed + 1))
    fi
done

# Every .punk file in examples/ is formatted as `punk fmt` lays it out.
unformatted=$("$roc" fmt --check $(find examples -name '*.punk' | sort) 2>&1)
if [ $? -ne 0 ]; then
    echo "FAIL punk fmt --check:"
    echo "$unformatted" | sed 's/^/     /'
    failed=$((failed + 1))
else
    echo "ok   punk fmt --check"
    passed=$((passed + 1))
fi

# src/punk/llms.txt is generated from the source; it must be up to date.
if python3 src/punk/gen_llms.py --check; then
    echo "ok   llms.txt up to date"
    passed=$((passed + 1))
else
    echo "FAIL llms.txt: run python3 src/punk/gen_llms.py"
    failed=$((failed + 1))
fi

[ "$update" = yes ] && exit 0
echo
echo "$passed passed, $failed failed"
[ "$failed" -eq 0 ]
