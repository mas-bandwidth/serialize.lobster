// test/strings/strings_test.lobster — TestSerializeStrings (STANDARD.md, Bytes
// and Strings: bytes, string; align; object; Reader Obligations; DESIGN.md
// (d), (e), (f)).
//
// Every record of conformance/bytes.txt, string.txt, align.txt and object.txt
// runs as a runner must: the reader's value and bits consumed, the
// canonical writer's exact bytes and bits, the measure count, and for a refusal
// a terminal stream. The record count printed per file must equal the file's
// own count of operation lines.
import serialize

struct strings_record:
    op:string = ""
    name:string = ""
    buffer_size:int = 0
    preceding_bits:int = 0
    count:int = 0
    steps:[string] = []
    bytes:[int] = []
    expect:[string] = []
    refused:bool = false
    reason:string = ""
    consumed:int = 0
    canonical:bool = false
    measure_at_least:int = -1

def strings_check(cond:bool, message:string):
    if not cond:
        print "FAIL " + message
        assert false

def strings_parse_int(text:string) -> int:
    let value, ok = string_to_int(text, 10)
    strings_check(ok, "not an integer: " + text)
    return value

def strings_byte_list(text:string) -> [int]:
    let out:[int] = []
    for(tokenize(text, " ", "")) tok:
        if length(tok) > 0:
            let b, ok = string_to_int(tok, 16)
            strings_check(ok and b >= 0 and b <= 255, "bad byte " + tok)
            out.push(b)
    return out

def strings_bytes_string(bytes:[int]) -> string:
    let data = ensure_size("", length(bytes), 0)
    for(bytes) b, i:
        write_int8_le(data, i, b)
    return data

def strings_hex_string(text:string) -> string:
    return strings_bytes_string(strings_byte_list(text))

def strings_hex_digit(b:int) -> string:
    let digits = "0123456789ABCDEF"
    return substring(digits, b & 15, 1)

def strings_bytes_hex(data:string) -> string:
    var out = ""
    for(length(data)) i:
        let b = read_uint8_le(data, i)
        out += strings_hex_digit(b >> 4) + strings_hex_digit(b)
    return out

// ---------------------------------------------------------------------------
// the record parser (STANDARD.md, "The vector format")
// ---------------------------------------------------------------------------

def strings_parse_records(text:string) -> [strings_record], int:
    let lines = tokenize(text, "\n", "")
    let records:[strings_record] = []
    var current = strings_record {}
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
            current = strings_record {}
            current.op = substring(line, 10, -1)
            have = true
        elif not have:
            continue
        elif length(line) >= 5 and substring(line, 0, 5) == "name ":
            current.name = substring(line, 5, -1)
        elif length(line) >= 6 and substring(line, 0, 6) == "param ":
            let key, value = split_string(substring(line, 6, -1), " = ")
            if key == "preceding_bits":
                current.preceding_bits = strings_parse_int(value)
            elif key == "count":
                current.count = strings_parse_int(value)
            elif key == "buffer_size":
                current.buffer_size = strings_parse_int(value)
            elif key == "step":
                current.steps.push(value)
            else:
                strings_check(false, "unknown param " + key)
        elif line == "bytes":
            current.bytes = []
        elif length(line) >= 6 and substring(line, 0, 6) == "bytes ":
            current.bytes = strings_byte_list(substring(line, 6, -1))
        elif length(line) >= 7 and substring(line, 0, 7) == "expect ":
            let e = substring(line, 7, -1)
            if length(e) > 8 and substring(e, 0, 8) == "refused ":
                current.refused = true
                current.reason = substring(e, 8, -1)
            elif e == "value =":
                current.expect = [""]
            elif length(e) >= 8 and substring(e, 0, 8) == "value = ":
                let rest = substring(e, 8, -1)
                if length(rest) == 0:
                    current.expect = [""]
                else:
                    current.expect = tokenize(rest, "|", " ")
            else:
                strings_check(false, "bad expect " + e)
        elif length(line) >= 9 and substring(line, 0, 9) == "consumed ":
            current.consumed = strings_parse_int(substring(line, 9, -1))
        elif length(line) >= 16 and substring(line, 0, 16) == "writer canonical":
            current.canonical = true
        elif length(line) >= 17 and substring(line, 0, 17) == "measure_at_least ":
            current.measure_at_least = strings_parse_int(substring(line, 17, -1))
    if have:
        records.push(current)
    return records, operations

