// test/conformance/conformance_test.lobster — TestConformanceCorpus
// (STANDARD.md, "The vector format" and "What a runner checks"; DESIGN.md
// (g) "Conformance").
//
// Discovers every conformance/*.txt at run time, never a fixed list, and runs
// every record the way a runner must (STANDARD.md, "What a runner checks"): an
// accepted read decodes the value (or the bit pattern for `expect bits`) and
// consumes exactly `consumed` bits; a `writer canonical` record's bytes are
// written byte for byte; a `writer_input` record's writer, handed that float32,
// emits the record's bytes; a refused read is refused FOR ITS STATED REASON,
// leaves its destination as it was, and leaves the stream terminal; sequence
// steps run in order on one stream and `measure_at_least` is a floor for the
// measure stream. Every stream is presented with eight bytes of NON-ZERO slack
// behind it, so a decode that reads past the end cannot pass on zeros.
//
// The controls (STANDARD.md, "A gate nobody has seen go red"): a corpus file
// whose operation has no runner is rejected, never skipped (below); and, per
// refusal rule, a reader with that one rule deleted must fail exactly the
// vectors conformance-controls/<rule>.expected names. Those readers are
// sabotaged copies of src/ staged by tools/controls.sh (make controls), which
// drives conf_control below; src/ itself is never edited.
import serialize

var conf_soft = false

class cval:
    kind:int = 0     // 0 text, 1 int, 2 128-bit, 3 float bits, -1 unknown
    text:string = ""
    i:int = 0
    lo:int = 0
    hi:int = 0
    f:float = 0.0

class conf_rec:
    op:string = ""
    name:string = ""
    bits_text:string = ""
    min_text:string = ""
    max_text:string = ""
    previous_text:string = ""
    res_text:string = ""
    buffer_text:string = ""
    count_text:string = ""
    preceding_text:string = ""
    integer_text:string = ""
    fraction_text:string = ""
    has_preceding:bool = false
    steps:[string] = []
    bytes:[int] = []
    expect_text:string = ""
    expect_bits:bool = false
    refused:bool = false
    reason:string = ""
    has_writer_input:bool = false
    writer_input:int = 0
    malformed:string = ""
    consumed:int = -1
    measure_at_least:int = -1
    canonical:bool = false

// The closed list of refusal reasons a vector may state (STANDARD.md, Refusal
// reasons); "none" is the port's own spelling of no refusal and never a
// vector's.
def conf_known_reason(reason:string) -> bool:
    for(serialize_refusal_names) name, i:
        if i > 0 and name == reason:
            return true
    return false

def conf_check(cond:bool, message:string) -> bool:
    if not cond and not conf_soft:
        print "FAIL " + message
    if not cond and not conf_soft:
        assert false
    return cond

// ---------------------------------------------------------------------------
// parsing (STANDARD.md, "The vector format": lexical rules)
// ---------------------------------------------------------------------------

def conf_digit(ch:int) -> int:
    if ch >= 48 and ch <= 57:
        return ch - 48
    if ch >= 97 and ch <= 102:
        return ch - 87
    if ch >= 65 and ch <= 70:
        return ch - 55
    return 0

def conf_u128_shl(a:serialize_uint128, n:int) -> serialize_uint128:
    if n == 0:
        return a
    let lo = serialize_shl(a.lo, n)
    let hi = serialize_shl(a.hi, n) | serialize_shr(a.lo, 64 - n)
    return serialize_uint128_make(hi, lo)

def conf_u128_mul10(a:serialize_uint128) -> serialize_uint128:
    let a2 = conf_u128_shl(a, 1)
    let a4 = conf_u128_shl(a2, 1)
    let a8 = conf_u128_shl(a4, 1)
    return serialize_u128_add(a8, a2)

// decimal or 0x, signed, up to 128 bits (two's complement for a leading -).
def conf_parse_u128(text:string) -> serialize_uint128:
    var negative = false
    var body = text
    if substring(text, 0, 1) == "-":
        negative = true
        body = substring(text, 1, -1)
    var base = 10
    if length(body) >= 2 and (substring(body, 0, 2) == "0x" or substring(body, 0, 2) == "0X"):
        base = 16
        body = substring(body, 2, -1)
    var acc = serialize_uint128_make(0, 0)
    for(body) ch:
        if base == 16:
            acc = conf_u128_shl(acc, 4)
        else:
            acc = conf_u128_mul10(acc)
        acc = serialize_u128_add(acc, serialize_uint128_make(0, conf_digit(ch)))
    if negative:
        acc = serialize_u128_sub(serialize_uint128_make(0, 0), acc)
    return acc

