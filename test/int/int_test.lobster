// test/int/int_test.lobster — TestSerializeInt (STANDARD.md, Integers: int
// (ranged), int64 (ranged), int128 (ranged), int_relative; Bit-Level
// Primitives: bits, bool, uint128; DESIGN.md (c), (e), (f)).
//
// Every record of conformance/bits.txt, bool.txt, int.txt, int64.txt,
// int128.txt, uint128.txt and int_relative.txt is run as a runner must: the
// reader's value and bits consumed, the canonical writer's exact bytes and
// bits, the measure count, and for a refusal the untouched destination and a
// terminal stream. The record count printed per file must equal the file's
// own count of operation lines.
import serialize

struct int_record:
    op:string = ""
    name:string = ""
    bits_text:string = ""
    min_text:string = ""
    max_text:string = ""
    previous_text:string = ""
    bytes:[int] = []
    expect_text:string = ""
    refused:bool = false
    reason:string = ""
    consumed:int = 0
    canonical:bool = false

def int_check(cond:bool, message:string):
    if not cond:
        print "FAIL " + message
        assert false

def int_parse_int(text:string) -> int:
    let value, ok = string_to_int(text, 10)
    int_check(ok, "not an integer: " + text)
    return value

// A 128-bit value from decimal or 0x hex, two's complement for a leading
// minus. Lobster's int is 64-bit, so the accumulator is the library's own
// { lo, hi } pair (DESIGN.md (c), 128 bits are two int lanes).
def int_digit(ch:int) -> int:
    if ch >= 48 and ch <= 57:
        return ch - 48
    if ch >= 97 and ch <= 102:
        return ch - 87
    if ch >= 65 and ch <= 70:
        return ch - 55
    int_check(false, "not a digit")
    return 0

def int_u128_shl(a:serialize_uint128, n:int) -> serialize_uint128:
    if n == 0:
        return a
    let lo = serialize_shl(a.lo, n)
    let hi = serialize_shl(a.hi, n) | serialize_shr(a.lo, 64 - n)
    return serialize_uint128_make(hi, lo)

def int_u128_mul10(a:serialize_uint128) -> serialize_uint128:
    let a2 = int_u128_shl(a, 1)
    let a4 = int_u128_shl(a2, 1)
    let a8 = int_u128_shl(a4, 1)
    return serialize_u128_add(a8, a2)

def int_parse_u128(text:string) -> serialize_uint128:
    var negative = false
    var body = text
    if substring(text, 0, 1) == "-":
        negative = true
        body = substring(text, 1, -1)
    var base = 10
    if length(body) >= 2 and substring(body, 0, 2) == "0x":
        base = 16
        body = substring(body, 2, -1)
    elif length(body) >= 2 and substring(body, 0, 2) == "0X":
        base = 16
        body = substring(body, 2, -1)
    var acc = serialize_uint128_make(0, 0)
    for(body) ch:
        if base == 16:
            acc = int_u128_shl(acc, 4)
        else:
            acc = int_u128_mul10(acc)
        acc = serialize_u128_add(acc, serialize_uint128_make(0, int_digit(ch)))
    if negative:
        acc = serialize_u128_sub(serialize_uint128_make(0, 0), acc)
    return acc

// A 64-bit pattern: the low lane of the 128-bit parse, which is exact for
// both signed values and the u64 bit patterns of bits.txt (DESIGN.md (c)).
def int_parse_i64(text:string) -> int:
    return int_parse_u128(text).lo

def int_parse_i128(text:string) -> serialize_int128:
    let u = int_parse_u128(text)
    return serialize_int128_make(u.hi, u.lo)

def int_bytes(rec:int_record) -> string:
    let data = ensure_size("", length(rec.bytes), 0)
    for(rec.bytes) b, i:
        write_int8_le(data, i, b)
    return data

def int_write_stream() -> serialize_write_stream:
    return serialize_write_stream(ensure_size("", 32, 0))

def int_canonical(w:serialize_write_stream, rec:int_record, what:string):
    w.flush()
    int_check(w.bits_processed() == rec.consumed, what + ": write bits")
    int_check(w.bytes_processed() == length(rec.bytes), what + ": write bytes")
    for(rec.bytes) b, i:
        int_check(read_uint8_le(w.buffer, i) == b, what + ": canonical byte " + string(i))

