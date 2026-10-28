// test/uniform/u9_test.lobster — the 2.1.1 rulings (IMPLEMENTING.md U6, U9,
// U15): one write-misuse mechanism, the trap. This port has no unchecked
// build, so it traps in every run: serialize_abort prints the rule and exits
// 70 (DESIGN.md (e)). Each trap is its own process, proved by the runner's
// `// expect-abort:` line (tools/run_tests.sh). Write misuse never latches: no
// reason recorded, no false return, no later failure. A measure makes every
// check a write makes, except room, by the same trap (U6). Unit tests: no real
// time, no sockets.
import serialize

def u9_write() -> serialize_write_stream:
    return serialize_write_stream(ensure_size("", 16, 0))

// An object whose serialize returns `result` and touches no field.
class u9_object : serialize_object_base
    result:bool = true

def serialize(o::u9_object, s) -> bool:
    return o.result

// ---------------------------------------------------------------------------
// U9 on a write: a value outside its range or width traps at the call.
// ---------------------------------------------------------------------------

// expect-abort: serialize: value must fit in bits
def TestU9WriteBitsOverWideTraps():
    var v = 0
    var ok = true
    v, ok = u9_write().serialize_bits(0x1FF, 8)

// expect-abort: serialize: value must fit in bits
def TestU9WriteBits64OverWideTraps():
    var v = 0
    var ok = true
    v, ok = u9_write().serialize_bits64(1 << 40, 40)

// expect-abort: serialize: value must fit in bits
def TestU9WriteUint8OverWideTraps():
    var v = 0
    var ok = true
    v, ok = u9_write().serialize_uint8(256)

// expect-abort: serialize: value must be in [min, max]
def TestU9WriteIntOutOfRangeTraps():
    var v = 0
    var ok = true
    v, ok = u9_write().serialize_int(11, 0, 10)

// expect-abort: serialize: value must be in [min, max]
def TestU9WriteInt64OutOfRangeTraps():
    var v = 0
    var ok = true
    v, ok = u9_write().serialize_int64(-1, 0, 1 << 40)

// expect-abort: serialize: value must be in [min, max]
def TestU9WriteInt128OutOfRangeTraps():
    var v = serialize_int128_from_int64(0)
    var ok = true
    v, ok = u9_write().serialize_int128(serialize_int128_from_int64(9), serialize_int128_from_int64(0), serialize_int128_from_int64(8))

// expect-abort: serialize: int_relative current must be in [0, INT32_MAX]
def TestU9WriteIntRelativeCurrentPastInt32Traps():
    var v = 0
    var ok = true
    v, ok = u9_write().serialize_int_relative(5, 2147483648)

// expect-abort: serialize: value must be in [min, max]
def TestU9WriteFixedOutOfRangeTraps():
    var v = 0
    var ok = true
    v, ok = u9_write().serialize_fixed32(2 << 16, 16, 16, -1, 1)

// expect-abort: serialize: float value must be finite
def TestU9WriteFloatNaNTraps():
    var v = 0.0
    var ok = true
    v, ok = u9_write().serialize_float(sqrt(-1.0))

// A finite double above FLT_MAX narrows to an infinity: that is what would be
// sent, so it traps (IMPLEMENTING.md, The check model).
// expect-abort: serialize: float value must be finite
def TestU9WriteFloatNarrowsToInfinityTraps():
    var v = 0.0
    var ok = true
    v, ok = u9_write().serialize_float(1.0e39)

// expect-abort: serialize: double value must be finite
def TestU9WriteDoubleInfinityTraps():
    var v = 0.0
    var ok = true
    v, ok = u9_write().serialize_double(1.0e308 * 10.0)

// compressed_float's clamp is no exception: a NaN traps, never clamped.
// expect-abort: serialize: compressed float value must be finite
def TestU9WriteCompressedFloatNaNTraps():
    var v = 0.0
    var ok = true
    v, ok = u9_write().serialize_compressed_float(sqrt(-1.0), 0.0, 1.0, 0.01)

// expect-abort: serialize: string must be shorter than buffer_size
def TestU9WriteStringTooLongTraps():
    var v = ""
    var ok = true
    v, ok = u9_write().serialize_string("abcd", 4)

// expect-abort: serialize: string must not hold a NUL
def TestU9WriteStringNulTraps():
    var v = ""
    var ok = true
    v, ok = u9_write().serialize_string("a\x00b", 16)

// expect-abort: serialize: string must be well-formed UTF-8
def TestU9WriteStringBadUtf8Traps():
    var v = ""
    var ok = true
    v, ok = u9_write().serialize_string("\xED\xA0\x80", 16)

// An operation that does not fit the room left traps before any bit moves.
// expect-abort: serialize: write does not fit the room left in the buffer
def TestU9WritePastEndTraps():
    let w = serialize_write_stream(ensure_size("", 8, 0))
    var v = 0
    var ok = true
    v, ok = w.serialize_bits64(0, 64)
    assert ok
    v, ok = w.serialize_bool(false)

