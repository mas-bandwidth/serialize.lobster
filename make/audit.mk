# Read-boundary models and their reversed witnesses. Run on a Linux bench;
# TLA_JAR names an already installed tla2tools.jar (no download in a gate).
TLA_JAR ?= tla2tools.jar

.PHONY: audit-models
audit-models:
	@test -f "$(TLA_JAR)" || { echo "audit-models REFUSES: TLA_JAR=$(TLA_JAR) is missing"; exit 1; }
	@mkdir -p build/audit-models
	@set -eu; for model in test/uniform/ReadInitialization; do \
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
