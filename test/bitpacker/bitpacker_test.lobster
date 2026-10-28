// test/bitpacker/bitpacker_test.lobster — TestBitpacker (STANDARD.md, General
// Conventions, Bit-Level Primitives, Reader Obligations; DESIGN.md (a), (b), (c), (d), (e)).
import serialize

def bitpacker_patterned_value(w:int, o:int) -> int:
    let base = 0xD6E8FEB86659FD93 ^ (o * 0x9E3779B97F4A7C15) ^ w
    let v = base & serialize_mask(w)
    let top_bit = serialize_shl(1, w - 1)
    return (v | 1) | top_bit

def bitpacker_oracle_set_bit(buf:string, bit_index:int, bit_val:int):
    if (bit_val & 1) != 0:
        let byte_idx = bit_index >> 3
        let shift = bit_index & 7
        let cur = read_uint8_le(buf, byte_idx)
        write_int8_le(buf, byte_idx, cur | (1 << shift))

def test_golden_sequence():
    let buf = ensure_size("", 256, 0)
    let w = serialize_write_stream(buf)
    assert w.bits_processed() == 0
    assert w.bytes_processed() == 0
    assert w.bits_available() == 256 * 8

    var v = 0
    var ok = false
    v, ok = w.serialize_bits(0, 1)
    assert ok
    v, ok = w.serialize_bits(1, 1)
    assert ok
    v, ok = w.serialize_bits(10, 8)
    assert ok
    v, ok = w.serialize_bits(255, 8)
    assert ok
    v, ok = w.serialize_bits(1000, 10)
    assert ok
    v, ok = w.serialize_bits(50000, 16)
    assert ok
    v, ok = w.serialize_bits(9999999, 32)
    assert ok
    w.flush()

    let expected_bits = 1 + 1 + 8 + 8 + 10 + 16 + 32
    assert w.bits_processed() == expected_bits
    assert w.bytes_processed() == 10
    assert w.bits_available() == 256 * 8 - expected_bits

    let golden = [0x2A, 0xFC, 0xA3, 0x0F, 0x35, 0xFC, 0x67, 0x89, 0x09, 0x00]
    for(10) i:
        assert read_uint8_le(buf, i) == golden[i]

    let r = serialize_read_stream(buf, 10)
    assert r.bits_processed() == 0
    assert r.bits_remaining() == 80

    var a = 99
    var b = 99
    var c = 99
    var d = 99
    var e = 99
    var f = 99
    var g = 99
    a, ok = r.serialize_bits(a, 1)
    assert ok and a == 0
    b, ok = r.serialize_bits(b, 1)
    assert ok and b == 1
    c, ok = r.serialize_bits(c, 8)
    assert ok and c == 10
    d, ok = r.serialize_bits(d, 8)
    assert ok and d == 255
    e, ok = r.serialize_bits(e, 10)
    assert ok and e == 1000
    f, ok = r.serialize_bits(f, 16)
    assert ok and f == 50000
    g, ok = r.serialize_bits(g, 32)
    assert ok and g == 9999999
    assert r.bits_processed() == expected_bits
    assert r.bytes_processed() == 10
    assert r.bits_remaining() == 4

    var tail = 99
    tail, ok = r.serialize_bits(tail, 4)
    assert ok and tail == 0
    assert r.bits_remaining() == 0
    var past = 77
    past, ok = r.serialize_bits(past, 1)
    assert not ok and past == 77
    assert r.error()

