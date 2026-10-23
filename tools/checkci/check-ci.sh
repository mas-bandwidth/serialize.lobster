#!/bin/sh
# tools/checkci/check-ci.sh -- TEST TestCheckCI (DESIGN.md, (g) THE RUNNER and
# "The vendored standard").
#
# Reads .github/workflows/ci.yml and DESIGN.md only; no network. It fails,
# naming the line, on any runs-on that is not [self-hosted, Linux, X64, fleet, serialize],
# when ci.yml spells a toolchain URL or sha256 (the pin lives once, in the
# Makefile), when the workflow does not run `make dist-lobster` and `make test`,
# or when its corpus tag differs from DESIGN.md's pin. Every other workflow in
# .github/workflows/ (the nightly functional test) is held to the same runner
# and the same one-place pin. Its own controls are
# scratch copies of ci.yml with `runs-on: ubuntu-latest` and with a pasted
# sha256 and without the fork guard: every copy must fail this check, or TestCheckCI fails.
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

# a_tag LINE extracts the first vX.Y.Z from a FILE:LINE record, or empty.
a_tag() {
	printf '%s\n' "$1" | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' | head -1
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

	for target in dist-lobster test; do
		runs_make "$target_ci" "$target" || fail "$target_ci:1: ci.yml does not run 'make $target'"
	done

	ci_line=$(grep -nE '^[[:space:]]*SERIALIZE_TAG:' "$target_ci" | head -1)
	ci_lineno=$(printf '%s\n' "$ci_line" | cut -d: -f1)
	ci_tag=$(a_tag "$ci_line")
	design_line=$(grep -nE 'VERBATIM from mas-bandwidth/serialize at tag' "$design" | head -1)
	design_lineno=$(printf '%s\n' "$design_line" | cut -d: -f1)
	design_tag=$(a_tag "$design_line")
	case "$ci_tag" in
	'')
		fail "$target_ci:${ci_lineno:-1}: ci.yml does not name a SERIALIZE_TAG corpus pin" ;;
	*)
		if [ "$ci_tag" != "$design_tag" ]; then
			fail "$target_ci:$ci_line: corpus tag $ci_tag differs from DESIGN.md:${design_lineno:-1} corpus pin ${design_tag:-none}"
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

		rm -rf "$ctl"
	fi
fi

if [ "$bad" -ne 0 ]; then
	printf -- '--- FAIL TestCheckCI\n'
	exit 1
fi
printf -- '--- PASS TestCheckCI\n'
