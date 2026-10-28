// test/uniform/uniform_test.lobster — the uniform behaviour rules of standard
// 2.1 (IMPLEMENTING.md, "Uniform behaviour: U1 to U16"), and the 2026-10-27
// audit's finding for this port. None of these is a corpus vector: each is
// write-side, measure-side, API-shape or caller-misuse behaviour, so each is
// proved here by unit test, named by its rule. No real time, no sockets.
import serialize

// A read stream over `bytes` bytes of 0xA5 with its eight bytes of slack.
def uniform_read(bytes:int) -> serialize_read_stream:
    return serialize_read_stream(ensure_size("", bytes + 8, 0xA5), bytes)

// A read stream that already refused past_end, to show that misuse on a
// failed stream keeps the first reason (U7: "The failure state is checked
// first").
def uniform_failed_read() -> serialize_read_stream:
    let r = uniform_read(0)
    var v = 0
    var ok = true
    v, ok = r.serialize_uint8(v)
    assert not ok and r.refusal_name() == "past_end"
    return r

// U7, U16: a call that returned (ok, value) on a read refused as
// value_out_of_range before any bit moved, leaving the value it was handed.
def uniform_refused(r:serialize_read_stream, ok:bool, unchanged:bool, what:string):
    if ok or not unchanged or not r.error() or r.refusal_name() != "value_out_of_range" or r.bits_processed() != 0:
        print "FAIL " + what + ": ok " + string(ok) + ", value unchanged " + string(unchanged) + ", refused as " + r.refusal_name() + ", consumed " + string(r.bits_processed())
        assert false

// The object a test hands serialize_object: it reads `bits` bits (none for
// 0), then returns `result`.
class uniform_object : serialize_object_base
    bits:int = 0
    result:bool = true

def serialize(o::uniform_object, s) -> bool:
    if o.bits > 0:
        var v = 0
        var ok = true
        v, ok = s.serialize_bits(v, o.bits)
    return o.result

// An object that defines no serialize of its own: the base answers.
class uniform_bare_object : serialize_object_base
    unused:int = 0

// U2: reject on a read latches rejected; it is terminal, and the first reason
// wins. On a write or a measure it traps (U9: u9_test's TestU9RejectOn*).
def TestU2Reject():
    let r = serialize_read_stream_padded("\x05")
    var v = 0
    var ok = true
    v, ok = r.serialize_bits(v, 4)
    assert ok and v == 5
    assert not r.reject()
    assert r.error() and r.refusal_name() == "rejected"
    let before = r.bits_processed()
    v, ok = r.serialize_bits(v, 4)
    assert not ok and v == 5 and r.bits_processed() == before
    var z = 12345
    z, ok = r.serialize_int(z, 7, 7)
    assert not ok and z == 12345
    assert not r.serialize_object(uniform_object {})
    assert r.refusal_name() == "rejected"
    // First reason wins: a reject on a stream that refused keeps its reason.
    let f = uniform_failed_read()
    assert not f.reject()
    assert f.refusal_name() == "past_end"

// U2: the object composition latches rejected when the callback refuses with
// nothing latched; a refusal inside it keeps its own reason, whether the
// callback then returns false or true.
def TestU2ObjectLatchesRejected():
    let r = serialize_read_stream_padded("\x05")
    assert not r.serialize_object(uniform_object { bits: 4, result: false })
    assert r.error() and r.refusal_name() == "rejected"
    var v = 9
    var ok = true
    v, ok = r.serialize_bits(v, 4)
    assert not ok and v == 9
    assert r.refusal_name() == "rejected"
    // A wire refusal inside, then the callback refuses: past_end stays.
    let p = serialize_read_stream_padded("\xFF")
    assert not p.serialize_object(uniform_object { bits: 16, result: false })
    assert p.refusal_name() == "past_end"
    // A wire refusal inside, then the callback says true: still refused.
    let q = serialize_read_stream_padded("\xFF")
    assert not q.serialize_object(uniform_object { bits: 16, result: true })
    assert q.refusal_name() == "past_end"
    // Accepted: fields accepted, callback true.
    let a = serialize_read_stream_padded("\x05")
    assert a.serialize_object(uniform_object { bits: 4, result: true })
    assert a.ok() and a.refusal_name() == "none"
    // On a write or a measure an object that refuses answers false and
    // records nothing (U6, U9).
    let w = serialize_write_stream(ensure_size("", 8, 0))
    assert not w.serialize_object(uniform_object { result: false })
    assert w.ok() and w.refusal_name() == "none"
    let m = serialize_measure_stream()
    assert not m.serialize_object(uniform_object { result: false })
    assert m.ok() and m.refusal_name() == "none"