def test_oracle_and_round_trip():
    for(64) o:
        for(64) w_idx:
            let w = w_idx + 1
            let buf = ensure_size("", 32, 0)
            let oracle = ensure_size("", 32, 0)
            let ws = serialize_write_stream(buf)

            var bit_pos = 0
            var dummy = 0
            var ok = false
            for(o) k:
                let bit = k & 1
                dummy, ok = ws.serialize_bits(bit, 1)
                assert ok
                bitpacker_oracle_set_bit(oracle, bit_pos, bit)
                bit_pos += 1

            let val = bitpacker_patterned_value(w, o)
            if w <= 32:
                dummy, ok = ws.serialize_bits(val, w)
                assert ok
            else:
                dummy, ok = ws.serialize_bits64(val, w)
                assert ok
            for(w) b:
                bitpacker_oracle_set_bit(oracle, bit_pos, serialize_shr(val, b) & 1)
                bit_pos += 1

            dummy, ok = ws.serialize_bits(5, 3)
            assert ok
            bitpacker_oracle_set_bit(oracle, bit_pos, 1)
            bitpacker_oracle_set_bit(oracle, bit_pos + 1, 0)
            bitpacker_oracle_set_bit(oracle, bit_pos + 2, 1)
            bit_pos += 3

            ws.flush()
            let nbytes = ws.bytes_processed()
            assert nbytes == (bit_pos + 7) >> 3
            for(nbytes) i:
                assert read_uint8_le(buf, i) == read_uint8_le(oracle, i)

            // Poison slack bytes past nbytes with 0xFF to prove the reader never
            // interprets slack bytes (STANDARD.md, Reader Obligations).
            let poisoned = ensure_size("", 32, 0xFF)
            for(nbytes) i:
                write_int8_le(poisoned, i, read_uint8_le(buf, i))

            let rs = serialize_read_stream(poisoned, nbytes)
            for(o) k:
                var bit = 9
                bit, ok = rs.serialize_bits(bit, 1)
                assert ok and bit == (k & 1)
            var got = 0
            if w <= 32:
                got, ok = rs.serialize_bits(got, w)
            else:
                got, ok = rs.serialize_bits64(got, w)
            assert ok and got == val
            var post = 0
            post, ok = rs.serialize_bits(post, 3)
            assert ok and post == 5
            assert rs.bits_processed() == bit_pos

            // Also verify via serialize_read_stream_padded.
            let exact = substring(buf, 0, nbytes)
            let rp = serialize_read_stream_padded(exact)
            for(o) k:
                var bit = 9
                bit, ok = rp.serialize_bits(bit, 1)
                assert ok and bit == (k & 1)
            var got_p = 0
            got_p, ok = rp.serialize_bits64(got_p, w)
            assert ok and got_p == val
            var post_p = 0
            post_p, ok = rp.serialize_bits(post_p, 3)
            assert ok and post_p == 5

def test_fixed_width_and_align():
    for(8) shift:
        let buf = ensure_size("", 32, 0)
        let w = serialize_write_stream(buf)
        let m = serialize_measure_stream()
        var b = false
        var v = 0
        var ok = false
        for(shift) i:
            b, ok = w.serialize_bool((i & 1) == 0)
            assert ok
            b, ok = m.serialize_bool((i & 1) == 0)
            assert ok
        v, ok = w.serialize_uint8(0xA5)
        assert ok
        v, ok = w.serialize_uint16(0xBEEF)
        assert ok
        v, ok = w.serialize_uint32(0xCAFEBABE)
        assert ok
        v, ok = w.serialize_uint64(0x0123456789ABCDEF)
        assert ok
        assert w.serialize_align()
        v, ok = w.serialize_uint8(0x5A)
        assert ok
        w.flush()

        v, ok = m.serialize_uint8(0xA5)
        assert ok
        v, ok = m.serialize_uint16(0xBEEF)
        assert ok
        v, ok = m.serialize_uint32(0xCAFEBABE)
        assert ok
        v, ok = m.serialize_uint64(0x0123456789ABCDEF)
        assert ok
        assert m.serialize_align()
        v, ok = m.serialize_uint8(0x5A)
        assert ok
        assert m.bits_processed() >= w.bits_processed()

        let r = serialize_read_stream(buf, w.bytes_processed())
        for(shift) i:
            var rb = true
            rb, ok = r.serialize_bool(rb)
            assert ok and rb == ((i & 1) == 0)
        var u8v = 0
        var u16v = 0
        var u32v = 0
        var u64v = 0
        var tail8 = 0
        u8v, ok = r.serialize_uint8(u8v)
        assert ok and u8v == 0xA5
        u16v, ok = r.serialize_uint16(u16v)
        assert ok and u16v == 0xBEEF
        u32v, ok = r.serialize_uint32(u32v)
        assert ok and u32v == 0xCAFEBABE
        u64v, ok = r.serialize_uint64(u64v)
        assert ok and u64v == 0x0123456789ABCDEF
        assert r.serialize_align()
        assert r.align_bits() == 0
        tail8, ok = r.serialize_uint8(tail8)
        assert ok and tail8 == 0x5A
        assert r.bits_remaining() == 0

