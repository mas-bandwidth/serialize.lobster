# Read-boundary models and their reversed witnesses. Run on a Linux bench;
# TLA_JAR names an already installed tla2tools.jar (no download in a gate).
TLA_JAR ?= tla2tools.jar

.PHONY: audit-models
audit-models:
	@test -f "$(TLA_JAR)" || { echo "audit-models REFUSES: TLA_JAR=$(TLA_JAR) is missing"; exit 1; }
	@mkdir -p build/audit-models
	@set -eu; for model in test/uniform/ReadInitialization test/strings/Utf8ScanBounds; do \
		name=$$(basename "$$model"); \
		java -Xmx512m -XX:+UseParallelGC -XX:ActiveProcessorCount=4 -cp "$(TLA_JAR)" tlc2.TLC -workers 4 \
			-metadir "$(CURDIR)/build/audit-models/$$name" -config "$$model.cfg" "$$model.tla" \
			>"build/audit-models/$$name.log" 2>&1 || { cat "build/audit-models/$$name.log"; exit 1; }; \
		tail -n 7 "build/audit-models/$$name.log"; \
		if java -Xmx512m -XX:+UseParallelGC -XX:ActiveProcessorCount=4 -cp "$(TLA_JAR)" tlc2.TLC -workers 4 \
			-metadir "$(CURDIR)/build/audit-models/$${name}Old" -config "$${model}Old.cfg" "$$model.tla" \
			>"build/audit-models/$${name}Old.log" 2>&1; then \
			echo "FAIL $$name reversed witness did not go red"; exit 1; \
		elif ! grep -q 'Error: Invariant .* is violated' "build/audit-models/$${name}Old.log"; then \
			cat "build/audit-models/$${name}Old.log"; exit 1; \
		fi; \
		echo "PASS $$name; reversed witness RED as expected"; \
	done

# Before/after numbers for the public UTF-8 span refusal on the string path.
# The timing program is separate from unit tests; staging never mutates src/.
.PHONY: audit-timing
audit-timing: toolchain-lobster
	@mkdir -p build/audit-timing/base build/audit-timing/fixed
	@set -eu; for file in src/*.lobster; do \
		git show ab34aba94a73f38c0bf71e470c07411776ad446a:$$file >"build/audit-timing/base/$$(basename "$$file")"; \
		cp "$$file" build/audit-timing/fixed/; \
	done
	@cp fuzz/receipts/2026-11-05-read-bounds/utf8_timing.lobster build/audit-timing/base/
	@cp fuzz/receipts/2026-11-05-read-bounds/utf8_timing.lobster build/audit-timing/fixed/
	@set -eu; for pair in 1 2 3; do \
		for leg in base fixed; do \
			echo "pair $$pair $$leg"; \
			(cd "build/audit-timing/$$leg" && "$(LOBSTER)" utf8_timing.lobster); \
		done; \
	done
