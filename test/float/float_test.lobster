// test/float/float_test.lobster — TestSerializeFloat (STANDARD.md, Floating
// Point: float, double, compressed_float; Integers: fixed; DESIGN.md (c), (e), (f)).
//
// The runner every record of conformance/float.txt, double.txt, fixed.txt and
// compressed_float.txt: an accepted read decodes the stated value or bit
// pattern and consumes the stated bits, a canonical writer emits the stated
// bytes, and a refused read leaves its destination untouched and the stream
// terminal. It prints the record count per file and fails unless the parser
// saw exactly the file's operation count.
//
// Plus every float32 NaN payload class and both zeros through float, and
// compressed_float at min, max, max - res/2 and one ulp outside.
import serialize

class serialize_float_record:
    op:string
    name:string
    param_names:[string]
    param_values:[string]
    bytes:[int]
    refused:bool
    expect_bits:bool
    bits:int
    expect_value:bool
    value_text:string
    consumed:int
    writer:bool

def serialize_float_test_fail(message:string):
    serialize_abort("TestSerializeFloat: " + message)

def serialize_float_test_check(condition:bool, message:string):
    if not condition:
        serialize_float_test_fail(message)

def serialize_float_test_words(line:string) -> [string]:
    return tokenize(line, " \t", "")

def serialize_float_test_new_record(op:string) -> serialize_float_record:
    return serialize_float_record {
        op: op, name: "", param_names: [], param_values: [], bytes: [],
        refused: false, expect_bits: false, bits: 0, expect_value: false,
        value_text: "", consumed: -1, writer: false
    }

def serialize_float_test_hex(text:string) -> int:
    var body = text
    if length(body) >= 2 and substring(body, 0, 2) == "0x":
        body = substring(body, 2, -1)
    var value = 0
    for(length(body)) i:
        let digit, ok = string_to_int(substring(body, i, 1), 16)
        value = (value << 4) | digit
    return value

// The unsigned 128-bit pair helpers the 128-bit expectations need (DESIGN.md
// (c)); the same two lanes the fixed128 value uses.
def serialize_float_test_u128_add(a:serialize_int128, b:serialize_int128) -> serialize_int128:
    let lo = a.lo + b.lo
    let carry = if serialize_ult(lo, a.lo): 1 else: 0
    return serialize_int128 { lo: lo, hi: a.hi + b.hi + carry }

def serialize_float_test_u128_sub(a:serialize_int128, b:serialize_int128) -> serialize_int128:
    let lo = a.lo - b.lo
    let borrow = if serialize_ult(a.lo, b.lo): 1 else: 0
    return serialize_int128 { lo: lo, hi: a.hi - b.hi - borrow }

def serialize_float_test_u128_shl(a:serialize_int128, n:int) -> serialize_int128:
    if n <= 0:
        return a
    if n < 64:
        return serialize_int128 {
            lo: serialize_shl(a.lo, n),
            hi: serialize_shl(a.hi, n) | serialize_shr(a.lo, 64 - n)
        }
    return serialize_int128 { lo: 0, hi: serialize_shl(a.lo, n - 64) }

// A decimal or 0x hexadecimal integer of up to 128 bits, as two's-complement
// lanes (STANDARD.md, The vector format, Lexical rules).
def serialize_float_test_parse_int128(text:string) -> serialize_int128:
    var body = text
    var negative = false
    if length(body) > 0 and substring(body, 0, 1) == "-":
        negative = true
        body = substring(body, 1, -1)
    let hexadecimal = length(body) >= 2 and substring(body, 0, 2) == "0x"
    if hexadecimal:
        body = substring(body, 2, -1)
    let base = if hexadecimal: 16 else: 10
    var acc = serialize_int128 { lo: 0, hi: 0 }
    for(length(body)) i:
        let digit, ok = string_to_int(substring(body, i, 1), base)
        if hexadecimal:
            acc = serialize_float_test_u128_add(serialize_float_test_u128_shl(acc, 4), serialize_int128 { lo: digit, hi: 0 })
        else:
            let ten = serialize_float_test_u128_add(serialize_float_test_u128_shl(acc, 3), serialize_float_test_u128_shl(acc, 1))
            acc = serialize_float_test_u128_add(ten, serialize_int128 { lo: digit, hi: 0 })
    if negative:
        acc = serialize_float_test_u128_sub(serialize_int128 { lo: 0, hi: 0 }, acc)
    return acc