def test_pack_and_unpack_bytes():
    for(10) head_bytes:
        for(20) count:
            let buf1 = ensure_size("", 64, 0xCC)
            let buf2 = ensure_size("", 64, 0xCC)
            let w1 = serialize_write_stream(buf1)
            let w2 = serialize_write_stream(buf2)
            var v = 0
            var ok = false

            v, ok = w1.serialize_bits(5, 3)
            assert ok
            assert w1.serialize_align()
            v, ok = w2.serialize_bits(5, 3)
            assert ok
            assert w2.serialize_align()

            for(head_bytes) i:
                let b = (i * 17 + 5) & 0xFF
                v, ok = w1.serialize_uint8(b)
                assert ok
                v, ok = w2.serialize_uint8(b)
                assert ok

            let payload = ensure_size("", 24, 0)
            for(count) i:
                let pb = (i * 31 + 9) & 0xFF
                write_int8_le(payload, i + 2, pb)
                v, ok = w2.serialize_uint8(pb)
                assert ok
            w1.pack_bytes(payload, 2, count)

            v, ok = w1.serialize_bits(0x12345, 19)
            assert ok
            v, ok = w2.serialize_bits(0x12345, 19)
            assert ok
            w1.flush()
            w2.flush()

            assert w1.bits_processed() == w2.bits_processed()
            let nbytes = w1.bytes_processed()
            for(nbytes) i:
                assert read_uint8_le(buf1, i) == read_uint8_le(buf2, i)

            let r = serialize_read_stream(buf1, nbytes)
            var lead = 0
            lead, ok = r.serialize_bits(lead, 3)
            assert ok and lead == 5
            assert r.serialize_align()
            for(head_bytes) i:
                var hb = 0
                hb, ok = r.serialize_uint8(hb)
                assert ok and hb == ((i * 17 + 5) & 0xFF)
            let got_payload = ensure_size("", 24, 0xEE)
            r.unpack_bytes(got_payload, 3, count)
            for(count) i:
                assert read_uint8_le(got_payload, i + 3) == read_uint8_le(payload, i + 2)
            var trail = 0
            trail, ok = r.serialize_bits(trail, 19)
            assert ok and trail == 0x12345