// U6: a measure refuses nothing. fail answers false and records nothing,
// and the measure goes on counting. Misuse on it traps, as on a write
// (u9_test's TestU6Measure*Traps).
def TestU6MeasureRefusesNothing():
    let m = serialize_measure_stream()
    assert not m.fail(serialize_refusal_past_end)
    assert m.ok() and not m.error() and m.refusal_name() == "none"
    var b = false
    var ok = true
    b, ok = m.serialize_bool(b)
    assert ok and m.ok() and m.bits_processed() == 1

// U3, U4, U6: text the writer refuses, the measure refuses by the same trap:
// a lone surrogate is not well-formed UTF-8.
// expect-abort: serialize: string must be well-formed UTF-8
def TestU3U4MeasureFollowsTheWriter():
    let m = serialize_measure_stream()
    m.serialize_string("\xED\xA0\x80", 16)

// U7, U16, U5: caller misuse on a read refuses value_out_of_range before any
// bit moves, never an abort; on a failed stream the first reason stays.
def TestU7ReadMisuseRefuses():
    var i = 77
    var ok = true
    var r = uniform_read(16)
    i, ok = r.serialize_bits(i, 0)
    uniform_refused(r, ok, i == 77, "bits 0")
    r = uniform_read(16)
    i, ok = r.serialize_bits(i, 33)
    uniform_refused(r, ok, i == 77, "bits 33")
    r = uniform_read(16)
    i, ok = r.serialize_bits64(i, 0)
    uniform_refused(r, ok, i == 77, "bits64 0")
    r = uniform_read(16)
    i, ok = r.serialize_bits64(i, 65)
    uniform_refused(r, ok, i == 77, "bits64 65")
    r = uniform_read(16)
    i, ok = r.serialize_int(i, 8, 7)
    uniform_refused(r, ok, i == 77, "int min > max")
    // U5: int bounds are int32; outside it is a bad declaration.
    r = uniform_read(16)
    i, ok = r.serialize_int(i, -2147483649, 0)
    uniform_refused(r, ok, i == 77, "int min below int32")
    r = uniform_read(16)
    i, ok = r.serialize_int(i, 0, 2147483648)
    uniform_refused(r, ok, i == 77, "int max above int32")
    r = uniform_read(16)
    i, ok = r.serialize_int64(i, 8, 7)
    uniform_refused(r, ok, i == 77, "int64 min > max")
    r = uniform_read(16)
    var i128 = serialize_int128_from_int64(77)
    i128, ok = r.serialize_int128(i128, serialize_int128_from_int64(8), serialize_int128_from_int64(7))
    uniform_refused(r, ok, i128.lo == 77, "int128 min > max")
    r = uniform_read(16)
    i, ok = r.serialize_int_relative(-1, i)
    uniform_refused(r, ok, i == 77, "int_relative previous -1")
    r = uniform_read(16)
    i, ok = r.serialize_int_relative(2147483648, i)
    uniform_refused(r, ok, i == 77, "int_relative previous past int32")
    r = uniform_read(16)
    i, ok = r.serialize_fixed32(i, 0, 32, -1, 1)
    uniform_refused(r, ok, i == 77, "fixed32 integer bits 0")
    r = uniform_read(16)
    i, ok = r.serialize_fixed32(i, 16, 16, 2, 1)
    uniform_refused(r, ok, i == 77, "fixed32 min > max")
    r = uniform_read(16)
    i, ok = r.serialize_fixed32(i, 8, 8, -200, 200)
    uniform_refused(r, ok, i == 77, "fixed32 bounds outside the Q format")
    r = uniform_read(16)
    i, ok = r.serialize_fixed64(i, 32, 16, -1, 1)
    uniform_refused(r, ok, i == 77, "fixed64 storage 48")
    r = uniform_read(16)
    i128, ok = r.serialize_fixed128(i128, 32, 32, -1, 1)
    uniform_refused(r, ok, i128.lo == 77, "fixed128 storage 64")
    var f = 7.5
    r = uniform_read(16)
    f, ok = r.serialize_compressed_float(f, 1.0, 1.0, 0.1)
    uniform_refused(r, ok, f == 7.5, "compressed_float min == max")
    r = uniform_read(16)
    f, ok = r.serialize_compressed_float(f, 0.0, 1.0, 0.0)
    uniform_refused(r, ok, f == 7.5, "compressed_float res 0")
    r = uniform_read(16)
    f, ok = r.serialize_compressed_float(f, -3.0e38, 3.0e38, 1.0)
    uniform_refused(r, ok, f == 7.5, "compressed_float non-finite delta")
    let mi, bits, delta = serialize_compressed_float_params(0.0, 1.0, 0.01)
    r = uniform_read(16)
    f, ok = r.serialize_compressed_float_precomputed(f, mi, bits + 1, delta, 0.0)
    uniform_refused(r, ok, f == 7.5, "compressed_float_precomputed bits")
    r = uniform_read(16)
    f, ok = r.serialize_compressed_float_precomputed(f, 0, 0, delta, 0.0)
    uniform_refused(r, ok, f == 7.5, "compressed_float_precomputed max_integer_value 0")
    r = uniform_read(16)
    f, ok = r.serialize_compressed_float_precomputed(f, mi, bits, 0.0, 0.0)
    uniform_refused(r, ok, f == 7.5, "compressed_float_precomputed delta 0")
    var str = "SENTINEL"
    r = uniform_read(16)
    str, ok = r.serialize_string(str, 0)
    uniform_refused(r, ok, str == "SENTINEL", "string buffer_size 0")
    r = uniform_read(16)
    str, ok = r.serialize_bytes(str, -1)
    uniform_refused(r, ok, str == "SENTINEL", "bytes -1")
    // U16, destination capacity: the destination holds fewer bytes than the
    // declared count.
    r = uniform_read(16)
    str, ok = r.serialize_bytes(str, 9)
    uniform_refused(r, ok, str == "SENTINEL", "bytes past the destination")
    // An object with no serialize of its own, on a read.
    r = uniform_read(16)
    ok = r.serialize_object(uniform_bare_object {})
    uniform_refused(r, ok, true, "object with no serialize")
    // The failure state first: misuse on a failed stream keeps past_end.
    let f1 = uniform_failed_read()
    i, ok = f1.serialize_bits(i, 0)
    assert not ok and i == 77 and f1.refusal_name() == "past_end"
    i, ok = f1.serialize_int(i, 8, 7)
    assert not ok and i == 77 and f1.refusal_name() == "past_end"
    str, ok = f1.serialize_string(str, 0)
    assert not ok and str == "SENTINEL" and f1.refusal_name() == "past_end"