def conf_parse_i64(text:string) -> int:
    return conf_parse_u128(text).lo

def conf_parse_i128(text:string) -> serialize_int128:
    let u = conf_parse_u128(text)
    return serialize_int128_make(u.hi, u.lo)

def conf_parse_int(text:string) -> int:
    let v, ok = string_to_int(text, 10)
    if not ok:
        let h = conf_parse_u128(text)
        return h.lo
    return v

def conf_parse_float(text:string) -> float:
    let v, ok = string_to_float(text)
    if not ok:
        return 0.0
    return v

def conf_bytes(text:string) -> [int]:
    let out:[int] = []
    for(tokenize(text, " ", "")) tok:
        if length(tok) > 0:
            out.push(conf_parse_u128("0x" + tok).lo)
    return out

def conf_string_from_bytes(bytes:[int]) -> string:
    let data = ensure_size("", length(bytes), 0)
    for(bytes) b, i:
        write_int8_le(data, i, b)
    return data

// ---------------------------------------------------------------------------
// 128-bit decimal formatting, for the sequence spellings
// ---------------------------------------------------------------------------

def conf_u128_bit(a:serialize_uint128, i:int) -> int:
    if i < 64:
        return serialize_shr(a.lo, i) & 1
    return serialize_shr(a.hi, i - 64) & 1

def conf_u128_div10(a:serialize_uint128) -> serialize_uint128, int:
    var q = serialize_uint128_make(0, 0)
    var rem = 0
    var i = 127
    while i >= 0:
        rem = rem * 2 + conf_u128_bit(a, i)
        if rem >= 10:
            rem -= 10
            if i < 64:
                q.lo = q.lo | serialize_shl(1, i)
            else:
                q.hi = q.hi | serialize_shl(1, i - 64)
        i -= 1
    return q, rem

def conf_u128_decimal(a:serialize_uint128) -> string:
    if a.lo == 0 and a.hi == 0:
        return "0"
    var digits = ""
    var v = a
    while v.lo != 0 or v.hi != 0:
        let q, r = conf_u128_div10(v)
        digits = string(r) + digits
        v = q
    return digits

def conf_i128_text(a:serialize_int128) -> string:
    if a.hi < 0:
        let mag = serialize_u128_sub(serialize_uint128_make(0, 0), serialize_uint128_make(a.hi, a.lo))
        return "-" + conf_u128_decimal(mag)
    return conf_u128_decimal(serialize_uint128_make(a.hi, a.lo))

def conf_hex_digit(d:int) -> string:
    let digits = "0123456789ABCDEF"
    return substring(digits, d, 1)

def conf_hex(v:int, width:int) -> string:
    var out = ""
    var i = width - 1
    while i >= 0:
        out = out + conf_hex_digit(serialize_shr(v, i * 4) & 15)
        i -= 1
    return out

def conf_hex_bytes(data:string) -> string:
    var out = ""
    for(length(data)) i:
        if i > 0:
            out = out + " "
        out = out + conf_hex(read_uint8_le(data, i), 2)
    return out

// ---------------------------------------------------------------------------
// record parsing
// ---------------------------------------------------------------------------

