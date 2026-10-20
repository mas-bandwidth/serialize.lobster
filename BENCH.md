# BENCH.md — the Lobster serialize benchmark

**Status: incomplete (HOLD).** This card's DONE-WHEN requires four runners
(C, C++, Rust, Lobster twice) over one workload set in `make bench`, and
`make bench-check` requiring every runner's bytes and checksums to agree.
What is here today is the **Lobster leg only**: one untimed shape gate
(`make bench-check`, `TestBenchShapesAgree`) and a timed target
(`make bench`). The C, C++, Rust and `--cpp` legs, the mixed message row,
and the cross-language tables are **not implemented**.

## Method

- **Workload.** The bits family is BENCH-STANDARD.md §1.4's 16-width table,
  `{1,32,7,13,3,25,8,19,4,28,11,16,2,30,6,22}`, over a 65536-byte buffer:
  one row per width, writing `65536*8/w` values to fill the buffer, and a
  separate read row over the same bytes.
- **Scalars.** `bool`, `uint32`, `uint64`, `int` in `[-1000,1000]`, `int64`
  in `[-1000000,1000000]`, `float`, `double`, `compressed_float` over
  `[-1,1]` with resolution `0.001`, `int_relative` (previous → previous+7),
  a 32-byte `bytes`, and a 24-byte `string`. Write and read are separate
  rows.
- **Shape gate.** `make bench-check` writes every row once, reads it back,
  and requires each row's byte count and FNV-1a-64 checksum to equal
  `bench/golden.csv`. It is untimed.
- **Timing (planned).** Three warm-up runs then 15 timed runs per row;
  report the median with min and max, pinned to one core with `taskset`;
  one CSV per sweep with host, CPU, governor, compiler and date.

## Measured

None published. The timed target reports ns/op for the bits write rows; no
cross-language table exists yet, so no ratio of C is shown. A table with a
single leg would not answer Glenn's question.

## What is not done

1. C (`serialize.c` v1.11.2), C++ (`serialize` v1.17.0) and Rust
   (`serialize.rs` v2.4.0) runners, built from the `.ref` checkouts.
2. The Lobster `--cpp` leg (clang -O2) as a second Lobster runner.
3. The `mixed` row: one message of all operations.
4. Timing for read rows, and the CSV's full recording.
5. Cross-language byte/checksum agreement: the shape gate currently pins
   the Lobster rows against a committed golden, not against the other
   runners.
6. `BENCH-STANDARD.md` §1.4 note: the bitpacker read leg must call the
   checked bit read; the Lobster read rows do (`serialize_read_stream`).
