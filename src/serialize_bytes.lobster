// serialize_bytes.lobster — bytes, string and wstring
// (STANDARD.md, Bytes and Strings: bytes, string, wstring; DESIGN.md (d), (f)).
//
// STUBS until serialize-lobster-strings fills this file (DESIGN.md (f)): every signature here is
// final; each body aborts `serialize: <name> not implemented`. The card that
// fills it cites the STANDARD.md section (and DESIGN.md section) from each
// function that implements a rule, and edits no other src/ file.

import .serialize_stream
import .serialize_bitpacker
import .serialize_int

def serialize_bytes(s:serialize_write_stream, data:string, bytes:int):
    serialize_stub("serialize_bytes")
    return data, false

def serialize_bytes(s:serialize_read_stream, data:string, bytes:int):
    serialize_stub("serialize_bytes")
    return data, false

def serialize_bytes(s:serialize_measure_stream, data:string, bytes:int):
    serialize_stub("serialize_bytes")
    return data, false

def serialize_string(s:serialize_write_stream, value:string, buffer_size:int):
    serialize_stub("serialize_string")
    return value, false

def serialize_string(s:serialize_read_stream, value:string, buffer_size:int):
    serialize_stub("serialize_string")
    return value, false

def serialize_string(s:serialize_measure_stream, value:string, buffer_size:int):
    serialize_stub("serialize_string")
    return value, false

def serialize_wstring(s:serialize_write_stream, value:[int], buffer_size:int):
    serialize_stub("serialize_wstring")
    return value, false

def serialize_wstring(s:serialize_read_stream, value:[int], buffer_size:int):
    serialize_stub("serialize_wstring")
    return value, false

def serialize_wstring(s:serialize_measure_stream, value:[int], buffer_size:int):
    serialize_stub("serialize_wstring")
    return value, false