def conf_parse_records(text:string) -> [conf_rec], int:
    let lines = tokenize(text, "\n", "")
    let records:[conf_rec] = []
    var current = conf_rec {}
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
            current = conf_rec {}
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
            elif key == "res":
                current.res_text = value
            elif key == "buffer_size":
                current.buffer_text = value
            elif key == "count":
                current.count_text = value
            elif key == "preceding_bits":
                current.preceding_text = value
                current.has_preceding = true
            elif key == "integer_bits":
                current.integer_text = value
            elif key == "fraction_bits":
                current.fraction_text = value
            elif key == "step":
                current.steps.push(value)
            else:
                conf_check(false, "unknown param " + key)
        elif line == "bytes":
            current.bytes = []
        elif length(line) >= 6 and substring(line, 0, 6) == "bytes ":
            current.bytes = conf_bytes(substring(line, 6, -1))
        elif length(line) >= 7 and substring(line, 0, 7) == "expect ":
            let expect = substring(line, 7, -1)
            if expect == "refused" or (length(expect) >= 8 and substring(expect, 0, 8) == "refused "):
                // `expect refused <reason>`: a missing or unknown reason makes
                // the vector malformed, which is red (STANDARD.md, Refusal
                // reasons; "What a runner checks").
                current.refused = true
                current.reason = if length(expect) > 8: substring(expect, 8, -1) else: ""
                if not conf_known_reason(current.reason):
                    current.malformed = "expect refused with a missing or unknown reason: " + current.reason
            elif expect == "value =" or expect == "value = ":
                current.expect_text = ""
            else:
                let key, value = split_string(expect, " = ")
                if key == "bits":
                    current.expect_bits = true
                conf_check(key == "value" or key == "bits", "bad expect " + expect)
                current.expect_text = value
        elif length(line) >= 9 and substring(line, 0, 9) == "consumed ":
            current.consumed = conf_parse_int(substring(line, 9, -1))
        elif length(line) >= 17 and substring(line, 0, 17) == "measure_at_least ":
            current.measure_at_least = conf_parse_int(substring(line, 17, -1))
        elif line == "writer canonical":
            current.canonical = true
        elif length(line) >= 13 and substring(line, 0, 13) == "writer_input ":
            // `writer_input bits = 0x...`: a float32 pattern a writer is handed.
            let key, value = split_string(substring(line, 13, -1), " = ")
            if key != "bits" or length(value) < 3 or substring(value, 0, 2) != "0x":
                current.malformed = "writer_input is not `bits = 0x...`: " + line
            current.has_writer_input = true
            current.writer_input = conf_parse_u128(value).lo
        else:
            // A key this runner does not know is a record it cannot run: red,
            // never skipped.
            current.malformed = "unknown key: " + line
    if have:
        records.push(current)
    return records, operations

// ---------------------------------------------------------------------------
// one step: read and write (STANDARD.md, "A sequence vector states more than
// one operation"; DESIGN.md (a), (e))
// ---------------------------------------------------------------------------

def conf_int_val(x:int) -> cval:
    let v = cval {}
    v.kind = 1
    v.i = x
    v.text = string(x)
    return v

def conf_u128_val(a:serialize_uint128) -> cval:
    let v = cval {}
    v.kind = 2
    v.lo = a.lo
    v.hi = a.hi
    v.text = conf_u128_decimal(a)
    return v

def conf_i128_val(a:serialize_int128) -> cval:
    let v = cval {}
    v.kind = 2
    v.lo = a.lo
    v.hi = a.hi
    v.text = conf_i128_text(a)
    return v

def conf_text_val(s:string) -> cval:
    let v = cval {}
    v.kind = 0
    v.text = s
    return v

def conf_float_val(f:float, bits:int, width:int) -> cval:
    let v = cval {}
    v.kind = 3
    v.f = f
    v.i = bits
    v.text = "0x" + conf_hex(bits, width)
    return v

