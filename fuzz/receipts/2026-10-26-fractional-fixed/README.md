# Receipt: the fractional fixed32/fixed64/fixed128 differential (exact head)

This directory is the executable evidence packet for the card
`ser-verify-lobster-fractional-fixed-differential` (attempt 2).  Every log
here was produced by a command that was actually run, in this order, on the
tree named below; each log begins with the exact command line (`# command:`)
and ends with its direct exit status (`# exit status:`).  Nothing in this
packet is copied from an earlier attempt: attempt 1's report was read once
and nothing was inferred from it.

## The source under test

- code under test: commit `dab091b46c132c162f0f5a82c0687d846994c021`
  ("Verify fractional fixed32/fixed64/fixed128 differential against
  serialize.c") on the branch
  `sprint/ser-verify-lobster-fractional-fixed-differential.w2.g1.e1`, off
  BASE `8782f3060cbd54cb454fd924b82a6697552907a6` (main as origin held it),
  plus this commit's comment-only correction in `fuzz/host.c` (13 lines, the
  description of the pairwise matrices, which did not match the matrices it
  describes).  `00-identities.log` prints that delta in full, and the runs
  were taken with it in the working tree.
- The commit that adds this packet changes nothing outside
  `fuzz/receipts/2026-10-26-fractional-fixed/` and that comment: check with
  `git diff --stat <head>~1 <head>`.
- The diff from BASE touches `fuzz/host.c`, `fuzz/fuzz_driver.lobster` and
  `make/fuzz.mk` only (493 insertions, 70 deletions, plus this packet).
  `src/` is untouched, so no public API, no wire format, no supported
  capacity and no trusted-writer doctrine changed, and no new diagnostic was
  added to the library.  `git diff --check BASE HEAD` is clean.
- The gate is wired into the existing CI and nightly tiers:
  `.github/workflows/ci.yml` runs `make fuzz` on every push,
  `.github/workflows/nightly-fuzz.yml` runs it with a drawn seed and a
  duration.  No workflow file was changed by this card.

## The gates, and their exit statuses

| log | command | exit | what it shows |
| --- | --- | --- | --- |
| `01-make-fuzz.log` | `make fuzz` | 0 | the per-push gate at its defaults: 2000 programs from the fixed seed 0x9e3779b97f4a7c15, and the seven named controls, each RED for its own reason |
| `02-make-test.log` | `make test` | 0 | the ordinary tests: 6 test directories, every one PASS |
| `03-make-controls.log` | `make controls` | 0 | the per-rule negative controls of the library: 20 controls |
| `04-make-check-ci.log` | `make check-ci` | 0 | the CI workflow invariants |
| `05-make-check-corpus-dir.log` | `make check-corpus-dir` | 0 | the corpus-override unit test |
| `06-make-roadmap-check.log` | `make roadmap-check` | 2 | **not runnable here**: the `sbcl` on PATH is a macOS Homebrew shim and this box has no sbcl (see "limits") |
| `07-fuzz-run-bounded-seed.log` | `make fuzz-run FUZZ_SEED=0xfeedfacecafebeef FUZZ_PROGRAMS=300` | 0 | the bounded fixed-seed differential |
| `nightly-seed-*.log` (4) | `make fuzz FUZZ_SEED=<seed> FUZZ_PROGRAMS=0 FUZZ_DURATION=<20 or 60>` | 0, 0, 0, 0 | the existing nightly tier, four seeds, with the seven controls red as expected in each |
| `12-failure-retention.log` | the host with `--corrupt-fraction-control --failures <dir>` | 1 | the first-failure witness: the run stops at the first failing batch and keeps it |
| `13-failure-retention-reproduce.log` | the same run from the retained `REPRODUCE.txt` | 1 | the retained batch is reproduced byte for byte (`cmp`: identical) |
| `16-base-make-fuzz.log` | `make fuzz` in the BASE tree | 0 | the BASE gate, with three controls, green |
| `17-base-fraction-mutant.log` | the BASE tree, the fraction mutant | 0 | **BASE-red**: the BASE cannot see a fractional defect |
| `18-head-fraction-mutant.log` | the HEAD tree, the same fraction mutant | 1 | **head-green**: HEAD sees it |

Every log is the raw stdout/stderr of the command; nothing is summarised
except where a log says so itself.

## The seven named controls

`19-control-counts.log` lists them: the BASE tree has three (`negative
control`, `reader negative control`, `reason negative control`), the tree
under test has seven (`c-fraction`, `lobster-fraction`, `c-high-group`,
`lobster-high-group` added).  Their raw logs are kept as artifacts:
`artifacts/default-make-fuzz/` (the default gate) and
`artifacts/nightly-<seed>/` (each nightly run).  The three that existed
before this card -- the widened range, the deleted range (the reader's range
refusal) and the wrong reason -- are still there and still red for their own
reason.

## BASE-red / head-green

