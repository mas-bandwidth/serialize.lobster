// serialize_int128.lobster — uint128 and ranged int128 over two int lanes
// (STANDARD.md, Bit-Level Primitives, uint128; Integers, int128; DESIGN.md (c), (f)).
//
// STUBS until serialize-lobster-integers fills this file (DESIGN.md (f)): every signature here is
// final; each body aborts `serialize: <name> not implemented`. The card that
// fills it cites the STANDARD.md section (and DESIGN.md section) from each
// function that implements a rule, and edits no other src/ file.
//
// The two types are final here: serialize.c's serialize_uint128_t and
// serialize_int128_t, the same two 64-bit lanes { lo, hi } (bits 0..63 and
// 64..127), read unsigned and two's complement.
import .serialize_stream
import .serialize_bitpacker

struct serialize_uint128:
    lo:int
    hi:int

struct serialize_int128:
    lo:int
    hi:int

def serialize_uint128_make(hi:int, lo:int) -> serialize_uint128:
    serialize_stub("serialize_uint128_make")
    return serialize_uint128 { lo, hi }

def serialize_int128_make(hi:int, lo:int) -> serialize_int128:
    serialize_stub("serialize_int128_make")
    return serialize_int128 { lo, hi }

def serialize_int128_from_int64(value:int) -> serialize_int128:
    serialize_stub("serialize_int128_from_int64")
    return serialize_int128 { value, 0 }

def serialize_uint128_equal(a:serialize_uint128, b:serialize_uint128) -> bool:
    serialize_stub("serialize_uint128_equal")
    return false

def serialize_int128_equal(a:serialize_int128, b:serialize_int128) -> bool:
    serialize_stub("serialize_int128_equal")
    return false

def serialize_int128_compare(a:serialize_int128, b:serialize_int128) -> int:
    serialize_stub("serialize_int128_compare")
    return 0

def serialize_uint128(s:serialize_write_stream, value:serialize_uint128):
    serialize_stub("serialize_uint128")
    return value, false

def serialize_uint128(s:serialize_read_stream, value:serialize_uint128):
    serialize_stub("serialize_uint128")
    return value, false

def serialize_uint128(s:serialize_measure_stream, value:serialize_uint128):
    serialize_stub("serialize_uint128")
    return value, false

def serialize_int128(s:serialize_write_stream, value:serialize_int128, min:serialize_int128, max:serialize_int128):
    serialize_stub("serialize_int128")
    return value, false

def serialize_int128(s:serialize_read_stream, value:serialize_int128, min:serialize_int128, max:serialize_int128):
    serialize_stub("serialize_int128")
    return value, false

def serialize_int128(s:serialize_measure_stream, value:serialize_int128, min:serialize_int128, max:serialize_int128):
    serialize_stub("serialize_int128")
    return value, false