def conf_step_read(r:serialize_read_stream, step:string) -> cval, bool:
    let toks = tokenize(step, " ", "")
    if length(toks) == 0:
        return conf_text_val(""), false
    let op = toks[0]
    if op == "object":
        if r.failed:
            return conf_text_val("-"), false
        return conf_text_val("-"), true
    if op == "align":
        return conf_text_val("-"), r.serialize_align()
    if op == "end":
        return conf_text_val("-"), r.serialize_end()
    if op == "bool":
        var b = true
        var ok = true
        b, ok = r.serialize_bool(b)
        let bv = conf_int_val(if b: 1 else: 0)
        bv.text = if b: "true" else: "false"
        return bv, ok
    if op == "bits":
        let width = conf_parse_int(toks[1])
        if width <= 32:
            var v = 0x12345678
            var ok = true
            v, ok = r.serialize_bits(v, width)
            return conf_int_val(v), ok
        var v64 = 0x12345678
        var ok64 = true
        v64, ok64 = r.serialize_bits64(v64, width)
        return conf_int_val(v64), ok64
    if op == "uint128":
        var u = serialize_uint128_make(0xCAFEF00D, 0xF00DCAFE)
        var ok = true
        u, ok = r.serialize_uint128(u)
        return conf_u128_val(u), ok
    if op == "int" or op == "int64":
        let mn = conf_parse_i64(toks[1])
        let mx = conf_parse_i64(toks[2])
        var v = 0x0BADF00D
        var ok = true
        if op == "int":
            v, ok = r.serialize_int(v, mn, mx)
        else:
            v, ok = r.serialize_int64(v, mn, mx)
        return conf_int_val(v), ok
    if op == "int128":
        let mn = conf_parse_i128(toks[1])
        let mx = conf_parse_i128(toks[2])
        var v = serialize_int128_make(0x0BADF00D, 0x12345678)
        var ok = true
        v, ok = r.serialize_int128(v, mn, mx)
        return conf_i128_val(v), ok
    if op == "int_relative":
        let previous = conf_parse_i64(toks[1])
        var v = previous
        var ok = true
        v, ok = r.serialize_int_relative(previous, v)
        return conf_int_val(v), ok
    if op == "float":
        var f = 123.5
        var ok = true
        f, ok = r.serialize_float(f)
        return conf_float_val(f, serialize_float32_bits(f), 8), ok
    if op == "double":
        var d = 123.5
        var ok = true
        d, ok = r.serialize_double(d)
        return conf_float_val(d, serialize_float64_bits(d), 16), ok
    if op == "compressed_float":
        let mn = conf_parse_float(toks[1])
        let mx = conf_parse_float(toks[2])
        let res = conf_parse_float(toks[3])
        var f = 123.5
        var ok = true
        f, ok = r.serialize_compressed_float(f, mn, mx, res)
        return conf_float_val(f, serialize_float32_bits(f), 8), ok
    if op == "bytes":
        let count = conf_parse_int(toks[1])
        let sentinel = conf_string_from_bytes(conf_bytes("53 45 4E 54 49 4E 45 4C"))
        var data = sentinel
        var ok = true
        data, ok = r.serialize_bytes(data, count)
        if ok and count < length(data):
            return conf_text_val(conf_hex_bytes(substring(data, 0, count))), ok
        return conf_text_val(conf_hex_bytes(data)), ok
    if op == "string":
        let buffer_size = conf_parse_int(toks[1])
        var value = "SENTINEL"
        var ok = true
        value, ok = r.serialize_string(value, buffer_size)
        return conf_text_val(conf_hex_bytes(value)), ok
    if op == "fixed":
        let ib = conf_parse_int(toks[1])
        let fb = conf_parse_int(toks[2])
        let mn = conf_parse_i64(toks[3])
        let mx = conf_parse_i64(toks[4])
        let storage = ib + fb
        if storage <= 32:
            var v = 0x0BADF00D
            var ok = true
            v, ok = r.serialize_fixed32(v, ib, fb, mn, mx)
            return conf_int_val(v), ok
        elif storage <= 64:
            var v = 0x0BADF00D
            var ok = true
            v, ok = r.serialize_fixed64(v, ib, fb, mn, mx)
            return conf_int_val(v), ok
        var v128 = serialize_int128_make(0x0BADF00D, 0x12345678)
        var ok128 = true
        v128, ok128 = r.serialize_fixed128(v128, ib, fb, mn, mx)
        return conf_i128_val(v128), ok128
    // A step this runner has no code for: red, never a refusal or a skip.
    let unknown = conf_text_val("")
    unknown.kind = -1
    return unknown, false

def conf_step_write(w, step:string, v:cval) -> bool:
    let toks = tokenize(step, " ", "")
    if length(toks) == 0:
        return false
    let op = toks[0]
    if op == "object":
        return true
    if op == "align":
        return w.serialize_align()
    if op == "end":
        return w.serialize_end()
    if op == "bool":
        var b = v.i != 0
        var ok = true
        b, ok = w.serialize_bool(b)
        return ok
    if op == "bits":
        let width = conf_parse_int(toks[1])
        if width <= 32:
            var x = v.i
            var ok = true
            x, ok = w.serialize_bits(x, width)
            return ok
        var x64 = v.i
        var ok64 = true
        x64, ok64 = w.serialize_bits64(x64, width)
        return ok64
    if op == "uint128":
        var u = serialize_uint128_make(v.hi, v.lo)
        var ok = true
        u, ok = w.serialize_uint128(u)
        return ok
    if op == "int" or op == "int64":
        let mn = conf_parse_i64(toks[1])
        let mx = conf_parse_i64(toks[2])
        var x = v.i
        var ok = true
        if op == "int":
            x, ok = w.serialize_int(x, mn, mx)
        else:
            x, ok = w.serialize_int64(x, mn, mx)
        return ok
    if op == "int128":
        let mn = conf_parse_i128(toks[1])
        let mx = conf_parse_i128(toks[2])
        var x = serialize_int128_make(v.hi, v.lo)
        var ok = true
        x, ok = w.serialize_int128(x, mn, mx)
        return ok
    if op == "int_relative":
        let previous = conf_parse_i64(toks[1])
        var x = v.i
        var ok = true
        x, ok = w.serialize_int_relative(previous, x)
        return ok
    if op == "float":
        var f = serialize_float32_from_bits(v.i)
        var ok = true
        f, ok = w.serialize_float(f)
        return ok
    if op == "double":
        var d = serialize_float64_from_bits(v.i)
        var ok = true
        d, ok = w.serialize_double(d)
        return ok
    if op == "compressed_float":
        let mn = conf_parse_float(toks[1])
        let mx = conf_parse_float(toks[2])
        let res = conf_parse_float(toks[3])
        var f = v.f
        var ok = true
        f, ok = w.serialize_compressed_float(f, mn, mx, res)
        return ok
    if op == "bytes":
        let count = conf_parse_int(toks[1])
        let data = conf_string_from_bytes(conf_bytes(v.text))
        var out = data
        var ok = true
        out, ok = w.serialize_bytes(out, count)
        return ok
    if op == "string":
        let buffer_size = conf_parse_int(toks[1])
        let data = conf_string_from_bytes(conf_bytes(v.text))
        var out = data
        var ok = true
        out, ok = w.serialize_string(out, buffer_size)
        return ok
    if op == "fixed":
        let ib = conf_parse_int(toks[1])
        let fb = conf_parse_int(toks[2])
        let mn = conf_parse_i64(toks[3])
        let mx = conf_parse_i64(toks[4])
        let storage = ib + fb
        if storage <= 32:
            var x = v.i
            var ok = true
            x, ok = w.serialize_fixed32(x, ib, fb, mn, mx)
            return ok
        elif storage <= 64:
            var x = v.i
            var ok = true
            x, ok = w.serialize_fixed64(x, ib, fb, mn, mx)
            return ok
        var x128 = serialize_int128_make(v.hi, v.lo)
        var ok128 = true
        x128, ok128 = w.serialize_fixed128(x128, ib, fb, mn, mx)
        return ok128
    return false

