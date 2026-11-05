// Bounded timing witness for sra-lobster-2. This is not a unit test.
// Stage beside either base or fixed src/, then run with the pinned JIT.
import serialize

let texts = ["abcdefghijklmnop", "\xF0\x9F\x98\x80\xF0\x9F\x98\x80\xF0\x9F\x98\x80\xF0\x9F\x98\x80"]
let packets:[string] = []
for(texts) text:
    let w = serialize_write_stream(ensure_size("", 32, 0))
    w.serialize_string(text, 32)
    w.flush()
    packets.push(substring(w.buffer, 0, w.bytes_processed()))

let iterations = 200000
for(5) trial:
    var accepted = 0
    let helper_start = seconds_elapsed()
    for(iterations) i:
        let text = texts[i & 1]
        if string_utf8_valid(text, length(text)):
            accepted += 1
    let helper_seconds = seconds_elapsed() - helper_start
    assert accepted == iterations
    accepted = 0
    let string_start = seconds_elapsed()
    for(iterations) i:
        let r = serialize_read_stream_padded(packets[i & 1])
        let text, ok = r.serialize_string("", 32)
        if ok and text == texts[i & 1] and r.serialize_end():
            accepted += 1
    let string_seconds = seconds_elapsed() - string_start
    assert accepted == iterations
    print "trial " + string(trial) + " helper_ns " + string(helper_seconds * 1000000000.0 / float(iterations)) + " string_ns " + string(string_seconds * 1000000000.0 / float(iterations))
