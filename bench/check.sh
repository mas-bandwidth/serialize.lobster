#!/bin/sh
# bench/check.sh -- the untimed shape gate: TestBenchShapesAgree.
#
# Runs the Lobster benchmark's one-write/one-read rows and compares every
# row's bytes and 64-bit checksum with bench/golden.csv. The golden is the
# Lobster port's pinned wire shape; a drift in values, widths or byte order
# moves a checksum and fails here, before any number is published.
set -eu

root=$(cd "$(dirname "$0")/.." && pwd)
: "${LOBSTER:?LOBSTER must name the lobster executable (make sets it)}"

run="$root/build/bench-check"
rm -rf "$run"
mkdir -p "$run"
cp "$root"/src/*.lobster "$run"/
cp "$root/bench/bench.lobster" "$run"/

got="$run/rows.csv"
(cd "$run" && "$LOBSTER" bench.lobster 2>/dev/null | grep -E '^[a-z0-9_]+,' > "$got")

echo "RUN TestBenchShapesAgree"
if cmp -s "$root/bench/golden.csv" "$got"; then
    echo "--- PASS TestBenchShapesAgree"
    exit 0
fi
echo "--- FAIL TestBenchShapesAgree"
diff -u "$root/bench/golden.csv" "$got" | sed 's/^/    /' || true
exit 1