The card's DONE-WHEN requires that corrupting the fraction bits of either
oracle makes a named control fail.  That property is exactly what the BASE
lacks: `fuzz/host.c` at BASE supplies `fraction_bits=0` for every randomized
fixed operation, so a fraction defect cannot be seen at all.  The pair below
runs the *same* sabotage on both trees, with the same seed and the same
program count; the sabotage is the one line of `src/serialize_fixed.lobster`
that `make fuzz`'s `lobster-fraction` control uses:

    return serialize_fixed_shl128(serialize_fixed_from_int64(whole), fraction_bits)
    -> return serialize_fixed_shl128(serialize_fixed_from_int64(whole), 0)

- BASE (`17-base-fraction-mutant.log`): the differential stays **green**
  (exit 0, 2000 programs, 495 mutants) -- the mutant survives, so the card's
  DONE-WHEN is **red at BASE**.
- HEAD (`18-head-fraction-mutant.log`): the same mutant makes the
  differential **red** (exit 1, "Lobster writer failed", failing batch
  programs 0..99) -- **green at HEAD**.

The BASE tree is the tracked files of BASE, extracted with `git archive`
(`15-base-tree.log`); it is not a clone of anything and shares no build
state with the tree under test.

## The coverage witness: fractional fixed cases are really generated

`14-fraction-coverage.log` tabulates the fixed specifications the
deterministic generator emitted in one retained batch (100 programs, the
default seed): 162 fixed operations (51 fixed32, 53 fixed64, 58 fixed128),
61 distinct `(kind, integer_bits, fraction_bits)` triples, with zero and
nonzero fraction bits, degenerate ranges, and the integer/fraction split at
and around the 32-bit group boundaries of each storage (the generator's own
pairwise matrices are in `fuzz/host.c`: `FIXED32_SPECS` 19 specs, `FIXED64_SPECS`
25, `FIXED128_SPECS` 30; the raw value is chosen by `pick_fixed_raw_value` at
and one step inside the representable extremes).  It is a pairwise matrix,
not a Cartesian product.

The comparison lanes the two oracles are held to (the C oracle in
`fuzz/host.c`, the Lobster driver in `fuzz/fuzz_driver.lobster`): canonical
written bytes (`host.c:1196`), the Lobster writer's own success
(`host.c:1190`), written bit counts (`host.c:1206`), the
`serialize_measure_stream` bit and byte counts (`host.c:1212`), the decoded
raw values, the refusal step and reason (`host.c:1096`, `host.c:1101`), the
consumed bits (`host.c:1106`) and the terminal post-refusal behaviour
(`host.c:1111`, `fuzz_driver.lobster:348`).

## The first-failure retention witness

`12-failure-retention.log` is a deliberately failing run (the C oracle's
fraction bits perturbed, `--corrupt-fraction-control`): the run stops at the
**first** failing batch, names it (`failing batch: programs 0..99, seed
0x9e3779b97f4a7c15`) and keeps it under `artifacts/failure-witness/`:

- `batch.txt` -- the batch the Lobster child read (the generated programs),
- `result.txt` -- what the child wrote,
- `REPRODUCE.txt` -- the seed and the program count that regenerate it.

`13-failure-retention-reproduce.log` runs the `REPRODUCE.txt` line again and
`cmp`s the two retained batches: identical.

## The identities (`00-identities.log`)

- source: the commit, the branch, the tracked delta the runs were taken on,
  the diff from BASE, `git diff --check` clean.
- oracle: serialize.c **v2.0.0**, commit
  `e11585b0dfbf214ed37c442d5f8b6133fd8b10df`, cloned by `make fuzz-ref` from
  `https://github.com/mas-bandwidth/serialize.c` (tag `v2.0.0`), sha256 of
  `serialize.h` and `serialize.c` recorded.
- toolchain: Lobster **v2026.8**, the pin's zip sha256
  `2f03fb96fdaf6935469c99e43ffb182cab0d797faec7b26eccc9a732df32ad31`
  (the fetched archive hashes to the pin), binary sha256 recorded; tag object
  `0921f7dd57458e1373a054880b84ceb9b5d719a5`, commit
  `acc66d71978ae5525be1356aa622fbaa9a57e848`.
- C compilers: gcc 13.3.0 (`cc`), clang 18.1.3, GNU Make 4.3.
- platform: Linux x86_64 (Ubuntu 24.04, kernel 6.8.0-142-generic).

## Limits, and what was not done

- `make roadmap-check` could not run here: the only `sbcl` on PATH is a
  macOS Homebrew shim (`06-make-roadmap-check.log`, exit 2, the interpreter
  path does not exist on this Linux box).  It is a CI step for `ROADMAP.md`,
  unrelated to the fuzz harness, and it is reported here as **not run**
  rather than as a pass.
- The GitHub Actions workflows themselves were not executed: they run on the
  project's own fleet runners.  What was executed is the make targets they
  call, on Linux x86_64 only.  No macOS, Windows or 32-bit platform was
  exercised; the differential gate is Linux-only in CI (`GATE-NEEDS: linux`).
- The nightly tier was exercised locally with the seeds and durations listed
  above (20s, 20s, 20s, 60s), not with the workflow's default hour.
- AOT and consumer equivalence remain unclaimed: nothing here compares the
  `--cpp` build or a consumer of the library.
- The one-line source change attempt 1 made is not repeated here; the
  receipt covers the tree that change produced.
