// serialize_int.lobster — ranged int (int32 domain), int64 and int_relative
// (STANDARD.md, Integers: int, int64, int_relative; DESIGN.md (c), (f)).
//
// STUBS until serialize-lobster-integers fills this file (DESIGN.md (f)): every signature here is
// final; each body aborts `serialize: <name> not implemented`. The card that
// fills it cites the STANDARD.md section (and DESIGN.md section) from each
// function that implements a rule, and edits no other src/ file.

import .serialize_stream
import .serialize_bitpacker

def serialize_int(s:serialize_write_stream, value:int, min:int, max:int):
    serialize_stub("serialize_int")
    return value, false

def serialize_int(s:serialize_read_stream, value:int, min:int, max:int):
    serialize_stub("serialize_int")
    return value, false

def serialize_int(s:serialize_measure_stream, value:int, min:int, max:int):
    serialize_stub("serialize_int")
    return value, false

def serialize_int64(s:serialize_write_stream, value:int, min:int, max:int):
    serialize_stub("serialize_int64")
    return value, false

def serialize_int64(s:serialize_read_stream, value:int, min:int, max:int):
    serialize_stub("serialize_int64")
    return value, false

def serialize_int64(s:serialize_measure_stream, value:int, min:int, max:int):
    serialize_stub("serialize_int64")
    return value, false

def serialize_int_relative(s:serialize_write_stream, previous:int, current:int):
    serialize_stub("serialize_int_relative")
    return current, false

def serialize_int_relative(s:serialize_read_stream, previous:int, current:int):
    serialize_stub("serialize_int_relative")
    return current, false

def serialize_int_relative(s:serialize_measure_stream, previous:int, current:int):
    serialize_stub("serialize_int_relative")
    return current, false