// ---------------------------------------------------------------------------
// the record parser (STANDARD.md, "The vector format")
// ---------------------------------------------------------------------------

def int_parse_records(text:string) -> [int_record], int:
    let lines = tokenize(text, "\n", "")
    let records:[int_record] = []
    var current = int_record {}
    var have = false
    var operations = 0
    for(lines) line:
        if length(line) == 0:
            continue
        if substring(line, 0, 1) == "#":
            continue
        if length(line) >= 10 and substring(line, 0, 10) == "operation ":
            if have:
                records.push(current)
            operations += 1
            current = int_record {}
            current.op = substring(line, 10, -1)
            have = true
        elif not have:
            continue
        elif length(line) >= 5 and substring(line, 0, 5) == "name ":
            current.name = substring(line, 5, -1)
        elif length(line) >= 6 and substring(line, 0, 6) == "param ":
            let key, value = split_string(substring(line, 6, -1), " = ")
            if key == "bits":
                current.bits_text = value
            elif key == "min":
                current.min_text = value
            elif key == "max":
                current.max_text = value
            elif key == "previous":
                current.previous_text = value
            else:
                int_check(false, "unknown param " + key)
        elif line == "bytes":
            current.bytes = []
        elif length(line) >= 6 and substring(line, 0, 6) == "bytes ":
            for(tokenize(substring(line, 6, -1), " ", "")) tok:
                if length(tok) > 0:
                    let b, ok = string_to_int(tok, 16)
                    int_check(ok and b >= 0 and b <= 255, "bad byte " + tok)
                    current.bytes.push(b)
        elif length(line) >= 7 and substring(line, 0, 7) == "expect ":
            let expect = substring(line, 7, -1)
            if length(expect) > 8 and substring(expect, 0, 8) == "refused ":
                current.refused = true
                current.reason = substring(expect, 8, -1)
            else:
                let key, value = split_string(expect, " = ")
                int_check(key == "value", "bad expect " + expect)
                current.expect_text = value
        elif length(line) >= 9 and substring(line, 0, 9) == "consumed ":
            current.consumed = int_parse_int(substring(line, 9, -1))
        elif length(line) >= 16 and substring(line, 0, 16) == "writer canonical":
            current.canonical = true
    if have:
        records.push(current)
    return records, operations

def int_count_operations(text:string) -> int:
    var count = 0
    for(tokenize(text, "\n", "")) line:
        if length(line) >= 10 and substring(line, 0, 10) == "operation ":
            count += 1
    return count

// ---------------------------------------------------------------------------
// per-operation runners
// ---------------------------------------------------------------------------

def int_run_bits(rec:int_record, what:string):
    let width = int_parse_int(rec.bits_text)
    if rec.refused:
        let r = serialize_read_stream_padded(int_bytes(rec))
        var v = 0x12345678
        var ok = true
        if width <= 32:
            v, ok = r.serialize_bits(v, width)
        else:
            v, ok = r.serialize_bits64(v, width)
        int_check(not ok, what + ": expected refusal")
        int_check(r.error(), what + ": refusal did not latch")
        int_check(r.refusal_name() == rec.reason, what + ": refused as " + r.refusal_name() + ", the vector states " + rec.reason)
        int_check(v == 0x12345678, what + ": refusal touched the destination")
        let before = r.bits_processed()
        var v2 = 0x12345678
        var ok2 = true
        if width <= 32:
            v2, ok2 = r.serialize_bits(v2, width)
        else:
            v2, ok2 = r.serialize_bits64(v2, width)
        int_check(not ok2 and v2 == 0x12345678 and r.bits_processed() == before, what + ": stream not terminal")
        return
    let expected = int_parse_i64(rec.expect_text)
    let r = serialize_read_stream_padded(int_bytes(rec))
    var v = 0
    var ok = true
    if width <= 32:
        v, ok = r.serialize_bits(v, width)
    else:
        v, ok = r.serialize_bits64(v, width)
    int_check(ok, what + ": read refused")
    int_check(v == expected, what + ": read value")
    int_check(r.bits_processed() == rec.consumed, what + ": read bits")
    if rec.canonical:
        let w = int_write_stream()
        var wv = expected
        var wok = true
        if width <= 32:
            wv, wok = w.serialize_bits(expected, width)
        else:
            wv, wok = w.serialize_bits64(expected, width)
        int_check(wok, what + ": write refused")
        int_canonical(w, rec, what)
        let m = serialize_measure_stream()
        var mv = 0
        var mok = true
        if width <= 32:
            mv, mok = m.serialize_bits(0, width)
        else:
            mv, mok = m.serialize_bits64(0, width)
        int_check(mok and m.bits_processed() == rec.consumed, what + ": measure bits")

