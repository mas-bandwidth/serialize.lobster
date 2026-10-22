#!/bin/sh
# tools/run_tests.sh — the test runner (DESIGN.md, (g) THE RUNNER).
#
# usage: LOBSTER=<lobster> tools/run_tests.sh [name]
#
# Runs every test/<name>/ (or only the one named). A test file is
# test/<name>/<x>_test.lobster; each `def Test<Name>():` at the start of a line
# is one test. Each test runs in its own process, from build/run/<name>/, which
# holds a copy of src/*.lobster, every .lobster file of test/<name>/, the
# vendored conformance/ and conformance-controls/ directories and one driver per test:
#
#     import <x>_test
#     Test<Name>()
#     print "serialize-test-done"
#
# A test passes when the process exits 0 AND printed the done line, and the
# compiler printed no warning (zero warnings, src/ and tests alike). A test whose
# def is preceded by the line `// expect-abort: <message>` passes only when the
# process exits nonzero AND printed <message> as a whole line, and never printed
# the done line: that is how an abort (API misuse, a stub) is proved.
#
# Prints `RUN Test<Name>`, then `--- PASS Test<Name>` or `--- FAIL Test<Name>`
# (the output indented below a FAIL). Exits nonzero on any FAIL, on a missing or
# empty test/<name>/, on a test file that declares no test: never a skip. The
# last line is `ok N test directories` or `FAIL k of N test directories`.

set -eu

root=$(cd "$(dirname "$0")/.." && pwd)
: "${LOBSTER:?LOBSTER must name the lobster executable (make test sets it)}"
done_line="serialize-test-done"

if [ $# -gt 1 ]; then
    echo "usage: tools/run_tests.sh [name]"
    exit 2
fi

if [ $# -eq 1 ] && [ -n "$1" ]; then
    names=$1
else
    names=""
    if [ -d "$root/test" ]; then
        for d in "$root"/test/*/; do
            [ -d "$d" ] || continue
            names="$names $(basename "$d")"
        done
    fi
    if [ -z "$names" ]; then
        echo "FAIL test/ has no test directories"
        echo "FAIL 1 of 1 test directories"
        exit 1
    fi
fi

if ! ls "$root"/src/*.lobster >/dev/null 2>&1; then
    echo "FAIL src/ has no .lobster files"
    echo "FAIL 1 of 1 test directories"
    exit 1
fi

total=0
failed_dirs=0

for name in $names; do
    total=$((total + 1))
    dir="$root/test/$name"
    if [ ! -d "$dir" ]; then
        echo "FAIL test/$name/ is missing"
        failed_dirs=$((failed_dirs + 1))
        continue
    fi
    files=$(ls "$dir"/*_test.lobster 2>/dev/null || true)
    if [ -z "$files" ]; then
        echo "FAIL test/$name/ is empty (no *_test.lobster)"
        failed_dirs=$((failed_dirs + 1))
        continue
    fi

    run="$root/build/run/$name"
    rm -rf "$run"
    mkdir -p "$run"
    cp "$root"/src/*.lobster "$run"/
    cp "$dir"/*.lobster "$run"/
    if [ -d "$root/conformance" ]; then
        cp -r "$root/conformance" "$run/conformance"
    fi
    if [ -d "$root/conformance-controls" ]; then
        cp -r "$root/conformance-controls" "$run/conformance-controls"
    fi

    dir_failed=0
    for file in $files; do
        base=$(basename "$file" .lobster)
        tests=$(sed -n 's/^def \(Test[A-Za-z0-9_]*\)().*/\1/p' "$file")
        if [ -z "$tests" ]; then
            echo "FAIL test/$name/$base.lobster declares no test"
            dir_failed=1
            continue
        fi
        for t in $tests; do
            expect=$(awk -v t="$t" '
                /^\/\/ expect-abort: / { msg = substr($0, 18); next }
                $0 ~ "^def " t "\\(\\)" { print msg; exit }
                { msg = "" }' "$file")
            driver="$run/_run_${base}_$t.lobster"
            printf 'import %s\n%s()\nprint "%s"\n' "$base" "$t" "$done_line" > "$driver"
            echo "RUN $t"
            set +e
            out=$(cd "$run" && "$LOBSTER" "$(basename "$driver")" 2>&1)
            code=$?
            set -e
            ok=0
            # Zero warnings, always: a compiler warning anywhere in the
            # program (src/ or the test) fails the test.
            warned=0
            if printf '%s\n' "$out" | grep -q ': warning: '; then warned=1; fi
            if [ $warned -eq 1 ]; then
                :
            elif [ -z "$expect" ]; then
                if [ $code -eq 0 ] && printf '%s\n' "$out" | grep -qx "$done_line"; then ok=1; fi
            else
                if [ $code -ne 0 ] && printf '%s\n' "$out" | grep -qxF "$expect" \
                    && ! printf '%s\n' "$out" | grep -qx "$done_line"; then ok=1; fi
            fi
            if [ $ok -eq 1 ]; then
                echo "--- PASS $t"
            else
                echo "--- FAIL $t"
                if [ $warned -eq 1 ]; then
                    echo "    the compiler warned (zero warnings is the rule)"
                fi
                if [ -n "$expect" ]; then
                    echo "    expected an abort (nonzero exit) printing: $expect"
                fi
                echo "    exit $code"
                printf '%s\n' "$out" | sed 's/^/    /'
                dir_failed=1
            fi
        done
    done
    if [ $dir_failed -ne 0 ]; then
        failed_dirs=$((failed_dirs + 1))
    fi
done

if [ $failed_dirs -ne 0 ]; then
    echo "FAIL $failed_dirs of $total test directories"
    exit 1
fi
echo "ok $total test directories"