// U10 with U9: the length field fits, the payload does not: trap.
// expect-abort: serialize: write does not fit the room left in the buffer
def TestU9WriteStringPayloadPastEndTraps():
    let w = serialize_write_stream(ensure_size("", 8, 0))
    var v = ""
    var ok = true
    v, ok = w.serialize_string("abcdefgh", 64)

// expect-abort: serialize: write does not fit the room left in the buffer
def TestU9WriteBytesPastEndTraps():
    let w = serialize_write_stream(ensure_size("", 8, 0))
    var v = ""
    var ok = true
    v, ok = w.serialize_bytes("abcdefghi", 9)

// reject is read only: on a write it is misuse, and traps.
// expect-abort: serialize: reject is read only
def TestU9RejectOnWriteTraps():
    u9_write().reject()

// expect-abort: serialize: reject is read only
def TestU9RejectOnMeasureTraps():
    serialize_measure_stream().reject()

// ---------------------------------------------------------------------------
// U6: a measure makes every check a write makes, except room, by the trap.
// ---------------------------------------------------------------------------

// expect-abort: serialize: value must fit in bits
def TestU6MeasureBitsOverWideTraps():
    var v = 0
    var ok = true
    v, ok = serialize_measure_stream().serialize_bits(0x1FF, 8)

// expect-abort: serialize: value must fit in bits
def TestU6MeasureBits64OverWideTraps():
    var v = 0
    var ok = true
    v, ok = serialize_measure_stream().serialize_bits64(-1, 63)

// expect-abort: serialize: value must fit in bits
def TestU6MeasureUint16OverWideTraps():
    var v = 0
    var ok = true
    v, ok = serialize_measure_stream().serialize_uint16(65536)

// expect-abort: serialize: value must be in [min, max]
def TestU6MeasureIntOutOfRangeTraps():
    var v = 0
    var ok = true
    v, ok = serialize_measure_stream().serialize_int(-1, 0, 10)

// expect-abort: serialize: value must be in [min, max]
def TestU6MeasureInt64OutOfRangeTraps():
    var v = 0
    var ok = true
    v, ok = serialize_measure_stream().serialize_int64(11, 0, 10)

// expect-abort: serialize: value must be in [min, max]
def TestU6MeasureInt128OutOfRangeTraps():
    var v = serialize_int128_from_int64(0)
    var ok = true
    v, ok = serialize_measure_stream().serialize_int128(serialize_int128_from_int64(-1), serialize_int128_from_int64(0), serialize_int128_from_int64(8))

// expect-abort: serialize: int_relative current must be in [0, INT32_MAX]
def TestU6MeasureIntRelativeCurrentPastInt32Traps():
    var v = 0
    var ok = true
    v, ok = serialize_measure_stream().serialize_int_relative(5, 2147483648)

// expect-abort: serialize: value must be in [min, max]
def TestU6MeasureFixedOutOfRangeTraps():
    var v = 0
    var ok = true
    v, ok = serialize_measure_stream().serialize_fixed64(-(2 << 32), 32, 32, -1, 1)

// expect-abort: serialize: float value must be finite
def TestU6MeasureFloatNaNTraps():
    var v = 0.0
    var ok = true
    v, ok = serialize_measure_stream().serialize_float(sqrt(-1.0))

// expect-abort: serialize: double value must be finite
def TestU6MeasureDoubleInfinityTraps():
    var v = 0.0
    var ok = true
    v, ok = serialize_measure_stream().serialize_double(1.0e308 * 10.0)

// expect-abort: serialize: compressed float value must be finite
def TestU6MeasureCompressedFloatNaNTraps():
    var v = 0.0
    var ok = true
    v, ok = serialize_measure_stream().serialize_compressed_float(sqrt(-1.0), 0.0, 1.0, 0.01)

// expect-abort: serialize: compressed float value must be finite
def TestU6MeasureCompressedFloatPrecomputedNaNTraps():
    let mi, bits, delta = serialize_compressed_float_params(0.0, 1.0, 0.01)
    var v = 0.0
    var ok = true
    v, ok = serialize_measure_stream().serialize_compressed_float_precomputed(sqrt(-1.0), mi, bits, delta, 0.0)

// The top decode check is a write check, so a measure makes it too.
// expect-abort: serialize: compressed float declaration must decode its top integer finite (min + delta)
def TestU6MeasureCompressedFloatNonFiniteTopTraps():
    var v = 0.0
    var ok = true
    let min = serialize_float32_from_bits(0x73C00000)
    v, ok = serialize_measure_stream().serialize_compressed_float(min, min, serialize_float32_from_bits(0x7F7FFFFF), serialize_float32_from_bits(0x73800000))