def int_run_bool(rec:int_record, what:string):
    if rec.refused:
        let r = serialize_read_stream_padded(int_bytes(rec))
        var v = true
        var ok = true
        v, ok = r.serialize_bool(v)
        int_check(not ok and v == true and r.error(), what + ": expected refusal")
        int_check(r.refusal_name() == rec.reason, what + ": refused as " + r.refusal_name() + ", the vector states " + rec.reason)
        let before = r.bits_processed()
        var v2 = true
        var ok2 = true
        v2, ok2 = r.serialize_bool(v2)
        int_check(not ok2 and v2 == true and r.bits_processed() == before, what + ": stream not terminal")
        return
    let expected = rec.expect_text == "true"
    let r = serialize_read_stream_padded(int_bytes(rec))
    var v = false
    var ok = true
    v, ok = r.serialize_bool(v)
    int_check(ok and v == expected, what + ": read value")
    int_check(r.bits_processed() == rec.consumed, what + ": read bits")
    if rec.canonical:
        let w = int_write_stream()
        var wv = false
        var wok = true
        wv, wok = w.serialize_bool(expected)
        int_check(wok, what + ": write refused")
        int_canonical(w, rec, what)
        let m = serialize_measure_stream()
        var mv = false
        var mok = true
        mv, mok = m.serialize_bool(false)
        int_check(mok and m.bits_processed() == rec.consumed, what + ": measure bits")

def int_run_uint128(rec:int_record, what:string):
    let sentinel = serialize_uint128_make(0xCAFEF00D, 0xF00DCAFE)
    if rec.refused:
        let r = serialize_read_stream_padded(int_bytes(rec))
        var v = sentinel
        var ok = true
        v, ok = r.serialize_uint128(v)
        int_check(not ok, what + ": expected refusal")
        int_check(r.error(), what + ": refusal did not latch")
        int_check(r.refusal_name() == rec.reason, what + ": refused as " + r.refusal_name() + ", the vector states " + rec.reason)
        int_check(serialize_uint128_equal(v, sentinel), what + ": refusal touched the destination")
        let before = r.bits_processed()
        var v2 = sentinel
        var ok2 = true
        v2, ok2 = r.serialize_uint128(v2)
        int_check(not ok2 and serialize_uint128_equal(v2, sentinel) and r.bits_processed() == before, what + ": stream not terminal")
        return
    let expected = int_parse_u128(rec.expect_text)
    let r = serialize_read_stream_padded(int_bytes(rec))
    var v = sentinel
    var ok = true
    v, ok = r.serialize_uint128(v)
    int_check(ok, what + ": read refused")
    int_check(serialize_uint128_equal(v, expected), what + ": read value")
    int_check(r.bits_processed() == rec.consumed, what + ": read bits")
    if rec.canonical:
        let w = int_write_stream()
        var wv = expected
        var wok = true
        wv, wok = w.serialize_uint128(expected)
        int_check(wok, what + ": write refused")
        int_canonical(w, rec, what)
        let m = serialize_measure_stream()
        var mv = expected
        var mok = true
        mv, mok = m.serialize_uint128(expected)
        int_check(mok and m.bits_processed() == rec.consumed, what + ": measure bits")

