# make/bench.mk -- the benchmark card's targets.
#
# bench-check is the untimed shape gate: every row's bytes and checksum must
# match bench/golden.csv, so no leg can win by doing less. It never takes a
# timed sample.
#
# bench runs the timed set pinned to one core and writes
# bench/results/<date>-<host>.csv with a host preamble (BENCH-STANDARD.md
# sections 1 and 2; the statistic is the median of 15 runs after 3 warm-ups).

.PHONY: bench-check bench

bench-check: toolchain-lobster
	@LOBSTER=$(LOBSTER) sh bench/check.sh

bench: toolchain-lobster
	@mkdir -p bench/results
	@stamp=$$(date +%Y-%m-%d); host=$$(hostname); out=bench/results/$$stamp-$$host.csv; \
	{ echo "# host: $$host"; \
	  echo "# cpu: $$(grep -m1 'model name' /proc/cpuinfo | cut -d: -f2- | sed 's/^ *//')"; \
	  echo "# governor: $$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null || echo unknown)"; \
	  echo "# cc: $$(cc --version | head -1)"; \
	  echo "# date: $$(date -u +%Y-%m-%dT%H:%M:%SZ)"; \
	  echo "leg,row,mode,ns_per_op,min_ns,max_ns"; \
	} > $$out
	@rm -rf build/bench && mkdir -p build/bench && cp src/*.lobster build/bench/ && \
	  sed 's/^main()$$/bench()/' bench/bench.lobster > build/bench/bench_timed.lobster
	@cd build/bench && taskset -c 0 $(LOBSTER) bench_timed.lobster >> ../../$$out
	@echo "bench: wrote $$out"
