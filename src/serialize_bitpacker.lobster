// serialize_bitpacker.lobster — the packer: the 64-bit scratch word, word stores and window
// loads, the bit primitives bits and bits64, and bits_required
// (STANDARD.md, General Conventions; Bit-Level Primitives, bits; DESIGN.md (b), (c), (f)).
//
// STUBS until serialize-lobster-bitpacker fills this file (DESIGN.md (f)): every signature here is
// final; each body aborts `serialize: <name> not implemented`. The card that
// fills it cites the STANDARD.md section (and DESIGN.md section) from each
// function that implements a rule, and edits no other src/ file.
//
// The packing primitives (called by every family, gated before the call: the
// width is in range, the value fits, and the stream has room or data):
//   pack_bits(value, bits)      bits in [1,32]
//   pack_bits64(value, bits)    bits in [1,64], the low 32 bits first
//   flush_bits()                store the partial scratch word
//   pack_bytes(data, offset, count)   an aligned run of count bytes
//   unpack_bits(bits) -> int    bits in [1,32]
//   unpack_bits64(bits) -> int  bits in [1,64], the low 32 bits first
//   unpack_bytes(data, offset, count) an aligned run, into data in place
import .serialize_stream

def pack_bits(s:serialize_write_stream, value:int, bits:int):
    serialize_stub("pack_bits")

def pack_bits64(s:serialize_write_stream, value:int, bits:int):
    serialize_stub("pack_bits64")

def flush_bits(s:serialize_write_stream):
    serialize_stub("flush_bits")

def pack_bytes(s:serialize_write_stream, data:string, offset:int, count:int):
    serialize_stub("pack_bytes")

def unpack_bits(s:serialize_read_stream, bits:int) -> int:
    serialize_stub("unpack_bits")
    return 0

def unpack_bits64(s:serialize_read_stream, bits:int) -> int:
    serialize_stub("unpack_bits64")
    return 0

def unpack_bytes(s:serialize_read_stream, data:string, offset:int, count:int):
    serialize_stub("unpack_bytes")

def serialize_bits(s:serialize_write_stream, value:int, bits:int):
    serialize_stub("serialize_bits")
    return value, false

def serialize_bits(s:serialize_read_stream, value:int, bits:int):
    serialize_stub("serialize_bits")
    return value, false

def serialize_bits(s:serialize_measure_stream, value:int, bits:int):
    serialize_stub("serialize_bits")
    return value, false

def serialize_bits64(s:serialize_write_stream, value:int, bits:int):
    serialize_stub("serialize_bits64")
    return value, false

def serialize_bits64(s:serialize_read_stream, value:int, bits:int):
    serialize_stub("serialize_bits64")
    return value, false

def serialize_bits64(s:serialize_measure_stream, value:int, bits:int):
    serialize_stub("serialize_bits64")
    return value, false

def serialize_bits_required(min:int, max:int) -> int:
    serialize_stub("serialize_bits_required")
    return 0

def serialize_bits_required64(min:int, max:int) -> int:
    serialize_stub("serialize_bits_required64")
    return 0