def int_run_ranged(rec:int_record, what:string):
    let is_128 = rec.op == "int128"
    var min64 = 0
    var max64 = 0
    var expected64 = 0
    var min128 = serialize_int128_make(0, 0)
    var max128 = serialize_int128_make(0, 0)
    var expected128 = serialize_int128_make(0, 0)
    if is_128:
        min128 = int_parse_i128(rec.min_text)
        max128 = int_parse_i128(rec.max_text)
        if not rec.refused:
            expected128 = int_parse_i128(rec.expect_text)
    else:
        min64 = int_parse_i64(rec.min_text)
        max64 = int_parse_i64(rec.max_text)
        if not rec.refused:
            expected64 = int_parse_i64(rec.expect_text)
    if rec.refused:
        let r = serialize_read_stream_padded(int_bytes(rec))
        var ok = true
        if is_128:
            var v = min128
            var vok = true
            v, vok = r.serialize_int128(v, min128, max128)
            ok = vok
            int_check(not ok, what + ": expected refusal")
            int_check(r.error(), what + ": refusal did not latch")
            int_check(r.refusal_name() == rec.reason, what + ": refused as " + r.refusal_name() + ", the vector states " + rec.reason)
            int_check(serialize_int128_equal(v, min128), what + ": refusal touched the destination")
            let before = r.bits_processed()
            var v2 = min128
            var ok2 = true
            v2, ok2 = r.serialize_int128(v2, min128, max128)
            int_check(not ok2 and serialize_int128_equal(v2, min128) and r.bits_processed() == before, what + ": stream not terminal")
        else:
            var v = min64
            var vok = true
            if rec.op == "int":
                v, vok = r.serialize_int(v, min64, max64)
            else:
                v, vok = r.serialize_int64(v, min64, max64)
            ok = vok
            int_check(not ok, what + ": expected refusal")
            int_check(r.error(), what + ": refusal did not latch")
            int_check(r.refusal_name() == rec.reason, what + ": refused as " + r.refusal_name() + ", the vector states " + rec.reason)
            int_check(v == min64, what + ": refusal touched the destination")
            let before = r.bits_processed()
            var v2 = min64
            var ok2 = true
            if rec.op == "int":
                v2, ok2 = r.serialize_int(v2, min64, max64)
            else:
                v2, ok2 = r.serialize_int64(v2, min64, max64)
            int_check(not ok2 and v2 == min64 and r.bits_processed() == before, what + ": stream not terminal")
        return
    let r = serialize_read_stream_padded(int_bytes(rec))
    var ok = true
    if is_128:
        var v = min128
        var vok = true
        v, vok = r.serialize_int128(v, min128, max128)
        ok = vok
        int_check(ok, what + ": read refused")
        int_check(serialize_int128_equal(v, expected128), what + ": read value")
    else:
        var v = min64
        var vok = true
        if rec.op == "int":
            v, vok = r.serialize_int(v, min64, max64)
        else:
            v, vok = r.serialize_int64(v, min64, max64)
        ok = vok
        int_check(ok, what + ": read refused")
        int_check(v == expected64, what + ": read value")
    int_check(r.bits_processed() == rec.consumed, what + ": read bits")
    if rec.canonical:
        if is_128:
            let w = int_write_stream()
            var wv = expected128
            var wok = true
            wv, wok = w.serialize_int128(expected128, min128, max128)
            int_check(wok, what + ": write refused")
            int_canonical(w, rec, what)
            let m = serialize_measure_stream()
            var mv = expected128
            var mok = true
            mv, mok = m.serialize_int128(expected128, min128, max128)
            int_check(mok and m.bits_processed() == rec.consumed, what + ": measure bits")
        else:
            let w = int_write_stream()
            var wv = expected64
            var wok = true
            if rec.op == "int":
                wv, wok = w.serialize_int(expected64, min64, max64)
            else:
                wv, wok = w.serialize_int64(expected64, min64, max64)
            int_check(wok, what + ": write refused")
            int_canonical(w, rec, what)
            let m = serialize_measure_stream()
            var mv = expected64
            var mok = true
            if rec.op == "int":
                mv, mok = m.serialize_int(expected64, min64, max64)
            else:
                mv, mok = m.serialize_int64(expected64, min64, max64)
            int_check(mok and m.bits_processed() == rec.consumed, what + ": measure bits")

