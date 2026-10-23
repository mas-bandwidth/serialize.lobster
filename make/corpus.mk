# make/corpus.mk -- check-corpus-dir runs tools/checkcorpus/check-corpus-dir.sh,
# the unit test of SERIALIZE_CONFORMANCE_DIR and SERIALIZE_CONFORMANCE_CONTROLS_DIR
# (the corpus override the nightly functional test uses). A stub lobster: no
# toolchain, no network.

.PHONY: check-corpus-dir

check-corpus-dir:
	@sh tools/checkcorpus/check-corpus-dir.sh
