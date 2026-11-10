# Changelog

## 2.1.3

The wire is format 2.0, standard 2.1; no byte a writer emits changed. STANDARD.md,
IMPLEMENTING.md and the conformance corpus are vendored from serialize v2.1.4.

- `serialize_bytes` on a read returns the string that holds the bytes read:
  the destination itself when it is writable in place, otherwise a new string.
  `unpack_bytes` returns that string.
- `serialize_write_stream(buffer)` traps on a buffer that is not writable in
  place.
- A write after a `flush` that stored a partial word traps (IMPLEMENTING.md
  U11).
- A compressed float decode rounds every operand to float32, as serialize.c
  does: an integer value float32 cannot hold decodes to the float32 the
  reference produces. A precomputed `delta` is rounded to float32 first.
- `serialize_bits_required(min, max)` takes the span at the full int width,
  the same rule as `serialize_bits_required64`.
- `string_utf8_valid(data, n)` returns false when `n` is outside the string.
- `failed` and `refusal` are fields of `serialize_read_stream` only; `ok()`,
  `error()`, `refusal_name()` and `fail()` remain on all three streams.
- `serialize_bytes` of zero count aligns and copies nothing on every stream
  (IMPLEMENTING.md U7).
- Added: `serialize_version`, this port's release; `serialize_u128_from_int64`,
  `serialize_int128_to_u128`, `serialize_u128_to_int128`, `serialize_u128_shl`.
- Removed internal names: `serialize_stub`, `serialize_ule`, the
  `serialize_fixed_*128` helpers, `serialize_fixed_group32`,
  `serialize_fixed_write_u128`, `serialize_fixed_read_u128`.
