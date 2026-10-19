// serialize_compressed_float.lobster — compressed_float, its precomputed form
// and the parameter derivation (STANDARD.md, Floating Point, compressed_float;
// DESIGN.md (c), (f)).
//
// STUBS until serialize-lobster-floats fills this file (DESIGN.md (f)): every signature here is
// final; each body aborts `serialize: <name> not implemented`. The card that
// fills it cites the STANDARD.md section (and DESIGN.md section) from each
// function that implements a rule, and edits no other src/ file.

import .serialize_stream
import .serialize_bitpacker
import .serialize_float

def serialize_compressed_float_params(min:float, max:float, res:float):
    serialize_stub("serialize_compressed_float_params")
    return 0, 0, 0.0

def serialize_compressed_float(s:serialize_write_stream, value:float, min:float, max:float, res:float):
    serialize_stub("serialize_compressed_float")
    return value, false

def serialize_compressed_float(s:serialize_read_stream, value:float, min:float, max:float, res:float):
    serialize_stub("serialize_compressed_float")
    return value, false

def serialize_compressed_float(s:serialize_measure_stream, value:float, min:float, max:float, res:float):
    serialize_stub("serialize_compressed_float")
    return value, false

def serialize_compressed_float_precomputed(s:serialize_write_stream, value:float, max_integer_value:int, bits:int, delta:float, min:float):
    serialize_stub("serialize_compressed_float_precomputed")
    return value, false

def serialize_compressed_float_precomputed(s:serialize_read_stream, value:float, max_integer_value:int, bits:int, delta:float, min:float):
    serialize_stub("serialize_compressed_float_precomputed")
    return value, false

def serialize_compressed_float_precomputed(s:serialize_measure_stream, value:float, max_integer_value:int, bits:int, delta:float, min:float):
    serialize_stub("serialize_compressed_float_precomputed")
    return value, false
