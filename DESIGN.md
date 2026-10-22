# serialize.lobster: the design every card copies

serialize.lobster ports serialize, the open-source bitpacking serializer, to
[Lobster](https://github.com/aardappel/lobster). It is the bottom layer under
schema's Lobster leg. This page settles every decision, so each family card
after it fills one set of files and decides nothing. Sections (a) to (g) are
the contract.

**The oracle.** serialize.c v2.0.0 (`e11585b0dfbf214ed37c442d5f8b6133fd8b10df`),
format 2.0, is the reference. This port matches it byte for byte and refusal for refusal.
serialize.luau (branch `sprint/serialize-luau`,
`e9acef6fee5efbb1c7b33a25843dba9aa59f6b22`) is the closest worked port and
shaped this page. Both are read and never imported. STANDARD.md's
Implementation Law says sibling ports are never sources, so where the Luau page
and serialize.c disagree, serialize.c and STANDARD.md decide.

**The vendored standard.** `STANDARD.md`, `IMPLEMENTING.md`, `conformance/`
and `conformance-controls/` are copied
VERBATIM from mas-bandwidth/serialize at tag v2.0.0
(merge `8dae4cc08b7b46c9b5fcf08dad5e99ad1348b76b`); the standard and
the corpus are byte-identical at the format 2.0 pin
`dedf58efa93832fd243dbf3a2a1ca0a91c46b14b`. `tools/revendor.sh <tag>` copies
them from a clone of the tag and diffs each one, and the CI `corpus` job diffs
all four against the tag on every run. The corpus holds 18 files: format 2.0
removed `wstring.txt` and added `end.txt`.

Nothing here edits them; a change arrives by re-vendoring from a new tag.

**The pin.** Lobster v2026.8 is pinned through its release zip, with the sha256
below. The tag `v2026.8` is the annotated tag object
`0921f7dd57458e1373a054880b84ceb9b5d719a5`, which points at commit
`acc66d71978ae5525be1356aa622fbaa9a57e848`. The brief's "commit 0921f7dd5745"
is the tag object; the `--cpp` leg checks out the commit. The setup is
`make dist-lobster`, described in (g).

## (a) THE API

`import serialize` brings in the whole library. The test runner and `make bench`
stage `src/` beside the program; see (g).

**One spelling for three streams.** serialize.c spells every operation three
times, as `serialize_write_X`, `serialize_read_X` and `serialize_measure_X`,
because C has no templates. Lobster has the next best thing. A function whose
argument has no type is specialized at compile time for each type it is called
with, which is the C++ library's template model. So this port gives each
operation ONE name, `serialize_X`, defined on all three stream classes with the
same signature. A message is written once, as a function over an untyped
stream:

    def serialize(m::message, s) -> bool:
        m.health = s.serialize_int(m.health, 0, 100)
        m.alive = s.serialize_bool(m.alive)
        return s.ok()

That one definition compiles three ways. STANDARD.md, "Read-only and write-only
forms", says the API surface is not constrained, and that one stream
abstraction with read, write and measure conformers is admitted. The
`serialize_` prefix is kept from serialize.c. Lobster's `namespace` does not
apply to methods called with dot syntax (measured: `s.serialize_int` fails to
resolve when the definition sits in a namespace), so the library uses the
prefix and declares no namespace.

**Values move by return.** Lobster has no out parameters. Every value operation
takes the destination's current value and returns two things: the new value,
and `ok`, which is `true` on success and `false` on a refusal.

- A write returns its input unchanged.
- A read returns the decoded value. On a refusal it returns the input
  unchanged, so a refused read leaves the destination as it was (STANDARD.md,
  Reader Obligations).
- A measure returns its input.

Lobster discards a return value that has no variable to receive it, so
`m.x = s.serialize_int(m.x, 0, 7)` is the usual form. The latch, (e), makes it
safe to check `s.ok()` once at the end. Operations that carry no value
(`serialize_align`, `serialize_end`, `serialize_object`) return `ok` alone.

**A packet ends with its end.** STANDARD.md, end: a reader reads
`s.serialize_end()` after the last field of the packet's top-level object,
over a stream holding exactly the bytes the writer reported. It refuses a
whole byte or more left over as `trailing_data` and a set bit in the final
byte's unused bits as `nonzero_padding`. A writer's end emits nothing and a
measure's costs nothing, so the same message function serves all three:

    def serialize(m::message, s) -> bool:
        m.health = s.serialize_int(m.health, 0, 100)
        m.alive = s.serialize_bool(m.alive)
        s.serialize_end()
        return s.ok()

### The streams (src/serialize_stream.lobster)

| Lobster | serialize.c | notes |
|---|---|---|
| `serialize_write_stream(buffer:string)` | `serialize_write_stream_init` | the capacity is `length(buffer)`, which must be a multiple of 8 (else abort) |
| `serialize_read_stream(data:string, bytes:int)` | `serialize_read_stream_init` | in place; `length(data) >= bytes + 8`, the slack contract (else abort) |
| `serialize_read_stream_padded(data:string)` | `serialize_read_stream_init_padded` | copies `data` into a fresh string with 8 zero bytes of slack |
| `serialize_measure_stream()` | `serialize_measure_stream_init` | |
| `s.flush()` (write) | `serialize_write_flush` | call once, after the final write |
| `s.bits_processed()`, `s.bytes_processed()` | `serialize_*_bits_processed`, `_bytes_processed` | |
| `s.bits_available()` (write) | `serialize_write_bits_available` | |
| `s.bits_remaining()` (read) | `serialize_read_bits_remaining` | |
| `s.align_bits()` (write, read) | `serialize_write_align_bits`, `serialize_read_align_bits` | |
| `s.error()`, `s.ok()` | `serialize_*_error` | `ok()` is `not error()` |
| `s.fail(reason)` | `serialize_write_fail`, `serialize_read_fail` | latches the stream with a reason and returns `false`; only the first reason is kept |
| `s.refusal`, `s.refusal_name()` | `serialize_read_refusal`, `serialize_refusal_name` | the first refusal's reason, `serialize_refusal_none` (`"none"`) before one |
| `s.is_writing()`, `s.is_reading()` | (C++ `IsWriting`, `IsReading`) | added, see below |

Deviations, each with its reason:

- **Write buffer.** serialize.c asks for a multiple of 4 bytes. This port asks
  for a multiple of 8, because each word is stored with `write_int64_le`, and
  Lobster's `write_int64_le` GROWS a string when the store runs past its end.
  A final 8-byte store into a 4-byte tail would silently resize the caller's
  buffer.
- **Read slack.** `serialize_read_stream` checks the slack contract once, at
  construction, and aborts there if it is broken. A Lobster read past a
  string's end is a VM error, not undefined behaviour, so a broken contract
  would otherwise abort later, at a point decided by data. With the check at
  construction, only the caller's own arguments can trigger the abort.
- **No re-initialization.** A stream is created fresh, and a failed stream is
  discarded. STANDARD.md, "Failure is terminal", says "An implementation with
  no re-initialization discards."
- **Direction.** `is_writing()` and `is_reading()` are added (the measure
  stream answers false to both). One function that serves three streams
  sometimes has to branch on direction, as the C++ `Stream` interface allows.
- **The failed read cursor.** serialize.c poisons a failed read stream's
  cursor to `num_bits + 1`. This port keeps the latch in the `failed` field
  instead, and the cursor stays where the last successful operation left it.
  Lobster's per-read cost is the same either way: every read tests the latch
  first, as STANDARD.md requires of zero-bit reads.

### The operations (every stream)

| method | value type | serialize.c | family file |
|---|---|---|---|
| `serialize_bits(value, bits)` | int in [0,2^32); bits in [1,32] | `serialize_*_bits` | bitpacker |
| `serialize_bits64(value, bits)` | int (u64 pattern); bits in [1,64] | `serialize_*_bits64` | bitpacker |
| `serialize_bool(value)` | bool | `serialize_*_bool` | stream |
| `serialize_align()` | returns ok | `serialize_*_align` | stream |
| `serialize_end()` | returns ok | `serialize_*_end` | stream |
| `serialize_uint8(value)`, `serialize_uint16`, `serialize_uint32` | int | `serialize_*_uint8/16/32` | stream |
| `serialize_uint64(value)` | int (u64 pattern) | `serialize_*_uint64` | stream |
| `serialize_int(value, min, max)` | int; min, max int32 | `serialize_*_int` | int |
| `serialize_int64(value, min, max)` | int | `serialize_*_int64` | int |
| `serialize_int_relative(previous, current)` | int; returns current | `serialize_*_int_relative` | int |
| `serialize_uint128(value)` | `serialize_uint128` | `serialize_*_uint128` | int128 |
| `serialize_int128(value, min, max)` | `serialize_int128` | `serialize_*_int128` | int128 |
| `serialize_float(value)` | float (a float32 on the wire) | `serialize_*_float` | float |
| `serialize_double(value)` | float | `serialize_*_double` | float |
| `serialize_fixed32(value, integer_bits, fraction_bits, min, max)` | int (int32 raw) | `serialize_*_fixed32` | fixed |
| `serialize_fixed64(value, integer_bits, fraction_bits, min, max)` | int (int64 raw) | `serialize_*_fixed64` | fixed |
| `serialize_fixed128(value, integer_bits, fraction_bits, min, max)` | `serialize_int128` raw; min, max int | `serialize_*_fixed128` | fixed |
| `serialize_compressed_float(value, min, max, res)` | float | `serialize_*_compressed_float` | compressed_float |
| `serialize_compressed_float_precomputed(value, max_integer_value, bits, delta, min)` | float | `serialize_*_compressed_float_precomputed` | compressed_float |
| `serialize_bytes(data, bytes)` | string; returns data | `serialize_*_bytes` | bytes |
| `serialize_string(value, buffer_size)` | string | `serialize_*_string` | bytes |
| `serialize_object(object)` | returns ok | (STANDARD.md, object) | object |

The measure forms take the same arguments as the write forms. A measure uses
only what sets the width: the bounds, `bits`, and the value only for
int_relative and string. That is the doctrine serialize.c states for
its measure functions.

### The free functions

| Lobster | serialize.c | family file |
|---|---|---|
| `serialize_format_version` (`"2.0"`) | STANDARD.md, Format version | stream |
| `serialize_refusal` (enum), `serialize_refusal_name(r)`, `serialize_refusal_names` | `serialize_refusal_t`, `serialize_refusal_name` | stream |
| `serialize_float32_bits_are_finite(u)`, `serialize_float64_bits_are_finite(u)` | (C++ `float_bits_are_finite`, `double_bits_are_finite`) | float |
| `serialize_bits_required(min, max)` | `serialize_bits_required` (the uint32 domain) | bitpacker |
| `serialize_bits_required64(min, max)` | `serialize_bits_required64` (u64 patterns) | bitpacker |
| `serialize_uint128 { lo, hi }`, `serialize_int128 { lo, hi }` | `serialize_uint128_t`, `serialize_int128_t` | int128 |
| `serialize_uint128_make(hi, lo)`, `serialize_int128_make(hi, lo)` | `serialize_uint128_make`, `serialize_int128_make` (hi first, as C) | int128 |
| `serialize_int128_from_int64(v)` | `serialize_int128_from_int64` | int128 |
| `serialize_uint128_equal(a, b)`, `serialize_int128_equal(a, b)` | same | int128 |
| `serialize_int128_compare(a, b)` (-1, 0, 1, signed) | same | int128 |
| `serialize_compressed_float_params(min, max, res)` returns `max_integer_value, bits, delta` | `serialize_compressed_float_params` (out parameters become three returns) | compressed_float |
| `serialize_float32_round(x)`, `serialize_float32_bits(x)`, `serialize_float32_from_bits(u)`, `serialize_float64_bits(x)`, `serialize_float64_from_bits(u)` | (the routes in (c)) | float |
| `serialize_ult`, `serialize_ule`, `serialize_mask`, `serialize_shr`, `serialize_shl` | (the number model, (c)) | stream |

`serialize_copy_string` is left out: a Lobster string is a counted value with
no terminator to copy.

**serialize_object.** serialize.c has no object operation; STANDARD.md does.
`s.serialize_object(o)` refuses on a failed stream before calling anything
(STANDARD.md, Reader Obligations: zero-bit reads consult the latch). Otherwise
it calls `o.serialize(s)`. That is the caller's own generic function, which is
specialized per stream and returns `true` on success. When it returns `false`,
the stream latches through `s.fail(serialize_refusal_value_out_of_range)`, so a
refused object leaves the stream terminal: a refusal inside the object keeps
its own first reason, and an object that rejects a decoded value of its own,
with no stream refusal, reports `value_out_of_range`. The operation adds no
bytes of its own.

**bool.** A Lobster `bool` is an enum. A read returns `bool(bit)`.

**Refusal reasons.** Every refusal names its rule from STANDARD.md's closed
list, spelled by `serialize_refusal_name` exactly as STANDARD.md spells it:
`past_end`, `value_out_of_range`, `nonzero_padding`, `trailing_data`,
`non_finite_float`, `invalid_utf8`, `embedded_nul`, `non_canonical`. The
stream latches the FIRST reason; a later refusal on a failed stream is its
echo and keeps it. The idiom is an accessor, `s.refusal_name()`, next to the
latch.

**wstring is gone.** Format 2.0 removed it: text is UTF-8 and only UTF-8.

## (b) BIT ORDER AND ENDIANNESS

Exactly as serialize.c. STANDARD.md, General Conventions, quoted:

> All multi-byte quantities are **little-endian**.
>
> The stream is accumulated in a **64-bit scratch word**. Bits are packed
> **least-significant-bit first**: the first value written occupies the lowest
> bits of the first word. When the scratch fills, the 64-bit word is copied to
> the buffer in host byte order on little-endian machines, and byte-swapped on
> big-endian machines. The result is the same bytes on the wire everywhere.
>
> A value of `n` bits, written when the scratch already holds `s` bits, occupies
> bits `[s, s+n)` of the current word. A value that would cross the 64-bit
> boundary is split: the low `64-s` bits complete the current word, and the
> remainder begins the next.
>
> **Flush.** After the final value, any partially filled scratch word is written
> out. The stream therefore always occupies a whole number of 8-byte words in the
> writer's buffer, but the meaningful length is the number of bytes actually
> required, rounded up to a byte.

The rules for this library:

- **The scratch word** is one Lobster `int`: `scratch`, `scratch_bits`,
  `word_index` and `bits_written` on the write stream. A full word is stored
  with `write_int64_le(buffer, word_index * 8, scratch)`. Lobster's
  `write_int64_le` is little-endian by definition, so no store consults the
  host.
- **The reader** loads a 64-bit window at byte granularity, with
  `read_uint64_le(data, bits_read >> 3)`, then shifts right by `bits_read & 7`
  and masks, as serialize.c's reader does. A window load may cover up to 8
  bytes past `bytes`, which is the slack contract (d). Those bytes are loaded
  and never interpreted: every bit the reader keeps lies below
  `8 * bytes`, because the read gate (e) checked the whole width first.
- **Widths over 32.** A `bits > 32` value is written as the low 32 bits first,
  as a 32-bit group, then the `bits - 32` high bits (STANDARD.md bits).
  `serialize_uint64` is the low 32 bits, then the high 32.
- **128-bit values.** A uint128 or int128 offset is the low 64-bit lane first,
  then the high lane. Each lane goes as `serialize_bits(half, 64)` (STANDARD.md
  uint128, int128).
- **Flush and length.** `flush()` stores the partial word.
  `bytes_processed()` is `(bits_processed() + 7) >> 3`.
- **Trailing bits.** The writer writes zeros, because the flushed scratch above
  the bit index is zero by construction. A reader never looks at them
  (STANDARD.md, Reader Obligations, Trailing bits).
- **Alignment.** `align_bits()` is `(8 - (bit_index & 7)) & 7`, and an already
  aligned align writes nothing.

## (c) THE NUMBER MODEL

Measured on hulk with the pinned release binary, 2026-10-19 (the brief's
hetzner2 measurements agree):

- **One integer type.** Lobster's `int` is signed 64-bit, and every value of
  64 bits or fewer lives in it. That covers bits, uint8 to uint64, int, int64,
  int_relative, raw fixed values, quantized compressed floats and lengths. A
  u64 (uint64, `serialize_bits64`, the 128-bit lanes) is held as its
  two's-complement bit pattern, so `read_uint64_le` of eight 0xFF bytes is
  `-1`. Spell an unsigned constant in hex.
- **Right shifts.** `>>` is arithmetic: `0x8000000000000000 >> 63` is `-1`.
  Lobster has no logical shift, so every right shift of a word is followed by
  its mask, written as `serialize_shr(v, n)`.
- **Shift counts.** A shift count is taken mod 64: `1 << 64` is `1`. Every
  count that can reach 0 or 64 is therefore guarded, through `serialize_shl`,
  `serialize_shr` and `serialize_mask(bits)`. `serialize_mask(64)` is `-1`
  and `serialize_mask(0)` is `0`.
- **Unsigned order.** Comparing two u64 patterns flips the sign bit and then
  compares signed: `serialize_ult(a, b)` and `serialize_ule(a, b)`. Signed
  values (int64, fixed raw, the int128 high lane) use `<` directly.
- **Wrapping.** Lobster's `+`, `-` and `*` on `int` wrap two's-complement and
  never trap, so offsets such as `value - min` are taken in that arithmetic and
  then read unsigned. This is STANDARD.md's "uses wrapping operations on the
  read path".
- **128 bits.** Lobster has no 128-bit integer, so a 128-bit value is two int
  lanes, `{ lo, hi }`. This is serialize.c's own emulation (`serialize_u128_*`)
  and is the same wire.
- **popcount** exists and may serve bit length.
- **The int32 domain.** A parameter whose C type is `int32` (the bounds of
  `serialize_int` and `serialize_fixed32`, and `previous` in int_relative) is
  checked as an int32 at the call, and anything else aborts, (e). A value the
  C type could hold but the operation refuses latches instead.

**float32.** Lobster's `float` is f64 only. A float32 is rounded, and its bits
are produced, through a 16-byte scratch string the float family owns,
allocated once and reused. Two rounding routes and two bit routes were timed
over 10,000,000 calls each, under the JIT and under `--cpp` with clang -O2, on
hulk on 2026-10-19 (the program is in "The timing" below). Run 1 drove the
binaries directly. Run 2 was `make bench`, at nice 19 with the bench's load
average near 24 on 64 cores.

| route | JIT ns/op (run 1 / run 2) | --cpp ns/op (run 1 / run 2) |
|---|---|---|
| f32 bits: `write_float32_le` + `read_uint32_le` into the scratch | 37.9 / 18.3 | 4.31 / 5.27 |
| f32 bits: `vector_to_buffer([x], 4)` + `read_uint32_le` | 149.8 / 71.3 | 34.3 / 50.5 |
| round to f32: `write_float32_le` + `read_float32_le` | 44.5 / 21.1 | 4.45 / 4.67 |
| round to f32: store into a `float<32>` struct field, read it back | 28.6 / 20.6 | 1.11 / 1.09 |
| f32 from bits: `write_int32_le` + `read_float32_le` | 42.7 / 21.3 | 4.21 / 4.63 |
| f64 bits: `write_float64_le` + `read_uint64_le` | 40.2 / 19.5 | 4.12 / 4.59 |

Decided:

- `serialize_float32_bits(x)` and `serialize_float32_from_bits(u)` go through
  the scratch string. It is the fastest route to the bits, 4x faster than
  `vector_to_buffer` under the JIT and 8x to 10x faster under `--cpp`.
- `serialize_float32_round(x)` goes through a `float<32>` field. It is never
  slower than the string under the JIT, and 4x faster under `--cpp`. Both
  routes produced the same sum over the 10,000,000 values.
- compressed_float's float32 arithmetic is emulated by `serialize_float32_round`
  after every float32 operation, in serialize.c's order. A double result
  carries more than 2p+2 bits, so each rounding of a double operation on
  float32 operands equals the float32 operation.
- `serialize_double` moves its bits through `write_float64_le` and
  `read_uint64_le`, and back the reverse way.
- A float32 read never converts: the 32 wire bits are tested for a finite
  pattern on the RAW bits, then become the value through
  `serialize_float32_from_bits`, so every finite pattern, negative zero and
  the subnormals included, is the value read. Format 2.0 carries finite
  values only, so no NaN payload needs to survive anything.

## (d) BYTES

- **The type.** Bytes are a Lobster `string` used as a byte buffer. A string
  is a reference value, and the `write_*_le`, `write_substring` and
  `ensure_size` builtins mutate it in place, so the change is visible through
  every reference.
- **Writing.** The write stream stores its words directly into the caller's
  buffer, which is the zero-copy way out. After `flush()`, the caller's own
  string holds the message in its first `bytes_processed()` bytes. The caller
  builds the buffer with `ensure_size(string_with_capacity(n), n, 0)`, `n` a
  multiple of 8, and reuses it across messages.
- **Reading.** The read stream reads the caller's string in place with no copy
  when the caller holds the slack contract: `length(data) >= bytes + 8`. This
  is serialize.c's fast path. `serialize_read_stream_padded(data)` is the
  admitted copying entry (STANDARD.md, Reader Obligations, "A copying entry
  point ... is admitted"). It takes exact-length data and pays one copy.
- **serialize_bytes(data, bytes).** On write it sends the first `bytes` bytes
  of `data`, which must be at least that long (else abort). On read it stores
  the bytes into `data` in place at offset 0. `data` must already be at least
  `bytes` long (else abort), and the same string is returned. After a refusal
  its contents are unspecified, as STANDARD.md allows. The aligned body moves
  through `pack_bytes` and `unpack_bytes` (bitpacker), using whole 64-bit
  words where the run allows.
- **Strings.** A string's payload is its bytes, and `length(s)` is its byte
  length. On a write, a string longer than `buffer_size - 1` latches (e). A
  read returns a fresh string, because Lobster strings are values, so the
  read costs one copy. The reader refuses a NUL in the payload and malformed
  UTF-8 by its own check, equal to serialize.c's. Lobster's
  `string_to_unicode` is not used: it is not that check.

## (e) WRITER AND READER

**The writer is STRICT.** For every value, it emits exactly the bytes
serialize.c v2.0.0 emits. serialize.c's write path is trusted and asserts in
debug builds only (its ERRORS block, STANDARD.md's writes-trusted doctrine).
This port has no NDEBUG, and every Lobster build runs the same code, so
serialize.c's write contracts split in two, as the brief rules:

- **Latch.** A value outside its range and a full buffer latch the stream and
  write nothing for that call. "A value outside its range" covers: `value`
  outside `[min, max]`, a bits value not below `2^bits`, a uint8, uint16 or
  uint32 outside `[0, 2^n)`, a string too long for `buffer_size`, a string
  with a zero byte or that is not well-formed UTF-8 (NUL first, as on read),
  a float or double that is NaN or an infinity (a finite double past FLT_MAX
  narrows to an infinity), and an int_relative `current` that is past
  2^31 - 1. Each latches with the reason a reader would give the same bytes. In serialize.c these are asserts, and in a release build they
  write wrong bytes or overrun the buffer; this port refuses them instead. The
  bounds check is of the whole operation's width before any bit moves
  (`write_gate(bits)` in src/serialize_stream.lobster), so a refused wide
  write leaves no dangling low word. A latched write stream is terminal: every
  later write returns `false` and writes nothing.
- **Abort.** API misuse, the asserts that concern the caller's own
  parameters, aborts. The abort prints `serialize: <rule>` and exits 70,
  through `serialize_abort` in src/serialize_stream.lobster, which uses
  `return from program` so that `--runtime-no-asserts` cannot remove it. The
  rules:
  - bits outside [1,32] (`serialize_bits`) or [1,64] (`serialize_bits64`)
  - `min > max` on any ranged operation (int, int64, int128, fixed)
  - an int32 parameter outside int32
  - a bad Q format: `integer_bits < 1`, `fraction_bits < 0`, or
    `integer_bits + fraction_bits` other than 32, 64 or 128 for the storage
    (STANDARD.md fixed)
  - compressed_float with `min >= max` or `res <= 0`, or a non-finite delta or
    value count (serialize.c's asserts); a non-finite value on write; and, on
    the write path only, a declaration whose top integer decodes non-finite
    (`min + delta` rounded once to float32: STANDARD.md compressed_float). A
    reader never aborts on it: it refuses the decode as `non_finite_float`.
  - precomputed constants with `max_integer_value < 1`, `bits` other than
    `serialize_bits_required(0, max_integer_value)`, or `delta <= 0` or
    non-finite
  - an int_relative `previous` outside [0, 2^31 - 1]
  - `buffer_size < 1`
  - a negative `bytes`, or `bytes` past the data's length
  - a write buffer that is not a multiple of 8 bytes
  - a read that breaks the slack contract

  The same contracts hold on the measure stream, where it has the argument;
  otherwise a measure never refuses (STANDARD.md, The Measure Stream).

**Reads forgive nothing.** Every value has exactly one encoding (STANDARD.md,
Reader Obligations), so a reader refuses every stream a conforming writer
cannot produce. The final byte's padding and any trailing bytes are checked
by `serialize_end`, which a packet reader calls after the top-level object.

**Security trumps** (STANDARD.md, Reader Obligations and Implementation Law):

- **Every refusal is made, for its stated reason.** These are the refusals
  STANDARD.md and serialize.c state:
  - a read past the end (`past_end`)
  - a decoded value outside `[min, max]`, an offset outside its span, a string
    length above `buffer_size - 1`, a compressed integer above
    `max_integer_value`, an int_relative reconstruction outside
    `[0, 2^31 - 1]` or not above `previous`, read in a width that cannot wrap
    (`value_out_of_range`)
  - nonzero align padding, including inside bytes and string, checked BEFORE
    the payload's length; and a set bit in the final byte at the end
    (`nonzero_padding`)
  - a whole byte or more after the end, checked before the padding
    (`trailing_data`)
  - a float or double whose exponent field is all ones, tested on the raw
    bits, and a compressed float whose decode is not finite
    (`non_finite_float`)
  - a string with a zero byte (`embedded_nul`), scanned over the whole payload
    BEFORE the UTF-8 check; malformed UTF-8: overlongs, surrogates D800-DFFF,
    anything above U+10FFFF, truncated sequences (`invalid_utf8`)
  - an int_relative absolute tier carrying a current in the domain, above
    `previous` and no more than 69914 above it (`non_canonical`), after the
    domain and ordering rule
- **A claimed length is checked before it is allocated.** A string read
  aligns, checks the padding, and holds the claimed length against the bytes
  that remain (`past_end`) before it allocates the payload, so a short stream
  claiming a huge length allocates nothing.
- **A refused primitive read leaves its destination unwritten.** The read
  returns its input value. A read into a caller's buffer (`serialize_bytes`)
  leaves the buffer unspecified, as STANDARD.md allows.
- **The stream is terminal after a refusal.** The first refusal sets
  `failed` and its reason through `s.fail(reason)`. Every later operation tests it before anything
  else, zero-bit ones included (a degenerate range, an aligned align,
  zero-count bytes, object, end), and returns `false` with its input value,
  consuming nothing.
- **Hostile bytes never abort.** An abort is decided by the caller's own
  arguments, never by data.
- **No read touches memory past the data's end.** The read gate refuses
  `bits_read + n > num_bits` before any load. The one load that runs ahead,
  the 64-bit window, stays inside the slack that the constructor checked
  (or that the padded constructor allocated), so no Lobster bounds error can
  fire on data.

## (f) THE FILE LAYOUT

| file | holds | card |
|---|---|---|
| `src/serialize.lobster` | the entry: imports every file below, ends with a declaration (see below) | serialize-lobster-design (this card) |
| `src/serialize_stream.lobster` | the three stream classes and their constructors; the latch (`failed`, `ok`, `error`, `fail`); `is_writing`, `is_reading`; accounting (`bits_processed`, `bytes_processed`, `bits_available`, `bits_remaining`, `align_bits`, `flush`); the gates `write_gate`, `read_gate`, `measure_bits`; bool, uint8, uint16, uint32 and uint64 on every stream; align on every stream; the number model helpers; `serialize_abort` and `serialize_stub`; `serialize_format_version` | serialize-lobster-design (this card), IMPLEMENTED |
| `src/serialize_bitpacker.lobster` | `pack_bits`, `pack_bits64`, `flush_bits`, `pack_bytes`, `unpack_bits`, `unpack_bits64`, `unpack_bytes`; `serialize_bits` and `serialize_bits64` on every stream; `serialize_bits_required`, `serialize_bits_required64` | serialize-lobster-bitpacker |
| `src/serialize_int.lobster` | `serialize_int`, `serialize_int64` and `serialize_int_relative` on every stream | serialize-lobster-integers |
| `src/serialize_int128.lobster` | the types `serialize_uint128` and `serialize_int128` (final here); make, from_int64, equal, compare; `serialize_uint128` and `serialize_int128` on every stream | serialize-lobster-integers |
| `src/serialize_float.lobster` | `serialize_float` and `serialize_double` on every stream; the float32 and float64 routes (c) | serialize-lobster-floats |
| `src/serialize_fixed.lobster` | `serialize_fixed32`, `serialize_fixed64` and `serialize_fixed128` on every stream | serialize-lobster-floats |
| `src/serialize_compressed_float.lobster` | `serialize_compressed_float` and `serialize_compressed_float_precomputed` on every stream; `serialize_compressed_float_params` | serialize-lobster-floats |
| `src/serialize_bytes.lobster` | `serialize_bytes` and `serialize_string` on every stream | serialize-lobster-strings |
| `src/serialize_object.lobster` | `serialize_object` on every stream | serialize-lobster-strings |

Every signature in the family files is final and present now. Each body is a
STUB, `serialize_stub("<name>")`, which aborts with
`serialize: <name> not implemented`. A family card replaces the bodies of its
own files and edits no other src/ file. Each card puts its tests in its own
`test/<name>/` (one directory per card) and any make target in its own
`make/<card>.mk`. Every function that implements a rule cites its STANDARD.md
section, and this page's section where one applies.

**How an arm is written.** A family arm takes the stream as `s:<class>`, with
a single colon. With `s::<class>`, the stream's fields come into scope, and a
parameter with a field's name (`data`, `buffer`) fails to compile. An arm does
the whole operation in this order:

1. Abort on API misuse (e). The check comes first, on every stream and in
   every state, so it fires even after a latch.
2. Return `value, false` when `s.failed`.
3. Make the value refusals: a write latches through `s.fail()` on a value
   outside its range.
4. Check the whole width once, with `s.write_gate(bits)` or
   `s.read_gate(bits)`. A gate returns `false` and latches past the end.
5. Move the bits with the bitpacker primitives.
6. A read checks the decoded value, refusing through `s.fail()`, and returns
   it last.

A measure adds the width with `s.measure_bits(bits)`. The fixed-width aliases
in src/serialize_stream.lobster are the worked example.

**Dependencies.** Each family file imports `.serialize_stream`, plus the
families it names:

- int imports bitpacker.
- int128 imports bitpacker.
- fixed imports bitpacker and int128.
- compressed_float imports bitpacker and float.
- bytes imports bitpacker and int.

Every family's tests need the bitpacker at run time, so every family card
depends on serialize-lobster-bitpacker.

**Lobster quirks the layout works around** (measured with the pin):

- An `import` on the LAST line of an imported file fails to compile, with
  ``illegal start of expression: `end of include` ``. The entry therefore ends
  with a declaration, `serialize_reference_version`, and no family file may
  end with an import.
- A program that imports a test file type-checks every function that file
  defines.

**The smoke test and the stub.** test/smoke's `TestStubAborts` proves the
stub mechanism on `serialize_object`, through the runner, by its exit code and
message. When serialize-lobster-strings implements `serialize_object`, that
card retargets `TestStubAborts` to call `serialize_stub("serialize_object")`
directly. That edit keeps the proof of the message format, and its PATHS must
name test/smoke/smoke_test.lobster.

## (g) THE RUNNER

- **Setup.** `make dist-lobster` fetches
  https://github.com/aardappel/lobster/releases/download/v2026.8/lobster_linux_release.zip.
  It REFUSES by name any archive whose sha256 is not
  `2f03fb96fdaf6935469c99e43ffb182cab0d797faec7b26eccc9a732df32ad31`, before
  anything is unpacked, then unzips into `dist/lobster-v2026.8/` (`bin/lobster`,
  with `modules/` beside it). dist/ and build/ are gitignored. This is setup:
  run it once, never from a test.
- **The pin.** `LOBSTER ?= dist/lobster-v2026.8/bin/lobster` can be overridden
  (the fleet installs the same pin). `make toolchain-lobster` refuses by name a
  `LOBSTER` that does not resolve.
- **Running tests.** `make test` runs every `test/*/*_test.lobster`, and
  `make test T=<name>` runs only the files of `test/<name>/`, both through
  `tools/run_tests.sh`. The runner refuses with a named FAIL, and never a
  skip, in these cases:
  - a missing `test/<name>/` (`FAIL test/nosuch/ is missing`)
  - an empty one (`FAIL test/<name>/ is empty (no *_test.lobster)`)
  - a test file that declares no test
  - an empty `src/`
- **A test.** Each `def Test<Name>():` at the start of a line in a
  `*_test.lobster` file is one test, and runs in its own process under the
  JIT, `$LOBSTER <driver>.lobster`. The process runs in `build/run/<name>/`,
  which holds copies of `src/*.lobster`, every `.lobster` file of
  `test/<name>/` and `conformance/`. The driver is
  `import <x>_test` / `Test<Name>()` / `print "serialize-test-done"`, and a
  test file holds only declarations. A test fails by `assert`.
- **Pass and fail.** The runner prints `RUN Test<Name>`, then
  `--- PASS Test<Name>` when the process exits 0 and printed the done line,
  else `--- FAIL Test<Name>` with the output indented. A test whose `def` is
  directly preceded by `// expect-abort: <message>` passes only when the
  process exits nonzero, printed `<message>` as a whole line, and never
  reached the done line. That is how an abort (a stub, API misuse) is proved.
  The last line is `ok N test directories` or `FAIL k of N test directories`,
  with a nonzero exit on any FAIL.
- **Timed programs** run both ways with `make bench F=<file>`. The file is
  staged beside a copy of `src/` (so `import serialize` resolves) and run
  under the JIT. It is then compiled with `--cpp` and built by clang -O2
  (`CMAKE_*_FLAGS_RELEASE=-O2 -DNDEBUG`) against `build/lobster-src`, a
  checkout of aardappel/lobster at commit
  `acc66d71978ae5525be1356aa622fbaa9a57e848` (refused by name otherwise),
  through the `dev/` tree's own `LOBSTER_TOCPP` CMake build, and run. The
  generator is that checkout's `bin/lobster`, built with
  `LOBSTER_ENGINE=OFF`. The release binary's `--cpp` output carries the
  engine's builtin library, and an engine-less `compiled_lobster` refuses it
  with "code compiled with mismatching builtin function library" (measured).
  `make lobster-cpp` builds both trees once, in about two minutes on hulk.
  clang's linker `lld` is found beside clang (`/usr/lib/llvm-18/bin` on Ubuntu
  24.04), as the CMake build's `-fuse-ld=lld` needs.
- **Unit tests** use no real time, no sockets, no network and no outside
  services. A test clock, where one is ever needed, is an argument starting at
  1000.0. Only `make bench` programs read `seconds_elapsed()`, and they are not
  tests.
- **Conformance.** test/conformance reads every vector of
  `conformance/<name>.txt` (staged beside the run) and checks every record
  against this library, byte for byte and refusal for refusal, each refusal for
  the reason the vector states, every stream behind eight bytes of non-zero
  slack (STANDARD.md, "What a runner checks").
- **Controls.** `make controls` (tools/controls/controls.sh) runs, for every
  `conformance-controls/<rule>.expected`, a staged copy of `src/` with that ONE
  rule deleted by the line replacement in tools/controls/table.txt, and
  requires its corpus failures to be exactly the listed vectors. It also runs
  the reversed witnesses of tools/controls/witnesses.txt (the old behaviour of
  a write-side rule planted back must turn its unit test red) and the
  harness's own control (an unsabotaged reader must fail a control).
- **Zero warnings.** tools/run_tests.sh fails any test whose program the
  compiler warned about, src/ and test code alike; `make fuzz` refuses a
  driver that compiles with warnings, and builds the C host with `-Werror`.

### The timing

This is the program behind the float32 table in (c), run with
`make bench F=<file>`:

    struct f32box:
        v:float<32>
    let n = 10000000
    let scratch = ensure_size(string_with_capacity(16), 16, 0)
    def bits_scratch(x:float) -> int:
        write_float32_le(scratch, 0, x)
        let u = read_uint32_le(scratch, 0)
        return u
    def bits_vector(x:float) -> int:
        let b = vector_to_buffer([x], 4)
        let u = read_uint32_le(b, 0)
        return u
    def fround_scratch(x:float) -> float:
        write_float32_le(scratch, 0, x)
        let f = read_float32_le(scratch, 0)
        return f
    def fround_struct(x:float) -> float:
        let b = f32box { x }
        return b.v
    // ... from_bits_scratch (write_int32_le + read_float32_le) and
    // bits64_scratch (write_float64_le + read_uint64_le) alike; each route
    // runs n times over i * 0.37 (or i), summed, timed with seconds_elapsed().