def strings_count_operations(text:string) -> int:
    var count = 0
    for(tokenize(text, "\n", "")) line:
        if length(line) >= 10 and substring(line, 0, 10) == "operation ":
            count += 1
    return count

def strings_read_pre(r:serialize_read_stream, n:int) -> int, bool:
    var pre = 0
    var ok = true
    if n > 0:
        pre, ok = r.serialize_bits(pre, n)
    return pre, ok

def strings_canonical(w:serialize_write_stream, rec:strings_record, what:string):
    w.flush()
    strings_check(w.bits_processed() == rec.consumed, what + ": write bits")
    strings_check(w.bytes_processed() == length(rec.bytes), what + ": write bytes")
    for(rec.bytes) b, i:
        strings_check(read_uint8_le(w.buffer, i) == b, what + ": canonical byte " + string(i))

// ---------------------------------------------------------------------------
// per-file runners
// ---------------------------------------------------------------------------

def strings_run_bytes(rec:strings_record, what:string):
    let data = strings_bytes_string(rec.bytes)
    let r = serialize_read_stream_padded(data)
    var pre = 0
    var ok = true
    pre, ok = strings_read_pre(r, rec.preceding_bits)
    strings_check(ok, what + ": preceding bits")
    let dst = ensure_size("", rec.count, 0xEE)
    var got = ""
    got, ok = r.serialize_bytes(dst, rec.count)
    if rec.refused:
        strings_check(not ok, what + ": expected refusal")
        strings_check(r.error(), what + ": refusal did not latch")
        strings_check(r.refusal_name() == rec.reason, what + ": refused as " + r.refusal_name() + ", the vector states " + rec.reason)
        let before = r.bits_processed()
        var d2 = ensure_size("", 1, 0)
        d2, ok = r.serialize_bytes(d2, 0)
        strings_check(not ok and r.bits_processed() == before, what + ": stream not terminal")
        return
    strings_check(ok, what + ": read refused")
    strings_check(r.bits_processed() == rec.consumed, what + ": read bits")
    strings_check(got == strings_hex_string(rec.expect[0]), what + ": read value")
    if rec.canonical:
        let w = serialize_write_stream(ensure_size("", 64, 0))
        if rec.preceding_bits > 0:
            var wp = pre
            var wok = true
            wp, wok = w.serialize_bits(wp, rec.preceding_bits)
            strings_check(wok, what + ": preceding write")
        var wd = got
        var wok2 = true
        wd, wok2 = w.serialize_bytes(got, rec.count)
        strings_check(wok2, what + ": write refused")
        strings_canonical(w, rec, what)

def strings_run_string(rec:strings_record, what:string):
    let r = serialize_read_stream_padded(strings_bytes_string(rec.bytes))
    var got = ""
    var ok = true
    got, ok = r.serialize_string(got, rec.buffer_size)
    if rec.refused:
        strings_check(not ok, what + ": expected refusal")
        strings_check(r.error(), what + ": refusal did not latch")
        strings_check(r.refusal_name() == rec.reason, what + ": refused as " + r.refusal_name() + ", the vector states " + rec.reason)
        strings_check(got == "", what + ": refusal touched the destination")
        let before = r.bits_processed()
        got, ok = r.serialize_string(got, rec.buffer_size)
        strings_check(not ok and got == "" and r.bits_processed() == before, what + ": stream not terminal")
        return
    strings_check(ok, what + ": read refused")
    strings_check(r.bits_processed() == rec.consumed, what + ": read bits")
    strings_check(got == strings_hex_string(rec.expect[0]), what + ": read value")
    if rec.canonical:
        let w = serialize_write_stream(ensure_size("", 256, 0))
        var wv = got
        var wok = true
        wv, wok = w.serialize_string(got, rec.buffer_size)
        strings_check(wok, what + ": write refused")
        strings_canonical(w, rec, what)

