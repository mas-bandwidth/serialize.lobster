// fuzz/fuzz_driver.lobster -- the Lobster half of TestDifferentialAgainstSerializeC.
//
// Reads one batch written by fuzz/host.c, replays every program on the port's
// write stream, then reads the C writer's bytes and, where present, the mutant
// bytes. Prints one W line per program (the port's bytes) and R/V lines with
// the accept/refuse verdict, the refusing step, the refusal reason ("none" on
// an accepted read) and every value decoded before it. The host compares
// these against serialize.c's own results.

import serialize

let fz_bufcap = 1024

def fz_hex(v:int, digits:int) -> string:
    let chars = "0123456789abcdef"
    var out = ""
    var i = digits - 1
    while i >= 0:
        let nib = serialize_shr(v, i * 4) & 15
        out += substring(chars, nib, 1)
        i -= 1
    return out

def fz_parse_hex(text:string) -> int:
    var v = 0
    for(length(text)) i:
        let d, ok = string_to_int(substring(text, i, 1), 16)
        if not ok:
            print "fuzz driver: bad hex " + text
            assert false
        v = v * 16 + d
    return v

def fz_parse_dec(text:string) -> int:
    let v, ok = string_to_int(text, 10)
    if not ok:
        print "fuzz driver: bad integer " + text
        assert false
    return v

def fz_hex_bytes(data:string) -> string:
    if length(data) == 0:
        return "-"
    var out = ""
    for(length(data)) i:
        out += fz_hex(read_uint8_le(data, i), 2)
    return out

def fz_hex_buf(data:string, n:int) -> string:
    if n == 0:
        return "-"
    var out = ""
    for(n) i:
        out += fz_hex(read_uint8_le(data, i), 2)
    return out

def fz_hex_string(text:string) -> string:
    if text == "-":
        return ""
    var out = ""
    for(length(text) / 2) i:
        out += fz_hex(fz_parse_hex(substring(text, i * 2, 2)), 2)
    return out

def fz_hex_to_bytes(text:string) -> string:
    if text == "-":
        return ""
    let n = length(text) / 2
    let out = ensure_size(string_with_capacity(n), n, 0)
    for(n) i:
        write_int8_le(out, i, fz_parse_hex(substring(text, i * 2, 2)))
    return out

def fz_join(items:[string]) -> string:
    var out = ""
    for(items) item, i:
        if i > 0:
            out += " "
        out += item
    return out

def fz_hex128(hi:int, lo:int) -> string:
    return fz_hex(hi, 16) + fz_hex(lo, 16)

// ---------------------------------------------------------------------------
// object: the caller's own serialize (STANDARD.md, object; DESIGN.md (a))
// ---------------------------------------------------------------------------

class fz_object : serialize_object_base
    b:bool = false
    i:int = 0
    u:int = 0

def serialize(o::fz_object, s) -> bool:
    o.b = s.serialize_bool(o.b)
    o.i = s.serialize_int(o.i, 0, 7)
    o.u = s.serialize_uint16(o.u)
    return s.ok()

// ---------------------------------------------------------------------------
// write and measure
// ---------------------------------------------------------------------------

