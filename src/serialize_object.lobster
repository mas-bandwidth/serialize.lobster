// serialize_object.lobster — object: the caller's own serialize, inline
// (STANDARD.md, object; DESIGN.md (a), (f)).
//
// STUBS until serialize-lobster-strings fills this file (DESIGN.md (f)): every signature here is
// final; each body aborts `serialize: <name> not implemented`. The card that
// fills it cites the STANDARD.md section (and DESIGN.md section) from each
// function that implements a rule, and edits no other src/ file.

import .serialize_stream

def serialize_object(s:serialize_write_stream, object) -> bool:
    serialize_stub("serialize_object")
    return false

def serialize_object(s:serialize_read_stream, object) -> bool:
    serialize_stub("serialize_object")
    return false

def serialize_object(s:serialize_measure_stream, object) -> bool:
    serialize_stub("serialize_object")
    return false