def conf_single_steps(rec:conf_rec) -> [string]:
    let steps:[string] = []
    if rec.has_preceding and conf_parse_int(rec.preceding_text) > 0:
        steps.push("bits " + rec.preceding_text)
    if rec.op == "align":
        steps.push("align")
    elif rec.op == "end":
        steps.push("end")
    elif rec.op == "bytes":
        steps.push("bytes " + rec.count_text)
    elif rec.op == "bits":
        steps.push("bits " + rec.bits_text)
    elif rec.op == "bool":
        steps.push("bool")
    elif rec.op == "uint128":
        steps.push("uint128")
    elif rec.op == "int" or rec.op == "int64" or rec.op == "int128":
        steps.push(rec.op + " " + rec.min_text + " " + rec.max_text)
    elif rec.op == "int_relative":
        steps.push("int_relative " + rec.previous_text)
    elif rec.op == "float" or rec.op == "double":
        steps.push(rec.op)
    elif rec.op == "compressed_float":
        steps.push("compressed_float " + rec.min_text + " " + rec.max_text + " " + rec.res_text)
    elif rec.op == "string":
        steps.push(rec.op + " " + rec.buffer_text)
    elif rec.op == "fixed":
        steps.push("fixed " + rec.integer_text + " " + rec.fraction_text + " " + rec.min_text + " " + rec.max_text)
    return steps

def conf_steps(rec:conf_rec) -> [string]:
    if rec.op == "sequence":
        return rec.steps
    return conf_single_steps(rec)

// The compare spelling for one step's expected token (STANDARD.md, "Values are
// typed by the operation's table").
def conf_expect_token(step:string, token:string) -> string:
    let toks = tokenize(step, " ", "")
    if length(toks) == 0:
        return token
    if toks[0] == "uint128":
        if length(token) >= 2 and (substring(token, 0, 2) == "0x" or substring(token, 0, 2) == "0X"):
            return conf_u128_decimal(conf_parse_u128(token))
    return token

def conf_step_value_ok(step:string, got:cval, token:string) -> bool:
    let want = conf_expect_token(step, token)
    if got.text == want:
        return true
    // 64-bit numeric spellings: a bit pattern may be written unsigned.
    let toks = tokenize(step, " ", "")
    if length(toks) > 0:
        let op = toks[0]
        if op == "bits" or op == "int" or op == "int64" or op == "int_relative":
            return got.i == conf_parse_i64(token)
        if op == "float" or op == "double" or op == "compressed_float":
            return got.i == conf_parse_i64(token)
        if op == "int128" or op == "fixed":
            return got.text == conf_i128_text(conf_parse_i128(want))
    return false

def conf_val_equal(a:cval, b:cval) -> bool:
    return a.kind == b.kind and a.text == b.text and a.i == b.i and a.lo == b.lo and a.hi == b.hi