def serialize_float_test_parse(text:string) -> [serialize_float_record]:
    let records = []::serialize_float_record
    let lines = tokenize(text, "\n", " \t", 1)
    var current = serialize_float_test_new_record("")
    var has_current = false
    for(lines) line:
        if length(line) == 0:
            if has_current:
                records.push(current)
                has_current = false
            continue
        if substring(line, 0, 1) == "#":
            continue
        let words = serialize_float_test_words(line)
        if length(words) == 0:
            continue
        if words[0] == "operation":
            if has_current:
                records.push(current)
            current = serialize_float_test_new_record(words[1])
            has_current = true
        elif has_current:
            if words[0] == "name":
                current.name = substring(line, 5, -1)
            elif words[0] == "param" and length(words) >= 4:
                current.param_names.push(words[1])
                current.param_values.push(words[3])
            elif words[0] == "bytes":
                current.bytes = []
                for(length(words) - 1) i:
                    current.bytes.push(serialize_float_test_hex(words[i + 1]))
            elif words[0] == "expect":
                if length(words) >= 2 and words[1] == "refused":
                    current.refused = true
                elif length(words) >= 4 and words[1] == "bits":
                    current.expect_bits = true
                    current.bits = serialize_float_test_hex(words[3])
                elif length(words) >= 4 and words[1] == "value":
                    current.expect_value = true
                    current.value_text = words[3]
            elif words[0] == "consumed" and length(words) >= 2:
                current.consumed = string_to_int(words[1])
            elif words[0] == "writer" and length(words) >= 2 and words[1] == "canonical":
                current.writer = true
    if has_current:
        records.push(current)
    return records

def serialize_float_test_count_operations(text:string) -> int:
    var count = 0
    let lines = tokenize(text, "\n", " \t", 1)
    for(lines) line:
        let words = serialize_float_test_words(line)
        if length(words) > 0 and words[0] == "operation":
            count += 1
    return count

def serialize_float_test_param_int(record:serialize_float_record, name:string) -> int:
    for(length(record.param_names)) i:
        if record.param_names[i] == name:
            return string_to_int(record.param_values[i])
    serialize_float_test_fail(record.name + ": missing parameter " + name)
    return 0

def serialize_float_test_param_float(record:serialize_float_record, name:string) -> float:
    for(length(record.param_names)) i:
        if record.param_names[i] == name:
            return string_to_float(record.param_values[i])
    serialize_float_test_fail(record.name + ": missing parameter " + name)
    return 0.0

def serialize_float_test_stream(bytes:[int]) -> serialize_read_stream:
    let data = ensure_size("", length(bytes) + 8, 0)
    var i = 0
    for(bytes) b:
        write_int8_le(data, i, b)
        i += 1
    return serialize_read_stream(data, length(bytes))

def serialize_float_test_write(nbits:int) -> serialize_write_stream:
    var need = (nbits + 7) >> 3
    need = ((need + 7) >> 3) << 3
    if need < 8:
        need = 8
    return serialize_write_stream(ensure_size("", need, 0))

def serialize_float_test_same_bytes(expected:[int], buffer:string, count:int, label:string):
    serialize_float_test_check(length(expected) == count, label + ": writer bytes length")
    for(count) i:
        serialize_float_test_check(read_uint8_le(buffer, i) == expected[i], label + ": writer byte " + string(i))

// The further read a refusal must poison (STANDARD.md, What a runner checks:
// terminality is checked by behavior).
def serialize_float_test_check_terminal_float(s:serialize_read_stream, is_double:bool, label:string):
    let before = s.bits_processed()
    var value = 123.5
    var ok = true
    if is_double:
        value, ok = s.serialize_double(value)
    else:
        value, ok = s.serialize_float(value)
    serialize_float_test_check(not ok, label + ": terminal read succeeded")
    serialize_float_test_check(value == 123.5, label + ": terminal read changed its destination")
    serialize_float_test_check(s.bits_processed() == before, label + ": terminal read consumed bits")

def serialize_float_test_check_terminal_compressed(s:serialize_read_stream, min:float, max:float, res:float, label:string):
    let before = s.bits_processed()
    var value = 123.5
    var ok = true
    value, ok = s.serialize_compressed_float(value, min, max, res)
    serialize_float_test_check(not ok, label + ": terminal compressed read succeeded")
    serialize_float_test_check(value == 123.5, label + ": terminal compressed read changed its destination")
    serialize_float_test_check(s.bits_processed() == before, label + ": terminal compressed read consumed bits")

