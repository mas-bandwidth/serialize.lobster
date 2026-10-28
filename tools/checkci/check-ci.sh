#!/bin/sh
# tools/checkci/check-ci.sh -- TEST TestCheckCI (DESIGN.md, (g) THE RUNNER and
# "The vendored standard").
#
# Reads .github/workflows/ci.yml and DESIGN.md only; no network. It fails,
# naming the line, on any runs-on that is not [self-hosted, Linux, X64, fleet, serialize],
# when ci.yml spells a toolchain URL or sha256 (the pin lives once, in the
# Makefile), when the workflow does not run `make dist-lobster` and `make test`,
# or when its corpus pin (SERIALIZE_REF) differs from DESIGN.md's pin. A step that can never fail
# is refused too (audit 2026-10-27): a `make NAME` whose target no Makefile defines, and a run
# guarded by a file test (`if [ -f ... ]`), which skips green when the file is gone. Every other workflow in
# .github/workflows/ (the nightly functional test) is held to the same runner
# and the same one-place pin. Its own controls are
# scratch copies of ci.yml with `runs-on: ubuntu-latest` and with a pasted
# sha256, without the fork guard, and with the 2.0 bench step that could never fail: every copy
# must fail this check, or TestCheckCI fails.
set -u

root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
ci=${1:-"$root/.github/workflows/ci.yml"}
design="$root/DESIGN.md"

bad=0
fail() {
	printf '%s\n' "$*"
	bad=1
}

# scan_runs_on FILE prints every non-comment runs-on line whose value is not
# [self-hosted, Linux, X64, fleet, serialize], prefixed FILE:LINE.
scan_runs_on() {
	f=$1
	grep -nE '^[[:space:]]*runs-on:' "$f" |
		grep -vE '^[0-9]+:[[:space:]]*runs-on:[[:space:]]*\[self-hosted,[[:space:]]*Linux,[[:space:]]*X64,[[:space:]]*fleet,[[:space:]]*serialize\][[:space:]]*$' |
		sed "s|^|$f:|"
}

# scan_pin FILE prints every non-comment line that spells the toolchain pin
# (its URL, its archive name, or any 64-digit hex sha256), prefixed FILE:LINE.
scan_pin() {
	f=$1
	grep -nE 'aardappel/lobster|lobster-v[0-9]|lobster_linux_release\.zip|[0-9A-Fa-f]{64}' "$f" |
		grep -vE '^[0-9]+:[[:space:]]*#' |
		sed "s|^|$f:|"
}

# runs_make FILE NAME is true when a non-comment line invokes `make NAME`.
runs_make() {
	grep -nE "make[[:space:]]+$2([[:space:]]|;|$)" "$1" |
		grep -vE '^[0-9]+:[[:space:]]*#' >/dev/null
}