// U5 on a write: bounds outside int32 are caught on the caller's value,
// before anything narrows it (the port's write-misuse abort).
// expect-abort: serialize: max must be in [INT32_MIN, INT32_MAX]
def TestU5IntBoundsOutsideInt32AbortOnWrite():
    let w = serialize_write_stream(ensure_size("", 8, 0))
    var v = 0
    var ok = true
    v, ok = w.serialize_int(v, 0, 4294967296)

// U10: a write checks room for the whole operation before writing any of it:
// bytes after 3 bits need 5 align bits and 64 payload bits, 72 > 64, so the
// call traps at the gate before the align bits move (U9).
// expect-abort: serialize: write does not fit the room left in the buffer
def TestU10WholeOperationRoom():
    let b = serialize_write_stream(ensure_size("", 8, 0))
    var v = 0
    var ok = true
    v, ok = b.serialize_bits(v, 3)
    assert ok
    b.serialize_bytes("abcdefgh", 8)

// U12: end on a write or a measure is a no-op returning true.
def TestU12EndOnWriteAndMeasure():
    let w = serialize_write_stream(ensure_size("", 8, 0))
    assert w.serialize_end() and w.bits_processed() == 0
    assert not w.serialize_object(uniform_object { result: false })
    assert w.serialize_end()
    let m = serialize_measure_stream()
    assert m.serialize_end() and m.bits_processed() == 0
    assert not m.serialize_object(uniform_object { result: false })
    assert m.serialize_end()