def serialize_float_test_run_float_double(record:serialize_float_record, label:string):
    let is_double = record.op == "double"
    let s = serialize_float_test_stream(record.bytes)
    var value = 123.5
    var ok = true
    if is_double:
        value, ok = s.serialize_double(value)
    else:
        value, ok = s.serialize_float(value)
    if record.refused:
        serialize_float_test_check(not ok, label + ": refused read succeeded")
        serialize_float_test_check(value == 123.5, label + ": refusal changed its destination")
        serialize_float_test_check(s.error(), label + ": refusal latched no error")
        serialize_float_test_check_terminal_float(s, is_double, label)
        return
    serialize_float_test_check(ok, label + ": accepted read refused")
    serialize_float_test_check(s.bits_processed() == record.consumed, label + ": consumed bits")
    let got = if is_double: serialize_float64_bits(value) else: serialize_float32_bits(value)
    serialize_float_test_check(got == record.bits, label + ": bit pattern")
    if record.writer:
        let w = serialize_float_test_write(if is_double: 64 else: 32)
        if is_double:
            value, ok = w.serialize_double(value)
        else:
            value, ok = w.serialize_float(value)
        w.flush()
        serialize_float_test_check(ok, label + ": canonical write refused")
        serialize_float_test_same_bytes(record.bytes, w.buffer, w.bytes_processed(), label)

def serialize_float_test_run_fixed(record:serialize_float_record, label:string):
    let integer_bits = serialize_float_test_param_int(record, "integer_bits")
    let fraction_bits = serialize_float_test_param_int(record, "fraction_bits")
    let min = serialize_float_test_param_int(record, "min")
    let max = serialize_float_test_param_int(record, "max")
    let storage = integer_bits + fraction_bits
    let s = serialize_float_test_stream(record.bytes)
    if storage <= 32:
        var value = 123456789
        var ok = true
        value, ok = s.serialize_fixed32(value, integer_bits, fraction_bits, min, max)
        if record.refused:
            serialize_float_test_check(not ok, label + ": refused read succeeded")
            serialize_float_test_check(value == 123456789, label + ": refusal changed its destination")
            serialize_float_test_check(s.error(), label + ": refusal latched no error")
            let before = s.bits_processed()
            var again = 123456789
            var ok2 = true
            again, ok2 = s.serialize_fixed32(again, integer_bits, fraction_bits, min, max)
            serialize_float_test_check(not ok2 and again == 123456789 and s.bits_processed() == before, label + ": terminal fixed32 read")
            return
        serialize_float_test_check(ok, label + ": accepted read refused")
        serialize_float_test_check(s.bits_processed() == record.consumed, label + ": consumed bits")
        let want = string_to_int(record.value_text)
        serialize_float_test_check(value == want, label + ": value")
        if record.writer:
            let w = serialize_float_test_write(record.consumed)
            var ignored = 0
            var ok2 = true
            ignored, ok2 = w.serialize_fixed32(value, integer_bits, fraction_bits, min, max)
            w.flush()
            serialize_float_test_check(ok2, label + ": canonical write refused")
            serialize_float_test_same_bytes(record.bytes, w.buffer, w.bytes_processed(), label)
    elif storage <= 64:
        var value = 123456789
        var ok = true
        value, ok = s.serialize_fixed64(value, integer_bits, fraction_bits, min, max)
        if record.refused:
            serialize_float_test_check(not ok, label + ": refused read succeeded")
            serialize_float_test_check(value == 123456789, label + ": refusal changed its destination")
            serialize_float_test_check(s.error(), label + ": refusal latched no error")
            let before = s.bits_processed()
            var again = 123456789
            var ok2 = true
            again, ok2 = s.serialize_fixed64(again, integer_bits, fraction_bits, min, max)
            serialize_float_test_check(not ok2 and again == 123456789 and s.bits_processed() == before, label + ": terminal fixed64 read")
            return
        serialize_float_test_check(ok, label + ": accepted read refused")
        serialize_float_test_check(s.bits_processed() == record.consumed, label + ": consumed bits")
        let want = string_to_int(record.value_text)
        serialize_float_test_check(value == want, label + ": value")
        if record.writer:
            let w = serialize_float_test_write(record.consumed)
            var ignored = 0
            var ok2 = true
            ignored, ok2 = w.serialize_fixed64(value, integer_bits, fraction_bits, min, max)
            w.flush()
            serialize_float_test_check(ok2, label + ": canonical write refused")
            serialize_float_test_same_bytes(record.bytes, w.buffer, w.bytes_processed(), label)
    else:
        var value = serialize_int128 { lo: 0x1234, hi: 0x5678 }
        var ok = true
        value, ok = s.serialize_fixed128(value, integer_bits, fraction_bits, min, max)
        if record.refused:
            serialize_float_test_check(not ok, label + ": refused read succeeded")
            serialize_float_test_check(value.lo == 0x1234 and value.hi == 0x5678, label + ": refusal changed its destination")
            serialize_float_test_check(s.error(), label + ": refusal latched no error")
            let before = s.bits_processed()
            var again = serialize_int128 { lo: 0x1234, hi: 0x5678 }
            var ok2 = true
            again, ok2 = s.serialize_fixed128(again, integer_bits, fraction_bits, min, max)
            serialize_float_test_check(not ok2 and again.lo == 0x1234 and again.hi == 0x5678 and s.bits_processed() == before, label + ": terminal fixed128 read")
            return
        serialize_float_test_check(ok, label + ": accepted read refused")
        serialize_float_test_check(s.bits_processed() == record.consumed, label + ": consumed bits")
        let want = serialize_float_test_parse_int128(record.value_text)
        serialize_float_test_check(value.lo == want.lo and value.hi == want.hi, label + ": value")
        if record.writer:
            let w = serialize_float_test_write(record.consumed)
            var ignored = serialize_int128 { lo: 0, hi: 0 }
            var ok2 = true
            ignored, ok2 = w.serialize_fixed128(value, integer_bits, fraction_bits, min, max)
            w.flush()
            serialize_float_test_check(ok2, label + ": canonical write refused")
            serialize_float_test_same_bytes(record.bytes, w.buffer, w.bytes_processed(), label)

