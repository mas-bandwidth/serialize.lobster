# Makefile — serialize.lobster (DESIGN.md, (g) THE RUNNER).
#
# Lobster v2026.8, pinned: tag v2026.8 of aardappel/lobster, tag object
# 0921f7dd5745 (commit acc66d71978a). To populate dist/ (gitignored), run
# `make dist-lobster` once:
#   url:    https://github.com/aardappel/lobster/releases/download/v2026.8/lobster_linux_release.zip
#   sha256: 2f03fb96fdaf6935469c99e43ffb182cab0d797faec7b26eccc9a732df32ad31
#   unzip into dist/lobster-v2026.8/ (bin/lobster, modules/ beside it)
#
# make test            run every test/*/*_test.lobster (JIT, the default)
# make test T=<name>   run the files of test/<name>/ only
# make bench F=<file>  run a timed program BOTH ways: the JIT, then the --cpp
#                      ahead-of-time build (clang -O2, the pin's dev/ tree)
#
# A later card adds its own targets in its own make/<card>.mk, included below,
# so no two cards edit this file.

LOBSTER_VERSION := v2026.8
LOBSTER_TAG_OBJ := 0921f7dd57458e1373a054880b84ceb9b5d719a5
LOBSTER_COMMIT  := acc66d71978ae5525be1356aa622fbaa9a57e848
LOBSTER_ZIP_URL := https://github.com/aardappel/lobster/releases/download/$(LOBSTER_VERSION)/lobster_linux_release.zip
LOBSTER_ZIP_SHA := 2f03fb96fdaf6935469c99e43ffb182cab0d797faec7b26eccc9a732df32ad31
LOBSTER_GIT     := https://github.com/aardappel/lobster
LOBSTER_DIST    := $(CURDIR)/dist/lobster-$(LOBSTER_VERSION)
LOBSTER        ?= $(LOBSTER_DIST)/bin/lobster
export LOBSTER

# The --cpp leg: a checkout of the pin's source, a JIT lobster built from it
# with the engine off (whose --cpp output matches the compiled_lobster build's
# builtin library), and the LOBSTER_TOCPP build itself, all with clang -O2.
LOBSTER_SRC   := $(CURDIR)/build/lobster-src
CLANG         ?= clang
CLANGXX       ?= clang++
CLANG_BINDIR  := $(dir $(realpath $(shell command -v $(CLANG) 2>/dev/null)))
CPP_CMAKE_ARGS := -G Ninja -DLOBSTER_ENGINE=OFF -DCMAKE_BUILD_TYPE=Release \
	-DCMAKE_C_COMPILER=$(CLANG) -DCMAKE_CXX_COMPILER=$(CLANGXX) \
	"-DCMAKE_C_FLAGS_RELEASE=-O2 -DNDEBUG" "-DCMAKE_CXX_FLAGS_RELEASE=-O2 -DNDEBUG"

.PHONY: all dist-lobster toolchain-lobster test lobster-src lobster-cpp bench clean
all: test

# dist-lobster fetches the pinned release and REFUSES any archive whose sha256
# is not the pin's: the archive is checked before it is unpacked, so a wrong
# download never reaches dist/.
dist-lobster:
	@mkdir -p build/dist-lobster
	@curl -fsSL -o build/dist-lobster/lobster_linux_release.zip $(LOBSTER_ZIP_URL)
	@got=$$(sha256sum build/dist-lobster/lobster_linux_release.zip | cut -d' ' -f1); \
	if [ "$$got" != "$(LOBSTER_ZIP_SHA)" ]; then \
		echo "dist-lobster REFUSES: lobster_linux_release.zip sha256 $$got is not the pin $(LOBSTER_ZIP_SHA)"; \
		rm -f build/dist-lobster/lobster_linux_release.zip; exit 1; fi
	@rm -rf $(LOBSTER_DIST) && mkdir -p $(LOBSTER_DIST)
	@unzip -o -q build/dist-lobster/lobster_linux_release.zip -d $(LOBSTER_DIST)
	@chmod +x $(LOBSTER_DIST)/bin/lobster
	@echo "dist-lobster: lobster $(LOBSTER_VERSION) at $(LOBSTER_DIST) sha256 $(LOBSTER_ZIP_SHA)"

