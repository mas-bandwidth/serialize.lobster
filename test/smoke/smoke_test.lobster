// test/smoke/smoke_test.lobster — the skeleton's smoke tests (DESIGN.md (a),
// (c), (f), (g)): the entry compiles, every API name resolves on every stream,
// a stub aborts with its not-implemented message, and the latch holds
// (STANDARD.md, Reader Obligations, "Failure is terminal" and "A refused
// primitive read must leave its destination unwritten").
import serialize

class smoke_object : serialize_object_base
    x:int = 0

// serialize_object's contract (DESIGN.md (a)): the object's own generic
// serialize, specialized per stream, returning true on success.
def serialize(o::smoke_object, s) -> bool:
    o.x = s.serialize_int(o.x, 0, 7)
    return s.ok()

// Every API name DESIGN.md (a) lists, called with its final types on one
// stream. Never executed (the guard is false at run time) but always compiled
// and type checked, so a missing or mistyped name fails the compile.
def smoke_every_name(s):
    var ok = false
    var i = 0
    var f = 0.0
    var str = ""
    var u128 = serialize_uint128_make(0, 1)
    var i128 = serialize_int128_from_int64(-1)
    i, ok = s.serialize_bits(i, 3)
    i, ok = s.serialize_bits64(i, 40)
    var b = false
    b, ok = s.serialize_bool(b)
    ok = s.serialize_align()
    i, ok = s.serialize_uint8(i)
    i, ok = s.serialize_uint16(i)
    i, ok = s.serialize_uint32(i)
    i, ok = s.serialize_uint64(i)
    i, ok = s.serialize_int(i, -5, 5)
    i, ok = s.serialize_int64(i, -5, 5)
    i128, ok = s.serialize_int128(i128, serialize_int128_from_int64(-9), serialize_int128_make(1, 0))
    u128, ok = s.serialize_uint128(u128)
    i, ok = s.serialize_int_relative(4, i)
    f, ok = s.serialize_float(f)
    f, ok = s.serialize_double(f)
    f, ok = s.serialize_compressed_float(f, -1.0, 1.0, 0.01)
    let mi, bits, delta = serialize_compressed_float_params(-1.0, 1.0, 0.01)
    f, ok = s.serialize_compressed_float_precomputed(f, mi, bits, delta, -1.0)
    i, ok = s.serialize_fixed32(i, 16, 16, -10, 10)
    i, ok = s.serialize_fixed64(i, 32, 32, -10, 10)
    i128, ok = s.serialize_fixed128(i128, 64, 64, -10, 10)
    str, ok = s.serialize_bytes(str, 0)
    str, ok = s.serialize_string(str, 64)
    ok = s.serialize_object(smoke_object {})
    ok = s.serialize_end()
    ok = s.ok()
    ok = s.error()
    let name = s.refusal_name()
    ok = s.fail(serialize_refusal_past_end) or name == ""
    ok = s.is_writing()
    ok = s.is_reading()
    i = s.bits_processed()
    i = s.bytes_processed()
    return ok

def smoke_names():
    let wbuf = ensure_size("", 16, 0)
    let w = serialize_write_stream(wbuf)
    let r = serialize_read_stream_padded("")
    let r2 = serialize_read_stream(ensure_size("", 8, 0), 0)
    let m = serialize_measure_stream()
    smoke_every_name(w)
    smoke_every_name(r)
    smoke_every_name(r2)
    smoke_every_name(m)
    w.flush()
    var i = w.bits_available()
    i = w.align_bits()
    i = r.bits_remaining()
    i = r.align_bits()
    i = serialize_bits_required(0, 7)
    i = serialize_bits_required64(0, 7)
    let a = serialize_uint128_make(1, 2)
    let b = serialize_int128_make(1, 2)
    var ok = serialize_uint128_equal(a, a)
    ok = serialize_int128_equal(b, b)
    i = serialize_int128_compare(b, b)
    var f = serialize_float32_round(0.1)
    i = serialize_float32_bits(0.1)
    f = serialize_float32_from_bits(i)
    i = serialize_float64_bits(0.1)
    f = serialize_float64_from_bits(i)

