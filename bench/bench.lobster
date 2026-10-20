// bench/bench.lobster -- the Lobster serialize benchmark workload.
//
// One workload set, written and read separately. The row set and the
// bits workload (the 16 widths over a 65536-byte buffer) are from
// .ref/schema/bench/BENCH-STANDARD.md section 1.4. The statistic is the
// median of 15 timed runs after 3 warm-ups, with min and max, as the card
// requires; timed runs happen here only, never under `make test`.
import serialize

let widths = [1, 32, 7, 13, 3, 25, 8, 19, 4, 28, 11, 16, 2, 30, 6, 22]
let scalar_ops = 100000
let mixed_ops = 50000
let bit_buffer = 65536
let fnv_offset = 1469598103934665603
let fnv_prime = 1099511628211

def fnv_byte(h:int, b:int) -> int:
    return ((h ^ b) & 0xFFFFFFFFFFFFFFFF) * fnv_prime

def checksum(buf:string, n:int) -> int:
    var h = fnv_offset
    for(n) i:
        h = fnv_byte(h, buf[i])
    return h

def mix(h:int, v:int) -> int:
    return ((h ^ (v & 0xFFFFFFFFFFFFFFFF)) * fnv_prime) & 0xFFFFFFFFFFFFFFFF

def vbool(i:int) -> bool: return (i % 3) != 0
def vu32(i:int) -> int: return (i * 2654435761) & 0xFFFFFFFF
def vu64(i:int) -> int: return i * 6364136223846793005 + 1442695040888963407
def vint(i:int) -> int: return (i % 2001) - 1000
def vi64(i:int) -> int: return (i % 2000001) - 1000000
def vfloat(i:int) -> float: return serialize_float32_from_bits((i * 2654435761) & 0x3F7FFFFF)
def vdouble(i:int) -> float: return serialize_float64_from_bits(i * 2862933555777941757 + 3037000493)
def vcfloat(i:int) -> float: return -1.0 + float(i % 2001) * 0.001
def vrelative(i:int) -> int: return i * 7
def vbytes(i:int) -> string:
    return "0123456789abcdefghijklmnopqrstuv"
def vstring(i:int) -> string:
    return substring("the quick brown fox jumps!", 0, 24)

def write_row(kind:int, param:int, buf:string) -> int, int:
    let s = serialize_write_stream(buf)
    var ok = true
    var sk = 0
    if kind == 0:
        var v = vbool(param)
        v, ok = s.serialize_bool(v)
    elif kind == 1:
        var v = vu32(param)
        v, ok = s.serialize_uint32(v)
    elif kind == 2:
        var v = vu64(param)
        v, ok = s.serialize_uint64(v)
    elif kind == 3:
        var v = vint(param)
        v, ok = s.serialize_int(v, -1000, 1000)
    elif kind == 4:
        var v = vi64(param)
        v, ok = s.serialize_int64(v, -1000000, 1000000)
    elif kind == 5:
        var v = vfloat(param)
        v, ok = s.serialize_float(v)
    elif kind == 6:
        var v = vdouble(param)
        v, ok = s.serialize_double(v)
    elif kind == 7:
        var v = vcfloat(param)
        v, ok = s.serialize_compressed_float(v, -1.0, 1.0, 0.001)
    elif kind == 8:
        var v = param
        v, ok = s.serialize_int_relative(v, v + 7)
    elif kind == 9:
        var v = vbytes(param)
        v, ok = s.serialize_bytes(v, 32)
    elif kind == 10:
        var v = vstring(param)
        v, ok = s.serialize_string(v, 64)
    if not ok:
        serialize_abort("bench: write failed")
    s.flush()
    return s.bytes_processed(), 0

def read_row(kind:int, param:int, data:string) -> int, int:
    let s = serialize_read_stream_padded(data)
    var h = fnv_offset
    var ok = true
    var v = 0
    if kind == 0:
        var b = false
        b, ok = s.serialize_bool(false)
        v = if b: 1 else: 0
    elif kind == 1:
        v, ok = s.serialize_uint32(0)
    elif kind == 2:
        v, ok = s.serialize_uint64(0)
    elif kind == 3:
        v, ok = s.serialize_int(0, -1000, 1000)
    elif kind == 4:
        v, ok = s.serialize_int64(0, -1000000, 1000000)
    elif kind == 5:
        var f = 0.0
        f, ok = s.serialize_float(0.0)
        v = serialize_float32_bits(f)
    elif kind == 6:
        var f = 0.0
        f, ok = s.serialize_double(0.0)
        v = serialize_float64_bits(f)
    elif kind == 7:
        var f = 0.0
        f, ok = s.serialize_compressed_float(0.0, -1.0, 1.0, 0.001)
        v = serialize_float32_bits(f)
    elif kind == 8:
        var c = 0
        c, ok = s.serialize_int_relative(0, 0)
        v = c
    elif kind == 9:
        var b = ensure_size("", 32, 0)
        b, ok = s.serialize_bytes(b, 32)
        return 32, checksum(b, 32)
    elif kind == 10:
        var t = ""
        t, ok = s.serialize_string("", 64)
        return length(t), checksum(t, length(t))
    if not ok:
        serialize_abort("bench: read failed")
    return s.bytes_processed(), mix(h, v)

def check():
    // One write and one read per row; print row,mode,bytes,checksum. Every
    // leg's bytes and checksums must be IDENTICAL (TestBenchShapesAgree).
    for(16) k:
        let w = widths[k]
        let n = (bit_buffer * 8) / w
        let buf = ensure_size("", bit_buffer, 0)
        let s = serialize_write_stream(buf)
        var ok = false
        for(n) i:
            var v = (i * 2654435761 + w * 97) & serialize_mask(w)
            v, ok = s.serialize_bits(v, w)
        s.flush()
        let bytes = s.bytes_processed()
        print "bits" + w + ",write," + bytes + "," + checksum(buf, bytes)
        let r = serialize_read_stream_padded(substring(buf, 0, bytes))
        var h = fnv_offset
        for(n) i:
            var v = 0
            v, ok = r.serialize_bits(0, w)
            h = mix(h, v)
        print "bits" + w + ",read," + bytes + "," + h
    for(11) k:
        let name = ["bool", "uint32", "uint64", "int", "int64", "float", "double", "compressed_float", "int_relative", "bytes32", "string24"][k]
        let cap = if k == 11: 512 else: 256
        let buf = ensure_size("", cap, 0)
        let bytes, _ = write_row(k, 12345, buf)
        print name + ",write," + bytes + "," + checksum(buf, bytes)
        let rb, v = read_row(k, 12345, substring(buf, 0, bytes))
        print name + ",read," + bytes + "," + v

def bench():
    for(16) k:
        let w = widths[k]
        let n = (bit_buffer * 8) / w
        var mn = 1000000000000.0
        var mx = 0.0
        var med = 0.0
        for(18) run:
            let buf = ensure_size("", bit_buffer, 0)
            let t0 = gl.time()
            let s = serialize_write_stream(buf)
            var ok = false
            for(n) i:
                var v = (i * 2654435761 + w * 97) & serialize_mask(w)
                v, ok = s.serialize_bits(v, w)
            s.flush()
            let t1 = gl.time()
            let dt = t1 - t0
            if run >= 3:
                mn = min(mn, dt)
                mx = max(mx, dt)
                med += dt
        let ns = med / 15.0 * 1000000000.0 / float(n)
        print "lobster,bits" + w + ",write," + ns + "," + (mn * 1000000000.0 / float(n)) + "," + (mx * 1000000000.0 / float(n))

def main():
    check()


main()
