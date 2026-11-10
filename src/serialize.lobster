// serialize.lobster — the entry (DESIGN.md (a), (f)): `import serialize`
// brings in the streams and every family. A port of serialize, the
// open-source bitpacking serializer, wire compatible with serialize.c v2.0.0
// (STANDARD.md, format version 2.0, as vendored from serialize v2.1.4).

import .serialize_stream
import .serialize_bitpacker
import .serialize_int
import .serialize_int128
import .serialize_float
import .serialize_fixed
import .serialize_compressed_float
import .serialize_bytes
import .serialize_object

// Lobster v2026.8 refuses an import on the last line of an imported file
// ("illegal start of expression: `end of include`"), so the entry ends with
// declarations: this port's release (its tag is v<serialize_version>), and the
// version of serialize.c.
let serialize_version = "2.1.3"
let serialize_reference_version = "serialize.c 2.0.0"