# scan_never_fails FILE prints every non-comment line that skips green: a run
# guarded by a file test, or a `make NAME` whose NAME no Makefile, make/*.mk or
# tools/roadmap/roadmap.mk defines as a target, prefixed FILE:LINE.
scan_never_fails() {
	f=$1
	grep -nE 'if[[:space:]]+\[[[:space:]]+-[ef][[:space:]]' "$f" |
		grep -vE '^[0-9]+:[[:space:]]*#' |
		sed "s|^|$f:|; s|$| (a file test that skips green)|"
	grep -nE 'make[[:space:]]+[A-Za-z][A-Za-z0-9_-]*' "$f" |
		grep -vE '^[0-9]+:[[:space:]]*#' |
		while IFS= read -r line; do
			for target in $(printf '%s\n' "$line" | grep -oE 'make[[:space:]]+[A-Za-z][A-Za-z0-9_-]*' | sed -E 's/^make[[:space:]]+//'); do
				if ! cat "$root/Makefile" "$root"/make/*.mk "$root/tools/roadmap/roadmap.mk" 2>/dev/null |
					grep -qE "^$target:"; then
					printf '%s:%s (make %s: no Makefile defines it)\n' "$f" "$line" "$target"
				fi
			done
		done
}

# a_ref LINE extracts the first corpus pin (a vX.Y.Z tag or a full 40-digit
# commit sha) from a FILE:LINE record, or empty.
a_ref() {
	printf '%s\n' "$1" | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+|[0-9a-f]{40}' | head -1
}

check_file() {
	target_ci=$1
	if [ ! -f "$target_ci" ]; then
		fail "$target_ci: ci.yml is missing"
		return
	fi

	runs_on_count=$(grep -cE '^[[:space:]]*runs-on:' "$target_ci" || true)
	if [ "$runs_on_count" -eq 0 ]; then
		fail "$target_ci:1: ci.yml declares no runs-on line"
	fi

	while IFS= read -r bad_runner; do
		[ -n "$bad_runner" ] && fail "$bad_runner: runs-on must be [self-hosted, Linux, X64, fleet, serialize]"
	done <<EOF_RUNS_ON
$(scan_runs_on "$target_ci")
EOF_RUNS_ON

	while IFS= read -r spelled; do
		[ -n "$spelled" ] && fail "$spelled: the toolchain pin is spelled in ci.yml; it belongs only in the Makefile"
	done <<EOF_PIN
$(scan_pin "$target_ci")
EOF_PIN

	# THE FORK GUARD: every job carries the same-repository `if:` (the repository
	# is public and its runners are the fleet's), so a fork's pull request never
	# reaches them.
	guard_count=$(grep -cE "^[[:space:]]*if:[[:space:]]*github\.event_name != 'pull_request' \|\| github\.event\.pull_request\.head\.repo\.full_name == github\.repository[[:space:]]*$" "$target_ci" || true)
	if [ "$guard_count" -ne "$runs_on_count" ]; then
		fail "$target_ci:1: $runs_on_count job(s) but $guard_count fork guard(s); every job needs the same-repository if:"
	fi

	while IFS= read -r never; do
		[ -n "$never" ] && fail "$never: a CI step that can never fail"
	done <<EOF_NEVER
$(scan_never_fails "$target_ci")
EOF_NEVER

	for target in dist-lobster test; do
		runs_make "$target_ci" "$target" || fail "$target_ci:1: ci.yml does not run 'make $target'"
	done

	ci_line=$(grep -nE '^[[:space:]]*SERIALIZE_REF:' "$target_ci" | head -1)
	ci_lineno=$(printf '%s\n' "$ci_line" | cut -d: -f1)
	ci_ref=$(a_ref "$ci_line")
	design_line=$(grep -nE 'VERBATIM from mas-bandwidth/serialize at ' "$design" | head -1)
	design_lineno=$(printf '%s\n' "$design_line" | cut -d: -f1)
	design_ref=$(a_ref "$design_line")
	case "$ci_ref" in
	'')
		fail "$target_ci:${ci_lineno:-1}: ci.yml does not name a SERIALIZE_REF corpus pin" ;;
	*)
		if [ "$ci_ref" != "$design_ref" ]; then
			fail "$target_ci:$ci_line: corpus pin $ci_ref differs from DESIGN.md:${design_lineno:-1} corpus pin ${design_ref:-none}"
		fi ;;
	esac
}

printf 'RUN TestCheckCI\n'

check_file "$ci"

# Every other workflow: the fleet runner and the Makefile pin, as ci.yml.
if [ $# -eq 0 ]; then
	for wf in "$root"/.github/workflows/*.yml; do
		[ "$wf" = "$ci" ] && continue
		while IFS= read -r bad_runner; do
			[ -n "$bad_runner" ] && fail "$bad_runner: runs-on must be [self-hosted, Linux, X64, fleet, serialize]"
		done <<EOF_WF_RUNS_ON
$(scan_runs_on "$wf")
EOF_WF_RUNS_ON
		while IFS= read -r spelled; do
			[ -n "$spelled" ] && fail "$spelled: the toolchain pin is spelled in a workflow; it belongs only in the Makefile"
		done <<EOF_WF_PIN
$(scan_pin "$wf")
EOF_WF_PIN
		while IFS= read -r never; do
			[ -n "$never" ] && fail "$never: a workflow step that can never fail"
		done <<EOF_WF_NEVER
$(scan_never_fails "$wf")
EOF_WF_NEVER
	done
fi

# Run self-controls when checking the repository's default ci.yml.
if [ $# -eq 0 ] && [ "$bad" -eq 0 ]; then
	mkdir -p "$root/build"
	ctl=$(mktemp -d "$root/build/checkci.XXXXXX") || fail "control: cannot make a scratch directory under $root/build"
	if [ -n "${ctl:-}" ] && [ -d "$ctl" ]; then
		sed 's/runs-on: \[self-hosted, Linux, X64, fleet, serialize\]/runs-on: ubuntu-latest/' "$ci" >"$ctl/ci-runner.yml"
		if sh "$0" "$ctl/ci-runner.yml" >"$ctl/runner.out" 2>&1; then
			fail "control: a scratch ci.yml with runs-on: ubuntu-latest passed; it must fail"
		else
			printf 'control: scratch ci.yml with runs-on: ubuntu-latest failed as required:\n'
			sed 's/^/  /' "$ctl/runner.out"
		fi

		cp "$ci" "$ctl/ci-pin.yml"
		printf '      - run: echo 2f03fb96fdaf6935469c99e43ffb182cab0d797faec7b26eccc9a732df32ad31\n' >>"$ctl/ci-pin.yml"
		if sh "$0" "$ctl/ci-pin.yml" >"$ctl/pin.out" 2>&1; then
			fail "control: a scratch ci.yml with a pasted sha256 passed; it must fail"
		else
			printf 'control: scratch ci.yml with a pasted sha256 failed as required:\n'
			sed 's/^/  /' "$ctl/pin.out"
		fi

		grep -v "head.repo.full_name == github.repository" "$ci" >"$ctl/ci-fork.yml"
		if sh "$0" "$ctl/ci-fork.yml" >"$ctl/fork.out" 2>&1; then
			fail "control: a scratch ci.yml without the fork guard passed; it must fail"
		else
			printf 'control: scratch ci.yml without the fork guard failed as required:\n'
			sed 's/^/  /' "$ctl/fork.out"
		fi

		cp "$ci" "$ctl/ci-bench.yml"
		printf '      - name: Bench check\n        run: if [ -f make/bench.mk ]; then make bench-check; fi\n' >>"$ctl/ci-bench.yml"
		if sh "$0" "$ctl/ci-bench.yml" >"$ctl/bench.out" 2>&1; then
			fail "control: a scratch ci.yml with the bench step that can never fail passed; it must fail"
		else
			printf 'control: scratch ci.yml with the bench step that can never fail failed as required:\n'
			sed 's/^/  /' "$ctl/bench.out"
		fi

		rm -rf "$ctl"
	fi
fi

if [ "$bad" -ne 0 ]; then
	printf -- '--- FAIL TestCheckCI\n'
	exit 1
fi
printf -- '--- PASS TestCheckCI\n'
