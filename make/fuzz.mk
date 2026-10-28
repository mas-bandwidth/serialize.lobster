# make/fuzz.mk -- the fuzz differential against serialize.c (DESIGN.md (g);
# STANDARD.md, the reference oracle).  `make fuzz` builds fuzz/host.c against
# the vendored serialize.c v2.0.0 oracle in .ref/, stages fuzz_driver.lobster
# beside src/, and runs TestDifferentialAgainstSerializeC: 2000 fixed-seed
# programs, one Lobster child process per batch of 100 over files in the
# test's own temporary directory.  The negative control makes the C side write
# one int range one bit wider and must go red.  A second control removes the
# reader's range refusals from a staged copy of src/ and must also go red,
# proving the targeted mutants reach those refusals.
#
# The budget and seed are knobs whose defaults are the per-push gate exactly
# (2000 programs from the fixed seed): FUZZ_SEED=<u64>, FUZZ_PROGRAMS=<n>
# (0 = no count limit) and FUZZ_DURATION=<seconds> pass through to the main
# differential run as --seed, --programs and --duration.  The negative
# controls always run at the defaults, so a witness never depends on a seed.
# The run prints its seed first; a failing run leaves the failing batch, the
# Lobster child's output and REPRODUCE.txt in build/fuzz/failures/.
# `make fuzz-run` is the differential run alone (no controls), for
# reproducing: make fuzz-run FUZZ_SEED=<seed> FUZZ_PROGRAMS=<n>.

FUZZ_REF     := $(CURDIR)/.ref/serialize.c-v2.0.0
FUZZ_BUILD   := $(CURDIR)/build/fuzz
FUZZ_HOST    := $(FUZZ_BUILD)/host
FUZZ_STAGE   := $(FUZZ_BUILD)/stage
FUZZ_DRIVER  := $(FUZZ_STAGE)/fuzz_driver.lobster
FUZZ_WORK    := $(FUZZ_BUILD)/work
FUZZ_NORANGE := $(FUZZ_BUILD)/stage-norange
FUZZ_REASON  := $(FUZZ_BUILD)/stage-reason
FUZZ_FRAC    := $(FUZZ_BUILD)/stage-fraction
FUZZ_HIGHGRP := $(FUZZ_BUILD)/stage-highgroup
FUZZ_FAILURES := $(FUZZ_BUILD)/failures

FUZZ_SEED     ?=
FUZZ_PROGRAMS ?=
FUZZ_DURATION ?=
FUZZ_KNOBS := $(if $(FUZZ_SEED),--seed $(FUZZ_SEED)) \
	$(if $(FUZZ_PROGRAMS),--programs $(FUZZ_PROGRAMS)) \
	$(if $(FUZZ_DURATION),--duration $(FUZZ_DURATION))

.PHONY: fuzz fuzz-run fuzz-warnings fuzz-ref

# The oracle, read only: serialize.c v2.0.0, header-only.  Cloned once into
# .ref/ (gitignored, and excluded through .git/info/exclude).
fuzz-ref:
	@if [ ! -f "$(FUZZ_REF)/serialize.h" ]; then \
		mkdir -p .ref; \
		git clone -q --branch v2.0.0 --depth 1 https://github.com/mas-bandwidth/serialize.c .ref/serialize.c-v2.0.0 || \
		{ echo "fuzz REFUSES: cannot clone serialize.c v2.0.0 into .ref/serialize.c-v2.0.0"; exit 1; }; \
	fi
	@grep -qxF '.ref/' .git/info/exclude 2>/dev/null || echo '.ref/' >> .git/info/exclude

$(FUZZ_HOST): fuzz/host.c fuzz-ref
	@mkdir -p $(FUZZ_BUILD)
	$(CC) -O2 -std=c99 -ffp-contract=off -Wall -Wextra -Werror -I$(FUZZ_REF) -o $@ fuzz/host.c