def int_run_relative(rec:int_record, what:string):
    let previous = int_parse_i64(rec.previous_text)
    if rec.refused:
        let r = serialize_read_stream_padded(int_bytes(rec))
        var v = previous
        var ok = true
        v, ok = r.serialize_int_relative(previous, v)
        int_check(not ok, what + ": expected refusal")
        int_check(r.error(), what + ": refusal did not latch")
        int_check(r.refusal_name() == rec.reason, what + ": refused as " + r.refusal_name() + ", the vector states " + rec.reason)
        int_check(v == previous, what + ": refusal touched the destination")
        let before = r.bits_processed()
        var v2 = previous
        var ok2 = true
        v2, ok2 = r.serialize_int_relative(previous, v2)
        int_check(not ok2 and v2 == previous and r.bits_processed() == before, what + ": stream not terminal")
        return
    let expected = int_parse_i64(rec.expect_text)
    let r = serialize_read_stream_padded(int_bytes(rec))
    var v = previous
    var ok = true
    v, ok = r.serialize_int_relative(previous, v)
    int_check(ok, what + ": read refused")
    int_check(v == expected, what + ": read value")
    int_check(r.bits_processed() == rec.consumed, what + ": read bits")
    if rec.canonical:
        let w = int_write_stream()
        var wv = expected
        var wok = true
        wv, wok = w.serialize_int_relative(previous, expected)
        int_check(wok, what + ": write refused")
        int_canonical(w, rec, what)
        let m = serialize_measure_stream()
        var mv = expected
        var mok = true
        mv, mok = m.serialize_int_relative(previous, expected)
        int_check(mok and m.bits_processed() == rec.consumed, what + ": measure bits")

def int_run_file(name:string):
    let maybe = read_file("conformance/" + name + ".txt")
    int_check(maybe != nil, "missing conformance/" + name + ".txt")
    let text = if maybe != nil: maybe else: ""
    let records, operations = int_parse_records(text)
    let declared = int_count_operations(text)
    print "test/int: " + name + ".txt has " + string(length(records)) + " records"
    int_check(length(records) == operations and operations == declared, name + ": record count")
    for(records) rec:
        let what = name + ".txt " + rec.name
        if rec.op == "bits":
            int_run_bits(rec, what)
        elif rec.op == "bool":
            int_run_bool(rec, what)
        elif rec.op == "uint128":
            int_run_uint128(rec, what)
        elif rec.op == "int" or rec.op == "int64" or rec.op == "int128":
            int_run_ranged(rec, what)
        elif rec.op == "int_relative":
            int_run_relative(rec, what)
        else:
            int_check(false, what + ": unknown operation " + rec.op)

// ---------------------------------------------------------------------------
// edge cases: serialize.c's bits_required edges, the full int64 range, and the
// writer's latch one past every bound (DESIGN.md (e))
// ---------------------------------------------------------------------------

def int_round_trip64(min:int, max:int, value:int):
    let w = serialize_write_stream(ensure_size("", 16, 0))
    var wv = value
    var wok = true
    wv, wok = w.serialize_int64(value, min, max)
    int_check(wok, "int64 write refused at " + string(value))
    w.flush()
    let r = serialize_read_stream_padded(substring(w.buffer, 0, w.bytes_processed()))
    var rv = min
    var rok = true
    rv, rok = r.serialize_int64(rv, min, max)
    int_check(rok, "int64 read refused at " + string(value))
    int_check(rv == value, "int64 round trip at " + string(value))
    int_check(r.bits_processed() == w.bits_processed(), "int64 round trip bits")

