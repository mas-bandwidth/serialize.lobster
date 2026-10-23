#!/bin/sh
# tools/controls/controls.sh -- the per-rule negative controls (STANDARD.md,
# "The conformance corpus": "A gate nobody has seen go red is a claim, not a
# measurement").
#
# usage: LOBSTER=<lobster> tools/controls/controls.sh [control]
#
# For each control in tools/controls/table.txt: stage a copy of src/*.lobster
# under build/controls/<control>/, delete ONE refusal rule from the copy by an
# exact whole-line replacement, and run the real corpus through
# test/conformance/conformance_test.lobster's conf_control. The control passes
# only when the sabotaged reader fails EXACTLY the vectors that
# conformance-controls/<control>.expected names, the reference's own list.
#
# A needle that no longer matches its line exactly the stated number of times
# is a FAIL, never a silent no-op: a control that has stopped sabotaging
# anything is worse than none. Every conformance-controls/*.expected file
# needs a row in the table, so a control the reference adds goes red here
# until this port carries it. src/ itself is never edited.
#
# Then the REVERSED WITNESSES of tools/controls/witnesses.txt: each plants the
# old behaviour of one rule a unit test pins (a write-side rule, the latch of
# the first reason) back into a staged copy of src/, and that unit test must
# then FAIL. And the harness's own control: conf_control over an UNSABOTAGED
# copy must fail, or the comparison it makes has stopped discriminating.
#
# The corpus and the controls' lists are the vendored conformance/ and
# conformance-controls/ unless SERIALIZE_CONFORMANCE_DIR and
# SERIALIZE_CONFORMANCE_CONTROLS_DIR name other directories (the nightly
# functional test points them at mas-bandwidth/serialize main). One that is not
# a directory fails, naming it.
#
# Prints `RUN Control<control>` / `RUN Witness<name>` then `--- PASS` or
# `--- FAIL` for each, and `ok N controls` or `FAIL k of N controls` last.

set -eu

root=$(cd "$(dirname "$0")/../.." && pwd)
: "${LOBSTER:?LOBSTER must name the lobster executable (make controls sets it)}"
table="$root/tools/controls/table.txt"
witnesses="$root/tools/controls/witnesses.txt"
done_line="serialize-test-done"
tab=$(printf '\t')
corpus=${SERIALIZE_CONFORMANCE_DIR:-$root/conformance}
controls=${SERIALIZE_CONFORMANCE_CONTROLS_DIR:-$root/conformance-controls}
for d in "SERIALIZE_CONFORMANCE_DIR=$corpus" "SERIALIZE_CONFORMANCE_CONTROLS_DIR=$controls"; do
    if [ ! -d "${d#*=}" ]; then
        echo "FAIL $d is not a directory"
        exit 1
    fi
done