def conf_sentinel(step:string) -> cval:
    let toks = tokenize(step, " ", "")
    if length(toks) == 0:
        return conf_text_val("")
    let op = toks[0]
    if op == "align" or op == "end":
        return conf_text_val("-")
    if op == "bool":
        let v = conf_int_val(1)
        v.text = "true"
        return v
    if op == "bits":
        return conf_int_val(0x12345678)
    if op == "uint128":
        return conf_u128_val(serialize_uint128_make(0xCAFEF00D, 0xF00DCAFE))
    if op == "int_relative":
        return conf_int_val(conf_parse_i64(toks[1]))
    if op == "int" or op == "int64":
        return conf_int_val(0x0BADF00D)
    if op == "int128":
        return conf_i128_val(serialize_int128_make(0x0BADF00D, 0x12345678))
    if op == "double":
        let d = serialize_float64_from_bits(serialize_float64_bits(123.5))
        return conf_float_val(d, serialize_float64_bits(d), 16)
    if op == "float" or op == "compressed_float":
        let f = serialize_float32_from_bits(serialize_float32_bits(123.5))
        return conf_float_val(f, serialize_float32_bits(f), 8)
    if op == "bytes" or op == "string":
        return conf_text_val(conf_hex_bytes("SENTINEL"))
    if op == "fixed":
        let storage = conf_parse_int(toks[1]) + conf_parse_int(toks[2])
        if storage <= 32 or storage <= 64:
            return conf_int_val(0x0BADF00D)
        return conf_i128_val(serialize_int128_make(0x0BADF00D, 0x12345678))
    return conf_int_val(0)

// The stream with eight bytes of NON-ZERO slack behind it (STANDARD.md, "A
// harness presents every stream with the slack its implementation's buffer
// contract requires, filled with a non-zero pattern").
def conf_read_stream(bytes:[int]) -> serialize_read_stream:
    let n = length(bytes)
    let data = ensure_size("", n + 8, 0)
    for(bytes) b, i:
        write_int8_le(data, i, b)
    for(8) i:
        write_int8_le(data, n + i, 0xA5)
    return serialize_read_stream(data, n)

// The writer_input leg (STANDARD.md, "What a runner checks"): a
// compressed_float writer handed the record's float32 pattern must emit the
// record's bytes exactly. It runs on refused vectors too: what a reader does
// with the bytes does not change what a writer owes for the input.
def conf_run_writer_input(rec:conf_rec, steps:[string], what:string) -> bool:
    let last = length(steps) - 1
    let toks = tokenize(steps[last], " ", "")
    if not conf_check(length(toks) > 0 and toks[0] == "compressed_float", what + ": writer_input on a step that is not compressed_float"):
        return false
    let w = serialize_write_stream(ensure_size("", 8192, 0))
    for(steps) step, i:
        var v = conf_int_val(0)
        if i == last:
            v = conf_float_val(serialize_float32_from_bits(rec.writer_input), rec.writer_input, 8)
        if not conf_step_write(w, step, v):
            return conf_check(false, what + ": writer_input write refused at step " + string(i))
    w.flush()
    if w.bytes_processed() != length(rec.bytes):
        return conf_check(false, what + ": writer_input byte count " + string(w.bytes_processed()) + " != " + string(length(rec.bytes)))
    for(rec.bytes) b, i:
        if read_uint8_le(w.buffer, i) != b:
            return conf_check(false, what + ": writer_input byte " + string(i) + " is " + conf_hex(read_uint8_le(w.buffer, i), 2) + ", the corpus states " + conf_hex(b, 2))
    return true