def strings_run_align(rec:strings_record, what:string):
    let r = serialize_read_stream_padded(strings_bytes_string(rec.bytes))
    var pre = 0
    var ok = true
    pre, ok = strings_read_pre(r, rec.preceding_bits)
    strings_check(ok, what + ": preceding bits")
    let aok = r.serialize_align()
    if rec.refused:
        strings_check(not aok, what + ": expected refusal")
        strings_check(r.error(), what + ": refusal did not latch")
        strings_check(r.refusal_name() == rec.reason, what + ": refused as " + r.refusal_name() + ", the vector states " + rec.reason)
        let before = r.bits_processed()
        strings_check(not r.serialize_align() and r.bits_processed() == before, what + ": stream not terminal")
        return
    strings_check(aok, what + ": read refused")
    strings_check(r.bits_processed() == rec.consumed, what + ": read bits")
    if rec.canonical:
        let w = serialize_write_stream(ensure_size("", 16, 0))
        if rec.preceding_bits > 0:
            var wp = pre
            var wok = true
            wp, wok = w.serialize_bits(wp, rec.preceding_bits)
            strings_check(wok, what + ": preceding write")
        strings_check(w.serialize_align(), what + ": align write")
        strings_canonical(w, rec, what)

// ---------------------------------------------------------------------------
// object: the caller's own serialize, inline (STANDARD.md, object)
// ---------------------------------------------------------------------------

class string_seq_object : serialize_object_base
    rec:strings_record = strings_record {}
    pos:int = 0
    count:int = 0
    values:[string] = []
    vpos:int = 0

def strings_top_count(steps:[string]) -> int:
    var count = 0
    var pos = 0
    while pos < length(steps):
        let kind, arg = split_string(steps[pos], " ")
        count += 1
        pos += 1
        if kind == "object":
            pos += strings_parse_int(arg)
    return count

def strings_exec_step(s, rec:strings_record, pos:int, values:[string], vpos:int) -> int, int, bool:
    let step = rec.steps[pos]
    let kind, arg = split_string(step, " ")
    if kind == "object":
        let n = strings_parse_int(arg)
        if s.is_reading():
            values.push("-")
        elif s.is_writing():
            if vpos >= length(values) or values[vpos] != "-":
                return pos + 1 + n, vpos, false
        var child_vpos = vpos
        if s.is_writing():
            child_vpos = vpos + 1
        let child = string_seq_object { rec: rec, pos: pos + 1, count: n, values: values, vpos: child_vpos }
        let ok = s.serialize_object(child)
        if s.is_writing():
            return pos + 1 + n, child.vpos, ok
        return pos + 1 + n, vpos, ok
    if s.is_reading():
        var ok = true
        if kind == "bits":
            var v = 0
            v, ok = s.serialize_bits(v, strings_parse_int(arg))
            if ok:
                values.push(string(v))
        elif kind == "bool":
            var v = false
            v, ok = s.serialize_bool(v)
            if ok:
                values.push(if v: "true" else: "false")
        elif kind == "bytes":
            let n = strings_parse_int(arg)
            var d = ensure_size("", n, 0)
            d, ok = s.serialize_bytes(d, n)
            if ok:
                values.push(strings_bytes_hex(d))
        elif kind == "align":
            ok = s.serialize_align()
            if ok:
                values.push("-")
        else:
            ok = false
        return pos + 1, vpos, ok
    if s.is_writing():
        if vpos >= length(values):
            return pos + 1, vpos, false
        let text = values[vpos]
        var ok = true
        if kind == "bits":
            var v = strings_parse_int(text)
            v, ok = s.serialize_bits(v, strings_parse_int(arg))
        elif kind == "bool":
            var v = text == "true"
            v, ok = s.serialize_bool(v)
        elif kind == "bytes":
            var d = strings_hex_string(text)
            d, ok = s.serialize_bytes(d, strings_parse_int(arg))
        elif kind == "align":
            ok = s.serialize_align()
        else:
            ok = false
        return pos + 1, vpos + 1, ok
    var ok = true
    if kind == "bits":
        var v = 0
        v, ok = s.serialize_bits(v, strings_parse_int(arg))
    elif kind == "bool":
        var v = false
        v, ok = s.serialize_bool(v)
    elif kind == "bytes":
        let n = strings_parse_int(arg)
        var d = ensure_size("", n, 0)
        d, ok = s.serialize_bytes(d, n)
    elif kind == "align":
        ok = s.serialize_align()
    else:
        ok = false
    return pos + 1, vpos, ok

