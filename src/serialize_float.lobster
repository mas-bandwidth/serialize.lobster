// serialize_float.lobster — float (float32 on the wire) and double, and the
// float32 routes (STANDARD.md, Floating Point: float, double; DESIGN.md (c), (f)).
//
// STUBS until serialize-lobster-floats fills this file (DESIGN.md (f)): every signature here is
// final; each body aborts `serialize: <name> not implemented`. The card that
// fills it cites the STANDARD.md section (and DESIGN.md section) from each
// function that implements a rule, and edits no other src/ file.

import .serialize_stream

def serialize_float32_round(x:float) -> float:
    serialize_stub("serialize_float32_round")
    return x

def serialize_float32_bits(x:float) -> int:
    serialize_stub("serialize_float32_bits")
    return 0

def serialize_float32_from_bits(u:int) -> float:
    serialize_stub("serialize_float32_from_bits")
    return 0.0

def serialize_float64_bits(x:float) -> int:
    serialize_stub("serialize_float64_bits")
    return 0

def serialize_float64_from_bits(u:int) -> float:
    serialize_stub("serialize_float64_from_bits")
    return 0.0

def serialize_float(s:serialize_write_stream, value:float):
    serialize_stub("serialize_float")
    return value, false

def serialize_float(s:serialize_read_stream, value:float):
    serialize_stub("serialize_float")
    return value, false

def serialize_float(s:serialize_measure_stream, value:float):
    serialize_stub("serialize_float")
    return value, false

def serialize_double(s:serialize_write_stream, value:float):
    serialize_stub("serialize_double")
    return value, false

def serialize_double(s:serialize_read_stream, value:float):
    serialize_stub("serialize_double")
    return value, false

def serialize_double(s:serialize_measure_stream, value:float):
    serialize_stub("serialize_double")
    return value, false