def conf_run_record(rec:conf_rec, what:string) -> bool:
    if rec.malformed != "":
        return conf_check(false, what + ": malformed vector: " + rec.malformed)
    let steps = conf_steps(rec)
    if length(steps) == 0:
        return conf_check(false, what + ": unknown operation " + rec.op)
    if rec.has_writer_input and not conf_run_writer_input(rec, steps, what):
        return false
    let r = conf_read_stream(rec.bytes)
    let vals:[cval] = []
    var failed_at = -1
    for(steps) step, i:
        let before = r.bits_processed()
        let v, ok = conf_step_read(r, step)
        if v.kind == -1:
            return conf_check(false, what + ": unknown step " + step)
        if failed_at >= 0:
            if ok:
                return conf_check(false, what + ": step " + string(i) + " did not fail after a refusal")
            if r.bits_processed() != before:
                return conf_check(false, what + ": step " + string(i) + " consumed bits after a refusal")
        if not ok and failed_at < 0:
            failed_at = i
        vals.push(v)

    if rec.refused:
        if failed_at < 0:
            return conf_check(false, what + ": expected refusal, read accepted")
        if not r.error():
            return conf_check(false, what + ": refusal did not latch")
        // The FIRST refusal's reason must be the one the vector states; a
        // refusal for any other reason is a disagreement about the format
        // (STANDARD.md, Refusal reasons).
        if r.refusal_name() != rec.reason:
            return conf_check(false, what + ": refused as " + r.refusal_name() + ", the vector states " + rec.reason)
        if not conf_val_equal(vals[failed_at], conf_sentinel(steps[failed_at])):
            return conf_check(false, what + ": refusal touched the destination")
        if failed_at == length(steps) - 1:
            let before = r.bits_processed()
            var v = 0x12345678
            var ok = true
            v, ok = r.serialize_bits(v, 1)
            if ok or v != 0x12345678 or r.bits_processed() != before:
                return conf_check(false, what + ": stream not terminal")
            if r.refusal_name() != rec.reason:
                return conf_check(false, what + ": a further read changed the reason to " + r.refusal_name())
        return true

    if failed_at >= 0:
        return conf_check(false, what + ": read refused")
    if r.bits_processed() != rec.consumed:
        return conf_check(false, what + ": read bits " + string(r.bits_processed()) + " != " + string(rec.consumed))

    let tokens = tokenize(rec.expect_text, "|", "")
    if rec.op == "sequence":
        if length(tokens) != length(steps):
            return conf_check(false, what + ": expected " + string(length(tokens)) + " values for " + string(length(steps)) + " steps")
        for(steps) step, i:
            let token = substring(tokens[i], 0, length(tokens[i]))
            let trimmed = conf_trim(token)
            if trimmed != "-" and not conf_step_value_ok(step, vals[i], trimmed):
                return conf_check(false, what + ": step " + string(i) + " value " + vals[i].text + " != " + trimmed)
    else:
        if rec.op == "align" or rec.op == "end":
            // An operation with no value of its own states 0 alone.
            if not conf_check(conf_trim(rec.expect_text) == "0", what + ": " + rec.op + " states value " + rec.expect_text + ", not 0"):
                return false
        else:
            let token = conf_trim(rec.expect_text)
            let last = length(steps) - 1
            if not conf_step_value_ok(steps[last], vals[last], token):
                return conf_check(false, what + ": value " + vals[last].text + " != " + token)

    if rec.canonical:
        let w = serialize_write_stream(ensure_size("", 8192, 0))
        for(steps) step, i:
            if not conf_step_write(w, step, vals[i]):
                return conf_check(false, what + ": canonical write refused at step " + string(i))
        w.flush()
        // A writer's end emits nothing, so a record ending in end consumed the
        // final byte's padding on read: its writer's bits round up to it.
        let written = if steps[length(steps) - 1] == "end": w.bytes_processed() * 8 else: w.bits_processed()
        if written != rec.consumed:
            return conf_check(false, what + ": canonical bits " + string(written) + " != " + string(rec.consumed))
        if w.bytes_processed() != length(rec.bytes):
            return conf_check(false, what + ": canonical byte count " + string(w.bytes_processed()) + " != " + string(length(rec.bytes)))
        for(rec.bytes) b, i:
            if read_uint8_le(w.buffer, i) != b:
                return conf_check(false, what + ": canonical byte " + string(i))

    if rec.measure_at_least >= 0:
        let m = serialize_measure_stream()
        for(steps) step, i:
            if not conf_step_write(m, step, vals[i]):
                return conf_check(false, what + ": measure refused at step " + string(i))
        if m.bits_processed() < rec.measure_at_least:
            return conf_check(false, what + ": measure " + string(m.bits_processed()) + " < floor " + string(rec.measure_at_least))
    return true

def conf_trim(s:string) -> string:
    var a = 0
    var b = length(s)
    while a < b and substring(s, a, 1) == " ":
        a += 1
    while b > a and substring(s, b - 1, 1) == " ":
        b -= 1
    return substring(s, a, b - a)

def conf_run_file(path:string) -> int, [string], int:
    let maybe = read_file(path)
    if maybe == nil:
        return 1, [], 0
    let text = if maybe != nil: maybe else: ""
    let records, _operations = conf_parse_records(text)
    if not conf_soft:
        print "conformance: " + path + " " + string(length(records)) + " records"
    var bad = 0
    let failed:[string] = []
    for(records) rec:
        if not conf_run_record(rec, path + " " + rec.name):
            bad += 1
            failed.push(rec.name)
    return bad, failed, length(records)

