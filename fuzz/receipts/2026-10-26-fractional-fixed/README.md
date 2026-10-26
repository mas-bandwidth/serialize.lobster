# Fractional fixed differential

`fuzz/host.c` draws `fraction_bits`, including zero, for fixed32, fixed64,
and fixed128. `make fuzz` compares the vendored serialize.c v2.0.0 host
with the Lobster driver on canonical bytes, decoded raw values, consumed
bits, measure results, refusal point and reason, and terminal behavior.
The generator's tables are a pairwise matrix, not a Cartesian product.

Named controls corrupt fraction bits or one high group in either oracle
and must go red. The widened-range, deleted-range, and wrong-reason
controls stay.

PATHS allows this README and not the raw logs. Those logs are not in
this tree. The sprint finish records the exact-head gate.