def serialize_float_test_run_compressed(record:serialize_float_record, label:string):
    let min = serialize_float_test_param_float(record, "min")
    let max = serialize_float_test_param_float(record, "max")
    let res = serialize_float_test_param_float(record, "res")
    let s = serialize_float_test_stream(record.bytes)
    var value = 123.5
    var ok = true
    value, ok = s.serialize_compressed_float(value, min, max, res)
    if record.refused:
        serialize_float_test_check(not ok, label + ": refused read succeeded")
        serialize_float_test_check(value == 123.5, label + ": refusal changed its destination")
        serialize_float_test_check(s.error(), label + ": refusal latched no error")
        serialize_float_test_check_terminal_compressed(s, min, max, res, label)
        return
    serialize_float_test_check(ok, label + ": accepted read refused")
    serialize_float_test_check(s.bits_processed() == record.consumed, label + ": consumed bits")
    serialize_float_test_check(serialize_float32_bits(value) == record.bits, label + ": bit pattern")

def serialize_float_test_run_record(record:serialize_float_record, file:string, index:int):
    let label = file + " " + string(index) + " " + record.name
    if record.op == "float" or record.op == "double":
        serialize_float_test_run_float_double(record, label)
    elif record.op == "fixed":
        serialize_float_test_run_fixed(record, label)
    elif record.op == "compressed_float":
        serialize_float_test_run_compressed(record, label)
    else:
        serialize_float_test_fail(label + ": no runner for operation " + record.op)

def serialize_float_test_run_file(name:string):
    let path = "conformance/" + name + ".txt"
    let maybe_text = read_file(path)
    if maybe_text == nil:
        serialize_float_test_fail("missing " + path)
    let text = maybe_text
    let records = serialize_float_test_parse(text)
    let operations = serialize_float_test_count_operations(text)
    print name + " records: " + string(length(records))
    serialize_float_test_check(length(records) == operations, path + ": parsed " + string(length(records)) + " records, file has " + string(operations))
    var index = 0
    for(records) record:
        serialize_float_test_run_record(record, name, index)
        index += 1

// Every float32 NaN payload class and both zeros through float: write the bit
// pattern, read it back and compare the pattern, never the value (STANDARD.md,
// Floating Point, "Bit transparency — both directions").
def serialize_float_test_nan_classes():
    let patterns = [
        0x00000000, 0x80000000,
        0x7F800000, 0xFF800000,
        0x7FC00000, 0xFFC00000,
        0x7F800001, 0xFF800001,
        0x7FDEAD00, 0xFFDEAD00,
        0x7FFFFFFF, 0xFFFFFFFF,
        0x00000001, 0x007FFFFF, 0x00800000, 0x7F7FFFFF
    ]
    for(patterns) pattern:
        let buf = ensure_size("", 8, 0)
        let w = serialize_write_stream(buf)
        var value = serialize_float32_from_bits(pattern)
        var ok = true
        value, ok = w.serialize_float(value)
        w.flush()
        assert ok
        assert read_uint32_le(buf, 0) == pattern
        let r = serialize_float_test_stream([pattern & 0xFF, serialize_shr(pattern, 8) & 0xFF, serialize_shr(pattern, 16) & 0xFF, serialize_shr(pattern, 24) & 0xFF])
        var got = 0.0
        got, ok = r.serialize_float(got)
        assert ok
        assert serialize_float32_bits(got) == pattern

