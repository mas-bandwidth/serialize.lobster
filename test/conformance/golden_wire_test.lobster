// test/conformance/golden_wire_test.lobster — TestGoldenWireFormat
// (STANDARD.md, "Worked Example"; "What a runner checks"). The golden message
// bytes are pasted as literals below, naming their source file and line, read,
// and re-written byte for byte. Every single-bit flip of a consumed bit must
// be refused or decode differently (STANDARD.md, "Conformance vectors must
// discriminate").
import serialize
import .conformance_test

// STEP 4's golden message, conformance/message.txt line 66 (the `bytes` line
// of record `message-golden-whole`), 112 bytes. STANDARD.md's "The whole
// message" prints the same block.
let golden_bytes = [
    0x5D, 0xDA, 0xF7, 0xE6, 0xD5, 0x77, 0xDF, 0x56, 0xEF, 0x9F, 0x75, 0x19,
    0x52, 0xBC, 0xDA, 0x0F, 0x49, 0x40, 0xF4, 0x55, 0x55, 0x55, 0x55, 0x55,
    0x55, 0x55, 0xFF, 0xFC, 0xD1, 0x48, 0xE0, 0x59, 0xD1, 0x48, 0xC0, 0x7B,
    0xF3, 0x6A, 0xE2, 0x59, 0xD1, 0x48, 0x84, 0xB7, 0x06, 0xDE, 0xAD, 0xBE,
    0xEF, 0xCA, 0xFE, 0x01, 0x06, 0x67, 0x6F, 0x6C, 0x64, 0x65, 0x6E, 0xE3,
    0x21, 0x00, 0x00, 0xC0, 0x21, 0x00, 0x00, 0x00, 0x22, 0x00, 0x00, 0x00,
    0xC0, 0x60, 0x00, 0x80, 0xA2, 0x7C, 0xFC, 0xEC, 0x26, 0xCB, 0xFF, 0xFF,
    0x4B, 0x1D, 0x1F, 0xEF, 0xD2, 0x1A, 0x1F, 0x01, 0xE9, 0xFF, 0xFF, 0x09,
    0x19, 0x2A, 0x3B, 0x4C, 0x5D, 0x6E, 0x7F, 0x78, 0x6F, 0x5E, 0x4D, 0x3C,
    0x2B, 0x1A, 0x09, 0x04,
]

def golden_read(data:string, steps:[string]) -> [cval], bool, int:
    let r = serialize_read_stream_padded(data)
    var vals:[cval] = []
    var ok = true
    for(steps) step:
        if not ok:
            vals.push(conf_text_val(""))
            continue
        var v, step_ok = conf_step_read(r, step)
        ok = step_ok
        vals.push(v)
    return vals, ok, r.bits_processed()

def golden_find(text:string, name:string) -> conf_rec:
    let records, ops = conf_parse_records(text)
    for(records) rec:
        if rec.name == name:
            return rec
    return conf_rec {}

def TestGoldenWireFormat():
    let maybe = read_file("conformance/message.txt")
    if not conf_check(maybe != nil, "missing conformance/message.txt"):
        return
    let text = if maybe != nil: maybe else: ""
    let rec = golden_find(text, "message-golden-whole")
    if not conf_check(length(rec.steps) == 28 and rec.consumed == 891, "golden record not found"):
        return
    let data = conf_string_from_bytes(golden_bytes)
    if not conf_check(length(rec.bytes) == length(golden_bytes), "pasted golden byte count differs from message.txt"):
        return
    for(golden_bytes) b, i:
        if not conf_check(rec.bytes[i] == b, "pasted golden byte " + string(i) + " differs from message.txt"):
            return
    let vals, ok, bits = golden_read(data, rec.steps)
    if not conf_check(ok and bits == 891, "golden read refused or consumed " + string(bits)):
        return
    // Re-write byte for byte.
    let w = serialize_write_stream(ensure_size("", 1024, 0))
    var wok = true
    for(rec.steps) step, i:
        if not conf_step_write(w, step, vals[i]):
            wok = false
    w.flush()
    if not conf_check(wok and w.bits_processed() == 891 and w.bytes_processed() == 112, "golden rewrite failed"):
        return
    for(golden_bytes) b, i:
        if not conf_check(read_uint8_le(w.buffer, i) == b, "golden rewrite byte " + string(i)):
            return

    // Every single-bit flip of a consumed bit: refused or decoded differently.
    var flips = 0
    for(891) bit:
        // A fresh copy per flip: a Lobster string is mutable and aliased, so
        // `var flipped = data` would let each flip accumulate on the golden
        // bytes and later flips would no longer be single-bit flips.
        let flipped = conf_string_from_bytes(golden_bytes)
        let byte_index = bit >> 3
        let b = read_uint8_le(flipped, byte_index) ^ (1 << (bit & 7))
        write_int8_le(flipped, byte_index, b)
        let fvals, fok, fbits = golden_read(flipped, rec.steps)
        var differs = not fok
        if fok:
            if fbits != bits:
                differs = true
            for(fvals) v, i:
                if v.text != vals[i].text:
                    differs = true
        if not conf_check(differs, "flipped bit " + string(bit) + " decoded identically"):
            return
        flips += 1
    print "golden: 112 bytes, 891 bits, " + string(flips) + " single-bit flips checked"
