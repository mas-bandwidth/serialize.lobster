------------------------- MODULE ReadInitialization -------------------------
EXTENDS Integers

\* sra-lobster-1: signed eight-bit abstraction of the int64 constructor.
\* The same eight-byte slack and byte-to-bit multiplication are retained.
\* OldBounds reverses the fix; both slack addition and bit multiplication
\* wrap in that version. A zero-bit read still has to consult the latch.
CONSTANT OldBounds
VARIABLES phase, dataLength, byteCount, valid, failed, reason, numBits,
          zeroReadAccepted

vars == <<phase, dataLength, byteCount, valid, failed, reason, numBits,
          zeroReadAccepted>>

Signed(v) == LET u == v % 256 IN IF u >= 128 THEN u - 256 ELSE u
Valid(length, count) == count >= 0 /\ count <= 15 /\ count <= length - 8

Init == /\ phase = "choose"
        /\ dataLength = 0 /\ byteCount = 0 /\ valid = FALSE
        /\ failed = FALSE /\ reason = "none" /\ numBits = 0
        /\ zeroReadAccepted = FALSE

Initialize ==
    /\ phase = "choose"
    /\ \E length \in 0..24, count \in -1..127:
        LET refuses == IF OldBounds
                       THEN count < 0 \/ length < Signed(count + 8)
                       ELSE ~Valid(length, count)
        IN /\ dataLength' = length /\ byteCount' = count
           /\ valid' = Valid(length, count)
           /\ failed' = refuses
           /\ reason' = IF refuses THEN "value_out_of_range" ELSE "none"
           /\ numBits' = IF refuses THEN 0 ELSE Signed(count * 8)
    /\ phase' = "ready"
    /\ UNCHANGED zeroReadAccepted

ReadZero == /\ phase = "ready"
            /\ zeroReadAccepted' = ~failed
            /\ phase' = "done"
            /\ UNCHANGED <<dataLength, byteCount, valid, failed, reason, numBits>>

Next == Initialize \/ ReadZero
Spec == Init /\ [][Next]_vars

InitializationBound == phase = "choose" \/
    /\ failed = ~valid
    /\ numBits = IF valid THEN byteCount * 8 ELSE 0
    /\ reason = IF valid THEN "none" ELSE "value_out_of_range"
ZeroReadBound == zeroReadAccepted => valid
=============================================================================