def TestSmoke():
    // The entry: the format version this port implements (STANDARD.md,
    // Format version).
    assert serialize_format_version == "2.0"

    // Every name resolves (compiled and type checked, never run).
    if length(command_line_arguments()) > 1000000:
        smoke_names()

    // Write stream accounting (DESIGN.md (a), (e)).
    let w = serialize_write_stream(ensure_size("", 16, 0))
    assert w.is_writing() and not w.is_reading()
    assert w.ok() and not w.error()
    assert w.bits_processed() == 0
    assert w.bytes_processed() == 0
    assert w.bits_available() == 128
    assert w.align_bits() == 0

    // Measure stream accounting: exact widths, and the worst case of 7 bits
    // for an align (STANDARD.md, The Measure Stream).
    let m = serialize_measure_stream()
    assert not m.is_writing() and not m.is_reading()
    var mv, mok = m.serialize_uint8(300)
    assert mok and mv == 300
    mv, mok = m.serialize_bool(true)
    assert mok
    mv, mok = m.serialize_uint64(-1)
    assert mok
    assert m.serialize_align()
    assert m.bits_processed() == 8 + 1 + 64 + 7
    assert m.bytes_processed() == 10

    // The read latch: on a read stream over empty data a failing call latches,
    // a later call fails and leaves its destination unchanged, and nothing is
    // consumed (STANDARD.md, Reader Obligations).
    let r = serialize_read_stream_padded("")
    assert r.is_reading() and not r.is_writing()
    assert r.ok()
    assert r.bits_remaining() == 0
    var d8 = 7
    var ok = true
    d8, ok = r.serialize_uint8(d8)
    assert not ok
    assert d8 == 7
    assert r.error() and not r.ok()
    var flag = true
    flag, ok = r.serialize_bool(flag)
    assert not ok
    assert flag == true
    var d64 = 0x123456789
    d64, ok = r.serialize_uint64(d64)
    assert not ok
    assert d64 == 0x123456789
    assert not r.serialize_align()
    assert r.bits_processed() == 0

    // A read stream with data refuses past its end the same way: 8 bits are
    // there, 16 are not, so the uint16 latches and leaves its value alone.
    let r2 = serialize_read_stream_padded("A")
    assert r2.bits_remaining() == 8
    var d16 = 0xBEEF
    d16, ok = r2.serialize_uint16(d16)
    assert not ok and d16 == 0xBEEF and r2.error()
    d8, ok = r2.serialize_uint8(d8)
    assert not ok and d8 == 7

    // The write latch: a write past the end of the buffer latches and writes
    // nothing, and the stream is terminal (DESIGN.md (e)).
    let wz = serialize_write_stream("")
    var wv = 1
    wv, ok = wz.serialize_uint8(wv)
    assert not ok and wz.error()
    var wb = true
    wb, ok = wz.serialize_bool(wb)
    assert not ok and wb
    assert wz.bits_processed() == 0
    // A value outside its range latches too, before any bit moves.
    let wr = serialize_write_stream(ensure_size("", 8, 0))
    wv, ok = wr.serialize_uint8(256)
    assert not ok and wr.error()
    assert wr.bits_processed() == 0
    // fail() latches by hand, as serialize_write_fail and serialize_read_fail.
    let wf = serialize_write_stream(ensure_size("", 8, 0))
    assert not wf.fail(serialize_refusal_value_out_of_range)
    assert wf.error()
    assert wf.refusal_name() == "value_out_of_range"
    // The first reason is kept; a later refusal is its echo.
    assert not wf.fail(serialize_refusal_past_end)
    assert wf.refusal_name() == "value_out_of_range"
    // The closed list, spelled exactly as STANDARD.md, Refusal reasons.
    assert serialize_refusal_name(serialize_refusal_none) == "none"
    assert serialize_refusal_name(serialize_refusal_past_end) == "past_end"
    assert serialize_refusal_name(serialize_refusal_value_out_of_range) == "value_out_of_range"
    assert serialize_refusal_name(serialize_refusal_nonzero_padding) == "nonzero_padding"
    assert serialize_refusal_name(serialize_refusal_trailing_data) == "trailing_data"
    assert serialize_refusal_name(serialize_refusal_non_finite_float) == "non_finite_float"
    assert serialize_refusal_name(serialize_refusal_invalid_utf8) == "invalid_utf8"
    assert serialize_refusal_name(serialize_refusal_embedded_nul) == "embedded_nul"
    assert serialize_refusal_name(serialize_refusal_non_canonical) == "non_canonical"
    assert serialize_refusal_name(serialize_refusal_rejected) == "rejected"
    assert length(serialize_refusal_names) == 10

    // The number model helpers (DESIGN.md (c)).
    assert serialize_ult(1, -1)
    assert not serialize_ult(-1, 1)
    assert serialize_ule(-1, -1)
    assert serialize_shr(0x8000000000000000, 63) == 1
    assert serialize_shr(-1, 0) == -1
    assert serialize_shr(-1, 64) == 0
    assert serialize_shr(-1, 32) == 0xFFFFFFFF
    assert serialize_mask(0) == 0
    assert serialize_mask(1) == 1
    assert serialize_mask(32) == 0xFFFFFFFF
    assert serialize_mask(64) == -1
    assert serialize_shl(1, 63) == 0x8000000000000000
    assert serialize_shl(1, 64) == 0

// expect-abort: serialize: serialize_object not implemented
def TestStubAborts():
    serialize_stub("serialize_object")

// expect-abort: serialize: write buffer bytes must be a multiple of 8
def TestWriteBufferMustBeWords():
    serialize_write_stream(ensure_size("", 12, 0))

// A read that breaks the slack contract, or names a negative byte count, is
// refused at initialization as value_out_of_range over no bits, never an
// abort (IMPLEMENTING.md U7): every read on it refuses and reads nothing.
def TestReadSlackContract():
    let r = serialize_read_stream("abc", 3)
    assert r.error() and r.refusal_name() == "value_out_of_range"
    var v = 7
    var ok = true
    v, ok = r.serialize_uint8(v)
    assert not ok and v == 7 and r.bits_processed() == 0
    assert r.refusal_name() == "value_out_of_range"
    let n = serialize_read_stream(ensure_size("", 16, 0), -1)
    assert n.error() and n.refusal_name() == "value_out_of_range"
    v, ok = n.serialize_uint8(v)
    assert not ok and v == 7 and n.bits_remaining() == 0