# Every .expected file has a row; every row names an .expected file.
missing=0
for f in "$controls"/*.expected; do
    name=$(basename "$f" .expected)
    if ! grep -q "^$name$tab" "$table"; then
        echo "FAIL conformance-controls/$name.expected has no sabotage in tools/controls/table.txt"
        missing=1
    fi
done
for name in $(grep -v '^#' "$table" | grep -v '^$' | cut -f1 | sort -u); do
    if [ ! -f "$controls/$name.expected" ]; then
        echo "FAIL tools/controls/table.txt names $name, which has no conformance-controls/$name.expected"
        missing=1
    fi
done

if [ $# -eq 1 ] && [ -n "$1" ]; then
    names=$1
else
    names=$(grep -v '^#' "$table" | grep -v '^$' | cut -f1 | sort -u)
fi

# stage DIR: a fresh copy of src/, the conformance runner and the corpus.
stage() {
    rm -rf "$1"
    mkdir -p "$1"
    cp "$root"/src/*.lobster "$1"/
    cp "$root"/test/conformance/conformance_test.lobster "$1"/
    cp -R "$corpus" "$1/conformance"
    cp -R "$controls" "$1/conformance-controls"
}

# patch DIR FILE COUNT NEEDLE PATCH: replace the whole line NEEDLE of
# DIR/basename(FILE) with PATCH, which must match exactly COUNT times. The
# strings travel through the environment, so awk applies no escape processing.
patch_line() {
    target="$1/$(basename "$2")"
    if [ ! -f "$target" ]; then
        echo "    $2 is not in src/"
        return 1
    fi
    if ! NEEDLE="$4" PATCH="$5" COUNT="$3" awk '
        $0 == ENVIRON["NEEDLE"] { print ENVIRON["PATCH"]; n++; next }
        { print }
        END { if (n != ENVIRON["COUNT"] + 0) { print "    needle matched " n " times, not " ENVIRON["COUNT"] > "/dev/stderr"; exit 1 } }
    ' "$target" >"$target.patched"; then
        echo "    $2: the needle no longer matches: $4"
        rm -f "$target.patched"
        return 1
    fi
    mv "$target.patched" "$target"
}

# run_driver DIR BODY: write a driver that runs BODY then prints the done
# line, run it in DIR, and leave its output in $out. True when it exited 0
# AND printed the done line.
run_driver() {
    driver="$1/_driver.lobster"
    printf '%s\nprint "%s"\n' "$2" "$done_line" >"$driver"
    set +e
    out=$(cd "$1" && "$LOBSTER" _driver.lobster 2>&1)
    code=$?
    set -e
    [ $code -eq 0 ] && printf '%s\n' "$out" | grep -qx "$done_line"
}

total=0
failed=0
out=""

for name in $names; do
    total=$((total + 1))
    echo "RUN Control$name"
    dir="$root/build/controls/$name"
    stage "$dir"
    ok=1
    rows=$(grep "^$name$tab" "$table" || true)
    if [ -z "$rows" ]; then
        echo "    no sabotage for $name in tools/controls/table.txt"
        ok=0
    fi
    while IFS="$tab" read -r control file count needle patch; do
        [ -n "$control" ] || continue
        patch_line "$dir" "$file" "$count" "$needle" "$patch" || ok=0
    done <<ROWS
$rows
ROWS
    if [ $ok -eq 1 ] && run_driver "$dir" "$(printf 'import conformance_test\nconf_control("%s")' "$name")"; then
        printf '%s\n' "$out" | grep "^control " | sed 's/^/    /'
        echo "--- PASS Control$name"
    else
        echo "--- FAIL Control$name"
        printf '%s\n' "$out" | grep -v ': warning: ' | sed 's/^/    /'
        failed=$((failed + 1))
    fi
    out=""
done

if [ $# -eq 0 ]; then
    # The harness's own control: with no rule deleted the corpus is green, so
    # conf_control must find the red set empty and refuse it.
    total=$((total + 1))
    echo "RUN ControlUnsabotaged"
    dir="$root/build/controls/unsabotaged"
    stage "$dir"
    if run_driver "$dir" "$(printf 'import conformance_test\nconf_control("align-padding")')"; then
        echo "    an unsabotaged reader passed the align-padding control"
        echo "--- FAIL ControlUnsabotaged"
        failed=$((failed + 1))
    else
        echo "    an unsabotaged reader fails the align-padding control, as required"
        echo "--- PASS ControlUnsabotaged"
    fi

    # The reversed witnesses: a unit test must go red on the old behaviour.
    while IFS="$tab" read -r wname file count needle patch tdir tname; do
        case "$wname" in ''|'#'*) continue ;; esac
        total=$((total + 1))
        echo "RUN Witness$wname"
        dir="$root/build/controls/witness-$wname"
        stage "$dir"
        cp "$root"/test/"$tdir"/*.lobster "$dir"/
        if ! patch_line "$dir" "$file" "$count" "$needle" "$patch"; then
            echo "--- FAIL Witness$wname"
            failed=$((failed + 1))
            continue
        fi
        tfile=$(grep -l "^def $tname()" "$root"/test/"$tdir"/*_test.lobster | head -1)
        if [ -z "$tfile" ]; then
            echo "    test/$tdir has no $tname"
            echo "--- FAIL Witness$wname"
            failed=$((failed + 1))
            continue
        fi
        # The test's own verdict, as tools/run_tests.sh judges it: a test
        # marked `// expect-abort: <message>` passes only by aborting with it.
        expect=$(awk -v t="$tname" '
            /^\/\/ expect-abort: / { msg = substr($0, 18); next }
            $0 ~ "^def " t "\\(\\)" { print msg; exit }
            { msg = "" }' "$tfile")
        passed=0
        if run_driver "$dir" "$(printf 'import %s\n%s()' "$(basename "$tfile" .lobster)" "$tname")"; then
            if [ -z "$expect" ]; then passed=1; fi
        else
            if [ -n "$expect" ] && printf '%s\n' "$out" | grep -qxF "$expect"; then passed=1; fi
        fi
        if [ $passed -eq 1 ]; then
            echo "    $tname PASSED with the old behaviour planted back"
            echo "--- FAIL Witness$wname"
            failed=$((failed + 1))
        else
            echo "    $tname goes red with the old behaviour planted back"
            echo "--- PASS Witness$wname"
        fi
        out=""
    done <"$witnesses"
fi

if [ $failed -ne 0 ] || [ $missing -ne 0 ]; then
    echo "FAIL $failed of $total controls"
    exit 1
fi
echo "ok $total controls"