// U14: the refusal names, "none" for none, and a public fail. On a read a
// fail with no reason, or with a value outside the closed list, records
// rejected and never traps: a refused stream never reports none. On a write it
// returns false and records nothing (U9).
def TestU14RefusalNamesAndFail():
    assert serialize_refusal_name(serialize_refusal_none) == "none"
    assert serialize_refusal_name(serialize_refusal_rejected) == "rejected"
    assert serialize_refusal_name(serialize_refusal(99)) == "rejected"
    let r = uniform_read(8)
    assert not r.fail(serialize_refusal_none)
    assert r.error() and r.refusal_name() == "rejected"
    let o = uniform_read(8)
    assert not o.fail(serialize_refusal(99))
    assert o.refusal_name() == "rejected"
    let g = uniform_read(8)
    assert not g.fail(serialize_refusal_trailing_data)
    assert g.refusal_name() == "trailing_data"
    let w = serialize_write_stream(ensure_size("", 8, 0))
    assert not w.fail(serialize_refusal_none)
    assert w.ok() and w.refusal_name() == "none"

// U15: serialize_copy_string: at most dest_size - 1 bytes, stopping at the
// first NUL (the back-off rule is u9_test's TestU15CopyString*).
def TestU15CopyString():
    assert serialize_copy_string("hello", 4) == "hel"
    assert serialize_copy_string("hello", 6) == "hello"
    assert serialize_copy_string("hello", 64) == "hello"
    assert serialize_copy_string("ab\x00cd", 16) == "ab"
    assert serialize_copy_string("hello", 1) == ""

// Audit 2026-10-27 (L, audit/cf_precomputed_wide.lobster), U16: precomputed
// max_integer_value must lie in [1, 4294967040]. bits_required works in the
// uint32 domain, so 2^40 passed with 0 bits and 2^32 + 5 with 3, and the
// read accepted wrong data. A read refuses them now; the top of the range is
// still accepted.
def TestU16PrecomputedMaxIntegerValueDomain():
    let wide = 1 << 40
    let r = serialize_read_stream_padded("\x06")
    var f = 7.5
    var ok = true
    f, ok = r.serialize_compressed_float_precomputed(f, wide, serialize_bits_required(0, wide), 100.0, 0.0)
    uniform_refused(r, ok, f == 7.5, "precomputed max_integer_value 2^40")
    let past = (1 << 32) + 5
    let p = serialize_read_stream_padded("\x06")
    f, ok = p.serialize_compressed_float_precomputed(f, past, serialize_bits_required(0, past), 100.0, 0.0)
    uniform_refused(p, ok, f == 7.5, "precomputed max_integer_value 2^32 + 5")
    let top = 4294967040
    let t = serialize_read_stream_padded("\x00\x00\x00\x00")
    f, ok = t.serialize_compressed_float_precomputed(f, top, 32, 100.0, 0.0)
    assert ok and f == 0.0 and t.bits_processed() == 32

// The same finding on a write: the constants abort (the write-misuse
// mechanism) instead of sending truncated bits.
// expect-abort: serialize: precomputed compressed float constants must be exactly what serialize_compressed_float_params derives
def TestU16PrecomputedMaxIntegerValueAbortOnWrite():
    let wide = 1 << 40
    let w = serialize_write_stream(ensure_size("", 16, 0))
    var f = 0.75
    var ok = true
    f, ok = w.serialize_compressed_float_precomputed(f, wide, serialize_bits_required(0, wide), 100.0, 0.0)