// compressed_float's writer at min, max, max - res/2 and one ulp outside
// (STANDARD.md, compressed_float): [0,10] at resolution 0.01 has
// max_integer_value 1000 and a ten-bit field; the last three all quantize to
// the top code 1000, and the clamp keeps the one-ulp-outside value there.
def serialize_float_test_compressed_bounds():
    let min = 0.0
    let max = 10.0
    let res = 0.01
    let max_integer_value, bits, delta = serialize_compressed_float_params(min, max, res)
    assert max_integer_value == 1000
    assert bits == 10
    let max_minus_half = serialize_float32_round(max - serialize_float32_round(res * 0.5))
    let one_ulp_outside = serialize_float32_from_bits(0x41200001)
    assert serialize_float32_bits(max_minus_half) == serialize_float32_bits(9.995)
    let values = [min, max, max_minus_half, one_ulp_outside]
    let codes = [0, 1000, 1000, 1000]
    var i = 0
    for(values) value:
        let buf = ensure_size("", 16, 0)
        let w = serialize_write_stream(buf)
        var ignored = value
        var ok = true
        ignored, ok = w.serialize_compressed_float(value, min, max, res)
        w.flush()
        assert ok
        assert w.bits_processed() == bits
        assert (read_uint16_le(buf, 0) & 0x3FF) == codes[i]
        let r = serialize_read_stream(buf, w.bytes_processed())
        var decoded = 0.0
        decoded, ok = r.serialize_compressed_float(decoded, min, max, res)
        assert ok
        if i >= 1:
            assert serialize_float32_bits(decoded) == serialize_float32_bits(max)
        else:
            assert serialize_float32_bits(decoded) == serialize_float32_bits(min)
        i += 1

def TestSerializeFloat():
    serialize_float_test_run_file("float")
    serialize_float_test_run_file("double")
    serialize_float_test_run_file("fixed")
    serialize_float_test_run_file("compressed_float")
    serialize_float_test_nan_classes()
    serialize_float_test_compressed_bounds()

// ---------------------------------------------------------------------------
// API misuse aborts (DESIGN.md (e), ABORT CASES): min >= max and res <= 0 on
// compressed_float, a bad Q format and min > max on fixed, bad precomputed
// constants. Each abort is its own process because it exits 70.
// ---------------------------------------------------------------------------

// expect-abort: serialize: compressed float requires min < max and resolution > 0
def TestSerializeFloatCompressedEqualBoundsAbort():
    let w = serialize_write_stream(ensure_size("", 8, 0))
    w.serialize_compressed_float(0.5, 1.0, 1.0, 0.01)

// expect-abort: serialize: compressed float requires min < max and resolution > 0
def TestSerializeFloatCompressedReversedBoundsAbort():
    let w = serialize_write_stream(ensure_size("", 8, 0))
    w.serialize_compressed_float(0.5, 2.0, 1.0, 0.01)

// expect-abort: serialize: compressed float requires min < max and resolution > 0
def TestSerializeFloatCompressedZeroResolutionAbort():
    let w = serialize_write_stream(ensure_size("", 8, 0))
    w.serialize_compressed_float(0.5, 0.0, 1.0, 0.0)

// expect-abort: serialize: compressed float requires min < max and resolution > 0
def TestSerializeFloatCompressedNegativeResolutionAbort():
    let w = serialize_write_stream(ensure_size("", 8, 0))
    w.serialize_compressed_float(0.5, 0.0, 1.0, -0.01)

// expect-abort: serialize: fixed point requires integer bits >= 1, fraction bits >= 0, a Q format that fits the storage width, and min <= max
def TestSerializeFloatFixedBadQFormatAbort():
    let w = serialize_write_stream(ensure_size("", 8, 0))
    w.serialize_fixed32(0, 0, 8, -1, 1)

// expect-abort: serialize: fixed point requires integer bits >= 1, fraction bits >= 0, a Q format that fits the storage width, and min <= max
def TestSerializeFloatFixedMinAboveMaxAbort():
    let w = serialize_write_stream(ensure_size("", 8, 0))
    w.serialize_fixed32(0, 8, 8, 100, -100)

// expect-abort: serialize: precomputed compressed float constants must be exactly what serialize_compressed_float_params derives
def TestSerializeFloatPrecomputedBitsAbort():
    let w = serialize_write_stream(ensure_size("", 8, 0))
    w.serialize_compressed_float_precomputed(0.5, 1000, 9, 10.0, 0.0)