def TestSerializeInt():
    int_run_file("bits")
    int_run_file("bool")
    int_run_file("int")
    int_run_file("int64")
    int_run_file("int128")
    int_run_file("uint128")
    int_run_file("int_relative")

    // serialize.c serialize_bits_required, the uint32 domain.
    let cases32 = [
        [0, 0, 0], [0, 1, 1], [0, 2, 2], [0, 3, 2], [0, 4, 3],
        [0, 5, 3], [0, 6, 3], [0, 7, 3], [0, 8, 4], [0, 255, 8],
        [0, 65535, 16], [0, 4294967295, 32],
    ]
    for(cases32) c:
        int_check(serialize_bits_required(c[0], c[1]) == c[2],
            "bits_required(" + string(c[0]) + "," + string(c[1]) + ")")

    // serialize.c serialize_bits_required64, over the u64 bit patterns.
    let cases64 = [
        [0, 0, 0], [0, 1, 1], [0, 255, 8], [0, 4294967295, 32],
        [0, 4294967296, 33], [0, 1099511627776, 41],
        [0, -1, 64],
        [-9223372036854775807 - 1, 9223372036854775807, 64],
        [-5000000000, 5000000000, 34],
    ]
    for(cases64) c:
        int_check(serialize_bits_required64(c[0], c[1]) == c[2],
            "bits_required64(" + string(c[0]) + "," + string(c[1]) + ")")

    // bits_required128: the 72-bit span, 64-bit span, degenerate range.
    let m72 = int_parse_i128("-1180591620717411303424")
    let x72 = int_parse_i128("1180591620717411303424")
    int_check(serialize_bits_required128(m72, x72) == 72, "bits_required128 72-bit span")
    let i64min = int_parse_i128("-9223372036854775808")
    let i64max = int_parse_i128("9223372036854775807")
    int_check(serialize_bits_required128(i64min, i64max) == 64, "bits_required128 64-bit span")
    int_check(serialize_bits_required128(i64min, i64min) == 0, "bits_required128 degenerate")

    // The full int64 range's edges: every value round-trips
    // (STANDARD.md, int64).
    let min64 = -9223372036854775807 - 1
    let max64 = 9223372036854775807
    int_round_trip64(min64, max64, min64)
    int_round_trip64(min64, max64, min64 + 1)
    int_round_trip64(min64, max64, -1)
    int_round_trip64(min64, max64, 0)
    int_round_trip64(min64, max64, 1)
    int_round_trip64(min64, max64, max64 - 1)
    int_round_trip64(min64, max64, max64)

    // The writer's latch one past each bound: false, latched, no bits moved,
    // and the stream is terminal (DESIGN.md (e)).
    let w1 = int_write_stream()
    var v = 8
    var ok = true
    v, ok = w1.serialize_int(v, 0, 7)
    int_check(not ok and w1.error() and w1.bits_processed() == 0, "int latch above max")
    let w2 = int_write_stream()
    v = -1
    v, ok = w2.serialize_int(v, 0, 7)
    int_check(not ok and w2.error() and w2.bits_processed() == 0, "int latch below min")
    let w3 = int_write_stream()
    var v64 = 8
    v64, ok = w3.serialize_int64(v64, 0, 7)
    int_check(not ok and w3.error() and w3.bits_processed() == 0, "int64 latch above max")
    let w4 = int_write_stream()
    v64 = 7
    v64, ok = w4.serialize_int64(v64, 8, 8)
    int_check(not ok and w4.error() and w4.bits_processed() == 0, "int64 latch below min")
    let w5 = int_write_stream()
    var v128 = serialize_int128_from_int64(8)
    var ok128 = true
    v128, ok128 = w5.serialize_int128(v128, serialize_int128_from_int64(0), serialize_int128_from_int64(7))
    int_check(not ok128 and w5.error() and w5.bits_processed() == 0, "int128 latch above max")
    let w6 = int_write_stream()
    v128 = serialize_int128_from_int64(-1)
    v128, ok128 = w6.serialize_int128(v128, serialize_int128_from_int64(0), serialize_int128_from_int64(7))
    int_check(not ok128 and w6.error() and w6.bits_processed() == 0, "int128 latch below min")
    let w7 = int_write_stream()
    var vr = 2147483648
    var okr = true
    vr, okr = w7.serialize_int_relative(100, vr)
    int_check(not okr and w7.error() and w7.bits_processed() == 0, "int_relative latch past the domain")

// The write contract serialize.c asserts on write (ABORT CASES).
// expect-abort: serialize: int_relative current must be greater than previous
def TestIntRelativeCurrentMustIncrease():
    let w = int_write_stream()
    var v = 5
    var ok = true
    v, ok = w.serialize_int_relative(5, 5)

// expect-abort: serialize: min must not be greater than max
def TestIntMinGreaterMaxAborts():
    let w = int_write_stream()
    var v = 0
    var ok = true
    v, ok = w.serialize_int(v, 8, 7)