// The byte primitives pass the same gates as every other operation: a full
// buffer latches at the whole width before a byte moves, a read past the end
// is refused before any load, and a zero-count call still consults the latch
// (DESIGN.md (e); STANDARD.md, Reader Obligations, "Failure is terminal").
def test_bytes_gates():
    let payload = ensure_size("", 16, 0)
    for(16) i:
        write_int8_le(payload, i, (i * 13 + 1) & 0xFF)

    let full = ensure_size("", 8, 0)
    let wf = serialize_write_stream(full)
    wf.pack_bytes(payload, 0, 8)
    assert not wf.error()
    assert wf.bits_processed() == 64
    assert wf.bits_available() == 0
    // A zero-count call on a full buffer fits, and moves nothing; one byte
    // more traps (IMPLEMENTING.md U9: TestBitpackerPackBytesPastEndTraps).
    wf.pack_bytes(payload, 0, 0)
    assert wf.ok() and wf.bits_processed() == 64
    for(8) i:
        assert read_uint8_le(full, i) == ((i * 13 + 1) & 0xFF)

    // Data of 0..9 bytes never reads outside itself: a count one byte past the
    // end is refused with the destination untouched.
    for(10) nbytes:
        let src = ensure_size("", 24, 0)
        for(nbytes) i:
            write_int8_le(src, i, (i + 1) * 0x11)
        let rs = serialize_read_stream(src, nbytes)
        let dst = ensure_size("", 16, 0xEE)
        rs.unpack_bytes(dst, 0, nbytes + 1)
        assert rs.error()
        assert rs.bits_processed() == 0
        for(16) i:
            assert read_uint8_le(dst, i) == 0xEE

    // A count wider than the backing string is refused by the gate, not by a
    // VM index error on a load past the data's end.
    let data = ensure_size("", 24, 0)
    for(16) i:
        write_int8_le(data, i, (i + 1) * 0x11)
    let r2 = serialize_read_stream(data, 16)
    let dst2 = ensure_size("", 32, 0xEE)
    r2.unpack_bytes(dst2, 0, 20)
    assert r2.error()
    assert r2.bits_processed() == 0
    for(32) i:
        assert read_uint8_le(dst2, i) == 0xEE
    r2.unpack_bytes(dst2, 0, 0)
    assert r2.error()

    // A fitting byte read still works and advances bits_read.
    let r3 = serialize_read_stream(data, 16)
    let dst3 = ensure_size("", 16, 0)
    r3.unpack_bytes(dst3, 3, 12)
    assert not r3.error()
    assert r3.bits_processed() == 96
    for(12) i:
        assert read_uint8_le(dst3, i + 3) == ((i + 1) * 0x11)

def test_bits_required():
    assert serialize_bits_required(0, 0) == 0
    assert serialize_bits_required(5, 5) == 0
    assert serialize_bits_required(0, 1) == 1
    assert serialize_bits_required(0, 2) == 2
    assert serialize_bits_required(0, 3) == 2
    assert serialize_bits_required(0, 4) == 3
    assert serialize_bits_required(0, 7) == 3
    assert serialize_bits_required(0, 8) == 4
    assert serialize_bits_required(-5, 5) == 4
    assert serialize_bits_required(0, 0xFFFFFFFF) == 32
    assert serialize_bits_required(-2147483648, 2147483647) == 32

    assert serialize_bits_required64(0, 0) == 0
    assert serialize_bits_required64(-1, -1) == 0
    assert serialize_bits_required64(0, 1) == 1
    assert serialize_bits_required64(0, 0xFFFFFFFF) == 32
    assert serialize_bits_required64(0, 0x100000000) == 33
    assert serialize_bits_required64(0, 0x7FFFFFFFFFFFFFFF) == 63
    assert serialize_bits_required64(0, 0x8000000000000000) == 64
    assert serialize_bits_required64(0, -1) == 64
    assert serialize_bits_required64(0x8000000000000000, 0x7FFFFFFFFFFFFFFF) == 64

