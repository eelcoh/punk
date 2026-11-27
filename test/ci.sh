#!/bin/sh
# Everything CI runs, in order (.github/workflows/punk.yml). Runs locally
# too, from the repo root; the Postgres and Mongo tests need PUNK_TEST_POSTGRES and PUNK_TEST_MONGO.
# ZIG_BUILD_FLAGS goes to `zig build`, e.g. `--fork=../roc` to try another Roc.
set -eu
zig test src/punk/test.zig
(cd platforms/roc-abi && cargo test --locked)
(cd platforms/cli/host && cargo test --locked)
(cd platforms/server/host && cargo test --locked)
(cd platforms/server/postgres && cargo test --locked)
(cd platforms/server/mongo && cargo test --locked)
(cd platforms/tui/host && cargo test --locked)
# shellcheck disable=SC2086
zig build ${ZIG_BUILD_FLAGS:-}
(cd test/server-abi && cargo test --locked)
sh test/setup.sh
sh test/golden.sh
zig-out/bin/punk test examples/activity-codec/Demo.punk
# The server apps: ambit's spec against the punk shortener, on a key-value
# store, on Postgres and on Mongo, and the notes kept apart by row-level
# security.
(cd examples/shortener/server && cargo test --locked)
(cd examples/shortener-postgres/server && cargo test --locked)
(cd examples/shortener-mongo/server && cargo test --locked)
(cd examples/notes/server && cargo test --locked)
(cd examples/todos/server && cargo test --locked)
# The notes API of the tutorial (docs/tutorial), before and after its migration.
zig-out/bin/punk check examples/tutorial/notes-v1/Notes.punk
(cd examples/tutorial/notes/server && PUNK="$PWD/../../../../zig-out/bin/punk" cargo test --locked)
# The terminal apps, on ambit's sim terminal: the counter and crossload's
# library view.
(cd examples/counter/tui && cargo test --locked)
(cd examples/library/tui && cargo test --locked)
# The shopping list of the tutorial's terminal app.
(cd examples/tutorial/shopping/tui && PUNK="$PWD/../../../../zig-out/bin/punk" cargo test --locked)
# A new app per platform, made with `punk new`.
sh test/new.sh
