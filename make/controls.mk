# make/controls.mk -- the per-rule negative controls (STANDARD.md, "A gate
# nobody has seen go red"). `make controls` runs tools/controls/controls.sh:
# for every conformance-controls/<rule>.expected, a staged copy of src/ with
# that one rule deleted must fail exactly the listed vectors.
# `make controls C=<rule>` runs one.

.PHONY: controls

controls: toolchain-lobster
	@tools/controls/controls.sh $(C)