// The same check on the precomputed measure.
// expect-abort: serialize: compressed float declaration must decode its top integer finite (min + delta)
def TestU6MeasurePrecomputedNonFiniteTopTraps():
    let min = serialize_float32_from_bits(0x73C00000)
    let max_integer_value, bits, delta = serialize_compressed_float_params(min, serialize_float32_from_bits(0x7F7FFFFF), serialize_float32_from_bits(0x73800000))
    var v = 0.0
    var ok = true
    v, ok = serialize_measure_stream().serialize_compressed_float_precomputed(min, max_integer_value, bits, delta, min)

// expect-abort: serialize: string must be shorter than buffer_size
def TestU6MeasureStringTooLongTraps():
    var v = ""
    var ok = true
    v, ok = serialize_measure_stream().serialize_string("abcd", 4)

// expect-abort: serialize: string must not hold a NUL
def TestU6MeasureStringNulTraps():
    var v = ""
    var ok = true
    v, ok = serialize_measure_stream().serialize_string("a\x00b", 16)

// expect-abort: serialize: string must be well-formed UTF-8
def TestU6MeasureStringBadUtf8Traps():
    var v = ""
    var ok = true
    v, ok = serialize_measure_stream().serialize_string("\xC3", 16)

// ---------------------------------------------------------------------------
// U9: fail and a refusing object on a write or a measure return false and
// record nothing; a later write emits exactly what it would have.
// ---------------------------------------------------------------------------

def u9_bytes_after(w:serialize_write_stream) -> string:
    var v = 0
    var ok = true
    v, ok = w.serialize_bits(0x5A, 8)
    assert ok
    v, ok = w.serialize_uint16(0xBEEF)
    assert ok
    w.flush()
    return substring(w.buffer, 0, w.bytes_processed())

def TestU9WriteFailRecordsNothing():
    let clean = u9_bytes_after(u9_write())
    for([serialize_refusal_none, serialize_refusal_past_end, serialize_refusal_value_out_of_range, serialize_refusal_rejected]) reason:
        let w = u9_write()
        assert not w.fail(reason)
        assert w.ok() and not w.error() and w.refusal_name() == "none"
        assert u9_bytes_after(w) == clean
        assert w.ok() and w.refusal_name() == "none"

def TestU9WriteObjectFalseRecordsNothing():
    let clean = u9_bytes_after(u9_write())
    let w = u9_write()
    assert not w.serialize_object(u9_object { result: false })
    assert w.ok() and w.refusal_name() == "none" and w.bits_processed() == 0
    assert u9_bytes_after(w) == clean
    assert w.serialize_object(u9_object { result: true })

def TestU6MeasureFailAndObjectRecordNothing():
    let m = serialize_measure_stream()
    assert not m.fail(serialize_refusal_past_end)
    assert not m.serialize_object(u9_object { result: false })
    assert m.ok() and m.refusal_name() == "none"
    var v = 0
    var ok = true
    v, ok = m.serialize_bits(3, 2)
    assert ok and m.bits_processed() == 2

// ---------------------------------------------------------------------------
// U15: serialize_copy_string backs off to a whole character (the reference's
// test_copy_string vectors; Lobster strings are bytes, so all of them).
// ---------------------------------------------------------------------------

def TestU15CopyStringBacksOffToACharacter():
    assert serialize_copy_string("abc", 8) == "abc"
    assert serialize_copy_string("a\x00bc", 8) == "a"
    assert serialize_copy_string("abcdefghij", 4) == "abc"
    assert serialize_copy_string("\xC3\xA9\xC3\xA9", 4) == "\xC3\xA9"
    assert serialize_copy_string("\xC3\xA9\xC3\xA9", 3) == "\xC3\xA9"
    assert serialize_copy_string("a\xF0\x9F\x98\x80", 3) == "a"
    assert serialize_copy_string("a\xF0\x9F\x98\x80", 4) == "a"
    assert serialize_copy_string("a\xF0\x9F\x98\x80", 5) == "a"
    assert serialize_copy_string("a\xF0\x9F\x98\x80", 6) == "a\xF0\x9F\x98\x80"
    assert serialize_copy_string("ab\x80\x80", 4) == "a"
    assert serialize_copy_string("\xC3\xA9\xA9\xA9", 4) == ""
    assert serialize_copy_string("abc", 1) == ""

// The copy is what serialize_string with buffer_size = dest_size accepts.
def TestU15CopyStringFeedsSerializeString():
    let src = "x\xE2\x82\xAC\xE2\x82\xAC"
    for(8) dest_size:
        if dest_size >= 1:
            let copy = serialize_copy_string(src, dest_size)
            let w = serialize_write_stream(ensure_size("", 16, 0))
            var v = ""
            var ok = true
            v, ok = w.serialize_string(copy, dest_size)
            assert ok

// expect-abort: serialize: copy_string dest_size must be at least 1
def TestU15CopyStringDestSizeZeroTraps():
    serialize_copy_string("abc", 0)
