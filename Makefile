# opam-depmap -- thin wrapper around dune.
#
#   make                                     # build
#   make PACKAGE=<opam package>              # -> out/{data.json,squarified_treemap.html}
#   make switch                              # map the whole current switch at once
#   make report  [PACKAGE=<pkg>]             # -> out/report.json  (model-oriented)
#   make digest  [PACKAGE=<pkg>]             # -> out/report.md    (compact digest)
#   make example                             # regenerate the bundled Dream example
#   make test                                # unit tests (incl. golden render/report)
#
# The package must be installed in the current opam switch (set OPAMSWITCH to use another).

PACKAGE ?=
OUT     ?= out
HERE    := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
DEPMAP  := dune exec --root $(HERE) --no-print-directory -- opam-depmap
O       := $(abspath $(OUT))

.PHONY: all build map switch report digest test example clean FORCE
all: $(if $(PACKAGE),map,build)

build:
	dune build --root $(HERE)

map:
	@mkdir -p $(OUT)
	$(DEPMAP) map $(PACKAGE) --data $(O)/data.json -o $(O)/squarified_treemap.html

switch:
	@mkdir -p $(OUT)
	$(DEPMAP) switch --data $(O)/data.json -o $(O)/squarified_treemap.html

# Collect into out/data.json: one PACKAGE, or (no PACKAGE) the whole switch.
# FORCE so a report always reflects the current switch, not a stale file.
$(O)/data.json: FORCE
	@mkdir -p $(OUT)
	$(if $(PACKAGE),$(DEPMAP) collect $(PACKAGE) -o $@,$(DEPMAP) switch --data $@ -o /dev/null)

FORCE:

report: $(O)/data.json
	$(DEPMAP) report $< -o $(O)/report.json

digest: $(O)/data.json
	$(DEPMAP) report $< -o $(O)/report.md

test:
	dune test --root $(HERE)

# Regenerate the committed example (needs dream installed: opam install dream)
example:
	$(MAKE) -f $(HERE)/Makefile PACKAGE=dream OUT=$(HERE)/example/dream map

clean:
	dune clean --root $(HERE)
	rm -rf $(OUT)