# toolchain-lobster refuses, by name, a pin that does not resolve: $(LOBSTER)
# must be an executable (a path, or a name on PATH).
toolchain-lobster:
	@if ! command -v "$(LOBSTER)" >/dev/null 2>&1; then \
		echo "toolchain-lobster REFUSES: LOBSTER=$(LOBSTER) does not resolve; run make dist-lobster (or set LOBSTER)"; exit 1; fi

# test: every test/<name>/ (or only T's) through tools/run_tests.sh. A missing
# or empty test/<name>/ fails, naming it: never a skip.
test: toolchain-lobster
	@tools/run_tests.sh $(T)

# lobster-src: the pin's source tree, checked out at the pinned commit and
# refused by name when the checkout does not resolve to it.
lobster-src:
	@if [ ! -d $(LOBSTER_SRC)/.git ]; then \
		git clone -q --filter=blob:none $(LOBSTER_GIT) $(LOBSTER_SRC); fi
	@git -C $(LOBSTER_SRC) checkout -q $(LOBSTER_COMMIT)
	@got=$$(git -C $(LOBSTER_SRC) rev-parse HEAD); \
	if [ "$$got" != "$(LOBSTER_COMMIT)" ]; then \
		echo "lobster-src REFUSES: $(LOBSTER_SRC) is at $$got, not the pin $(LOBSTER_COMMIT)"; exit 1; fi

# lobster-cpp: the generator (bin/lobster, engine off) and a first
# compiled_lobster build tree, both from the pinned source.
lobster-cpp: lobster-src
	@if [ -z "$(CLANG_BINDIR)" ]; then echo "lobster-cpp REFUSES: CLANG=$(CLANG) does not resolve"; exit 1; fi
	@PATH=$(CLANG_BINDIR):$$PATH cmake -S $(LOBSTER_SRC)/dev -B build/lobster-jit $(CPP_CMAKE_ARGS) >build/lobster-jit.log 2>&1
	@PATH=$(CLANG_BINDIR):$$PATH cmake --build build/lobster-jit -j 16 >>build/lobster-jit.log 2>&1
	@mkdir -p $(LOBSTER_SRC)/dev/compiled_lobster/src
	@echo 'print "lobster-cpp ok"' > build/lobster-cpp-probe.lobster
	@$(LOBSTER_SRC)/bin/lobster --cpp build/lobster-cpp-probe.lobster
	@PATH=$(CLANG_BINDIR):$$PATH cmake -S $(LOBSTER_SRC)/dev -B build/lobster-tocpp $(CPP_CMAKE_ARGS) -DLOBSTER_TOCPP=ON >build/lobster-tocpp.log 2>&1
	@PATH=$(CLANG_BINDIR):$$PATH cmake --build build/lobster-tocpp -j 16 >>build/lobster-tocpp.log 2>&1
	@$(LOBSTER_SRC)/bin/compiled_lobster

# bench: F is a .lobster program; it runs staged beside a copy of src/ (so
# `import serialize` resolves), first under the JIT, then as --cpp.
bench: toolchain-lobster
	@if [ -z "$(F)" ] || [ ! -f "$(F)" ]; then echo "bench REFUSES: F=$(F) is not a file"; exit 1; fi
	@if [ ! -x $(LOBSTER_SRC)/bin/compiled_lobster ]; then $(MAKE) --no-print-directory lobster-cpp; fi
	@rm -rf build/bench && mkdir -p build/bench && cp src/*.lobster build/bench/ && cp $(F) build/bench/
	@echo "== JIT: $(F)"
	@cd build/bench && $(LOBSTER) $(notdir $(F))
	@cd build/bench && $(LOBSTER_SRC)/bin/lobster --cpp $(notdir $(F))
	@PATH=$(CLANG_BINDIR):$$PATH cmake --build build/lobster-tocpp -j 16 >>build/lobster-tocpp.log 2>&1
	@echo "== --cpp (clang -O2): $(F)"
	@$(LOBSTER_SRC)/bin/compiled_lobster

clean:
	rm -rf build

-include make/*.mk