def conf_name_in(names:[string], name:string) -> bool:
    for(names) n:
        if n == name:
            return true
    return false

// Every conformance/*.txt, discovered at run time, never a fixed list.
def conf_corpus_files() -> [string]:
    let names, _sizes, _times = scan_folder("conformance", true)
    let files:[string] = []
    if names:
        for(names) n:
            if length(n) >= 4 and substring(n, length(n) - 4, -1) == ".txt":
                files.push("conformance/" + n)
    return files

// Runs the whole corpus softly and returns the names of the vectors that fail.
def conf_corpus_failures(files:[string]) -> [string], int:
    let red:[string] = []
    var total = 0
    conf_soft = true
    for(files) path:
        let _b, failed, count = conf_run_file(path)
        total += count
        for(failed) n:
            red.push(n)
    conf_soft = false
    return red, total

// The names a control's .expected file lists: every line that is neither blank
// nor a # comment.
def conf_expected_names(path:string) -> [string], bool:
    let maybe = read_file(path)
    if maybe == nil:
        return [], false
    let names:[string] = []
    for(tokenize(if maybe != nil: maybe else: "", "\n", "")) line:
        let t = conf_trim(line)
        if length(t) > 0 and substring(t, 0, 1) != "#":
            names.push(t)
    return names, true

// conf_control: the driver tools/controls.sh runs inside a staged copy of
// src/ with ONE refusal rule deleted (STANDARD.md, "A gate nobody has seen go
// red"). The sabotaged reader runs the real corpus, and its failures must be
// EXACTLY conformance-controls/<control>.expected: a sabotage that breaks more
// than its rule, or less, measures something other than what it claims. The
// oracle is the reference's own list, never derived from the sabotage.
def conf_control(control:string):
    let files = conf_corpus_files()
    if not conf_check(length(files) > 0, "control " + control + ": conformance/ has no .txt files"):
        return
    let expected, found = conf_expected_names("conformance-controls/" + control + ".expected")
    if not conf_check(found and length(expected) > 0, "control " + control + ": conformance-controls/" + control + ".expected is missing or empty"):
        return
    let red, total = conf_corpus_failures(files)
    var good = true
    for(expected) name:
        if not conf_name_in(red, name):
            print "control " + control + ": the sabotaged reader did not fail " + name
            good = false
    for(red) name:
        if not conf_name_in(expected, name):
            print "control " + control + ": the sabotaged reader failed " + name + ", which is not in the .expected list"
            good = false
    if not conf_check(good, "control " + control + ": red on " + string(length(red)) + " of " + string(total) + " vectors, expected exactly " + string(length(expected))):
        return
    print "control " + control + ": red on exactly its " + string(length(expected)) + " expected vectors of " + string(total)

def TestConformanceCorpus():
    let files = conf_corpus_files()
    if not conf_check(length(files) > 0, "conformance/ has no .txt files"):
        return
    var bad = 0
    var total = 0
    var refused = 0
    let seen:[string] = []
    for(files) path:
        let maybe = read_file(path)
        let records, _ops = conf_parse_records(if maybe != nil: maybe else: "")
        for(records) rec:
            // Vector names are unique across the corpus (STANDARD.md, the
            // vector format, `name`).
            if not conf_check(not conf_name_in(seen, rec.name), "conformance: vector name " + rec.name + " is not unique"):
                return
            seen.push(rec.name)
            if rec.refused:
                refused += 1
        let b, _failed, count = conf_run_file(path)
        bad += b
        total += count
        if b != 0:
            print "FAIL " + path + " " + string(b) + " bad record(s)"
    print "conformance: " + string(length(files)) + " files, " + string(total) + " records, " + string(total - bad) + " pass, " + string(refused) + " refused for their stated reason"
    if not conf_check(bad == 0, "conformance corpus: " + string(bad) + " record(s) failed"):
        return

    // Control (STANDARD.md, "A runner discovers the directory"): an operation
    // with no runner is a REJECTED corpus, never a skip. The control is the
    // reference's own negative control, conformance-controls/unknown-operation.txt,
    // vendored verbatim beside the corpus and never inside it.
    conf_soft = true
    let ub, ufailed, ucount = conf_run_file("conformance-controls/unknown-operation.txt")
    conf_soft = false
    if not conf_check(ucount == 1, "control: conformance-controls/unknown-operation.txt did not parse to one record"):
        return
    if not conf_check(ub == 1 and length(ufailed) == 1, "control: unknown operation was not rejected"):
        return
    print "control: conformance-controls/unknown-operation.txt rejected as required"