// Rowan's mandatory check: feed VALID data with plenty of remaining bits after
// a forced read error (both via r.fail(reason) and via a data-triggered refusal in
// byte 0) and prove every subsequent read stays refused, leaves its destination
// untouched, and consumes 0 bits. Removing the latch guard in read_gate turns
// this test red because bits_read + bits <= num_bits holds over the remaining
// valid data.
def test_read_latch_over_valid_data():
    let valid_data = ensure_size("", 24, 0)
    write_int8_le(valid_data, 0, 0xFF)
    for(15) i:
        write_int8_le(valid_data, i + 1, (i + 1) * 0x11)

    // Case 1: explicit r.fail(reason) when 128 valid bits remain.
    let r1 = serialize_read_stream(valid_data, 16)
    assert r1.bits_remaining() == 128
    assert not r1.fail(serialize_refusal_value_out_of_range)
    assert r1.error() and not r1.ok()
    assert r1.bits_remaining() == 128

    var b1 = false
    var v = 0
    var ok = true
    b1, ok = r1.serialize_bool(b1)
    assert not ok and not b1
    v, ok = r1.serialize_bits(0x13572468, 8)
    assert not ok and v == 0x13572468
    v, ok = r1.serialize_bits64(0x1122334455667788, 16)
    assert not ok and v == 0x1122334455667788
    v, ok = r1.serialize_uint8(0x42)
    assert not ok and v == 0x42
    v, ok = r1.serialize_uint16(0x4242)
    assert not ok and v == 0x4242
    v, ok = r1.serialize_uint32(0x13572468)
    assert not ok and v == 0x13572468
    v, ok = r1.serialize_uint64(0x1122334455667788)
    assert not ok and v == 0x1122334455667788
    assert not r1.serialize_align()
    assert r1.bits_processed() == 0
    assert r1.bits_remaining() == 128

    // Case 2: data-triggered refusal (nonzero align padding in byte 0) when
    // 120 valid bits remain in the stream.
    let r2 = serialize_read_stream(valid_data, 16)
    var first_bit = false
    first_bit, ok = r2.serialize_bool(first_bit)
    assert ok and first_bit
    assert r2.bits_processed() == 1
    assert r2.bits_remaining() == 127

    assert not r2.serialize_align()
    assert r2.error()
    assert r2.bits_processed() == 8
    assert r2.bits_remaining() == 120

    b1, ok = r2.serialize_bool(b1)
    assert not ok and not b1
    v, ok = r2.serialize_bits(0x13572468, 8)
    assert not ok and v == 0x13572468
    v, ok = r2.serialize_bits64(0x1122334455667788, 16)
    assert not ok and v == 0x1122334455667788
    v, ok = r2.serialize_uint8(0x42)
    assert not ok and v == 0x42
    v, ok = r2.serialize_uint16(0x4242)
    assert not ok and v == 0x4242
    v, ok = r2.serialize_uint32(0x13572468)
    assert not ok and v == 0x13572468
    v, ok = r2.serialize_uint64(0x1122334455667788)
    assert not ok and v == 0x1122334455667788
    assert not r2.serialize_align()
    assert r2.bits_processed() == 8
    assert r2.bits_remaining() == 120

// Write misuse traps, never latches (IMPLEMENTING.md U9): a value wider than
// its bits, a negative value, and a write past the end each end the process.
// expect-abort: serialize: value must fit in bits
def TestBitpackerWriteOverWideTraps():
    let w = serialize_write_stream(ensure_size("", 8, 0))
    w.serialize_bits(8, 3)

// expect-abort: serialize: value must fit in bits
def TestBitpackerWriteNegativeTraps():
    let w = serialize_write_stream(ensure_size("", 8, 0))
    w.serialize_bits(-1, 3)

// expect-abort: serialize: write does not fit the room left in the buffer
def TestBitpackerWriteBoolPastEndTraps():
    let w = serialize_write_stream(ensure_size("", 8, 0))
    var v = 0
    var ok = true
    v, ok = w.serialize_uint64(-1)
    assert ok and w.bits_available() == 0
    w.serialize_bool(true)

// expect-abort: serialize: write does not fit the room left in the buffer
def TestBitpackerPackBytesPastEndTraps():
    let w = serialize_write_stream(ensure_size("", 8, 0))
    w.pack_bytes("abcdefghi", 0, 9)

def check_bits_vec(w:int, hex_bytes:[int], expected_ok:bool, expected_val:int, expected_consumed:int, canonical_writer:bool):
    let nbytes = hex_bytes.length
    let buf = ensure_size("", 16, 0xFF)
    for(nbytes) i:
        write_int8_le(buf, i, hex_bytes[i])
    let r = serialize_read_stream(buf, nbytes)
    var got = 0x55555555
    var ok = false
    if w <= 32:
        got, ok = r.serialize_bits(got, w)
    else:
        got, ok = r.serialize_bits64(got, w)
    assert ok == expected_ok
    if expected_ok:
        assert got == expected_val
        assert r.bits_processed() == expected_consumed
        assert not r.error()
    else:
        assert got == 0x55555555
        assert r.error()
    if canonical_writer:
        let wbuf = ensure_size("", 16, 0)
        let ws = serialize_write_stream(wbuf)
        var wv = expected_val
        var wok = false
        if w <= 32:
            wv, wok = ws.serialize_bits(wv, w)
        else:
            wv, wok = ws.serialize_bits64(wv, w)
        assert wok
        assert ws.bits_processed() == expected_consumed
        ws.flush()
        assert ws.bytes_processed() == nbytes
        for(nbytes) i:
            assert read_uint8_le(wbuf, i) == hex_bytes[i]