def fz_write(s, line:string) -> bool:
    let t = tokenize(line, " ", "")
    let kind = t[0]
    var ok = true
    if kind == "bits":
        var v = fz_parse_dec(t[2])
        v, ok = s.serialize_bits(v, fz_parse_dec(t[1]))
    elif kind == "bits64":
        var v = fz_parse_hex(t[2])
        v, ok = s.serialize_bits64(v, fz_parse_dec(t[1]))
    elif kind == "bool":
        var v = fz_parse_dec(t[1]) != 0
        v, ok = s.serialize_bool(v)
    elif kind == "uint8":
        var v = fz_parse_dec(t[1])
        v, ok = s.serialize_uint8(v)
    elif kind == "uint16":
        var v = fz_parse_dec(t[1])
        v, ok = s.serialize_uint16(v)
    elif kind == "uint32":
        var v = fz_parse_dec(t[1])
        v, ok = s.serialize_uint32(v)
    elif kind == "uint64":
        var v = fz_parse_hex(t[1])
        v, ok = s.serialize_uint64(v)
    elif kind == "int":
        var v = fz_parse_dec(t[3])
        v, ok = s.serialize_int(v, fz_parse_dec(t[1]), fz_parse_dec(t[2]))
    elif kind == "int64":
        var v = fz_parse_dec(t[3])
        v, ok = s.serialize_int64(v, fz_parse_dec(t[1]), fz_parse_dec(t[2]))
    elif kind == "int_rel":
        let cur = fz_parse_dec(t[2])
        let _got, o2 = s.serialize_int_relative(fz_parse_dec(t[1]), cur)
        ok = o2
    elif kind == "uint128":
        let v = serialize_uint128_make(fz_parse_hex(t[2]), fz_parse_hex(t[1]))
        let _got, o2 = s.serialize_uint128(v)
        ok = o2
    elif kind == "int128":
        let v = serialize_int128_make(fz_parse_hex(t[6]), fz_parse_hex(t[5]))
        let mn = serialize_int128_make(fz_parse_hex(t[2]), fz_parse_hex(t[1]))
        let mx = serialize_int128_make(fz_parse_hex(t[4]), fz_parse_hex(t[3]))
        let _got, o2 = s.serialize_int128(v, mn, mx)
        ok = o2
    elif kind == "float":
        var v = serialize_float32_from_bits(fz_parse_hex(t[1]))
        v, ok = s.serialize_float(v)
    elif kind == "double":
        var v = serialize_float64_from_bits(fz_parse_hex(t[1]))
        v, ok = s.serialize_double(v)
    elif kind == "fixed32":
        var v = fz_parse_dec(t[5])
        v, ok = s.serialize_fixed32(v, fz_parse_dec(t[1]), fz_parse_dec(t[2]), fz_parse_dec(t[3]), fz_parse_dec(t[4]))
    elif kind == "fixed64":
        var v = fz_parse_dec(t[5])
        v, ok = s.serialize_fixed64(v, fz_parse_dec(t[1]), fz_parse_dec(t[2]), fz_parse_dec(t[3]), fz_parse_dec(t[4]))
    elif kind == "fixed128":
        let v = serialize_int128_make(fz_parse_hex(t[6]), fz_parse_hex(t[5]))
        let _got, o2 = s.serialize_fixed128(v, fz_parse_dec(t[1]), fz_parse_dec(t[2]), fz_parse_dec(t[3]), fz_parse_dec(t[4]))
        ok = o2
    elif kind == "cfloat":
        var v = serialize_float32_from_bits(fz_parse_hex(t[4]))
        v, ok = s.serialize_compressed_float(v,
            serialize_float32_from_bits(fz_parse_hex(t[1])),
            serialize_float32_from_bits(fz_parse_hex(t[2])),
            serialize_float32_from_bits(fz_parse_hex(t[3])))
    elif kind == "cfloat_pre":
        var v = serialize_float32_from_bits(fz_parse_hex(t[5]))
        v, ok = s.serialize_compressed_float_precomputed(v,
            fz_parse_dec(t[1]), fz_parse_dec(t[2]),
            serialize_float32_from_bits(fz_parse_hex(t[3])),
            serialize_float32_from_bits(fz_parse_hex(t[4])))
    elif kind == "bytes":
        let n = fz_parse_dec(t[1])
        var d = fz_hex_to_bytes(t[2])
        d, ok = s.serialize_bytes(d, n)
    elif kind == "string":
        var d = fz_hex_to_bytes(t[2])
        d, ok = s.serialize_string(d, fz_parse_dec(t[1]))
    elif kind == "align":
        ok = s.serialize_align()
    elif kind == "end":
        ok = s.serialize_end()
    elif kind == "object":
        let o = fz_object { b: true, i: 3, u: 42 }
        ok = s.serialize_object(o)
    else:
        print "fuzz driver: unknown op " + kind
        assert false
    return ok

def fz_run_write(ops:[string]) -> string, bool, int, int, int:
    let w = serialize_write_stream(ensure_size(string_with_capacity(fz_bufcap), fz_bufcap, 0))
    let m = serialize_measure_stream()
    var ok = true
    for(ops) line:
        if not ok:
            break
        let wok = fz_write(w, line)
        let mok = fz_write(m, line)
        ok = wok and mok
    w.flush()
    return fz_hex_buf(w.buffer, w.bytes_processed()), ok and w.ok() and m.ok(), w.bits_processed(), m.bits_processed(), m.bytes_processed()

// ---------------------------------------------------------------------------
// read
// ---------------------------------------------------------------------------

