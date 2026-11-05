--------------------------- MODULE Utf8ScanBounds ---------------------------
EXTENDS Integers

\* sra-lobster-2: ASCII is sufficient to witness the scan-span boundary.
\* Unicode continuation accesses are bounded by n in the implementation;
\* this model establishes the missing n <= data length precondition.
CONSTANT OldBounds
VARIABLES phase, dataLength, count, index, refused, accepted, badAccess
vars == <<phase, dataLength, count, index, refused, accepted, badAccess>>

Init == /\ phase = "choose"
        /\ dataLength = 0 /\ count = 0 /\ index = 0
        /\ refused = FALSE /\ accepted = FALSE /\ badAccess = FALSE

Choose ==
    /\ phase = "choose"
    /\ \E length \in 0..4, n \in -1..6:
        /\ dataLength' = length /\ count' = n
        /\ refused' = (~OldBounds /\ (n < 0 \/ n > length))
    /\ phase' = "scan"
    /\ UNCHANGED <<index, accepted, badAccess>>

Scan == /\ phase = "scan" /\ ~refused /\ index < count
        /\ badAccess' = (index >= dataLength)
        /\ index' = index + 1
        /\ UNCHANGED <<phase, dataLength, count, refused, accepted>>

Finish == /\ phase = "scan" /\ (refused \/ index >= count)
          /\ phase' = "done" /\ accepted' = ~refused
          /\ UNCHANGED <<dataLength, count, index, refused, badAccess>>

Next == Choose \/ Scan \/ Finish
Spec == Init /\ [][Next]_vars
NoOutsideAccess == ~badAccess
AcceptedSpan == accepted => (count >= 0 /\ count <= dataLength)
=============================================================================
