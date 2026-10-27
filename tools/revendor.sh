#!/bin/sh
# tools/revendor.sh -- re-vendor the standard and the corpus VERBATIM from a
# tag or commit of mas-bandwidth/serialize (DESIGN.md, "The vendored standard").
#
# usage: tools/revendor.sh <tag-or-commit>
#
# Fetches the ref into build/revendor/, replaces STANDARD.md, IMPLEMENTING.md,
# conformance/ and conformance-controls/ with its copies, then diffs each one
# against the checkout: anything but an empty diff is a failure. Set
# SERIALIZE_REF in .github/workflows/ci.yml and the pin in DESIGN.md to the
# same ref afterwards (make check-ci holds them equal).
set -eu

if [ $# -ne 1 ]; then
    echo "usage: tools/revendor.sh <tag-or-commit>"
    exit 2
fi
ref_name=$1
root=$(cd "$(dirname "$0")/.." && pwd)
ref="$root/build/revendor/serialize"

rm -rf "$ref"
mkdir -p "$ref"
git -C "$ref" init -q
git -C "$ref" fetch -q --depth 1 https://github.com/mas-bandwidth/serialize.git "$ref_name"
git -C "$ref" checkout -q FETCH_HEAD

rm -rf "$root/conformance" "$root/conformance-controls"
cp -R "$ref/conformance" "$root/conformance"
cp -R "$ref/conformance-controls" "$root/conformance-controls"
cp "$ref/STANDARD.md" "$root/STANDARD.md"
cp "$ref/IMPLEMENTING.md" "$root/IMPLEMENTING.md"

diff -ru "$ref/conformance" "$root/conformance"
diff -ru "$ref/conformance-controls" "$root/conformance-controls"
diff -u "$ref/STANDARD.md" "$root/STANDARD.md"
diff -u "$ref/IMPLEMENTING.md" "$root/IMPLEMENTING.md"
echo "revendor: STANDARD.md, IMPLEMENTING.md, conformance/ and conformance-controls/ are $ref_name's ($(git -C "$ref" rev-parse HEAD))"
