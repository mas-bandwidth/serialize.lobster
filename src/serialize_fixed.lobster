// serialize_fixed.lobster — Q format fixed point at three storage widths
// (STANDARD.md, Integers, fixed (Q format, ranged); DESIGN.md (c), (f)).
//
// STUBS until serialize-lobster-floats fills this file (DESIGN.md (f)): every signature here is
// final; each body aborts `serialize: <name> not implemented`. The card that
// fills it cites the STANDARD.md section (and DESIGN.md section) from each
// function that implements a rule, and edits no other src/ file.

import .serialize_stream
import .serialize_bitpacker
import .serialize_int128

def serialize_fixed32(s:serialize_write_stream, value:int, integer_bits:int, fraction_bits:int, min:int, max:int):
    serialize_stub("serialize_fixed32")
    return value, false

def serialize_fixed32(s:serialize_read_stream, value:int, integer_bits:int, fraction_bits:int, min:int, max:int):
    serialize_stub("serialize_fixed32")
    return value, false

def serialize_fixed32(s:serialize_measure_stream, value:int, integer_bits:int, fraction_bits:int, min:int, max:int):
    serialize_stub("serialize_fixed32")
    return value, false

def serialize_fixed64(s:serialize_write_stream, value:int, integer_bits:int, fraction_bits:int, min:int, max:int):
    serialize_stub("serialize_fixed64")
    return value, false

def serialize_fixed64(s:serialize_read_stream, value:int, integer_bits:int, fraction_bits:int, min:int, max:int):
    serialize_stub("serialize_fixed64")
    return value, false

def serialize_fixed64(s:serialize_measure_stream, value:int, integer_bits:int, fraction_bits:int, min:int, max:int):
    serialize_stub("serialize_fixed64")
    return value, false

def serialize_fixed128(s:serialize_write_stream, value:serialize_int128, integer_bits:int, fraction_bits:int, min:int, max:int):
    serialize_stub("serialize_fixed128")
    return value, false

def serialize_fixed128(s:serialize_read_stream, value:serialize_int128, integer_bits:int, fraction_bits:int, min:int, max:int):
    serialize_stub("serialize_fixed128")
    return value, false

def serialize_fixed128(s:serialize_measure_stream, value:serialize_int128, integer_bits:int, fraction_bits:int, min:int, max:int):
    serialize_stub("serialize_fixed128")
    return value, false