def check_bool_vec(hex_bytes:[int], expected_ok:bool, expected_val:bool, expected_consumed:int, canonical_writer:bool):
    let nbytes = hex_bytes.length
    let buf = ensure_size("", 16, 0xFF)
    for(nbytes) i:
        write_int8_le(buf, i, hex_bytes[i])
    let r = serialize_read_stream(buf, nbytes)
    var got = not expected_val
    var ok = false
    got, ok = r.serialize_bool(got)
    assert ok == expected_ok
    if expected_ok:
        assert got == expected_val
        assert r.bits_processed() == expected_consumed
        assert not r.error()
    else:
        assert got == (not expected_val)
        assert r.error()
    if canonical_writer:
        let wbuf = ensure_size("", 16, 0)
        let ws = serialize_write_stream(wbuf)
        var wv = expected_val
        var wok = false
        wv, wok = ws.serialize_bool(wv)
        assert wok
        assert ws.bits_processed() == expected_consumed
        ws.flush()
        assert ws.bytes_processed() == nbytes
        for(nbytes) i:
            assert read_uint8_le(wbuf, i) == hex_bytes[i]

def check_align_vec(preceding_bits:int, hex_bytes:[int], expected_ok:bool, expected_consumed:int, canonical_writer:bool):
    let nbytes = hex_bytes.length
    let buf = ensure_size("", 16, 0xFF)
    for(nbytes) i:
        write_int8_le(buf, i, hex_bytes[i])
    let r = serialize_read_stream(buf, nbytes)
    var pre = 0
    var ok = true
    if preceding_bits > 0:
        pre, ok = r.serialize_bits(pre, preceding_bits)
        assert ok
    let aok = r.serialize_align()
    assert aok == expected_ok
    if expected_ok:
        assert r.bits_processed() == expected_consumed
        assert not r.error()
    else:
        assert r.error()
    if canonical_writer:
        let wbuf = ensure_size("", 16, 0)
        let ws = serialize_write_stream(wbuf)
        if preceding_bits > 0:
            var wpre = pre
            var wok = false
            wpre, wok = ws.serialize_bits(wpre, preceding_bits)
            assert wok
        assert ws.serialize_align()
        assert ws.bits_processed() == expected_consumed
        ws.flush()
        assert ws.bytes_processed() == nbytes
        for(nbytes) i:
            assert read_uint8_le(wbuf, i) == hex_bytes[i]

