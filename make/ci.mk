# make/ci.mk -- this card's targets; the design's Makefile includes make/*.mk.
#
# check-ci runs tools/checkci/check-ci.sh: it reads ci.yml and DESIGN.md only,
# never the network, and holds the workflow to the fleet runner, the Makefile
# toolchain pin, and DESIGN.md's corpus pin.

.PHONY: check-ci

check-ci:
	@sh tools/checkci/check-ci.sh
