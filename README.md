# serialize.lobster

A simple bitpacking serializer for [Lobster](https://github.com/aardappel/lobster), wire compatible with the C++ [serialize](https://github.com/mas-bandwidth/serialize) library and [serialize.c](https://github.com/mas-bandwidth/serialize.c): the same values produce the same bytes.

The wire format is serialize's STANDARD.md, format version 2.0, at standard 2.1 (serialize v2.1.1, serialize.c v2.0.0): the wire carries only integers and bytes, and every value has exactly one encoding. Floats and doubles are finite only, text is UTF-8 only (wstring is gone), and every refusal names its reason (`s.refusal_name()`, from STANDARD.md's closed list). A caller refuses a value it decoded with `s.reject()`, or by returning `false` from an object's `serialize`, and the stream reports `rejected`. A read never aborts: caller misuse on a read refuses `value_out_of_range`. Write and measure misuse (a value outside its range or width, a non-finite float, text that is not well-formed UTF-8 or holds a NUL or is too long, a bad declaration, a write that does not fit the buffer, `reject()` on a writer) traps in every run: `serialize_abort` prints the rule and exits 70, and nothing is latched (IMPLEMENTING.md U9). Names not listed in DESIGN.md, "The public surface", are internal (U15). A packet reader calls `s.serialize_end()` after the packet's top-level object, which refuses trailing bytes and set padding:

```lobster
import serialize

class message : serialize_object_base
    health:int = 0
    alive:bool = false

def serialize(m::message, s) -> bool:
    m.health = s.serialize_int(m.health, 0, 100)
    m.alive = s.serialize_bool(m.alive)
    return s.ok()

def read_packet(data:string) -> message?:
    let s = serialize_read_stream_padded(data)
    let m = message {}
    s.serialize_object(m)
    s.serialize_end()
    if not s.ok():
        print "refused: " + s.refusal_name()
        return nil
    return m
```

The conformance runner passes every vector of the format 2.0 corpus, each refusal for its stated reason, and `make controls` proves each refusal rule is load-bearing: a copy of the library with that one rule deleted fails exactly the vectors the reference lists for it. The pinned compiler is Lobster v2026.8 (commit 0921f7dd5745).

BSD 3-Clause license.