def serialize(o::string_seq_object, s) -> bool:
    var cur_pos = o.pos
    var cur_vpos = o.vpos
    var i = 0
    while i < o.count:
        var ok = true
        cur_pos, cur_vpos, ok = strings_exec_step(s, o.rec, cur_pos, o.values, cur_vpos)
        if not ok:
            return false
        i += 1
    o.pos = cur_pos
    o.vpos = cur_vpos
    return s.ok()

def strings_run_sequence(rec:strings_record, what:string):
    let r = serialize_read_stream_padded(strings_bytes_string(rec.bytes))
    let values:[string] = []
    let root = string_seq_object { rec: rec, pos: 0, count: strings_top_count(rec.steps), values: values }
    let ok = r.serialize_object(root)
    if rec.refused:
        strings_check(not ok, what + ": expected refusal")
        strings_check(r.error(), what + ": refusal did not latch")
        strings_check(r.refusal_name() == rec.reason, what + ": refused as " + r.refusal_name() + ", the vector states " + rec.reason)
        return
    strings_check(ok, what + ": read refused")
    strings_check(r.bits_processed() == rec.consumed, what + ": read bits")
    strings_check(length(values) == length(rec.expect), what + ": value count")
    for(values) v, i:
        strings_check(v == rec.expect[i], what + ": value " + string(i) + " (" + v + " != " + rec.expect[i] + ")")
    let m = serialize_measure_stream()
    let mroot = string_seq_object { rec: rec, pos: 0, count: strings_top_count(rec.steps), values: [] }
    let mok = m.serialize_object(mroot)
    strings_check(mok, what + ": measure refused")
    if rec.measure_at_least >= 0:
        strings_check(m.bits_processed() >= rec.measure_at_least, what + ": measure floor")
    strings_check(m.bits_processed() >= r.bits_processed(), what + ": measure below write")
    if rec.canonical:
        let w = serialize_write_stream(ensure_size("", 64, 0))
        let wroot = string_seq_object { rec: rec, pos: 0, count: strings_top_count(rec.steps), values: values }
        let wok = w.serialize_object(wroot)
        strings_check(wok, what + ": write refused")
        strings_canonical(w, rec, what)

def strings_run_file(name:string):
    let maybe = read_file("conformance/" + name + ".txt")
    strings_check(maybe != nil, "missing conformance/" + name + ".txt")
    let text = if maybe != nil: maybe else: ""
    let records, operations = strings_parse_records(text)
    let declared = strings_count_operations(text)
    print "test/strings: " + name + ".txt has " + string(length(records)) + " records"
    strings_check(length(records) == operations and operations == declared, name + ": record count")
    for(records) rec:
        let what = name + ".txt " + rec.name
        if rec.op == "bytes":
            strings_run_bytes(rec, what)
        elif rec.op == "string":
            strings_run_string(rec, what)
        elif rec.op == "align":
            strings_run_align(rec, what)
        elif rec.op == "sequence":
            strings_run_sequence(rec, what)
        else:
            strings_check(false, what + ": unknown operation " + rec.op)