def fz_read(s:serialize_read_stream, line:string) -> bool, [string]:
    let t = tokenize(line, " ", "")
    let kind = t[0]
    var ok = true
    let toks:[string] = []
    if kind == "bits":
        var v = 0
        v, ok = s.serialize_bits(v, fz_parse_dec(t[1]))
        if ok:
            toks.push(fz_hex(v, 16))
    elif kind == "bits64":
        var v = 0
        v, ok = s.serialize_bits64(v, fz_parse_dec(t[1]))
        if ok:
            toks.push(fz_hex(v, 16))
    elif kind == "bool":
        var v = false
        v, ok = s.serialize_bool(v)
        if ok:
            toks.push(if v: "1" else: "0")
    elif kind == "uint8":
        var v = 0
        v, ok = s.serialize_uint8(v)
        if ok:
            toks.push(fz_hex(v, 16))
    elif kind == "uint16":
        var v = 0
        v, ok = s.serialize_uint16(v)
        if ok:
            toks.push(fz_hex(v, 16))
    elif kind == "uint32":
        var v = 0
        v, ok = s.serialize_uint32(v)
        if ok:
            toks.push(fz_hex(v, 16))
    elif kind == "uint64":
        var v = 0
        v, ok = s.serialize_uint64(v)
        if ok:
            toks.push(fz_hex(v, 16))
    elif kind == "int":
        var v = 0
        v, ok = s.serialize_int(v, fz_parse_dec(t[1]), fz_parse_dec(t[2]))
        if ok:
            toks.push(fz_hex(v, 16))
    elif kind == "int64":
        var v = 0
        v, ok = s.serialize_int64(v, fz_parse_dec(t[1]), fz_parse_dec(t[2]))
        if ok:
            toks.push(fz_hex(v, 16))
    elif kind == "int_rel":
        var v = 0
        v, ok = s.serialize_int_relative(fz_parse_dec(t[1]), v)
        if ok:
            toks.push(fz_hex(v, 16))
    elif kind == "uint128":
        var v = serialize_uint128_make(0, 0)
        v, ok = s.serialize_uint128(v)
        if ok:
            toks.push(fz_hex128(v.hi, v.lo))
    elif kind == "int128":
        var v = serialize_int128_make(0, 0)
        let mn = serialize_int128_make(fz_parse_hex(t[2]), fz_parse_hex(t[1]))
        let mx = serialize_int128_make(fz_parse_hex(t[4]), fz_parse_hex(t[3]))
        v, ok = s.serialize_int128(v, mn, mx)
        if ok:
            toks.push(fz_hex128(v.hi, v.lo))
    elif kind == "float":
        var v = 0.0
        v, ok = s.serialize_float(v)
        if ok:
            toks.push(fz_hex(serialize_float32_bits(v), 8))
    elif kind == "double":
        var v = 0.0
        v, ok = s.serialize_double(v)
        if ok:
            toks.push(fz_hex(serialize_float64_bits(v), 16))
    elif kind == "fixed32":
        var v = 0
        v, ok = s.serialize_fixed32(v, fz_parse_dec(t[1]), fz_parse_dec(t[2]), fz_parse_dec(t[3]), fz_parse_dec(t[4]))
        if ok:
            toks.push(fz_hex(v, 16))
    elif kind == "fixed64":
        var v = 0
        v, ok = s.serialize_fixed64(v, fz_parse_dec(t[1]), fz_parse_dec(t[2]), fz_parse_dec(t[3]), fz_parse_dec(t[4]))
        if ok:
            toks.push(fz_hex(v, 16))
    elif kind == "fixed128":
        var v = serialize_int128_make(0, 0)
        v, ok = s.serialize_fixed128(v, fz_parse_dec(t[1]), fz_parse_dec(t[2]), fz_parse_dec(t[3]), fz_parse_dec(t[4]))
        if ok:
            toks.push(fz_hex128(v.hi, v.lo))
    elif kind == "cfloat":
        var v = 0.0
        v, ok = s.serialize_compressed_float(v,
            serialize_float32_from_bits(fz_parse_hex(t[1])),
            serialize_float32_from_bits(fz_parse_hex(t[2])),
            serialize_float32_from_bits(fz_parse_hex(t[3])))
        if ok:
            toks.push(fz_hex(serialize_float32_bits(v), 8))
    elif kind == "cfloat_pre":
        var v = 0.0
        v, ok = s.serialize_compressed_float_precomputed(v,
            fz_parse_dec(t[1]), fz_parse_dec(t[2]),
            serialize_float32_from_bits(fz_parse_hex(t[3])),
            serialize_float32_from_bits(fz_parse_hex(t[4])))
        if ok:
            toks.push(fz_hex(serialize_float32_bits(v), 8))
    elif kind == "bytes":
        let n = fz_parse_dec(t[1])
        var d = ensure_size("", n, 0)
        d, ok = s.serialize_bytes(d, n)
        if ok:
            toks.push(fz_hex_bytes(d))
    elif kind == "string":
        var v = ""
        v, ok = s.serialize_string(v, fz_parse_dec(t[1]))
        if ok:
            toks.push(fz_hex_bytes(v))
    elif kind == "align":
        ok = s.serialize_align()
    elif kind == "end":
        ok = s.serialize_end()
    elif kind == "object":
        let o = fz_object {}
        ok = s.serialize_object(o)
        if ok:
            toks.push(if o.b: "1" else: "0")
            toks.push(fz_hex(o.i, 16))
            toks.push(fz_hex(o.u, 16))
    else:
        print "fuzz driver: unknown op " + kind
        assert false
    return ok, toks