def test_conformance_vectors():
    // conformance/bool.txt
    check_bool_vec([0x00], true, false, 1, true)
    check_bool_vec([0x01], true, true, 1, true)
    check_bool_vec([0xFF], true, true, 1, false)
    check_bool_vec([0xFE], true, false, 1, false)
    check_bool_vec([], false, false, 0, false)

    // conformance/align.txt
    check_align_vec(8, [0xAB], true, 8, true)
    check_align_vec(0, [], true, 0, true)
    check_align_vec(7, [0x7F], true, 8, true)
    check_align_vec(4, [0x0A], true, 8, true)
    check_align_vec(1, [0x01], true, 8, true)
    check_align_vec(7, [0xFF], false, 0, false)
    check_align_vec(4, [0xAA], false, 0, false)
    check_align_vec(1, [0xFF], false, 0, false)
    check_align_vec(1, [0x81], false, 0, false)
    check_align_vec(1, [0x03], false, 0, false)

    // conformance/bits.txt
    check_bits_vec(1, [0x00], true, 0, 1, true)
    check_bits_vec(1, [0x01], true, 1, 1, true)
    check_bits_vec(1, [0xFF], true, 1, 1, false)
    check_bits_vec(8, [0x7F], true, 127, 8, true)
    check_bits_vec(8, [0xFF], true, 255, 8, true)
    check_bits_vec(16, [0x34, 0x12], true, 4660, 16, true)
    check_bits_vec(24, [0xEF, 0xCD, 0xAB], true, 11259375, 24, true)
    check_bits_vec(32, [0xEF, 0xBE, 0xAD, 0xDE], true, 3735928559, 32, true)
    check_bits_vec(32, [0xFF, 0xFF, 0xFF, 0xFF], true, 4294967295, 32, true)
    check_bits_vec(33, [0x00, 0x00, 0x00, 0x00, 0x01], true, 4294967296, 33, true)
    check_bits_vec(33, [0xFF, 0xFF, 0xFF, 0xFF, 0x01], true, 8589934591, 33, true)
    check_bits_vec(64, [0xF0, 0xDE, 0xBC, 0x9A, 0x78, 0x56, 0x34, 0x12], true, 1311768467463790320, 64, true)
    check_bits_vec(64, [0x00, 0x00, 0x00, 0x00, 0xFF, 0xFF, 0xFF, 0xFF], true, -4294967296, 64, true)
    check_bits_vec(64, [0xFF, 0xFF, 0xFF, 0xFF, 0x00, 0x00, 0x00, 0x00], true, 4294967295, 64, true)
    check_bits_vec(64, [0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF], true, -1, 64, true)
    check_bits_vec(1, [], false, 0, 0, false)
    check_bits_vec(16, [0xFF], false, 0, 0, false)
    check_bits_vec(16, [0xFF, 0xFF], true, 65535, 16, true)
    check_bits_vec(33, [0xFF, 0xFF, 0xFF, 0xFF], false, 0, 0, false)
    check_bits_vec(64, [0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF], false, 0, 0, false)

def TestBitpacker():
    test_conformance_vectors()
    test_golden_sequence()
    test_oracle_and_round_trip()
    test_fixed_width_and_align()
    test_pack_and_unpack_bytes()
    test_bytes_gates()
    test_bits_required()
    test_read_latch_over_valid_data()

// expect-abort: serialize: bits must be in [1,32]
def TestBitpackerBitsZeroAborts():
    let w = serialize_write_stream(ensure_size("", 8, 0))
    w.serialize_bits(0, 0)

// expect-abort: serialize: bits must be in [1,32]
def TestBitpackerBits33Aborts():
    let w = serialize_write_stream(ensure_size("", 8, 0))
    w.serialize_bits(0, 33)

// A bad bit count aborts on a write (and a measure); on a read it is refused,
// never an abort (IMPLEMENTING.md U7: test/uniform's TestU7ReadMisuseRefuses).
// expect-abort: serialize: bits must be in [1,64]
def TestBitpackerBits64ZeroAborts():
    let w = serialize_write_stream(ensure_size("", 8, 0))
    w.serialize_bits64(0, 0)

// expect-abort: serialize: bits must be in [1,64]
def TestBitpackerBits64TooWideAborts():
    let m = serialize_measure_stream()
    m.serialize_bits64(0, 65)

// expect-abort: serialize: byte array serialization requires byte alignment
def TestBitpackerPackBytesUnalignedAborts():
    let w = serialize_write_stream(ensure_size("", 16, 0))
    w.serialize_bool(true)
    w.pack_bytes("abcd", 0, 4)

// On a read an unaligned unpack_bytes is refused, never an abort
// (IMPLEMENTING.md U7), and it touches neither the cursor nor the destination.
def TestBitpackerUnpackBytesUnalignedRefuses():
    let r = serialize_read_stream_padded("abcd")
    r.serialize_bool(false)
    let dst = ensure_size("", 4, 0x55)
    r.unpack_bytes(dst, 0, 4)
    assert r.error() and r.refusal_name() == "value_out_of_range"
    assert r.bits_processed() == 1
    assert dst == ensure_size("", 4, 0x55)
