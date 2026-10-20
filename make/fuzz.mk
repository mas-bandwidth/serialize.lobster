# make/fuzz.mk -- the fuzz differential against serialize.c (DESIGN.md (g);
# STANDARD.md, the reference oracle).  `make fuzz` builds fuzz/host.c against
# the vendored serialize.c v1.11.2 oracle in .ref/, stages fuzz_driver.lobster
# beside src/, and runs TestDifferentialAgainstSerializeC: 2000 fixed-seed
# programs, one Lobster child process per batch of 100 over files in the
# test's own temporary directory.  The negative control makes the C side write
# one int range one bit wider and must go red.  A second control removes the
# reader's range refusals from a staged copy of src/ and must also go red,
# proving the targeted mutants reach those refusals.

FUZZ_REF     := $(CURDIR)/.ref/serialize.c
FUZZ_BUILD   := $(CURDIR)/build/fuzz
FUZZ_HOST    := $(FUZZ_BUILD)/host
FUZZ_STAGE   := $(FUZZ_BUILD)/stage
FUZZ_DRIVER  := $(FUZZ_STAGE)/fuzz_driver.lobster
FUZZ_WORK    := $(FUZZ_BUILD)/work
FUZZ_NORANGE := $(FUZZ_BUILD)/stage-norange

.PHONY: fuzz fuzz-ref

# The oracle, read only: serialize.c v1.11.2, header-only.  Cloned once into
# .ref/ (gitignored, and excluded through .git/info/exclude).
fuzz-ref:
	@if [ ! -f "$(FUZZ_REF)/serialize.h" ]; then \
		mkdir -p .ref; \
		git clone -q --branch v1.11.2 --depth 1 https://github.com/mas-bandwidth/serialize.c .ref/serialize.c || \
		{ echo "fuzz REFUSES: cannot clone serialize.c v1.11.2 into .ref/"; exit 1; }; \
	fi
	@grep -qxF '.ref/' .git/info/exclude 2>/dev/null || echo '.ref/' >> .git/info/exclude

$(FUZZ_HOST): fuzz/host.c fuzz-ref
	@mkdir -p $(FUZZ_BUILD)
	$(CC) -O2 -std=c99 -Wall -Wextra -I$(FUZZ_REF) -o $@ fuzz/host.c

$(FUZZ_DRIVER): fuzz/fuzz_driver.lobster $(wildcard src/*.lobster)
	@rm -rf $(FUZZ_STAGE) && mkdir -p $(FUZZ_STAGE)
	@cp src/*.lobster $(FUZZ_STAGE)/
	@cp fuzz/fuzz_driver.lobster $(FUZZ_STAGE)/

fuzz: toolchain-lobster $(FUZZ_HOST) $(FUZZ_DRIVER)
	@rm -rf $(FUZZ_WORK) && mkdir -p $(FUZZ_WORK)
	@$(FUZZ_HOST) --lobster $(LOBSTER) --driver $(FUZZ_DRIVER) --tmp $(FUZZ_WORK)
	@echo "negative control: the C side writes one int range one bit wider"
	@if $(FUZZ_HOST) --lobster $(LOBSTER) --driver $(FUZZ_DRIVER) --tmp $(FUZZ_WORK) \
		--negative-control >$(FUZZ_BUILD)/negative.log 2>&1; then \
		echo "negative control DID NOT go red"; exit 1; \
	elif ! grep -q 'write bytes differ' $(FUZZ_BUILD)/negative.log || \
		! grep -q -- '--- FAIL TestDifferentialAgainstSerializeC' $(FUZZ_BUILD)/negative.log; then \
		echo "negative control went red for the wrong reason (see build/fuzz/negative.log)"; exit 1; \
	else \
		echo "negative control: RED as expected (write bytes differ; see build/fuzz/negative.log)"; \
	fi
	@echo "reader negative control: the Lobster reader's range refusal is off"
	@rm -rf $(FUZZ_NORANGE) && cp -r $(FUZZ_STAGE) $(FUZZ_NORANGE)
	@sed -i '/if offset > span:/,+1d' $(FUZZ_NORANGE)/serialize_int.lobster
	@sed -i '/if serialize_ult(span, offset):/,+1d' $(FUZZ_NORANGE)/serialize_int.lobster
	@sed -i '/if serialize_fixed_compare128(offset, span) > 0:/,+1d' $(FUZZ_NORANGE)/serialize_fixed.lobster
	@sed -i '/if serialize_u128_compare(offset, span) > 0:/,+1d' $(FUZZ_NORANGE)/serialize_int128.lobster
	@if $(FUZZ_HOST) --lobster $(LOBSTER) --driver $(FUZZ_NORANGE)/fuzz_driver.lobster --tmp $(FUZZ_WORK) \
		>$(FUZZ_BUILD)/reader.log 2>&1; then \
		echo "reader negative control DID NOT go red"; exit 1; \
	elif ! grep -q 'mutant: accept mismatch' $(FUZZ_BUILD)/reader.log || \
		! grep -q -- '--- FAIL TestDifferentialAgainstSerializeC' $(FUZZ_BUILD)/reader.log; then \
		echo "reader negative control went red for the wrong reason (see build/fuzz/reader.log)"; exit 1; \
	else \
		echo "reader negative control: RED as expected (mutant: accept mismatch; see build/fuzz/reader.log)"; \
	fi