// ---------------------------------------------------------------------------
// write refusals (coordinator ruling 2026-10-19): bad text latches and writes
// nothing, mirroring the reader; it never aborts (DESIGN.md (e)).
// ---------------------------------------------------------------------------

def strings_expect_write_latch_string(value:string, buffer_size:int, reason:string, what:string):
    let w = serialize_write_stream(ensure_size("", 8, 0))
    var v = value
    var ok = true
    v, ok = w.serialize_string(v, buffer_size)
    strings_check(not ok and w.error(), what + ": expected latch")
    strings_check(w.refusal_name() == reason, what + ": latched " + w.refusal_name() + ", not " + reason)
    strings_check(w.bits_processed() == 0, what + ": wrote bits")
    v, ok = w.serialize_string(value, buffer_size)
    strings_check(not ok and v == value and w.bits_processed() == 0, what + ": stream not terminal")

def strings_write_refusals():
    let with_nul = ensure_size("", 3, 0)
    write_int8_le(with_nul, 0, 0x61)
    write_int8_le(with_nul, 1, 0)
    write_int8_le(with_nul, 2, 0x62)
    strings_expect_write_latch_string(with_nul, 16, "embedded_nul", "string interior NUL")

    let overlong = ensure_size("", 2, 0)
    write_int8_le(overlong, 0, 0xC0)
    write_int8_le(overlong, 1, 0x80)
    strings_expect_write_latch_string(overlong, 16, "invalid_utf8", "string overlong UTF-8")

    // A NUL and bad UTF-8 together: the NUL rule first, as on read.
    let both = ensure_size("", 2, 0)
    write_int8_le(both, 0, 0xFF)
    write_int8_le(both, 1, 0)
    strings_expect_write_latch_string(both, 16, "embedded_nul", "string NUL after a byte that is never UTF-8")

    let too_long = ensure_size("", 4, 0x41)
    strings_expect_write_latch_string(too_long, 4, "value_out_of_range", "string past buffer_size")

// A string read holds the claimed length against the bytes that remain BEFORE
// it allocates the payload (PORT-BRIEF 2026-10-22, allocate-before-check): a
// 4-byte stream under a buffer_size of 2^31 that claims 2^31 - 1 bytes is
// refused as past_end with its destination untouched, and nothing of the
// claimed size is allocated. The same holds for a stream whose padding is set:
// nonzero_padding comes first.
def strings_claimed_length_before_allocation():
    let buffer_size = 2147483647
    let r = serialize_read_stream_padded(strings_hex_string("fe ff ff 7f"))
    var v = "SENTINEL"
    var ok = true
    v, ok = r.serialize_string(v, buffer_size)
    strings_check(not ok and v == "SENTINEL" and r.refusal_name() == "past_end", "huge claimed length: refused as " + r.refusal_name())
    let p = serialize_read_stream_padded(strings_hex_string("fe ff ff ff 01"))
    v, ok = p.serialize_string(v, buffer_size)
    strings_check(not ok and v == "SENTINEL" and p.refusal_name() == "nonzero_padding", "huge claimed length after set padding: refused as " + p.refusal_name())
    print "test/strings: a claimed length past the stream is refused before any allocation"

def TestSerializeStrings():
    strings_run_file("bytes")
    strings_run_file("string")
    strings_run_file("align")
    strings_run_file("object")
    strings_write_refusals()
    strings_claimed_length_before_allocation()

// The API misuse serialize.c asserts on (DESIGN.md (e), ABORT).
// expect-abort: serialize: buffer_size must be at least 1
def TestSerializeStringsBufferSizeAborts():
    let w = serialize_write_stream(ensure_size("", 8, 0))
    var v = ""
    var ok = true
    v, ok = w.serialize_string(v, 0)

// expect-abort: serialize: bytes must not be negative
def TestSerializeStringsNegativeBytesAborts():
    let r = serialize_read_stream_padded("")
    var v = ""
    var ok = true
    v, ok = r.serialize_bytes(v, -1)