def fz_check_terminal(r:serialize_read_stream, reason:string) -> bool:
    let b0 = r.bits_processed()
    if not r.failed or r.refusal_name() != reason:
        return false
    var v32 = 0x13572468
    var ok32 = false
    v32, ok32 = r.serialize_fixed32(v32, 16, 16, -5, -5)
    if ok32 or v32 != 0x13572468 or not r.failed or r.refusal_name() != reason or r.bits_processed() != b0:
        return false
    var v64 = 0x1357246824681357
    var ok64 = false
    v64, ok64 = r.serialize_fixed64(v64, 32, 32, -10, 10)
    if ok64 or v64 != 0x1357246824681357 or not r.failed or r.refusal_name() != reason or r.bits_processed() != b0:
        return false
    var v128 = serialize_int128_make(0x5555666677778888, 0x1111222233334444)
    var ok128 = false
    v128, ok128 = r.serialize_fixed128(v128, 64, 64, -10, 10)
    if ok128 or v128.lo != 0x1111222233334444 or v128.hi != 0x5555666677778888 or not r.failed or r.refusal_name() != reason or r.bits_processed() != b0:
        return false
    return true

def fz_run_read(bytes:string, ops:[string], id:int, src:string) -> string:
    let r = serialize_read_stream_padded(bytes)
    var acc = true
    var step = length(ops)
    var consumed = 0
    var term = true
    var body = ""
    for(ops) line, i:
        let ok, toks = fz_read(r, line)
        if not ok:
            acc = false
            step = i
            term = fz_check_terminal(r, r.refusal_name())
            break
        consumed = r.bits_processed()
        if length(toks) > 0:
            body += "V " + string(id) + " " + src + " " + string(i) + " " + fz_join(toks) + "\n"
    let accint = if acc: "1" else: "0"
    let termint = if term: "1" else: "0"
    return "R " + string(id) + " " + src + " " + accint + " " + string(step) + " " + r.refusal_name() + " " + string(consumed) + " " + termint + "\n" + body

def fz_main():
    let args = command_line_arguments()
    if length(args) < 2:
        print "fuzz driver: usage <batch> <output>"
        set_exit_code(2)
        return
    let maybe = read_file(args[0], false)
    if maybe == nil:
        print "fuzz driver: cannot read " + args[0]
        set_exit_code(2)
        return
    let lines = tokenize(if maybe != nil: maybe else: "", "\n", "")
    var out = ""
    var i = 0
    while i < length(lines):
        let line = lines[i]
        if length(line) == 0:
            i += 1
            continue
        if substring(line, 0, 1) != "P":
            print "fuzz driver: expected P line: " + line
            set_exit_code(2)
            return
        let t = tokenize(line, " ", "")
        let id = fz_parse_dec(t[1])
        let nops = fz_parse_dec(t[2])
        let has_mutant = fz_parse_dec(t[3]) != 0
        let cbytes = fz_hex_to_bytes(t[4])
        let mbytes = fz_hex_to_bytes(t[5])
        let ops:[string] = []
        for(nops) k:
            ops.push(lines[i + 1 + k])
        i += 1 + nops

        let wbytes, wok, wbits, mbits, mbytes_cnt = fz_run_write(ops)
        out += "W " + string(id) + " " + wbytes + " " + (if wok: "1" else: "0") + " " + string(wbits) + " " + string(mbits) + " " + string(mbytes_cnt) + "\n"
        out += fz_run_read(cbytes, ops, id, "c")
        if has_mutant:
            out += fz_run_read(mbytes, ops, id, "m")

    if not write_file(args[1], out, false, true):
        print "fuzz driver: cannot write " + args[1]
        set_exit_code(2)

fz_main()