$(FUZZ_DRIVER): fuzz/fuzz_driver.lobster $(wildcard src/*.lobster)
	@rm -rf $(FUZZ_STAGE) && mkdir -p $(FUZZ_STAGE)
	@cp src/*.lobster $(FUZZ_STAGE)/
	@cp fuzz/fuzz_driver.lobster $(FUZZ_STAGE)/

fuzz-warnings: toolchain-lobster $(FUZZ_HOST) $(FUZZ_DRIVER)
	@# Zero warnings, always: the driver run with no batch compiles everything
	@# it reaches and prints its usage; any compiler warning is red.
	@if (cd $(FUZZ_STAGE) && $(LOBSTER) fuzz_driver.lobster 2>&1) | grep ': warning: '; then \
		echo "fuzz REFUSES: the driver or src/ compiles with warnings"; exit 1; fi

fuzz-run: fuzz-warnings
	@rm -rf $(FUZZ_WORK) $(FUZZ_FAILURES) && mkdir -p $(FUZZ_WORK)
	@$(FUZZ_HOST) --lobster $(LOBSTER) --driver $(FUZZ_DRIVER) --tmp $(FUZZ_WORK) \
		--failures $(FUZZ_FAILURES) $(strip $(FUZZ_KNOBS))

fuzz: fuzz-run
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
	@echo "reason negative control: the Lobster reader names invalid_utf8 where embedded_nul is due"
	@rm -rf $(FUZZ_REASON) && cp -r $(FUZZ_STAGE) $(FUZZ_REASON)
	@sed -i 's/^        return serialize_refusal_embedded_nul$$/        return serialize_refusal_invalid_utf8/' $(FUZZ_REASON)/serialize_bytes.lobster
	@grep -q '^        return serialize_refusal_invalid_utf8$$' $(FUZZ_REASON)/serialize_bytes.lobster || \
		{ echo "reason negative control: the sabotage needle no longer matches"; exit 1; }
	@if $(FUZZ_HOST) --lobster $(LOBSTER) --driver $(FUZZ_REASON)/fuzz_driver.lobster --tmp $(FUZZ_WORK) \
		>$(FUZZ_BUILD)/reason.log 2>&1; then \
		echo "reason negative control DID NOT go red"; exit 1; \
	elif ! grep -q 'refusal reason mismatch (C embedded_nul, Lobster invalid_utf8)' $(FUZZ_BUILD)/reason.log; then \
		echo "reason negative control went red for the wrong reason (see build/fuzz/reason.log)"; exit 1; \
	else \
		echo "reason negative control: RED as expected (refusal reason mismatch; see build/fuzz/reason.log)"; \
	fi
	@echo "c-fraction negative control: the C oracle perturbs fraction_bits on a fractional fixed field"
	@if $(FUZZ_HOST) --lobster $(LOBSTER) --driver $(FUZZ_DRIVER) --tmp $(FUZZ_WORK) \
		--corrupt-fraction-control >$(FUZZ_BUILD)/c-fraction.log 2>&1; then \
		echo "c-fraction negative control DID NOT go red"; exit 1; \
	elif ! grep -q 'write bytes differ' $(FUZZ_BUILD)/c-fraction.log || \
		! grep -q -- '--- FAIL TestDifferentialAgainstSerializeC' $(FUZZ_BUILD)/c-fraction.log; then \
		echo "c-fraction negative control went red for the wrong reason (see build/fuzz/c-fraction.log)"; exit 1; \
	else \
		echo "c-fraction negative control: RED as expected (write bytes differ; see build/fuzz/c-fraction.log)"; \
	fi
	@echo "lobster-fraction negative control: the Lobster oracle ignores fraction_bits"
	@rm -rf $(FUZZ_FRAC) && cp -r $(FUZZ_STAGE) $(FUZZ_FRAC)
	@sed -i 's/return serialize_fixed_shl128(serialize_fixed_from_int64(whole), fraction_bits)/return serialize_fixed_shl128(serialize_fixed_from_int64(whole), 0)/' $(FUZZ_FRAC)/serialize_fixed.lobster
	@grep -q 'serialize_fixed_from_int64(whole), 0' $(FUZZ_FRAC)/serialize_fixed.lobster || \
		{ echo "lobster-fraction negative control: the sabotage needle no longer matches"; exit 1; }
	@if $(FUZZ_HOST) --lobster $(LOBSTER) --driver $(FUZZ_FRAC)/fuzz_driver.lobster --tmp $(FUZZ_WORK) \
		>$(FUZZ_BUILD)/lobster-fraction.log 2>&1; then \
		echo "lobster-fraction negative control DID NOT go red"; exit 1; \
	elif ! grep -qxF 'serialize: value must be in [min, max]' $(FUZZ_BUILD)/lobster-fraction.log || \
		! grep -q 'lobster child failed' $(FUZZ_BUILD)/lobster-fraction.log || \
		! grep -q -- '--- FAIL TestDifferentialAgainstSerializeC' $(FUZZ_BUILD)/lobster-fraction.log; then \
		echo "lobster-fraction negative control went red for the wrong reason (see build/fuzz/lobster-fraction.log)"; exit 1; \
	else \
		echo "lobster-fraction negative control: RED as expected (the Lobster writer traps on the value, IMPLEMENTING.md U9; see build/fuzz/lobster-fraction.log)"; \
	fi
	@echo "c-high-group negative control: the C oracle corrupts group 2 of a wide fixed128 field"
	@if $(FUZZ_HOST) --lobster $(LOBSTER) --driver $(FUZZ_DRIVER) --tmp $(FUZZ_WORK) \
		--corrupt-high-group-control >$(FUZZ_BUILD)/c-high-group.log 2>&1; then \
		echo "c-high-group negative control DID NOT go red"; exit 1; \
	elif ! grep -q 'write bytes differ' $(FUZZ_BUILD)/c-high-group.log || \
		! grep -q -- '--- FAIL TestDifferentialAgainstSerializeC' $(FUZZ_BUILD)/c-high-group.log; then \
		echo "c-high-group negative control went red for the wrong reason (see build/fuzz/c-high-group.log)"; exit 1; \
	else \
		echo "c-high-group negative control: RED as expected (write bytes differ; see build/fuzz/c-high-group.log)"; \
	fi
	@echo "lobster-high-group negative control: the Lobster oracle corrupts group 2 of a wide fixed128 field"
	@rm -rf $(FUZZ_HIGHGRP) && cp -r $(FUZZ_STAGE) $(FUZZ_HIGHGRP)
	@sed -i 's/case 2: return v.hi & 0xFFFFFFFF/case 2: return (v.hi ^ 1) \& 0xFFFFFFFF/' $(FUZZ_HIGHGRP)/serialize_fixed.lobster
	@grep -q 'case 2: return (v.hi ^ 1) & 0xFFFFFFFF' $(FUZZ_HIGHGRP)/serialize_fixed.lobster || \
		{ echo "lobster-high-group negative control: the sabotage needle no longer matches"; exit 1; }
	@if $(FUZZ_HOST) --lobster $(LOBSTER) --driver $(FUZZ_HIGHGRP)/fuzz_driver.lobster --tmp $(FUZZ_WORK) \
		>$(FUZZ_BUILD)/lobster-high-group.log 2>&1; then \
		echo "lobster-high-group negative control DID NOT go red"; exit 1; \
	elif ! grep -q 'write bytes differ' $(FUZZ_BUILD)/lobster-high-group.log || \
		! grep -q -- '--- FAIL TestDifferentialAgainstSerializeC' $(FUZZ_BUILD)/lobster-high-group.log; then \
		echo "lobster-high-group negative control went red for the wrong reason (see build/fuzz/lobster-high-group.log)"; exit 1; \
	else \
		echo "lobster-high-group negative control: RED as expected (write bytes differ; see build/fuzz/lobster-high-group.log)"; \
	fi
